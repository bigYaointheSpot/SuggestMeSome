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
