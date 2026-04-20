//
//  WorkoutLiveActivityController.swift
//  SuggestMeSome
//
//  ActivityKit lifecycle wrapper for the active-workout Live Activity.
//  Starts a new activity when a workout session begins, updates the
//  ContentState when the session mutates (paused/resumed, new exercise,
//  more sets logged), and ends the activity on teardown.
//
//  All ActivityKit calls are gated behind
//  `#if canImport(ActivityKit) && !os(macOS)` so this compiles on every
//  target without Live Activity requirements. When the Widget Extension
//  target is added to the project, no code here changes — iOS will wire
//  the widget bundle to render the activities this controller starts.
//
//  See `docs/LIVE_ACTIVITY_SETUP.md` for the manual Widget Extension
//  target setup steps.
//

import Foundation

#if canImport(ActivityKit) && !os(macOS)
import ActivityKit
#endif

@MainActor
final class WorkoutLiveActivityController {
    /// Shared instance wired into `ActiveWorkoutSessionStore.session.didSet`
    /// via `SuggestMeSomeApp.onAppear`. Singleton is acceptable here
    /// because Live Activities are a process-wide resource — only one
    /// active-workout activity can exist at a time per app.
    static let shared = WorkoutLiveActivityController()

    /// Activity-framework availability guard. Live Activities require
    /// iOS 16.1+, user-enabled Live Activities in Settings, and the app
    /// to be active at start time.
    var isAvailable: Bool {
        #if canImport(ActivityKit) && !os(macOS)
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
        #else
        return false
        #endif
    }

    private init() {}

    /// Start an activity for the given session. No-ops if Live Activities
    /// are unavailable, if one is already running for this session, or if
    /// the system rejects the request (user-disabled, throttled, etc.).
    func start(for session: ActiveWorkoutSession, now: Date = .now) {
        #if canImport(ActivityKit) && !os(macOS)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard Self.runningActivity(for: session.id) == nil else { return }

        let attributes = WorkoutLiveActivityAttributes(
            sessionID: session.id,
            sessionTitle: Self.resolvedSessionTitle(for: session)
        )
        let state = WorkoutLiveActivityAttributes.ContentState.fromSession(session, now: now)

        _ = try? Activity<WorkoutLiveActivityAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        #endif
    }

    /// Push a fresh ContentState to the running activity for this
    /// session. Lightweight; safe to call from didSet on every session
    /// mutation because ActivityKit coalesces in-flight updates.
    func update(for session: ActiveWorkoutSession, now: Date = .now) {
        #if canImport(ActivityKit) && !os(macOS)
        guard #available(iOS 16.1, *) else { return }
        guard let activity = Self.runningActivity(for: session.id) else {
            start(for: session, now: now)
            return
        }
        let state = WorkoutLiveActivityAttributes.ContentState.fromSession(session, now: now)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        #endif
    }

    /// End every running workout activity. Called when the session
    /// finishes (save) or is discarded. Uses the `.immediate` dismissal
    /// policy so the activity disappears from the lock screen and
    /// Dynamic Island as soon as the user leaves the workout.
    func endAll() {
        #if canImport(ActivityKit) && !os(macOS)
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }

    /// End a specific session's activity (if any). Used when sessions
    /// swap identity — e.g., user discards, then starts a fresh one.
    func end(sessionID: UUID) {
        #if canImport(ActivityKit) && !os(macOS)
        guard #available(iOS 16.1, *) else { return }
        guard let activity = Self.runningActivity(for: sessionID) else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        #endif
    }

    // MARK: - Helpers

    #if canImport(ActivityKit) && !os(macOS)
    @available(iOS 16.1, *)
    private static func runningActivity(
        for sessionID: UUID
    ) -> Activity<WorkoutLiveActivityAttributes>? {
        Activity<WorkoutLiveActivityAttributes>.activities
            .first { $0.attributes.sessionID == sessionID }
    }
    #endif

    /// Human-readable header for the Live Activity card. Keeps the copy
    /// consistent with the in-app "Workout in Progress" banner without
    /// duplicating strings across targets.
    static func resolvedSessionTitle(for session: ActiveWorkoutSession) -> String {
        if let context = session.programContext {
            return "Program · Week \(context.weekNumber) · Session \(context.sessionNumber)"
        }
        return "Workout in Progress"
    }
}
