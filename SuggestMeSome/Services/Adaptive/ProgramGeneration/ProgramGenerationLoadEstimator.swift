import Foundation

struct ProgramGenerationLoadEstimator {
    private let progressionResolver = ProgramGenerationProgressionResolver()
    private let cardioPlanner = ProgramGenerationCardioPlanner()

    func estimateLoad(
        for exercise: TemplateExercise,
        focusProfile: ProgramFocusProgrammingProfile,
        level: ProgramLevel,
        schedule: ProgramGenerationWeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int,
        sessionName: String
    ) -> ProgramGenerationExerciseLoadEstimate {
        if exercise.role == .cardio {
            let cardioPrescription = cardioPlanner.resolveCardioPrescription(
                sessionName: sessionName,
                focusProfile: focusProfile,
                schedule: schedule
            )
            return ProgramGenerationExerciseLoadEstimate(
                hardSetsByMuscle: emptyMuscleTotals(),
                fatigueScore: cardioPrescription.estimatedFatigueScore,
                highFatigueScore: cardioPrescription.highFatigueScore
            )
        }

        let strategy = progressionResolver.resolveStrategy(
            focusProfile: focusProfile,
            level: level
        )
        let params = progressionResolver.computeParams(
            exercise: exercise,
            strategy: strategy,
            focusProfile: focusProfile,
            schedule: schedule,
            sessionIdx: sessionIdx,
            sessionsPerWeek: sessionsPerWeek
        )
        let effectiveWorkingSets = schedule.isDeload ? max(2, params.sets / 2) : params.sets
        let blocks = progressionResolver.buildWorkingSetBlocks(
            exercise: exercise,
            isSessionOpener: exercise.role == .primary,
            focusProfile: focusProfile,
            level: level,
            schedule: schedule,
            params: params,
            totalWorkingSets: effectiveWorkingSets
        )
        let totalWorkingSets = blocks.reduce(0) { $0 + $1.sets }
        guard totalWorkingSets > 0 else {
            return ProgramGenerationExerciseLoadEstimate(
                hardSetsByMuscle: emptyMuscleTotals(),
                fatigueScore: 0,
                highFatigueScore: 0
            )
        }

        let metadata = ProgramExerciseMetadataService.metadata(for: exercise.exerciseName)
        var hardSetsByMuscle = emptyMuscleTotals()
        for (muscle, weight) in metadata.muscleContributions {
            hardSetsByMuscle[muscle, default: 0] += Double(totalWorkingSets) * weight
        }

        let maxPct = blocks.compactMap(\.percentage1RM).max()
        let minReps = blocks.map(\.reps).min() ?? params.reps
        let hasTopSet = blocks.contains { $0.style == .topSet }
        let fatigueTier = ProgramExerciseMetadataService.fatigueTier(
            for: exercise.exerciseName,
            role: exercise.role,
            maxPercentage1RM: maxPct,
            minReps: minReps,
            hasTopSet: hasTopSet
        )

        var intensityMultiplier = 1.0
        if let maxPct {
            switch maxPct {
            case let p where p >= 0.90: intensityMultiplier += 0.25
            case let p where p >= 0.82: intensityMultiplier += 0.15
            case let p where p <= 0.65: intensityMultiplier -= 0.05
            default: break
            }
        } else if let rpe = params.rpe {
            if rpe >= 8.5 { intensityMultiplier += 0.15 }
            if rpe <= 6.5 { intensityMultiplier -= 0.05 }
        } else if let rir = params.rir {
            if rir <= 1.0 { intensityMultiplier += 0.15 }
            else if rir >= 3.0 { intensityMultiplier -= 0.08 }
        }
        if schedule.isDeload {
            intensityMultiplier *= 0.78
        }

        let setCount = Double(totalWorkingSets)
        let fatigueScore = setCount * fatigueTier.baseScorePerSet * intensityMultiplier
        let highFatigueScore = setCount * fatigueTier.highFatigueWeight * intensityMultiplier

        return ProgramGenerationExerciseLoadEstimate(
            hardSetsByMuscle: hardSetsByMuscle,
            fatigueScore: fatigueScore,
            highFatigueScore: highFatigueScore
        )
    }

    func estimateLoad(
        for exercise: ProgramSessionExercise
    ) -> ProgramGenerationExerciseLoadEstimate {
        if exercise.targetSets == nil {
            let mins = Double(exercise.targetReps ?? 0)
            let intensityPerMinute = cardioPlanner.cardioFatiguePerMinute(targetRPE: exercise.targetRPE)
            let highFatigueWeight = cardioPlanner.cardioHighFatiguePerMinute(targetRPE: exercise.targetRPE)
            return ProgramGenerationExerciseLoadEstimate(
                hardSetsByMuscle: emptyMuscleTotals(),
                fatigueScore: mins * intensityPerMinute,
                highFatigueScore: mins * highFatigueWeight
            )
        }

        let setCount = max(0, exercise.targetSets ?? 0)
        guard setCount > 0 else {
            return ProgramGenerationExerciseLoadEstimate(
                hardSetsByMuscle: emptyMuscleTotals(),
                fatigueScore: 0,
                highFatigueScore: 0
            )
        }

        let metadata = ProgramExerciseMetadataService.metadata(for: exercise.exerciseName)
        var hardSetsByMuscle = emptyMuscleTotals()
        for (muscle, weight) in metadata.muscleContributions {
            hardSetsByMuscle[muscle, default: 0] += Double(setCount) * weight
        }

        let fatigueTier = ProgramExerciseMetadataService.fatigueTier(
            for: exercise.exerciseName,
            role: .accessory,
            maxPercentage1RM: exercise.targetPercentage1RM,
            minReps: exercise.targetReps ?? 8,
            hasTopSet: exercise.workingSetStyle == .topSet
        )

        var intensityMultiplier = 1.0
        if let pct = exercise.targetPercentage1RM {
            if pct >= 0.90 { intensityMultiplier += 0.25 }
            else if pct >= 0.82 { intensityMultiplier += 0.15 }
            else if pct <= 0.65 { intensityMultiplier -= 0.05 }
        } else if let rpe = exercise.targetRPE {
            if rpe >= 8.5 { intensityMultiplier += 0.15 }
            else if rpe <= 6.5 { intensityMultiplier -= 0.05 }
        } else if let rir = exercise.targetRIR {
            if rir <= 1.0 { intensityMultiplier += 0.15 }
            else if rir >= 3.0 { intensityMultiplier -= 0.08 }
        }

        let sets = Double(setCount)
        return ProgramGenerationExerciseLoadEstimate(
            hardSetsByMuscle: hardSetsByMuscle,
            fatigueScore: sets * fatigueTier.baseScorePerSet * intensityMultiplier,
            highFatigueScore: sets * fatigueTier.highFatigueWeight * intensityMultiplier
        )
    }

    func emptyMuscleTotals() -> [ProgramVolumeMuscle: Double] {
        Dictionary(uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map { ($0, 0.0) })
    }

    func addMuscleSets(
        _ source: [ProgramVolumeMuscle: Double],
        into target: inout [ProgramVolumeMuscle: Double]
    ) {
        for muscle in ProgramVolumeMuscle.allCases {
            target[muscle, default: 0] += source[muscle] ?? 0
        }
    }

    func isDeadliftHeavySession(_ sessionDef: SessionDefinition) -> Bool {
        sessionDef.primaryExercises.contains { exercise in
            let lower = exercise.exerciseName.lowercased()
            return lower.contains(CanonicalLift.deadlift.rawValue) || lower.contains("block pull")
        }
    }
}
