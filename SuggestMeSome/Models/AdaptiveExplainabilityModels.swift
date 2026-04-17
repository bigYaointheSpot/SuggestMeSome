//
//  AdaptiveExplainabilityModels.swift
//  SuggestMeSome
//
//  Feature 15 Prompt 3 — shared explainability and light steering models.
//

import Foundation

enum AdaptiveProgressionBias: String, Codable, CaseIterable, Identifiable {
    case conservative
    case balanced
    case push

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conservative: return "Conservative"
        case .balanced: return "Balanced"
        case .push: return "Push"
        }
    }

    var effectSummary: String {
        switch self {
        case .conservative:
            return "Uses smaller stress jumps and more recovery margin."
        case .balanced:
            return "Keeps normal progression ramps."
        case .push:
            return "Presses progression harder when guardrails allow it."
        }
    }
}

enum AdaptiveRecoveryBias: String, Codable, CaseIterable, Identifiable {
    case protectRecovery
    case balanced
    case trainThrough

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protectRecovery: return "Protect Recovery"
        case .balanced: return "Balanced"
        case .trainThrough: return "Train Through"
        }
    }

    var effectSummary: String {
        switch self {
        case .protectRecovery:
            return "Keeps more reps in reserve and trims session stress sooner."
        case .balanced:
            return "Leaves recovery shaping to the adaptive defaults."
        case .trainThrough:
            return "Allows slightly more stress before stepping back, within safety caps."
        }
    }
}

enum AdaptiveContinuityBias: String, Codable, CaseIterable, Identifiable {
    case preserveAnchors
    case balanced
    case rotateMore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preserveAnchors: return "Preserve Anchors"
        case .balanced: return "Balanced"
        case .rotateMore: return "Rotate More"
        }
    }

    var effectSummary: String {
        switch self {
        case .preserveAnchors:
            return "Sticks closer to familiar lifts and recent anchors."
        case .balanced:
            return "Keeps the default continuity vs novelty mix."
        case .rotateMore:
            return "Invites more underused movements when the session can support it."
        }
    }
}

struct AdaptiveSteeringProfile: Codable, Equatable {
    let progressionBias: AdaptiveProgressionBias
    let recoveryBias: AdaptiveRecoveryBias
    let continuityBias: AdaptiveContinuityBias

    static let balanced = AdaptiveSteeringProfile(
        progressionBias: .balanced,
        recoveryBias: .balanced,
        continuityBias: .balanced
    )

    init(
        progressionBias: AdaptiveProgressionBias = .balanced,
        recoveryBias: AdaptiveRecoveryBias = .balanced,
        continuityBias: AdaptiveContinuityBias = .balanced
    ) {
        self.progressionBias = progressionBias
        self.recoveryBias = recoveryBias
        self.continuityBias = continuityBias
    }

    var isBalanced: Bool {
        self == .balanced
    }
}

enum AdaptiveGovernanceLevel: String, Codable {
    case automatic
    case reviewRequired

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .reviewRequired: return "Review Required"
        }
    }
}

enum AdaptiveExplanationCategory: String, Codable {
    case nextBlockRecommendation
    case programGeneration
    case dailyRecommendation
    case dailySession
}

enum AdaptiveReasonCode: String, Codable, CaseIterable {
    case sparseHistoryFallback
    case highAdherence
    case lowAdherence
    case fatigueProtection
    case activeProgramProtection
    case continuityCarryForward
    case acceptedContinuityHistory
    case declinedContinuityHistory
    case preferredAnchorPreserved
    case underusedRotation
    case missedMovementBackfill
    case equipmentFit
    case volumeScaledDown
    case volumeScaledUp
    case intensityScaledDown
    case intensityScaledUp
    case deloadAdvanced
    case minimumExposureGuardrail
    case interferenceGuardrail
    case recoveryCapGuardrail
    case cardioDistributionGuardrail
    case progressionBiasConservative
    case progressionBiasPush
    case recoveryBiasProtect
    case recoveryBiasTrainThrough
    case continuityBiasPreserve
    case continuityBiasRotate

    var shortLabel: String {
        switch self {
        case .sparseHistoryFallback: return "Low-Data Fallback"
        case .highAdherence: return "Strong Adherence"
        case .lowAdherence: return "Consistency Friction"
        case .fatigueProtection: return "Fatigue Protection"
        case .activeProgramProtection: return "Program Protection"
        case .continuityCarryForward: return "Carry Forward"
        case .acceptedContinuityHistory: return "Accepted History"
        case .declinedContinuityHistory: return "Declined History"
        case .preferredAnchorPreserved: return "Anchor Continuity"
        case .underusedRotation: return "Novelty Rotation"
        case .missedMovementBackfill: return "Coverage Backfill"
        case .equipmentFit: return "Equipment Fit"
        case .volumeScaledDown: return "Volume Down"
        case .volumeScaledUp: return "Volume Up"
        case .intensityScaledDown: return "Intensity Down"
        case .intensityScaledUp: return "Intensity Up"
        case .deloadAdvanced: return "Earlier Step-Back"
        case .minimumExposureGuardrail: return "Exposure Floor"
        case .interferenceGuardrail: return "Interference Guardrail"
        case .recoveryCapGuardrail: return "Recovery Guardrail"
        case .cardioDistributionGuardrail: return "Cardio Guardrail"
        case .progressionBiasConservative: return "Conservative Bias"
        case .progressionBiasPush: return "Push Bias"
        case .recoveryBiasProtect: return "Recovery Bias"
        case .recoveryBiasTrainThrough: return "Train-Through Bias"
        case .continuityBiasPreserve: return "Preserve Bias"
        case .continuityBiasRotate: return "Rotate Bias"
        }
    }
}

struct AdaptiveAdjustment: Codable, Equatable, Identifiable {
    let key: String
    let title: String
    let baseValue: String
    let personalizedValue: String
    let reasonCodes: [AdaptiveReasonCode]
    let guardrailsApplied: [String]

    var id: String { key }
}

struct AdaptiveCarryForwardSource: Codable, Equatable, Identifiable {
    let key: String
    let title: String
    let detail: String

    var id: String { key }
}

struct AdaptiveSteeringPreview: Codable, Equatable, Identifiable {
    let key: String
    let title: String
    let effectText: String
    let governance: AdaptiveGovernanceLevel

    var id: String { key }
}

struct AdaptiveExplanationBundle: Codable, Equatable {
    let category: AdaptiveExplanationCategory
    let summary: String
    let topReasons: [AdaptiveReasonCode]
    let adjustments: [AdaptiveAdjustment]
    let protectedConstraints: [String]
    let carryForwardSources: [AdaptiveCarryForwardSource]
    let governance: AdaptiveGovernanceLevel
    let steeringPreview: [AdaptiveSteeringPreview]

    var topReasonLabels: [String] {
        topReasons.map(\.shortLabel)
    }
}
