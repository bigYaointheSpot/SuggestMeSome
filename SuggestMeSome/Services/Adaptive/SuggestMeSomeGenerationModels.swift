import Foundation

/// Request configuration for daily SuggestMeSome workout generation.
/// Future fields are intentionally additive for upcoming recommendation/equipment logic.
struct SuggestMeSomeGenerationRequest {
    let generationType: WorkoutGenerationType
    let durationMinutes: Double
    let intensity: Int
    let selectedMuscleGroups: [MuscleGroup]
    let selectedExercises: [Exercise]
    let goal: SuggestMeSomeGenerationGoal?
    let equipmentProfile: SuggestMeSomeEquipmentProfile?

    init(
        generationType: WorkoutGenerationType,
        durationMinutes: Double,
        intensity: Int,
        selectedMuscleGroups: [MuscleGroup] = [],
        selectedExercises: [Exercise] = [],
        goal: SuggestMeSomeGenerationGoal? = nil,
        equipmentProfile: SuggestMeSomeEquipmentProfile? = nil
    ) {
        self.generationType = generationType
        self.durationMinutes = durationMinutes
        self.intensity = intensity
        self.selectedMuscleGroups = selectedMuscleGroups
        self.selectedExercises = selectedExercises
        self.goal = goal
        self.equipmentProfile = equipmentProfile
    }
}

enum SuggestMeSomeGenerationGoal: String {
    case generalFitness
    case strength
    case hypertrophy
    case conditioning
}

/// Equipment profile scaffold for future filtering logic.
struct SuggestMeSomeEquipmentProfile {
    let availableTags: Set<String>

    init(availableTags: Set<String> = []) {
        self.availableTags = availableTags
    }
}
