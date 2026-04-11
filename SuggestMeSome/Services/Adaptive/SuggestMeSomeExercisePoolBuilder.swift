import Foundation
import SwiftData

struct SuggestMeSomeExercisePoolBuilder {
    struct ExercisePools {
        let strength: [Exercise]
        let cardio: [Exercise]
    }

    let context: ModelContext

    func buildCustomPools(
        muscleGroups: [MuscleGroup],
        selectedExercises: [Exercise]
    ) -> ExercisePools {
        var seenIDs: Set<PersistentIdentifier> = []
        var strength: [Exercise] = []
        var cardio: [Exercise] = []

        for group in muscleGroups {
            for exercise in group.exercises where !seenIDs.contains(exercise.persistentModelID) {
                if exercise.exerciseType == .cardio { cardio.append(exercise) }
                else { strength.append(exercise) }
                seenIDs.insert(exercise.persistentModelID)
            }
        }

        for exercise in selectedExercises where !seenIDs.contains(exercise.persistentModelID) {
            if exercise.exerciseType == .cardio { cardio.append(exercise) }
            else { strength.append(exercise) }
            seenIDs.insert(exercise.persistentModelID)
        }

        return ExercisePools(strength: strength, cardio: cardio)
    }

    func fetchAllNonCardioGroups() -> [MuscleGroup] {
        let descriptor = FetchDescriptor<MuscleGroup>()
        let allGroups = (try? context.fetch(descriptor)) ?? []
        return allGroups.filter { $0.name.lowercased() != "cardio" }
    }
}
