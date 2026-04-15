//
//  ProgramWorkoutDraftBuilder.swift
//  SuggestMeSome
//
//  Shared conversion from resolved program rows into in-memory workout drafts.
//

import Foundation

struct ProgramWorkoutDraftBuilder {
    static func buildEntries(
        from exercises: [ProgramSessionExercise],
        unitProvider: (ProgramSessionExercise) -> WeightUnit
    ) -> [DraftExerciseEntry] {
        let ordered = exercises.sorted { $0.orderIndex < $1.orderIndex }
        let groups = ProgramSessionRowGroupingService.group(ordered)

        return groups.enumerated().map { index, rows in
            let anchor = rows.first(where: { !$0.isWarmup }) ?? rows[0]
            let unit = unitProvider(anchor)

            if isCardio(anchor) {
                let totalSeconds = (anchor.targetReps ?? 0) * 60
                let mins = totalSeconds / 60
                let secs = totalSeconds % 60
                return DraftExerciseEntry(
                    exerciseName: anchor.exerciseName,
                    unit: unit,
                    orderIndex: index,
                    sets: [],
                    isCardio: true,
                    cardioMinutesText: mins > 0 ? "\(mins)" : "",
                    cardioSecondsText: secs > 0 ? "\(secs)" : "",
                    sourceProgramSessionExerciseID: anchor.id,
                    prescribedTargetSets: anchor.targetSets,
                    prescribedTargetReps: anchor.targetReps,
                    prescribedTargetPercentage1RM: anchor.targetPercentage1RM,
                    prescribedTargetRPE: anchor.targetRPE,
                    prescribedTargetRIR: anchor.targetRIR,
                    prescribedWeight: anchor.prescribedWeight,
                    prescribedWeightUnit: anchor.prescribedWeightUnit,
                    prescribedWorkingSetStyle: anchor.workingSetStyle,
                    prescribedTargetEffortType: anchor.targetEffortType
                )
            }

            var setNumber = 1
            var mergedSets: [DraftSet] = []
            for row in rows {
                let rowSetCount = max(1, row.targetSets ?? (row.isWarmup ? 1 : 3))
                let repsText = row.targetReps.map { "\($0)" } ?? ""
                let weightText = formatWeight(row.prescribedWeight)
                for _ in 0..<rowSetCount {
                    mergedSets.append(
                        DraftSet(
                            setNumber: setNumber,
                            repsText: repsText,
                            weightText: weightText,
                            isWarmup: row.isWarmup,
                            isPrefilledFromPrescription: true
                        )
                    )
                    setNumber += 1
                }
            }

            return DraftExerciseEntry(
                exerciseName: anchor.exerciseName,
                unit: unit,
                orderIndex: index,
                sets: mergedSets,
                sourceProgramSessionExerciseID: anchor.id,
                prescribedTargetSets: anchor.targetSets,
                prescribedTargetReps: anchor.targetReps,
                prescribedTargetPercentage1RM: anchor.targetPercentage1RM,
                prescribedTargetRPE: anchor.targetRPE,
                prescribedTargetRIR: anchor.targetRIR,
                prescribedWeight: anchor.prescribedWeight,
                prescribedWeightUnit: anchor.prescribedWeightUnit,
                prescribedWorkingSetStyle: anchor.workingSetStyle,
                prescribedTargetEffortType: anchor.targetEffortType
            )
        }
    }

    private static func isCardio(_ row: ProgramSessionExercise) -> Bool {
        row.targetSets == nil && row.targetPercentage1RM == nil && row.targetRPE != nil
    }

    private static func formatWeight(_ w: Double?) -> String {
        guard let w, w > 0 else { return "" }
        return w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
    }
}
