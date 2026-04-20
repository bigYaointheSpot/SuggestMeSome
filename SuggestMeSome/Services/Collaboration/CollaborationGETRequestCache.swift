//
//  CollaborationGETRequestCache.swift
//  SuggestMeSome
//
//  In-memory coalescer + TTL cache for collaboration GET requests.
//
//  Two callers racing the same request now share one Task; repeat GETs
//  inside the TTL window return the cached response without a network
//  round-trip. Mutation requests (POST/PUT) invalidate the entire cache
//  so stale list views don't linger after a mutation. Actor isolation
//  guarantees the in-flight map can't interleave.
//

import Foundation

actor CollaborationGETRequestCache {
    /// Composite key: URL string + hash of the bearer token so cached
    /// entries don't leak across accounts.
    struct Key: Hashable {
        let urlString: String
        let authHash: Int
    }

    private struct Entry {
        let data: Data
        let cachedAt: Date
    }

    private var cache: [Key: Entry] = [:]
    private var inFlight: [Key: Task<Data, Error>] = [:]
    private let ttl: TimeInterval
    private let clock: @Sendable () -> Date

    init(
        ttl: TimeInterval = 300,
        clock: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.ttl = ttl
        self.clock = clock
    }

    /// Returns cached data if still fresh; nil on miss or expiry.
    func cachedData(for key: Key) -> Data? {
        guard let entry = cache[key] else { return nil }
        if clock().timeIntervalSince(entry.cachedAt) >= ttl {
            cache[key] = nil
            return nil
        }
        return entry.data
    }

    /// Runs `execute` if no identical request is in flight; otherwise
    /// awaits the existing Task. Caches successful responses for future
    /// cachedData hits. Failures are not cached — the next caller retries.
    func coalesce(
        key: Key,
        execute: @Sendable @escaping () async throws -> Data
    ) async throws -> Data {
        if let entry = cache[key], clock().timeIntervalSince(entry.cachedAt) < ttl {
            return entry.data
        }
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task<Data, Error> {
            try await execute()
        }
        inFlight[key] = task

        do {
            let data = try await task.value
            inFlight[key] = nil
            cache[key] = Entry(data: data, cachedAt: clock())
            return data
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    /// Clears the entire cache. Called from HTTPCloudCollaborationClient
    /// after any POST/PUT so subsequent GETs don't return stale reads.
    func invalidateAll() {
        cache.removeAll()
    }
}
