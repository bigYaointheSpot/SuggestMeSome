//
//  CachedDerivation.swift
//  SuggestMeSome
//
//  Small @ObservationIgnored holder used by CollaborationCoordinator's
//  derived views (role-partitioned relationships, roster snapshots, unread
//  counters) so the filter work runs once per source-data change instead
//  of on every SwiftUI body invocation. The coordinator invalidates these
//  wrappers inside `loadCache()` and `clearInMemoryState()` — the two
//  entry points where source data actually changes.
//

import Foundation

/// Lazy cache that recomputes its value only after explicit invalidation.
///
/// Used by `CollaborationCoordinator`'s derived views — role-partitioned
/// relationships and invites, roster snapshots, the `hasAnyCollaboration`
/// aggregate — so the underlying filter / Set-construction work runs once
/// per source-data change instead of on every SwiftUI body invocation.
///
/// Reference semantics let holders call `get(...)` from a computed
/// property getter without tripping Swift's mutating-getter restriction on
/// `let` fields.
///
/// ## Invalidation triggers
/// Holders must call `invalidate()` whenever the inputs the `compute`
/// closure reads can change. In the coordinator this happens inside
/// `loadCache()` (after a refresh populates the source arrays) and
/// `clearInMemoryState()` (on account sign-out). Forgetting to invalidate
/// leaves views displaying stale filtered results.
@MainActor
final class CachedDerivation<Value> {
    private var cachedValue: Value?

    init() {}

    /// Returns the cached value if valid; otherwise invokes `compute`,
    /// caches the result, and returns it.
    func get(compute: () -> Value) -> Value {
        if let cachedValue { return cachedValue }
        let fresh = compute()
        cachedValue = fresh
        return fresh
    }

    func invalidate() {
        cachedValue = nil
    }
}
