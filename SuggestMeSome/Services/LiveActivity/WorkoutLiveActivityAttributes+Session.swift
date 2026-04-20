//
//  WorkoutLiveActivityAttributes+Session.swift
//  SuggestMeSome
//
//  Main-app-only extensions on `WorkoutLiveActivityAttributes.ContentState`
//  that derive a snapshot from the live `ActiveWorkoutSession`. Kept in
//  a sibling file because they reference types
//  (ActiveWorkoutSession, DraftExerciseEntry, WatchPayloadMapper,
//  WeightUnit) that only exist in the main app target — the Widget
//  Extension builds against `WorkoutLiveActivityAttributes.swift`
//  without dragging those dependencies in.
//

import Foundation

extension WorkoutLiveActivityAttributes.ContentState {
    /// Derive a ContentState from the live session snapshot. Centralized
    /// here so the controller and any future callers compute the same
    /// values — especially the completed-set predicate (which must match
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
