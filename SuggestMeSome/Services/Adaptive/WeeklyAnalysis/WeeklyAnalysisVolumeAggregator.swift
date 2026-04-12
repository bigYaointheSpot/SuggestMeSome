import Foundation

enum WeeklyAnalysisVolumeAggregator {
    static func completedVolume(from workouts: [Workout]) -> (
        completedHardSetsByMuscle: [ProgramVolumeMuscle: Double],
        weightedHardSetsByMuscle: [ProgramVolumeMuscle: Double],
        totalCompletedHardSets: Double,
        totalCompletedTonnageLbs: Double
    ) {
        var completedHardSetsByMuscle = Dictionary(uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map { ($0, 0.0) })
        var weightedHardSetsByMuscle = Dictionary(uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map { ($0, 0.0) })
        var totalCompletedHardSets = 0.0
        var totalCompletedTonnageLbs = 0.0

        for workout in workouts {
            let sourceWeight = workout.programRun == nil
                ? AdaptiveSignalWeights.standaloneWorkout
                : AdaptiveSignalWeights.programWorkout

            for entry in workout.exerciseEntries where !entry.isCardio {
                let validSets = entry.sets.filter { $0.reps > 0 && $0.weight > 0 }
                guard !validSets.isEmpty else { continue }

                let hardSets = Double(validSets.count)
                totalCompletedHardSets += hardSets
                totalCompletedTonnageLbs += validSets.reduce(0.0) { partial, set in
                    partial + (Double(set.reps) * inLbs(set.weight, unit: entry.unit))
                }

                let contributions = ProgramExerciseMetadataService.metadata(for: entry.exerciseName).muscleContributions
                for (muscle, contribution) in contributions {
                    let setsForMuscle = hardSets * contribution
                    completedHardSetsByMuscle[muscle, default: 0] += setsForMuscle
                    weightedHardSetsByMuscle[muscle, default: 0] += setsForMuscle * sourceWeight
                }
            }
        }

        return (
            completedHardSetsByMuscle: completedHardSetsByMuscle,
            weightedHardSetsByMuscle: weightedHardSetsByMuscle,
            totalCompletedHardSets: totalCompletedHardSets,
            totalCompletedTonnageLbs: totalCompletedTonnageLbs
        )
    }

    static func plannedVolumeByMuscle(
        program: TrainingProgram,
        weekNumber: Int
    ) -> [ProgramVolumeMuscle: Double] {
        guard let week = program.weeks.first(where: { $0.weekNumber == weekNumber }) else { return [:] }

        var totals = Dictionary(uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map { ($0, 0.0) })

        for session in week.sessions {
            for exercise in session.exercises where !exercise.isWarmup {
                let setCount = Double(max(0, exercise.targetSets ?? 0))
                guard setCount > 0 else { continue }

                let contributions = ProgramExerciseMetadataService.metadata(for: exercise.exerciseName).muscleContributions
                for (muscle, contribution) in contributions {
                    totals[muscle, default: 0] += setCount * contribution
                }
            }
        }

        return totals
    }

    private static func inLbs(_ weight: Double, unit: WeightUnit) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }
}
