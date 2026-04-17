import Foundation

struct SuggestMeSomeWorkoutPrescriptionService {
    let personalRecordLookupService: SuggestMeSomePersonalRecordLookupService
    let timeBudgetService: SuggestMeSomeTimeBudgetService

    private struct StrengthPrescriptionProfile {
        let style: SuggestMeSomePrescriptionStyle
        let workingSetCount: Int
        let workingReps: Int
        let backoffReps: Int
        let topSetWeightScale: Double
        let straightSetWeightScales: [Double]
        let usesTopSetBackoff: Bool
    }

    // MARK: - Goal-aware configuration

    /// Load multiplier applied to the derived working weight.
    /// Recovery sessions use a lighter load to reduce overall stress.
    private func loadFactor(for goal: SuggestMeSomeGenerationGoal?) -> Double {
        switch goal {
        case .recovery: return 0.65
        case .conditioning, .fatLoss: return 0.85
        default: return 1.0
        }
    }

    /// Returns true when warmup sets should be skipped.
    /// Warmups are skipped for recovery/conditioning goals and for
    /// accessory/isolation exercises where graduated warm-up is unnecessary.
    private func shouldSkipWarmups(
        for exercise: Exercise,
        goal: SuggestMeSomeGenerationGoal?
    ) -> Bool {
        switch goal {
        case .recovery, .conditioning:
            return true
        default:
            break
        }
        return exercise.exerciseType == .accessory || exercise.exerciseType == .isolation
    }

    /// Number of working sets to prescribe given the goal.
    private func prescriptionProfile(
        for exercise: Exercise,
        intensity: Int,
        goal: SuggestMeSomeGenerationGoal?,
        style: SuggestMeSomePrescriptionStyle?
    ) -> StrengthPrescriptionProfile {
        let resolvedStyle = style ?? defaultStyle(for: goal, exercise: exercise)

        switch resolvedStyle {
        case .strengthTopSetBackoff:
            let topReps: Int
            switch intensity {
            case 5: topReps = 3
            case 4: topReps = 4
            default: topReps = 5
            }
            return StrengthPrescriptionProfile(
                style: resolvedStyle,
                workingSetCount: exercise.exerciseType == .compound ? 4 : 3,
                workingReps: topReps,
                backoffReps: topReps + 2,
                topSetWeightScale: 0.74 + Double(intensity) * 0.045,
                straightSetWeightScales: [0.92, 0.89, 0.87],
                usesTopSetBackoff: true
            )
        case .strengthStraightSets:
            let reps = intensity >= 4 ? 5 : 6
            return StrengthPrescriptionProfile(
                style: resolvedStyle,
                workingSetCount: exercise.exerciseType == .compound ? 4 : 3,
                workingReps: reps,
                backoffReps: reps,
                topSetWeightScale: 0.72 + Double(intensity) * 0.04,
                straightSetWeightScales: [0.94, 0.97, 1.0, 1.0],
                usesTopSetBackoff: false
            )
        case .hypertrophyDoubleProgression:
            let reps: Int
            switch intensity {
            case 1: reps = 12
            case 2: reps = 10
            case 3: reps = 8
            case 4: reps = 8
            default: reps = 6
            }
            return StrengthPrescriptionProfile(
                style: resolvedStyle,
                workingSetCount: exercise.exerciseType == .compound ? 4 : 3,
                workingReps: reps,
                backoffReps: reps,
                topSetWeightScale: 0.66 + Double(intensity) * 0.035,
                straightSetWeightScales: [0.95, 0.97, 1.0, 1.0],
                usesTopSetBackoff: false
            )
        case .recoveryTechnique:
            return StrengthPrescriptionProfile(
                style: resolvedStyle,
                workingSetCount: 2,
                workingReps: 10,
                backoffReps: 10,
                topSetWeightScale: 0.62,
                straightSetWeightScales: [0.96, 1.0],
                usesTopSetBackoff: false
            )
        case .conditioningIntervals:
            return StrengthPrescriptionProfile(
                style: resolvedStyle,
                workingSetCount: exercise.exerciseType == .compound ? 3 : 2,
                workingReps: 12,
                backoffReps: 12,
                topSetWeightScale: 0.68,
                straightSetWeightScales: [0.96, 1.0, 1.0],
                usesTopSetBackoff: false
            )
        case .cardioSteadyState:
            return StrengthPrescriptionProfile(
                style: .hypertrophyDoubleProgression,
                workingSetCount: exercise.exerciseType == .compound ? 3 : 2,
                workingReps: 8,
                backoffReps: 8,
                topSetWeightScale: 0.70,
                straightSetWeightScales: [0.95, 1.0, 1.0],
                usesTopSetBackoff: false
            )
        }
    }

    private func defaultStyle(
        for goal: SuggestMeSomeGenerationGoal?,
        exercise: Exercise
    ) -> SuggestMeSomePrescriptionStyle {
        switch goal {
        case .strength:
            return exercise.exerciseType == .compound ? .strengthTopSetBackoff : .strengthStraightSets
        case .hypertrophy:
            return .hypertrophyDoubleProgression
        case .recovery:
            return .recoveryTechnique
        case .conditioning, .fatLoss:
            return .conditioningIntervals
        case .generalFitness, nil:
            return .hypertrophyDoubleProgression
        }
    }

