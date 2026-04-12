import Foundation

struct ProgramGenerationProgressionStrategy {
    let family: ProgramProgressionStrategyFamily
    let level: ProgramLevel
}

enum ProgramGenerationAdvancedPhaseType {
    case hypertrophy
    case strength
    case peaking

    var percentageAnchorAdjustmentRange: (start: Double, end: Double) {
        switch self {
        case .hypertrophy: return (-0.08, -0.03)
        case .strength: return (-0.02, 0.03)
        case .peaking: return (0.04, 0.08)
        }
    }

    var repRange: (min: Int, max: Int) {
        switch self {
        case .hypertrophy: return (8, 12)
        case .strength: return (4, 6)
        case .peaking: return (1, 3)
        }
    }

    var defaultSets: Int {
        switch self {
        case .hypertrophy: return 4
        case .strength, .peaking: return 5
        }
    }

    var rpeAnchorOffset: Double {
        switch self {
        case .hypertrophy: return 0.0
        case .strength: return 0.5
        case .peaking: return 1.0
        }
    }

    var midReps: Int {
        let range = repRange
        return (range.min + range.max + 1) / 2
    }
}

struct ProgramGenerationWeekSchedule {
    let weekNumber: Int
    let isDeload: Bool
    /// 0-based count of completed working weeks used to drive linear progression.
    /// Deload weeks carry the same index as the preceding working week.
    let progressionIndex: Int
    /// Active phase for advanced periodization (carries previous phase through deload weeks).
    let advancedPhase: ProgramGenerationAdvancedPhaseType?
    /// 0-based week within the current phase, used for % interpolation.
    let phaseWeekIndex: Int
    /// Total working weeks in the current phase.
    let phaseLength: Int
}

struct ProgramGenerationExerciseParams {
    let sets: Int
    let reps: Int
    let percentage1RM: Double?
    let rpe: Double?
    let rir: Double?
}

struct ProgramGenerationWorkingSetBlock {
    let style: ProgramWorkingSetStyle
    let sets: Int
    let reps: Int
    let percentage1RM: Double?
    let rpe: Double?
    let rir: Double?
    let backoffDrop: Double?
}

struct ProgramGenerationPrescribedLoadContext {
    let prescribedWeight: Double?
    let prescribedWeightUnit: String?
    let baseLiftUsed: String?
    let effectiveOneRepMax: Double?
    let effectiveOneRepMaxUnit: String?
    let usedMappedSourceLift: Bool
}

struct ProgramGenerationCardioPrescription {
    let minutes: Int
    let targetRPE: Double
    let estimatedFatigueScore: Double
    let highFatigueScore: Double
}

struct ProgramGenerationExerciseLoadEstimate {
    let hardSetsByMuscle: [ProgramVolumeMuscle: Double]
    let fatigueScore: Double
    let highFatigueScore: Double
}

struct ProgramGenerationSelectedAccessory {
    let exercise: TemplateExercise
    let reason: ProgramAccessorySelectionReason
}
