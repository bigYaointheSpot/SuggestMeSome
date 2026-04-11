import Foundation
import SwiftData

struct SuggestMeSomePersonalRecordLookupService {
    let context: ModelContext

    // MARK: - Direct lookup

    func personalRecord(for exercise: Exercise, repCount: Int) -> PersonalRecord? {
        personalRecord(forName: exercise.name, repCount: repCount)
    }

    func personalRecord(forName name: String, repCount: Int) -> PersonalRecord? {
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseName == name && $0.repCount == repCount }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - Best available weight (direct → variation mapping → canonical family)

    /// Returns the best available (weight, unit) pair for load prescription.
    ///
    /// Resolution order:
    /// 1. Direct PR for this exercise + repCount
    /// 2. Variation load mapping: if `FocusTemplateLibrary.loadMapping(for:)` has a source lift,
    ///    look up the source lift PR and apply the multiplier (e.g. Front Squat → Back Squats × 0.85)
    /// 3. Canonical lift primary variation: look up the first variation name in the canonical
    ///    lift family and apply a conservative 0.90 multiplier as a last-resort estimate
    func bestAvailableWeight(
        for exercise: Exercise,
        repCount: Int
    ) -> (weight: Double, unit: WeightUnit)? {
        // 1. Direct PR
        if let pr = personalRecord(for: exercise, repCount: repCount) {
            return (pr.weight, pr.unit)
        }

        // 2. Variation load mapping (FocusTemplateLibrary)
        if let mapping = FocusTemplateLibrary.loadMapping(for: exercise.name),
           let sourcePR = personalRecord(forName: mapping.sourceLift, repCount: repCount) {
            return (sourcePR.weight * mapping.multiplier, sourcePR.unit)
        }

        // 3. Canonical lift family: use the primary variation's PR with a conservative multiplier
        if let canonical = CanonicalLift.from(exerciseName: exercise.name) {
            let primaryName = canonical.variationNames.first ?? ""
            guard primaryName != exercise.name,
                  let primaryPR = personalRecord(forName: primaryName, repCount: repCount) else {
                return nil
            }
            // Use the explicit multiplier if available; otherwise apply a conservative 0.90 fallback
            let multiplier = FocusTemplateLibrary.loadMapping(for: exercise.name)?.multiplier ?? 0.90
            return (primaryPR.weight * multiplier, primaryPR.unit)
        }

        return nil
    }
}
