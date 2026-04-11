import Foundation
import SwiftData

// MARK: - Output Types

enum WorkoutGenerationType {
    case custom
    case fullBody
}

struct GeneratedSet {
    let setNumber: Int
    let isWarmup: Bool
    let suggestedReps: Int
    let suggestedWeight: Double?
    let unit: WeightUnit
}

struct GeneratedExercise {
    let exercise: Exercise
    let sets: [GeneratedSet]
    let effectiveTimeMinutes: Double
}

struct GeneratedWorkout {
    let exercises: [GeneratedExercise]
    let totalEstimatedMinutes: Double
    let intensity: Int
    let generationType: WorkoutGenerationType
}

// MARK: - Compatibility Adapter
/// Legacy adapter retained for existing call sites while generation logic
/// now lives in `SuggestMeSomeGenerationService` and focused generator-domain services.
struct WorkoutGeneratorService {
    let context: ModelContext

    func generateCustomWorkout(
        muscleGroups: [MuscleGroup],
        selectedExercises: [Exercise],
        durationMinutes: Double,
        intensity: Int
    ) -> GeneratedWorkout {
        let request = SuggestMeSomeGenerationRequest(
            generationType: .custom,
            durationMinutes: durationMinutes,
            intensity: intensity,
            selectedMuscleGroups: muscleGroups,
            selectedExercises: selectedExercises
        )
        return SuggestMeSomeGenerationService(context: context).generateWorkout(request: request)
    }

    func generateFullBodyWorkout(durationMinutes: Double, intensity: Int) -> GeneratedWorkout {
        let request = SuggestMeSomeGenerationRequest(
            generationType: .fullBody,
            durationMinutes: durationMinutes,
            intensity: intensity
        )
        return SuggestMeSomeGenerationService(context: context).generateWorkout(request: request)
    }
}
