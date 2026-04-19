//
//  CollaborationRefreshCoalescer.swift
//  SuggestMeSome
//
//  Serializes concurrent refresh requests into a single in-flight Task so
//  overlapping launch/foreground/manual refreshes share one network pass.
//  Lives on the main actor because the work it wraps reads and writes the
//  main-actor-bound ModelContext and coordinator state; using a Swift actor
//  here would just add boundary hops.
//

import Foundation

/// Serializes concurrent collaboration refresh requests into a single
/// in-flight Task.
///
/// The coordinator's refresh path is driven by several independent triggers
/// — app launch, foreground transitions, manual pull-to-refresh, post-mutation
/// reloads. Without coalescing, two overlapping refreshes would both fan out
/// across every collaboration endpoint and race for cache writes.
///
/// `coalesce(_:)` guarantees the first caller runs the work; every caller
/// that arrives while the Task is still executing awaits the same result
/// instead of kicking off a second pass. The class stays `@MainActor` because
/// the work it wraps reads and writes main-actor-bound state (ModelContext,
/// coordinator view properties); promoting it to a Swift actor would force
/// boundary hops with no isolation benefit.
///
/// ## Invalidation triggers
/// - Account sign-in / sign-out transitions call through `refreshAll(...)`
///   after the coordinator reseats its account state, so the new account's
///   refresh runs with the new tokens.
/// - Foreground and manual refreshes share the same slot.
@MainActor
final class CollaborationRefreshCoalescer {
    private var inFlight: Task<Void, Never>?
    private var inFlightID: UUID?

    /// Runs `work` if nothing is already in flight, otherwise awaits the
    /// existing Task. Safe to call re-entrantly — the first caller wins and
    /// subsequent callers piggyback on the same Task's result.
    func coalesce(_ work: @MainActor @escaping () async -> Void) async {
        if let inFlight {
            await inFlight.value
            return
        }

        let token = UUID()
        inFlightID = token
        let task = Task<Void, Never> {
            await work()
        }
        inFlight = task
        await task.value
        // Only the originating caller clears the slot; a later overlapping
        // call that piggybacked already saw a non-nil inFlight and returned.
        if inFlightID == token {
            inFlight = nil
            inFlightID = nil
        }
    }
}
