//
//  LiveWorkoutActivityController.swift
//  SuggestMeSome
//
//  Feature 14 — iPhone Live Activity lifecycle for active workouts.
//
//  Mirrors the watch bridge contract: start on `workoutLaunch`, update on
//  every `liveWorkoutSnapshot`, end on `sessionCompletion`. The surface
//  appears on the iPhone Lock Screen and in the Dynamic Island so the user
//  can glance without lifting the wrist. No-ops cleanly on OS versions or
//  devices that don't support ActivityKit.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class LiveWorkoutActivityController {
    static let shared = LiveWorkoutActivityController()

#if canImport(ActivityKit)
    private var currentActivity: Activity<LiveWorkoutActivityAttributes>?
    private var activeWorkoutID: UUID?
#endif

    func start(launch: WatchWorkoutLaunchPayload, sessionLabel: String) {
#if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let existingID = activeWorkoutID, existingID == launch.workoutID, currentActivity != nil {
            return
        }
        end()

        let attributes = LiveWorkoutActivityAttributes(workoutID: launch.workoutID)
        let state = LiveWorkoutActivityAttributes.ContentState(
            currentExerciseName: "Starting workout",
            sessionLabel: sessionLabel,
            completedExercises: 0,
            totalExercises: 0,
            completedSetsInCurrentExercise: 0,
            totalSetsInCurrentExercise: 0,
            startedAt: launch.startedAt,
            elapsedSecondsAtCapture: 0,
            capturedAt: Date()
        )
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
            activeWorkoutID = launch.workoutID
        } catch {
            // ActivityKit can reject when the system is over its live-activity
            // budget or when no widget extension is registered to render this
            // attributes type. Silent fallback: the workout still runs, the
            // phone just doesn't surface it on the Lock Screen yet.
        }
#else
        _ = launch
        _ = sessionLabel
#endif
    }

    func update(with snapshot: WatchLiveWorkoutSnapshot) {
#if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        guard let activity = currentActivity, activity.attributes.workoutID == snapshot.workoutID else { return }

        let startedAt = Date().addingTimeInterval(-TimeInterval(snapshot.elapsedSeconds))
        let state = LiveWorkoutActivityAttributes.ContentState(
            currentExerciseName: snapshot.currentExerciseName ?? snapshot.sessionLabel,
            sessionLabel: snapshot.sessionLabel,
            completedExercises: snapshot.completedExercises,
            totalExercises: snapshot.totalExercises,
            completedSetsInCurrentExercise: snapshot.completedSetsInCurrentExercise,
            totalSetsInCurrentExercise: snapshot.totalSetsInCurrentExercise,
            startedAt: startedAt,
            elapsedSecondsAtCapture: snapshot.elapsedSeconds,
            capturedAt: snapshot.capturedAt
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60 * 15))

        Task {
            await activity.update(content)
        }
#else
        _ = snapshot
#endif
    }

    func end() {
#if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        activeWorkoutID = nil
#endif
    }
}