    // MARK: - Prescription

    func prescribeStrengthExercise(
        _ exercise: Exercise,
        intensity: Int,
        goal: SuggestMeSomeGenerationGoal? = nil,
        prescriptionStyle: SuggestMeSomePrescriptionStyle? = nil
    ) -> GeneratedExercise {
        let profile = prescriptionProfile(
            for: exercise,
            intensity: intensity,
            goal: goal,
            style: prescriptionStyle
        )
        let reps = profile.workingReps
        let factor = loadFactor(for: goal)
        let skipWarmups = shouldSkipWarmups(for: exercise, goal: goal)
        let workingSetCount = profile.workingSetCount

        let sets: [GeneratedSet]

        if let (baseWeight, unit) = personalRecordLookupService.bestAvailableWeight(
            for: exercise,
            repCount: reps
        ) {
            let heavyWorkingWeight = baseWeight * profile.topSetWeightScale * factor

            if skipWarmups {
                sets = workingSets(
                    profile: profile,
                    workingSets: workingSetCount,
                    topWeight: heavyWorkingWeight,
                    unit: unit
                )
            } else {
                let warmupPercentages: [Double] = [0.40, 0.55, 0.70]
                let warmups = warmupPercentages.enumerated().map { i, pct in
                    GeneratedSet(
                        setNumber: i + 1,
                        isWarmup: true,
                        suggestedReps: profile.style == .strengthTopSetBackoff ? max(3, reps - 1) : reps,
                        suggestedWeight: heavyWorkingWeight * pct,
                        unit: unit
                    )
                }
                let working = workingSets(
                    profile: profile,
                    workingSets: workingSetCount,
                    topWeight: heavyWorkingWeight,
                    unit: unit
                )
                sets = warmups + working
            }
        } else {
            // No usable PR data — emit nil-weight sets
            if skipWarmups {
                sets = nilWeightWorkingSets(profile: profile, workingSets: workingSetCount)
            } else {
                let warmups = (1...3).map { i in
                    GeneratedSet(
                        setNumber: i,
                        isWarmup: true,
                        suggestedReps: profile.style == .strengthTopSetBackoff ? max(3, reps - 1) : reps,
                        suggestedWeight: nil,
                        unit: .lbs
                    )
                }
                let working = nilWeightWorkingSets(profile: profile, workingSets: workingSetCount)
                sets = warmups + working
            }
        }

        return GeneratedExercise(
            exercise: exercise,
            sets: sets,
            effectiveTimeMinutes: timeBudgetService.effectiveTimeMinutes(for: exercise, intensity: intensity)
        )
    }

    func prescribeCardioExercise(
        _ exercise: Exercise,
        durationMinutes: Double,
        prescriptionStyle: SuggestMeSomePrescriptionStyle = .cardioSteadyState
    ) -> GeneratedExercise {
        GeneratedExercise(exercise: exercise, sets: [], effectiveTimeMinutes: durationMinutes)
    }

    // MARK: - Helpers

    private func workingSets(
        profile: StrengthPrescriptionProfile,
        workingSets: Int,
        topWeight: Double,
        unit: WeightUnit
    ) -> [GeneratedSet] {
        if profile.usesTopSetBackoff {
            var sets: [GeneratedSet] = [
                GeneratedSet(
                    setNumber: 1,
                    isWarmup: false,
                    suggestedReps: profile.workingReps,
                    suggestedWeight: topWeight,
                    unit: unit
                )
            ]
            let backoffCount = max(0, workingSets - 1)
            for index in 0..<backoffCount {
                let scale = profile.straightSetWeightScales[min(index, profile.straightSetWeightScales.count - 1)]
                sets.append(
                    GeneratedSet(
                        setNumber: index + 2,
                        isWarmup: false,
                        suggestedReps: profile.backoffReps,
                        suggestedWeight: topWeight * scale,
                        unit: unit
                    )
                )
            }
            return sets
        }

        return (0..<workingSets).map { index in
            let scale = profile.straightSetWeightScales[min(index, profile.straightSetWeightScales.count - 1)]
            return GeneratedSet(
                setNumber: index + 1,
                isWarmup: false,
                suggestedReps: profile.workingReps,
                suggestedWeight: topWeight * scale,
                unit: unit
            )
        }
    }

    private func nilWeightWorkingSets(
        profile: StrengthPrescriptionProfile,
        workingSets: Int
    ) -> [GeneratedSet] {
        if profile.usesTopSetBackoff {
            var sets: [GeneratedSet] = [
                GeneratedSet(
                    setNumber: 1,
                    isWarmup: false,
                    suggestedReps: profile.workingReps,
                    suggestedWeight: nil,
                    unit: .lbs
                )
            ]
            let backoffCount = max(0, workingSets - 1)
            for index in 0..<backoffCount {
                sets.append(
                    GeneratedSet(
                        setNumber: index + 2,
                        isWarmup: false,
                        suggestedReps: profile.backoffReps,
                        suggestedWeight: nil,
                        unit: .lbs
                    )
                )
            }
            return sets
        }

        return (1...workingSets).map { index in
            GeneratedSet(
                setNumber: index,
                isWarmup: false,
                suggestedReps: profile.workingReps,
                suggestedWeight: nil,
                unit: .lbs
            )
        }
    }
}
