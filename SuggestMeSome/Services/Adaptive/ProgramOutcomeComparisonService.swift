//
//  ProgramOutcomeComparisonService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation

struct ProgramOutcomeComparison {
    let exerciseEntryID: UUID
    let sourceProgramSessionExerciseID: UUID
    let prescribedSets: Int?
    let completedSetCount: Int
    let prescribedReps: Int?
    let completedAverageReps: Double?
    let prescribedWeight: Double?
    let completedAverageWeight: Double?
}

enum ProgramOutcomeComparisonService {
    static func buildComparison(for entry: ExerciseEntry) -> ProgramOutcomeComparison? {
        guard let sourceID = entry.sourceProgramSessionExerciseID else { return nil }

        let nonZeroSets = entry.sets.filter { $0.reps > 0 && $0.weight > 0 }
        let avgReps = nonZeroSets.isEmpty
            ? nil
            : nonZeroSets.map { Double($0.reps) }.reduce(0, +) / Double(nonZeroSets.count)
        let avgWeight = nonZeroSets.isEmpty
            ? nil
            : nonZeroSets.map(\.weight).reduce(0, +) / Double(nonZeroSets.count)

        return ProgramOutcomeComparison(
            exerciseEntryID: entry.id,
            sourceProgramSessionExerciseID: sourceID,
            prescribedSets: entry.prescribedTargetSets,
            completedSetCount: entry.sets.count,
            prescribedReps: entry.prescribedTargetReps,
            completedAverageReps: avgReps,
            prescribedWeight: entry.prescribedWeight,
            completedAverageWeight: avgWeight
        )
    }
}
