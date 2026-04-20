//
//  WorkoutLiveActivityAttributes.swift
//  SuggestMeSome
//
//  ActivityKit contract for the active-workout Live Activity. Shared
//  between the iOS app target (which starts/updates/ends the activity
//  via ActivityKit) and a future Widget Extension target (which renders
//  the lock-screen and Dynamic Island presentations).
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
    /// Derive a ContentState from the live session snapshot. Centralized
    /// here so the controller and any future callers compute the same
    /// values — especially the `currentExerciseInitial` transformation
    /// and the completed-set predicate (which must match
    /// WatchPayloadMapper.isSetLogged for consistency with the Watch
    /// companion's progress reporting).
    static func fromSession(
        _ session: ActiveWorkoutSession,
        now: Date = .now
    ) -> Self {
        let currentEntry = session.exerciseEntries.first { entry in
            !WatchPayloadMapper.isExerciseComplete(entry)
        } ?? session.exerciseEntries.last

        let completedSets = session.exerciseEntries.reduce(0) { running, entry in
            running + entry.sets.filter { WatchPayloadMapper.isSetLogged($0) }.count
        }
        let totalSets = session.exerciseEntries.reduce(0) { running, entry in
            running + entry.sets.count
        }

        return Self(
            startDate: session.startTime,
            isPaused: session.lifecycleState == .paused,
            pausedElapsedSeconds: session.elapsedSeconds(at: now),
            currentExerciseName: currentEntry?.exerciseName,
            currentExerciseInitial: Self.initialGlyph(for: currentEntry?.exerciseName),
            completedSetCount: completedSets,
            totalSetCount: totalSets,
            nextSetTarget: Self.nextSetTarget(in: session)
        )
    }

    /// First letter of the exercise name, uppercased, stripped of
    /// diacritics. Returns nil for empty / whitespace-only names so the
    /// compact Dynamic Island can fall back to a dumbbell glyph.
    static func initialGlyph(for exerciseName: String?) -> String? {
        guard let name = exerciseName else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return String(first).folding(
            options: .diacriticInsensitive,
            locale: .current
        ).uppercased()
    }

    /// Compact human-readable target for the next pending strength set —
    /// "Set 3/8 · 8 × 185 lbs", "Set 1/1 · 10 reps" for bodyweight, nil
    /// when the session is fully logged or only cardio remains (cardio
    /// has no per-set progression, so we fall back to the title line).
    static func nextSetTarget(in session: ActiveWorkoutSession) -> String? {
        for entry in session.exerciseEntries {
            if entry.isCardio { continue }
            if let pendingIndex = entry.sets.firstIndex(where: { !WatchPayloadMapper.isSetLogged($0) }) {
                let set = entry.sets[pendingIndex]
                let reps = set.repsText.isEmpty ? "–" : set.repsText
                let weight = set.weightText.isEmpty ? nil : "\(set.weightText) \(entry.unit.rawValue)"
                let setNumber = pendingIndex + 1
                let totalSets = entry.sets.count
                if let weight {
                    return "Set \(setNumber)/\(totalSets) · \(reps) × \(weight)"
                }
                return "Set \(setNumber)/\(totalSets) · \(reps) reps"
            }
        }
        return nil
    }
}
