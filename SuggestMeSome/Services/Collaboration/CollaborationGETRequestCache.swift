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

    private struct InFlightEntry {
        let task: Task<Data, Error>
        let generation: UInt64
    }

    private var cache: [Key: Entry] = [:]
    private var inFlight: [Key: InFlightEntry] = [:]
    private let ttl: TimeInterval
    private let clock: @Sendable () -> Date
    private var invalidationGeneration: UInt64 = 0

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
    ///
    /// Cleanup is bound to the shared Task's own completion (inside its
    /// body) rather than to each caller's await, so a cancelled first
    /// caller can't yank `inFlight[key]` out from under still-waiting
    /// piggy-backers and cause a subsequent caller to spawn a duplicate
    /// request.
    func coalesce(
        key: Key,
        execute: @Sendable @escaping () async throws -> Data
    ) async throws -> Data {
        if let entry = cache[key], clock().timeIntervalSince(entry.cachedAt) < ttl {
            return entry.data
        }
        if let existing = inFlight[key] {
            return try await existing.task.value
        }

        let generation = invalidationGeneration
        let task = Task<Data, Error> { [weak self] in
            do {
                let data = try await execute()
                await self?.finishInFlight(
                    key: key,
                    generation: generation,
                    cachedData: data
                )
                return data
            } catch {
                await self?.finishInFlight(
                    key: key,
                    generation: generation,
                    cachedData: nil
                )
                throw error
            }
        }
        inFlight[key] = InFlightEntry(task: task, generation: generation)
        return try await task.value
    }

    /// Single cleanup entry point — called exactly once by the shared
    /// Task when it completes, regardless of how many callers awaited it.
    private func finishInFlight(key: Key, generation: UInt64, cachedData: Data?) {
        if let entry = inFlight[key], entry.generation == generation {
            inFlight[key] = nil
        }
        if generation == invalidationGeneration, let cachedData {
            cache[key] = Entry(data: cachedData, cachedAt: clock())
        }
    }

    /// Clears the entire cache. Called from HTTPCloudCollaborationClient
    /// after any POST/PUT so subsequent GETs don't return stale reads.
    func invalidateAll() {
        invalidationGeneration &+= 1
        cache.removeAll()
        inFlight.removeAll()
    }
}
