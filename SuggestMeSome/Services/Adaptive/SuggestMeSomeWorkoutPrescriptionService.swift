import Foundation

struct SuggestMeSomeWorkoutPrescriptionService {
    let personalRecordLookupService: SuggestMeSomePersonalRecordLookupService
    let timeBudgetService: SuggestMeSomeTimeBudgetService

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

    func prescribeStrengthExercise(_ exercise: Exercise, intensity: Int) -> GeneratedExercise {
        let reps = targetReps(for: intensity)

        let sets: [GeneratedSet]
        if let pr = personalRecordLookupService.personalRecord(for: exercise, repCount: reps) {
            let heavyWorkingWeight = pr.weight * (0.75 + Double(intensity) * 0.04)
            let unit = pr.unit

            let warmupPercentages: [Double] = [0.40, 0.55, 0.70]
            let workingPercentages: [Double] = [0.85, 0.90, 0.95, 1.00]

            let warmups = warmupPercentages.enumerated().map { i, pct in
                GeneratedSet(
                    setNumber: i + 1,
                    isWarmup: true,
                    suggestedReps: reps,
                    suggestedWeight: heavyWorkingWeight * pct,
                    unit: unit
                )
            }
            let working = workingPercentages.enumerated().map { i, pct in
                GeneratedSet(
                    setNumber: i + 1,
                    isWarmup: false,
                    suggestedReps: reps,
                    suggestedWeight: heavyWorkingWeight * pct,
                    unit: unit
                )
            }
            sets = warmups + working
        } else {
            let warmups = (1...3).map { i in
                GeneratedSet(setNumber: i, isWarmup: true, suggestedReps: reps, suggestedWeight: nil, unit: .lbs)
            }
            let working = (1...4).map { i in
                GeneratedSet(setNumber: i, isWarmup: false, suggestedReps: reps, suggestedWeight: nil, unit: .lbs)
            }
            sets = warmups + working
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
}
