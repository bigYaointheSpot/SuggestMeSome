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

/// Protocol-based seam so tests can substitute a counting mock without
/// pulling in ActivityKit. Covers the three session-lifecycle events
/// ActiveWorkoutSessionStore's `session.didSet` needs to fan out to.
@MainActor
protocol WorkoutLiveActivityBridging: AnyObject {
    func startLiveActivity(for session: ActiveWorkoutSession)
    func updateLiveActivity(for session: ActiveWorkoutSession)
    func endLiveActivity(sessionID: UUID)
}

@MainActor
protocol WorkoutLiveActivitySystemDriving: AnyObject {
    var areActivitiesEnabled: Bool { get }

    func hasRunningActivity(for sessionID: UUID) -> Bool
    func requestActivity(
        attributes: WorkoutLiveActivityAttributes,
        state: WorkoutLiveActivityAttributes.ContentState
    )
    func updateActivity(
        sessionID: UUID,
        state: WorkoutLiveActivityAttributes.ContentState
    ) async
    func endActivity(sessionID: UUID) async
    func endAllActivities() async
}

@MainActor
final class WorkoutLiveActivityOperationSequencer {
    private var tails: [UUID: Task<Void, Never>] = [:]
    private var generations: [UUID: UInt64] = [:]

    func enqueueUpdate(
        for sessionID: UUID,
        operation: @escaping @MainActor () async -> Void
    ) {
        let generation = generations[sessionID, default: 0]
        let previous = tails[sessionID]
        let task = Task { [weak self] in
            _ = await previous?.result
            guard let self else { return }
            await self.runIfCurrentGeneration(
                generation,
                for: sessionID,
                operation: operation
            )
        }
        tails[sessionID] = task
    }

    func enqueueTerminal(
        for sessionID: UUID,
        operation: @escaping @MainActor () async -> Void
    ) {
        let previous = tails[sessionID]
        generations[sessionID, default: 0] &+= 1
        let generation = generations[sessionID, default: 0]
        let task = Task { [weak self] in
            _ = await previous?.result
            guard let self else { return }
            await self.runIfCurrentGeneration(
                generation,
                for: sessionID,
                operation: operation
            )
        }
        tails[sessionID] = task
    }

    func invalidateAllAndAwaitPending() -> Task<Void, Never> {
        let sessionIDs = Set(tails.keys).union(generations.keys)
        for sessionID in sessionIDs {
            generations[sessionID, default: 0] &+= 1
        }
        let pendingTasks = Array(tails.values)
        tails.removeAll()
        return Task {
            for task in pendingTasks {
                _ = await task.result
            }
        }
    }

    private func runIfCurrentGeneration(
        _ generation: UInt64,
        for sessionID: UUID,
        operation: @escaping @MainActor () async -> Void
    ) async {
        guard generations[sessionID, default: 0] == generation else { return }
        await operation()
    }
}

@MainActor
final class WorkoutLiveActivityController: WorkoutLiveActivityBridging {
    private let driver: any WorkoutLiveActivitySystemDriving
    private let operationSequencer: WorkoutLiveActivityOperationSequencer

    func startLiveActivity(for session: ActiveWorkoutSession) {
        start(for: session)
    }

    func updateLiveActivity(for session: ActiveWorkoutSession) {
        update(for: session)
    }

    func endLiveActivity(sessionID: UUID) {
        end(sessionID: sessionID)
    }

    /// Shared instance wired into `ActiveWorkoutSessionStore.session.didSet`
    /// via `SuggestMeSomeApp.onAppear`. Singleton is acceptable here
    /// because Live Activities are a process-wide resource — only one
    /// active-workout activity can exist at a time per app.
    static let shared = WorkoutLiveActivityController()

    /// Activity-framework availability guard. Live Activities require
    /// iOS 16.1+, user-enabled Live Activities in Settings, and the app
    /// to be active at start time.
    var isAvailable: Bool {
        driver.areActivitiesEnabled
    }

    init(
        driver: (any WorkoutLiveActivitySystemDriving)? = nil,
        operationSequencer: WorkoutLiveActivityOperationSequencer? = nil
    ) {
        self.driver = driver ?? DefaultWorkoutLiveActivitySystemDriver()
        self.operationSequencer = operationSequencer ?? WorkoutLiveActivityOperationSequencer()
    }

