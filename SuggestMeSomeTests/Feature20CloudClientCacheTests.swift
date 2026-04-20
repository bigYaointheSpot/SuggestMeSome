//
//  Feature20CloudClientCacheTests.swift
//  SuggestMeSomeTests
//
//  Coverage for CollaborationGETRequestCache — concurrent-request
//  coalescing, TTL expiry, invalidation on mutation.
//

import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
struct Feature20CloudClientCacheTests {

    // MARK: - Coalescing

    @Test func concurrentGETsShareOneUnderlyingFetch() async throws {
        let cache = CollaborationGETRequestCache(ttl: 300)
        let key = CollaborationGETRequestCache.Key(urlString: "https://example/x", authHash: 1)
        let counter = FetchCounter()

        async let first = cache.coalesce(key: key) {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await counter.increment()
            return Data("fresh".utf8)
        }
        // Small delay so the first coalesce registers its in-flight Task
        // before the second caller arrives.
        try? await Task.sleep(nanoseconds: 5_000_000)
        async let second = cache.coalesce(key: key) {
            await counter.increment()
            return Data("should-not-run".utf8)
        }

        let (r1, r2) = try await (first, second)
        #expect(r1 == Data("fresh".utf8))
        #expect(r2 == Data("fresh".utf8))
        #expect(await counter.value == 1)
    }

    // MARK: - TTL

    @Test func cacheReturnsFreshDataWithinTTL() async throws {
        var stubNow = Date()
        let cache = CollaborationGETRequestCache(ttl: 60) { stubNow }
        let key = CollaborationGETRequestCache.Key(urlString: "https://example/y", authHash: 2)
        let counter = FetchCounter()

        _ = try await cache.coalesce(key: key) {
            await counter.increment()
            return Data("v1".utf8)
        }
        stubNow = stubNow.addingTimeInterval(30)
        let second = try await cache.coalesce(key: key) {
            await counter.increment()
            return Data("v2".utf8)
        }

        // Second call inside TTL serves from cache — fetch count stays 1.
        #expect(second == Data("v1".utf8))
        #expect(await counter.value == 1)
    }

    @Test func cacheRefetchesAfterTTLExpiry() async throws {
        var stubNow = Date()
        let cache = CollaborationGETRequestCache(ttl: 60) { stubNow }
        let key = CollaborationGETRequestCache.Key(urlString: "https://example/z", authHash: 3)
        let counter = FetchCounter()

        _ = try await cache.coalesce(key: key) {
            await counter.increment()
            return Data("v1".utf8)
        }
        stubNow = stubNow.addingTimeInterval(120)
        let second = try await cache.coalesce(key: key) {
            await counter.increment()
            return Data("v2".utf8)
        }

        // TTL elapsed — second call actually runs the closure.
        #expect(second == Data("v2".utf8))
        #expect(await counter.value == 2)
    }

    // MARK: - Invalidation

    @Test func invalidateAllClearsSubsequentGETs() async throws {
        let cache = CollaborationGETRequestCache(ttl: 300)
        let key = CollaborationGETRequestCache.Key(urlString: "https://example/a", authHash: 4)
        let counter = FetchCounter()

        _ = try await cache.coalesce(key: key) {
            await counter.increment()
            return Data("v1".utf8)
        }
        await cache.invalidateAll()
        let second = try await cache.coalesce(key: key) {
            await counter.increment()
            return Data("v2".utf8)
        }

        #expect(second == Data("v2".utf8))
        #expect(await counter.value == 2)
    }

    // MARK: - Failures are not cached

    @Test func cacheDoesNotPersistFailedFetches() async throws {
        let cache = CollaborationGETRequestCache(ttl: 300)
        let key = CollaborationGETRequestCache.Key(urlString: "https://example/b", authHash: 5)
        let counter = FetchCounter()
        struct Boom: Error {}

        do {
            _ = try await cache.coalesce(key: key) {
                await counter.increment()
                throw Boom()
            }
            Issue.record("expected throw")
        } catch is Boom {}

        let second = try await cache.coalesce(key: key) {
            await counter.increment()
            return Data("recovered".utf8)
        }
        #expect(second == Data("recovered".utf8))
        #expect(await counter.value == 2)
    }

    private actor FetchCounter {
        private(set) var value = 0
        func increment() { value += 1 }
    }
}
