//
//  ExerciseDisplayFormatter.swift
//  SuggestMeSome
//
//  Pure formatting helpers extracted from ProgramReviewView so program
//  detail strings (sets × reps @ load, RIR/RPE, warm-up mapping fallbacks)
//  can be reused by Daily Coach previews, coach-facing views, and tests
//  without dragging in SwiftUI types.
//

import Foundation

enum ExerciseDisplayFormatter {
    /// Resolve a one-rep-max for a given exercise name, falling back to a
    /// mapped source lift + multiplier when the direct lift has never been
    /// tested. Mirrors FocusTemplateLibrary's variation mapping.
    static func resolvedOneRepMax(
        for exerciseName: String,
        oneRepMaxes: [String: (weight: Double, unit: String)]
    ) -> (weight: Double, unit: String)? {
        if let direct = oneRepMaxes[exerciseName] {
            return direct
        }

        guard
            let mapping = FocusTemplateLibrary.loadMapping(for: exerciseName),
            let sourceORM = oneRepMaxes[mapping.sourceLift]
        else {
            return nil
        }

        return (
            weight: sourceORM.weight * mapping.multiplier,
            unit: sourceORM.unit
        )
    }

    /// One-line prescription summary for a program session exercise:
    /// "3×8 @ 185 lbs (75%) · RIR 2 · -10%" etc. Cardio folds to a simple
    /// duration string. Callers pass in the latest one-rep-max map; when a
    /// generation-time weight is cached on the exercise it takes priority.
    static func exerciseDisplayText(
        exercise: ProgramSessionExercise,
        oneRepMaxes: [String: (weight: Double, unit: String)]
    ) -> String {
        // Cardio: no targetSets, targetReps holds duration in minutes
        if exercise.targetSets == nil, let mins = exercise.targetReps {
            return "\(mins) min"
        }

        let sStr = exercise.targetSets.map(String.init) ?? "—"
        let rStr = exercise.targetReps.map(String.init) ?? "—"

        if let pct = exercise.targetPercentage1RM {
            let pctInt = Int((pct * 100).rounded())

            // Prefer weight stored at generation time
            if let w = exercise.prescribedWeight, let unit = exercise.prescribedWeightUnit {
                let wStr = w == w.rounded(.towardZero)
                    ? "\(Int(w)) \(unit)"
                    : String(format: "%.1f \(unit)", w)
                var detail = "\(sStr)×\(rStr) @ \(wStr) (\(pctInt)%)"
                detail += effortSuffix(for: exercise)
                detail += backoffSuffix(for: exercise)
                return detail
            }

            // Fallback: compute from oneRepMaxes (programs generated before fix)
            // Supports mapped variation lifts when direct 1RM is unavailable.
            if let orm = resolvedOneRepMax(for: exercise.exerciseName, oneRepMaxes: oneRepMaxes) {
                let raw = pct * orm.weight
                let rounded = orm.unit == "lbs"
                    ? (raw / 5.0).rounded() * 5.0
                    : (raw / 2.5).rounded() * 2.5
                let wStr = rounded == rounded.rounded(.towardZero)
                    ? "\(Int(rounded)) \(orm.unit)"
                    : String(format: "%.1f \(orm.unit)", rounded)
                var detail = "\(sStr)×\(rStr) @ \(wStr) (\(pctInt)%)"
                detail += effortSuffix(for: exercise)
                detail += backoffSuffix(for: exercise)
                return detail
            }
            var detail = "\(sStr)×\(rStr) @ \(pctInt)%"
            detail += effortSuffix(for: exercise)
            detail += backoffSuffix(for: exercise)
            return detail
        }

        if let rir = exercise.targetRIR {
            return "\(sStr)×\(rStr) @ RIR \(formatEffortValue(rir))"
        }

        if let rpe = exercise.targetRPE {
            return "\(sStr)×\(rStr) @ RPE \(formatEffortValue(rpe))"
        }

        return "\(sStr)×\(rStr)"
    }

    // MARK: - Working-set style + explainability chips

    /// Short chip label describing how the prescribed sets should be
    /// executed — "Top Set" for a single-rep heavy working set with
    /// follow-on backoffs, "Backoff" for the percentage-drop sets
    /// themselves, "Straight Sets" for equal-load repeats, and "Cardio"
    /// when the exercise has no targetSets (cardio uses duration only).
    static func workingSetStyleLabel(for exercise: ProgramSessionExercise) -> String {
        if exercise.targetSets == nil { return "Cardio" }
        switch exercise.workingSetStyle {
        case .topSet: return "Top Set"
        case .backoff: return "Backoff"
        case .straight, .none: return "Straight Sets"
        }
    }

    /// Chip label for the exercise's programmed purpose (e.g. "Primary",
    /// "Assistance"). Returns nil when the program didn't tag the
    /// exercise — call sites should hide the chip entirely in that case
    /// rather than show an empty capsule.
    static func exercisePurposeLabel(for exercise: ProgramSessionExercise) -> String? {
        exercise.explainabilityPurpose?.shortLabel
    }

    /// Chip label for the selector's reason tag (e.g. "Rotation",
    /// "Balance"). Same nil-means-hide contract as purposeLabel.
    static func exerciseSelectionReasonLabel(for exercise: ProgramSessionExercise) -> String? {
        exercise.explainabilitySelectionReason?.shortLabel
    }

    // MARK: - Private helpers

    private static func formatEffortValue(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    private static func effortSuffix(for exercise: ProgramSessionExercise) -> String {
        if let rir = exercise.targetRIR {
            return " · RIR \(formatEffortValue(rir))"
        }
        if let rpe = exercise.targetRPE {
            return " · RPE \(formatEffortValue(rpe))"
        }
        return ""
    }

    private static func backoffSuffix(for exercise: ProgramSessionExercise) -> String {
        guard
            exercise.workingSetStyle == .backoff,
            let drop = exercise.backoffPercentageDrop
        else {
            return ""
        }
        return String(format: " · -%.0f%%", drop * 100.0)
    }
}