    /// Start an activity for the given session. No-ops if Live Activities
    /// are unavailable, if one is already running for this session, or if
    /// the system rejects the request (user-disabled, throttled, etc.).
    func start(for session: ActiveWorkoutSession, now: Date = .now) {
        guard driver.areActivitiesEnabled else { return }
        guard !driver.hasRunningActivity(for: session.id) else { return }

        let attributes = WorkoutLiveActivityAttributes(
            sessionID: session.id,
            sessionTitle: Self.resolvedSessionTitle(for: session)
        )
        let state = WorkoutLiveActivityAttributes.ContentState.fromSession(session, now: now)

        driver.requestActivity(attributes: attributes, state: state)
    }

    /// Push a fresh ContentState to the running activity for this
    /// session. Mutations queue behind prior updates for the same
    /// session so pause/resume bursts and watch-driven deltas stay
    /// ordered before reaching ActivityKit.
    func update(for session: ActiveWorkoutSession, now: Date = .now) {
        guard driver.areActivitiesEnabled else { return }
        guard driver.hasRunningActivity(for: session.id) else {
            start(for: session, now: now)
            return
        }
        let state = WorkoutLiveActivityAttributes.ContentState.fromSession(session, now: now)
        operationSequencer.enqueueUpdate(for: session.id) { [driver] in
            await driver.updateActivity(sessionID: session.id, state: state)
        }
    }

    /// End every running workout activity. Called when the session
    /// finishes (save) or is discarded. Uses the `.immediate` dismissal
    /// policy so the activity disappears from the lock screen and
    /// Dynamic Island as soon as the user leaves the workout.
    func endAll() {
        guard driver.areActivitiesEnabled else { return }
        let pending = operationSequencer.invalidateAllAndAwaitPending()
        Task { [driver] in
            _ = await pending.result
            await driver.endAllActivities()
        }
    }

    /// End a specific session's activity (if any). Used when sessions
    /// swap identity — e.g., user discards, then starts a fresh one.
    func end(sessionID: UUID) {
        guard driver.areActivitiesEnabled else { return }
        guard driver.hasRunningActivity(for: sessionID) else { return }
        operationSequencer.enqueueTerminal(for: sessionID) { [driver] in
            await driver.endActivity(sessionID: sessionID)
        }
    }

    // MARK: - Helpers

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

@MainActor
private final class DefaultWorkoutLiveActivitySystemDriver: WorkoutLiveActivitySystemDriving {
    var areActivitiesEnabled: Bool {
        #if canImport(ActivityKit) && !os(macOS)
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        #endif
        return false
    }

    func hasRunningActivity(for sessionID: UUID) -> Bool {
        #if canImport(ActivityKit) && !os(macOS)
        guard #available(iOS 16.1, *) else { return false }
        return runningActivity(for: sessionID) != nil
        #else
        return false
        #endif
    }

    func requestActivity(
        attributes: WorkoutLiveActivityAttributes,
        state: WorkoutLiveActivityAttributes.ContentState
    ) {
        #if canImport(ActivityKit) && !os(macOS)
        guard #available(iOS 16.1, *) else { return }
        _ = try? Activity<WorkoutLiveActivityAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        #endif
    }

    func updateActivity(
        sessionID: UUID,
        state: WorkoutLiveActivityAttributes.ContentState
    ) async {
        #if canImport(ActivityKit) && !os(macOS)
        guard #available(iOS 16.1, *) else { return }
        guard let activity = runningActivity(for: sessionID) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
        #endif
    }

    func endActivity(sessionID: UUID) async {
        #if canImport(ActivityKit) && !os(macOS)
        guard #available(iOS 16.1, *) else { return }
        guard let activity = runningActivity(for: sessionID) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        #endif
    }

    func endAllActivities() async {
        #if canImport(ActivityKit) && !os(macOS)
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }

    #if canImport(ActivityKit) && !os(macOS)
    @available(iOS 16.1, *)
    private func runningActivity(
        for sessionID: UUID
    ) -> Activity<WorkoutLiveActivityAttributes>? {
        Activity<WorkoutLiveActivityAttributes>.activities
            .first { $0.attributes.sessionID == sessionID }
    }
    #endif
}
