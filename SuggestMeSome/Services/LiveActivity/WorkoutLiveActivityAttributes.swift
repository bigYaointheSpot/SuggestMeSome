//
//  WorkoutLiveActivityAttributes.swift
//  SuggestMeSome
//
//  ActivityKit contract for the active-workout Live Activity. Shared
//  between the iOS app target (which starts/updates/ends the activity
//  via ActivityKit) and the Widget Extension target (which renders the
//  lock-screen and Dynamic Island presentations).
//
//  Keep this file dependency-free beyond Foundation + ActivityKit so it
//  can ship to the Widget Extension target by simply checking its target
//  membership box. Helpers that touch app-target types
//  (ActiveWorkoutSession, WatchPayloadMapper, DraftExerciseEntry) live
//  in the +Session.swift sibling, which stays in the main app only.
//
//  Content-state fields are kept deliberately small — each update writes
//  the whole ContentState to the system, and iOS rate-limits rapid
//  updates. ActiveWorkoutSessionStore only snapshots this when the
//  underlying session identity or current-exercise changes, not on every
//  TimelineView tick (the elapsed timer is derived from `startDate` +
//  `.timer` Text style on the widget side).
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

struct WorkoutLiveActivityAttributes: Codable, Hashable {
    /// Immutable identity for the session — set at start, matched to the
    /// ActiveWorkoutSession.id so deep-links can resolve the right
    /// workout even if multiple activities briefly overlap during
    /// start / end transitions.
    let sessionID: UUID

    /// Static label shown above the live readout ("Strength", "Cardio",
    /// "Program Workout — Week 3 Day 2"). Captured at start to avoid
    /// mutating the attributes bundle mid-flight.
    let sessionTitle: String

    struct ContentState: Codable, Hashable {
        /// Clock-face start time. The widget computes elapsed via
        /// `Text(startDate, style: .timer)` so the iOS system ticks the
        /// label — no per-second `Activity.update()` calls needed.
        var startDate: Date

        /// Paused activities freeze the timer. When true the widget
        /// renders `pausedElapsedSeconds` as a static string instead of
        /// a live timer.
        var isPaused: Bool
        var pausedElapsedSeconds: Int

        /// Header line the user sees first — current exercise name.
        var currentExerciseName: String?

        /// Single-character prefix for the compact Dynamic Island layout
        /// (e.g. "B" for Bench Press). Precomputed here so the widget
        /// view stays cheap.
        var currentExerciseInitial: String?

        /// Progress numerator / denominator — logged sets out of total
        /// sets across the whole session. Feeds the progress ring on
        /// the expanded Dynamic Island.
        var completedSetCount: Int
        var totalSetCount: Int

        /// Short human-readable next-set target ("3 × 8 @ 185 lbs",
        /// "1 × 5 RIR 2", "2 × 12"). Optional — nil means nothing
        /// queued, render as "No next set" placeholder.
        var nextSetTarget: String?

        var progressFraction: Double {
            guard totalSetCount > 0 else { return 0 }
            let raw = Double(completedSetCount) / Double(totalSetCount)
            return min(max(raw, 0), 1)
        }

        static let placeholder = ContentState(
            startDate: Date(),
            isPaused: false,
            pausedElapsedSeconds: 0,
            currentExerciseName: nil,
            currentExerciseInitial: nil,
            completedSetCount: 0,
            totalSetCount: 0,
            nextSetTarget: nil
        )
    }
}

#if canImport(ActivityKit)
extension WorkoutLiveActivityAttributes: ActivityAttributes {}
#endif

extension WorkoutLiveActivityAttributes.ContentState {
    /// First letter of the exercise name, uppercased, stripped of
    /// diacritics. Returns nil for empty / whitespace-only names so the
    /// compact Dynamic Island can fall back to a dumbbell glyph.
    ///
    /// Lives on the cross-target file because the widget preview data
    /// generator calls it directly — no app-target types needed.
    static func initialGlyph(for exerciseName: String?) -> String? {
        guard let name = exerciseName else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return String(first).folding(
            options: .diacriticInsensitive,
            locale: .current
        ).uppercased()
    }
}
