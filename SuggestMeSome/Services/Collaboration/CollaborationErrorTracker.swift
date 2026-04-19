//
//  CollaborationErrorTracker.swift
//  SuggestMeSome
//
//  Single source of truth for per-endpoint errors, the aggregate banner
//  string, and the recent-activity log that CollaborationCoordinator
//  surfaces to views. Splitting this out of the coordinator keeps the
//  sub-stores (introduced in the following commits) sharing one error
//  channel instead of each maintaining their own.
//

import Foundation

/// Single source of truth for per-endpoint collaboration errors, the
/// aggregate banner string, and the recent-activity log.
///
/// `CollaborationCoordinator` holds one `CollaborationErrorTracker`
/// instance and forwards its `endpointErrors`, `lastErrorMessage`, and
/// `recentActivity` through read-only computed properties so every view
/// observes the same state. Extracting the tracker sets up the coordinator
/// split queued for a future pass — the eventual sub-stores
/// (Relationships, Assignments, Notes, Insights, Shares, Blueprints) can
/// all share one error channel instead of each maintaining their own.
///
/// ## Invalidation triggers
/// - `recordError(_:_:)` and `recordErrorMessage(_:message:)` set the
///   per-endpoint entry, bump `lastErrorMessage`, and append an error row
///   to `recentActivity`.
/// - `clearError(_:)` zeroes the entry and recomputes the aggregate banner
///   so recovery paths don't leave a stale message in place.
/// - `clearAllErrors()` covers account-switch / sign-out transitions.
///
/// `@Observable` propagates state changes through SwiftUI's observation
/// system transparently, so view re-renders fire without manual wiring.
@Observable
@MainActor
final class CollaborationErrorTracker {
    private(set) var endpointErrors: [CollaborationEndpoint: String] = [:]
    private(set) var lastErrorMessage: String?
    private(set) var recentActivity: [CollaborationActivityRecord] = []

    func endpointError(_ endpoint: CollaborationEndpoint) -> String? {
        endpointErrors[endpoint]
    }

    func recordError(_ endpoint: CollaborationEndpoint, _ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        recordErrorMessage(endpoint, message: message)
    }

    func recordErrorMessage(_ endpoint: CollaborationEndpoint, message: String) {
        endpointErrors[endpoint] = message
        lastErrorMessage = message
        appendActivity(.error, message)
    }

    func clearError(_ endpoint: CollaborationEndpoint) {
        endpointErrors[endpoint] = nil
        // Recompute aggregate so top-level banners clear once the last
        // failure is resolved instead of showing a stale message.
        lastErrorMessage = endpointErrors.values.first
    }

    func clearAllErrors() {
        endpointErrors.removeAll()
        lastErrorMessage = nil
    }

    func logActivity(_ level: CollaborationActivityLevel, _ message: String) {
        appendActivity(level, message)
    }

    private func appendActivity(_ level: CollaborationActivityLevel, _ message: String) {
        recentActivity.insert(
            CollaborationActivityRecord(level: level, message: message),
            at: 0
        )
        recentActivity = Array(recentActivity.prefix(20))
    }
}
