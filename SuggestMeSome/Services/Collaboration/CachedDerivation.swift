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

/// Lazy cache that recomputes only after explicit invalidation. Uses
/// reference semantics so holders can invoke `get(...)` from a computed
/// property getter without running into Swift's mutating-getter
/// restriction on `let` fields.
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
