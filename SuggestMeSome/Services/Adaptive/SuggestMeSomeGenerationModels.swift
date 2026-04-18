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
    /// Optional active-program context used to support the next planned session.
    let activeProgramContext: DailyProgramContext?
    /// Optional adaptive-state override used by deterministic tests and validation paths.
    let stateSnapshotOverride: TrainingStateSnapshot?
    /// Session-local steering that shapes generation without changing persistent user settings.
    let steeringProfile: AdaptiveSteeringProfile

    init(
        generationType: WorkoutGenerationType,
        durationMinutes: Double,
        intensity: Int,
        selectedMuscleGroups: [MuscleGroup] = [],
        selectedExercises: [Exercise] = [],
        goal: SuggestMeSomeGenerationGoal? = nil,
        equipmentProfile: SuggestMeSomeEquipmentProfile? = nil,
        sessionMode: SuggestMeSomeSessionMode? = nil,
        activeProgramContext: DailyProgramContext? = nil,
        stateSnapshotOverride: TrainingStateSnapshot? = nil,
        steeringProfile: AdaptiveSteeringProfile = .balanced
    ) {
        self.generationType = generationType
        self.durationMinutes = durationMinutes
        self.intensity = intensity
        self.selectedMuscleGroups = selectedMuscleGroups
        self.selectedExercises = selectedExercises
        self.goal = goal
        self.equipmentProfile = equipmentProfile
        self.sessionMode = sessionMode
        self.activeProgramContext = activeProgramContext
        self.stateSnapshotOverride = stateSnapshotOverride
        self.steeringProfile = steeringProfile
    }
}

enum SuggestMeSomeSessionMode: String, CaseIterable, Identifiable, Codable {
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

enum SuggestMeSomeGenerationGoal: String, CaseIterable, Identifiable, Codable {
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

enum SuggestMeSomeEquipmentProfile: String, CaseIterable, Identifiable, Codable {
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
    /// Follow-through explanation connecting recent training context to this recommendation.
    let continuitySummary: String
    /// Clear "what to do next" guidance for this recommendation.
    let nextActionGuidance: String
    let recommendedMovementPriorities: [String]
    let candidateExerciseFamilies: [String]
    let candidateAnchorLifts: [String]
    let isBuildableIntoWorkout: Bool
    let request: SuggestMeSomeGenerationRequest?
    let explanationBundle: AdaptiveExplanationBundle?
}

// MARK: - Coach Context Types

/// Aggregated coaching signals passed into the SuggestMeSome recommendation stage.
///
/// All fields are optional; the recommendation service degrades gracefully when signals
/// are absent. This struct is never persisted — it is built on demand from SwiftData models.
struct SuggestMeSomeCoachContext {
    /// Latest weekly fatigue state derived from `WeeklyTrainingAnalysis`.
    let fatigueStatus: FatigueStatus?
    /// Readiness tier derived from today's `DailyCoachCheckIn`.
    let readinessTier: ReadinessTier?
    /// Whether the user flagged pain or discomfort in today's check-in.
    /// When true, the recommendation must cap intensity to 1 and force recovery mode.
    let hasPainOrDiscomfort: Bool
    /// One-line summaries of active non-destructive overlays on the current program run.
    /// Present when the coach has already approved adjustments that should carry forward.
    let activeOverlaySummaries: [String]
    /// Lightweight view of pending proposals relevant to session shaping (e.g. deload, swap).
    let pendingProposals: [SuggestMeSomeCoachContextProposal]
    /// Objective HealthKit recovery insight — medium influence only.
    /// A `.caution` status nudges intensity down by 1 but cannot override manual readiness.
    let objectiveRecoveryInsight: ObjectiveRecoveryInsight?
    /// Learned exercise preferences derived from the user's recent workout history.
    let exercisePreferences: SuggestMeSomeExercisePreferences?

    init(
        fatigueStatus: FatigueStatus? = nil,
        readinessTier: ReadinessTier? = nil,
        hasPainOrDiscomfort: Bool = false,
        activeOverlaySummaries: [String] = [],
        pendingProposals: [SuggestMeSomeCoachContextProposal] = [],
        objectiveRecoveryInsight: ObjectiveRecoveryInsight? = nil,
        exercisePreferences: SuggestMeSomeExercisePreferences? = nil
    ) {
        self.fatigueStatus = fatigueStatus
        self.readinessTier = readinessTier
        self.hasPainOrDiscomfort = hasPainOrDiscomfort
        self.activeOverlaySummaries = activeOverlaySummaries
        self.pendingProposals = pendingProposals
        self.objectiveRecoveryInsight = objectiveRecoveryInsight
        self.exercisePreferences = exercisePreferences
    }
}

/// Lightweight view of one pending adaptation proposal for SuggestMeSome shaping.
struct SuggestMeSomeCoachContextProposal {
    let proposalType: ProposalType
    let targetLiftKey: String?
    let summaryText: String
}

/// Learned exercise preference signals derived from the user's workout history.
struct SuggestMeSomeExercisePreferences {
    /// Exercise names that appeared 3 or more times in the last 30 workouts.
    /// Used to bias anchor lift selection toward familiar patterns.
    let frequentlyUsedExercises: [String]
    /// Exercise names present in overall history but absent from the last 8 sessions.
    /// Surfaced as variety candidates in candidateExerciseFamilies context.
    let underusedExercises: [String]

    init(frequentlyUsedExercises: [String] = [], underusedExercises: [String] = []) {
        self.frequentlyUsedExercises = frequentlyUsedExercises
        self.underusedExercises = underusedExercises
    }
}
