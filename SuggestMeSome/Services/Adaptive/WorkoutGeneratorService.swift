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
    /// Present when this exercise replaced a preferred exercise due to equipment constraints.
    /// Example: "Dumbbell Bench Press (replaces Bench Press — dumbbell variation)"
    let substitutionNote: String?

    init(
        exercise: Exercise,
        sets: [GeneratedSet],
        effectiveTimeMinutes: Double,
        substitutionNote: String? = nil
    ) {
        self.exercise = exercise
        self.sets = sets
        self.effectiveTimeMinutes = effectiveTimeMinutes
        self.substitutionNote = substitutionNote
    }
}

struct GeneratedWorkout {
    let exercises: [GeneratedExercise]
    let totalEstimatedMinutes: Double
    let intensity: Int
    let generationType: WorkoutGenerationType
    /// Present when the session shape was adapted due to equipment constraints.
    let adaptationNote: String?
    let explanationBundle: AdaptiveExplanationBundle?

    init(
        exercises: [GeneratedExercise],
        totalEstimatedMinutes: Double,
        intensity: Int,
        generationType: WorkoutGenerationType,
        adaptationNote: String? = nil,
        explanationBundle: AdaptiveExplanationBundle? = nil
    ) {
        self.exercises = exercises
        self.totalEstimatedMinutes = totalEstimatedMinutes
        self.intensity = intensity
        self.generationType = generationType
        self.adaptationNote = adaptationNote
        self.explanationBundle = explanationBundle
    }
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
