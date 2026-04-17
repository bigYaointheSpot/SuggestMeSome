import Foundation
import SwiftData

enum SessionOutcomeHistoryLoader {
    static func loadHistoricalEntries(
        for workout: Workout,
        context: ModelContext
    ) -> [ExerciseEntry] {
        let workoutID = workout.id
        let workoutDate = workout.date
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> {
                $0.id != workoutID && $0.date < workoutDate
            },
            sortBy: [SortDescriptor(\Workout.date, order: .reverse)]
        )

        return ((try? context.fetch(descriptor)) ?? []).flatMap(\.exerciseEntries)
    }

    static func sortedStrengthEntries(for workout: Workout) -> [ExerciseEntry] {
        workout.exerciseEntries
            .filter { !$0.isCardio }
            .sorted {
                if $0.orderIndex == $1.orderIndex {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.orderIndex < $1.orderIndex
            }
    }

    static func validLoggedSets(for entry: ExerciseEntry) -> [SetEntry] {
        entry.sets
            .filter { $0.reps > 0 && $0.weight > 0 }
            .sorted { $0.setNumber < $1.setNumber }
    }
}
