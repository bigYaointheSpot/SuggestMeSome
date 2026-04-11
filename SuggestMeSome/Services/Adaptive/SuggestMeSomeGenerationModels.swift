import Foundation

/// Request configuration for daily SuggestMeSome workout generation.
struct SuggestMeSomeGenerationRequest {
    let generationType: WorkoutGenerationType
    let durationMinutes: Double
    let intensity: Int
    let selectedMuscleGroups: [MuscleGroup]
    let selectedExercises: [Exercise]
    let goal: SuggestMeSomeGenerationGoal?
    let equipmentProfile: SuggestMeSomeEquipmentProfile?
    /// Session mode carried from the recommendation stage.
    /// Used by the generation service to apply mode-specific workout shaping.
    let sessionMode: SuggestMeSomeSessionMode?

    init(
        generationType: WorkoutGenerationType,
        durationMinutes: Double,
        intensity: Int,
        selectedMuscleGroups: [MuscleGroup] = [],
        selectedExercises: [Exercise] = [],
        goal: SuggestMeSomeGenerationGoal? = nil,
        equipmentProfile: SuggestMeSomeEquipmentProfile? = nil,
        sessionMode: SuggestMeSomeSessionMode? = nil
    ) {
        self.generationType = generationType
        self.durationMinutes = durationMinutes
        self.intensity = intensity
        self.selectedMuscleGroups = selectedMuscleGroups
        self.selectedExercises = selectedExercises
        self.goal = goal
        self.equipmentProfile = equipmentProfile
        self.sessionMode = sessionMode
    }
}

enum SuggestMeSomeSessionMode: String, CaseIterable, Identifiable {
    case fullBody
    case upper
    case lower
    case push
    case pull
    case armsShoulders
    case recovery
    case conditioning
    case surpriseMe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullBody: return "Full Body"
        case .upper: return "Upper"
        case .lower: return "Lower"
        case .push: return "Push"
        case .pull: return "Pull"
        case .armsShoulders: return "Arms/Shoulders"
        case .recovery: return "Recovery"
        case .conditioning: return "Conditioning"
        case .surpriseMe: return "Surprise Me"
        }
    }
}

enum SuggestMeSomeGenerationGoal: String, CaseIterable, Identifiable {
    case strength
    case hypertrophy
    case generalFitness
    case fatLoss
    case recovery
    case conditioning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: return "Strength"
        case .hypertrophy: return "Hypertrophy"
        case .generalFitness: return "General Fitness"
        case .fatLoss: return "Fat Loss"
        case .recovery: return "Recovery"
        case .conditioning: return "Conditioning"
        }
    }
}

enum SuggestMeSomeEquipmentProfile: String, CaseIterable, Identifiable {
    case fullGym
    case homeGym
    case dumbbellsOnly
    case barbellRackOnly
    case hotelGym
    case bodyweightOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullGym: return "Full Gym"
        case .homeGym: return "Home Gym"
        case .dumbbellsOnly: return "Dumbbells Only"
        case .barbellRackOnly: return "Barbell + Rack Only"
        case .hotelGym: return "Hotel Gym"
        case .bodyweightOnly: return "Bodyweight Only"
        }
    }

    var availableTags: Set<String> {
        switch self {
        case .fullGym:
            return ["barbell", "rack", "machine", "dumbbell", "cable", "bodyweight", "cardio"]
        case .homeGym:
            return ["barbell", "rack", "dumbbell", "bodyweight", "cardio"]
        case .dumbbellsOnly:
            return ["dumbbell", "bodyweight", "cardio"]
        case .barbellRackOnly:
            return ["barbell", "rack", "bodyweight"]
        case .hotelGym:
            return ["machine", "dumbbell", "bodyweight", "cardio"]
        case .bodyweightOnly:
            return ["bodyweight"]
        }
    }
}

struct SuggestMeSomeSessionConfiguration {
    var mode: SuggestMeSomeSessionMode
    var goal: SuggestMeSomeGenerationGoal
    var equipmentProfile: SuggestMeSomeEquipmentProfile
    var durationMinutes: Int
    var intensity: Int
}

struct SuggestMeSomeSessionRecommendation {
    let title: String
    let summary: String
    let rationale: String
    /// Short explainability chips surfaced in the recommendation UI.
    /// Each chip is a compact phrase (2–5 words) describing a factor that shaped this recommendation.
    let reasonChips: [String]
    /// True when the final session mode differs from the user's configured mode.
    let wasRedirected: Bool
    let mode: SuggestMeSomeSessionMode
    let goal: SuggestMeSomeGenerationGoal
    let recommendedMovementPriorities: [String]
    let candidateExerciseFamilies: [String]
    let candidateAnchorLifts: [String]
    let isBuildableIntoWorkout: Bool
    let request: SuggestMeSomeGenerationRequest?
}
