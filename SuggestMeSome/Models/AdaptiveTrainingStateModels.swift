//
//  AdaptiveTrainingStateModels.swift
//  SuggestMeSome
//
//  Feature 15 Prompt 2 — shared adaptive state and dose targets.
//

import Foundation

enum TrainingStateAdherenceTier: String, Codable, CaseIterable {
    case sparseHistory
    case low
    case moderate
    case high
}

enum TrainingStateRecoveryPressure: String, Codable, CaseIterable {
    case conservative
    case neutral
    case elevated
}

enum SuggestMeSomeSessionSlotKind: String, Codable, CaseIterable {
    case anchorCompound
    case secondaryCompound
    case upperPush
    case upperPull
    case lowerPattern
    case posteriorChain
    case singleLeg
    case trunkStability
    case armAccessory
    case shoulderAccessory
    case mobilityTempo
    case cardioPrimary
    case cardioFinisher
}

enum SuggestMeSomePrescriptionStyle: String, Codable, CaseIterable {
    case strengthTopSetBackoff
    case strengthStraightSets
    case hypertrophyDoubleProgression
    case recoveryTechnique
    case conditioningIntervals
    case cardioSteadyState
}

struct TrainingStateSnapshot: Codable, Equatable {
    let historyWindowWorkoutCount: Int
    let hasSparseHistory: Bool
    let adherenceTier: TrainingStateAdherenceTier
    let recentVolumeCompletionRate: Double
    let fatigueStatus: FatigueStatus?
    let recoveryPressure: TrainingStateRecoveryPressure
    let liftMomentumByCanonicalLift: [CanonicalLift: LiftTrendStatus]
    let perMuscleStressSaturation: [ProgramVolumeMuscle: Double]
    let preferredAnchorExerciseNames: [String]
    let underusedExerciseNames: [String]
    let activeProgramInterferenceRisk: Double
    let equipmentReliabilityScore: Double
    let continuityBias: Double
    let blockedCanonicalLifts: [CanonicalLift]

    var shouldBiasRecovery: Bool {
        if activeProgramInterferenceRisk >= 0.70 { return true }
        switch fatigueStatus {
        case .high, .critical:
            return true
        default:
            return recoveryPressure == .elevated
        }
    }
}

struct DoseTargetProfile: Codable, Equatable {
    let weeklyVolumeScale: Double
    let fatigueBudgetScale: Double
    let intensityScale: Double
    let rirOffset: Double
    let sessionStressScale: Double
    let deloadIntervalOverride: Int?
    let accessoryCountAdjustment: Int
    let cardioDurationScale: Double
    let preserveAnchorBias: Double
    let interferencePenaltyScale: Double
}

struct SessionConstructionProfile: Codable, Equatable {
    let requiredSlots: [SuggestMeSomeSessionSlotKind]
    let optionalSlots: [SuggestMeSomeSessionSlotKind]
    let strengthTimeShare: Double
    let cardioTimeShare: Double
    let prioritizePreferredAnchors: Bool
    let allowAutomaticCardioAppend: Bool
    let interferencePenaltyScale: Double
    let prescriptionStyle: SuggestMeSomePrescriptionStyle
}

struct DailyProgramContext: Codable, Equatable {
    let shouldSupportActiveProgram: Bool
    let activeProgramName: String?
    let nextSessionName: String?
    let nextSessionMode: SuggestMeSomeSessionMode?
    let nextSessionAnchorExercises: [String]
    let missedMovementFamilies: [String]
    let blockedCanonicalLifts: [CanonicalLift]
    let interferenceScore: Double
}
