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
