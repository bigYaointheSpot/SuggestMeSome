import Foundation

struct SuggestMeSomeWorkoutPrescriptionService {
    let personalRecordLookupService: SuggestMeSomePersonalRecordLookupService
    let timeBudgetService: SuggestMeSomeTimeBudgetService

    // MARK: - Rep range

    private func repRange(for intensity: Int) -> ClosedRange<Int> {
        switch intensity {
        case 1: return 10...12
        case 2: return 8...10
        case 3: return 6...8
        case 4: return 4...6
        case 5: return 3...5
        default: return 8...10
        }
    }

    private func targetReps(for intensity: Int) -> Int {
        Int.random(in: repRange(for: intensity))
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
    private func workingSetCount(for goal: SuggestMeSomeGenerationGoal?) -> Int {
        switch goal {
        case .recovery: return 2
        case .conditioning: return 3
        default: return 4
        }
    }

    // MARK: - Prescription

    func prescribeStrengthExercise(
        _ exercise: Exercise,
        intensity: Int,
        goal: SuggestMeSomeGenerationGoal? = nil
    ) -> GeneratedExercise {
        let reps = targetReps(for: intensity)
        let factor = loadFactor(for: goal)
        let skipWarmups = shouldSkipWarmups(for: exercise, goal: goal)
        let workingSets = workingSetCount(for: goal)

        let sets: [GeneratedSet]

        if let (baseWeight, unit) = personalRecordLookupService.bestAvailableWeight(
            for: exercise,
            repCount: reps
        ) {
            // Apply intensity scaling and goal-aware load factor
            let heavyWorkingWeight = baseWeight * (0.75 + Double(intensity) * 0.04) * factor

            if skipWarmups {
                sets = (1...workingSets).map { i in
                    GeneratedSet(
                        setNumber: i,
                        isWarmup: false,
                        suggestedReps: reps,
                        suggestedWeight: heavyWorkingWeight * workingPercentage(setIndex: i, totalSets: workingSets),
                        unit: unit
                    )
                }
            } else {
                let warmupPercentages: [Double] = [0.40, 0.55, 0.70]
                let warmups = warmupPercentages.enumerated().map { i, pct in
                    GeneratedSet(
                        setNumber: i + 1,
                        isWarmup: true,
                        suggestedReps: reps,
                        suggestedWeight: heavyWorkingWeight * pct,
                        unit: unit
                    )
                }
                let working = (1...workingSets).map { i in
                    GeneratedSet(
                        setNumber: i,
                        isWarmup: false,
                        suggestedReps: reps,
                        suggestedWeight: heavyWorkingWeight * workingPercentage(setIndex: i, totalSets: workingSets),
                        unit: unit
                    )
                }
                sets = warmups + working
            }
        } else {
            // No usable PR data — emit nil-weight sets
            if skipWarmups {
                sets = (1...workingSets).map { i in
                    GeneratedSet(setNumber: i, isWarmup: false, suggestedReps: reps, suggestedWeight: nil, unit: .lbs)
                }
            } else {
                let warmups = (1...3).map { i in
                    GeneratedSet(setNumber: i, isWarmup: true, suggestedReps: reps, suggestedWeight: nil, unit: .lbs)
                }
                let working = (1...workingSets).map { i in
                    GeneratedSet(setNumber: i, isWarmup: false, suggestedReps: reps, suggestedWeight: nil, unit: .lbs)
                }
                sets = warmups + working
            }
        }

        return GeneratedExercise(
            exercise: exercise,
            sets: sets,
            effectiveTimeMinutes: timeBudgetService.effectiveTimeMinutes(for: exercise, intensity: intensity)
        )
    }

    func prescribeCardioExercise(_ exercise: Exercise, durationMinutes: Double) -> GeneratedExercise {
        GeneratedExercise(exercise: exercise, sets: [], effectiveTimeMinutes: durationMinutes)
    }

    // MARK: - Helpers

    /// Ramping working-set percentages: starts at 85% and climbs to 100% over the set count.
    private func workingPercentage(setIndex: Int, totalSets: Int) -> Double {
        guard totalSets > 1 else { return 1.0 }
        let step = 0.15 / Double(totalSets - 1)
        return 0.85 + step * Double(setIndex - 1)
    }
}
