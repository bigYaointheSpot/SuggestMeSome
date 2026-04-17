//
//  LiveWorkoutActivityAttributes.swift
//  SuggestMeSome
//
//  Feature 14 — Live Activity payload for iPhone Lock Screen + Dynamic Island.
//
//  Mirrors the shape of `WatchLiveWorkoutSnapshot` but trimmed to what the
//  lock-screen surface actually needs. Defined inside the main target today;
//  to render the UI, a WidgetKit Extension must declare an
//  `ActivityConfiguration` against this attributes type. See
//  `LiveWorkoutActivityWidget` below for the ready-to-host widget code.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct LiveWorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var currentExerciseName: String
        public var sessionLabel: String
        public var completedExercises: Int
        public var totalExercises: Int
        public var completedSetsInCurrentExercise: Int
        public var totalSetsInCurrentExercise: Int
        public var startedAt: Date
        public var elapsedSecondsAtCapture: Int
        public var capturedAt: Date

        public init(
            currentExerciseName: String,
            sessionLabel: String,
            completedExercises: Int,
            totalExercises: Int,
            completedSetsInCurrentExercise: Int,
            totalSetsInCurrentExercise: Int,
            startedAt: Date,
            elapsedSecondsAtCapture: Int,
            capturedAt: Date
        ) {
            self.currentExerciseName = currentExerciseName
            self.sessionLabel = sessionLabel
            self.completedExercises = completedExercises
            self.totalExercises = totalExercises
            self.completedSetsInCurrentExercise = completedSetsInCurrentExercise
            self.totalSetsInCurrentExercise = totalSetsInCurrentExercise
            self.startedAt = startedAt
            self.elapsedSecondsAtCapture = elapsedSecondsAtCapture
            self.capturedAt = capturedAt
        }
    }

    public var workoutID: UUID

    public init(workoutID: UUID) {
        self.workoutID = workoutID
    }
}
#endif
