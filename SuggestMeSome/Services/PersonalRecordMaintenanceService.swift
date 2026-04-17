import Foundation
import SwiftData

@MainActor
enum PersonalRecordMaintenanceService {
    static func deleteWorkout(_ workout: Workout, context: ModelContext) throws {
        try deleteWorkouts([workout], context: context)
    }

    static func deleteWorkouts(_ workouts: [Workout], context: ModelContext) throws {
        guard !workouts.isEmpty else { return }

        let affectedExerciseNames = exerciseNames(in: workouts)
        for workout in workouts {
            context.delete(workout)
        }
        try context.save()

        try recomputePRs(for: affectedExerciseNames, context: context)
        try context.save()
    }

    static func recomputePRs(
        for exerciseNames: Set<String>,
        context: ModelContext
    ) throws {
        guard !exerciseNames.isEmpty else { return }

        let existingPRs = (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? []
        for pr in existingPRs where exerciseNames.contains(pr.exerciseName) {
            context.delete(pr)
        }

        let allWorkouts = (try? context.fetch(
            FetchDescriptor<Workout>(
                sortBy: [
                    SortDescriptor(\Workout.date, order: .forward),
                    SortDescriptor(\Workout.startTime, order: .forward),
                ]
            )
        )) ?? []

        struct PRKey: Hashable {
            let exerciseName: String
            let repCount: Int
        }

        typealias Candidate = (weight: Double, unit: WeightUnit, date: Date, setEntry: SetEntry)
        var best: [PRKey: Candidate] = [:]

        for workout in allWorkouts {
            for entry in workout.exerciseEntries {
                guard exerciseNames.contains(entry.exerciseName) else { continue }
                for set in entry.sets {
                    set.isPR = false
                    guard set.reps > 0, set.weight > 0 else { continue }

                    let key = PRKey(exerciseName: entry.exerciseName, repCount: set.reps)
                    let newWeightLbs = inLbs(set.weight, unit: entry.unit)

                    if let current = best[key] {
                        if newWeightLbs > inLbs(current.weight, unit: current.unit) {
                            best[key] = (set.weight, entry.unit, workout.date, set)
                        }
                    } else {
                        best[key] = (set.weight, entry.unit, workout.date, set)
                    }
                }
            }
        }

        for (key, candidate) in best {
            let pr = PersonalRecord(
                exerciseName: key.exerciseName,
                repCount: key.repCount,
                weight: candidate.weight,
                unit: candidate.unit,
                dateAchieved: candidate.date
            )
            context.insert(pr)
            candidate.setEntry.isPR = true
        }
    }

    static func clearAllPRData(context: ModelContext) throws {
        let existingPRs = (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? []
        for pr in existingPRs {
            context.delete(pr)
        }

        let allSets = (try? context.fetch(FetchDescriptor<SetEntry>())) ?? []
        for set in allSets where set.isPR {
            set.isPR = false
        }

        try context.save()
    }

    static func exerciseNames(in workouts: [Workout]) -> Set<String> {
        Set(workouts.flatMap { $0.exerciseEntries.map(\.exerciseName) })
    }

    private static func inLbs(_ weight: Double, unit: WeightUnit) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }
}
