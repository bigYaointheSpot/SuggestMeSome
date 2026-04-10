//
//  ProgramGenerationMetadata.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation

enum ProgramProgressionModel: String, Codable {
    case linear
    case dup
    case block

    var displayName: String {
        switch self {
        case .linear: return "Linear Progression"
        case .dup: return "Daily Undulating Periodization"
        case .block: return "Block Periodization"
        }
    }
}

enum ProgramProgressionPhase: String, Codable {
    case linearWorking
    case dupHeavy
    case dupModerate
    case dupLight
    case hypertrophy
    case strength
    case peaking
    case deload
}

enum ProgramTargetEffortType: String, Codable {
    case percentage1RM
    case rpe
    case rir
    case none
}

enum ProgramSessionReasonCode: String, Codable {
    case specificityExposure
    case hypertrophyVolume
    case balancedCoverage
    case enduranceBase
    case enduranceQuality
    case enduranceLong
    case enduranceRecovery
    case deloadRecovery

    var shortLabel: String {
        switch self {
        case .specificityExposure: return "Specificity"
        case .hypertrophyVolume: return "Hypertrophy Volume"
        case .balancedCoverage: return "Pattern Coverage"
        case .enduranceBase: return "Aerobic Base"
        case .enduranceQuality: return "Quality Work"
        case .enduranceLong: return "Long Endurance"
        case .enduranceRecovery: return "Recovery Endurance"
        case .deloadRecovery: return "Deload Recovery"
        }
    }
}

enum ProgramExercisePurposeCode: String, Codable {
    case specificity
    case volumeFill
    case fatigueControl
    case technique
    case recovery
    case conditioningBase
    case conditioningQuality

    var shortLabel: String {
        switch self {
        case .specificity: return "Specificity"
        case .volumeFill: return "Volume Fill"
        case .fatigueControl: return "Fatigue Control"
        case .technique: return "Technique"
        case .recovery: return "Recovery"
        case .conditioningBase: return "Base"
        case .conditioningQuality: return "Quality"
        }
    }
}

enum ProgramAccessorySelectionReason: String, Codable {
    case muscleDeficit
    case movementCoverage
    case fatigueFit
    case sessionSpecificity
    case recoveryBias
    case noveltyRotation
    case defaultRule

    var shortLabel: String {
        switch self {
        case .muscleDeficit: return "Muscle Deficit"
        case .movementCoverage: return "Coverage Gap"
        case .fatigueFit: return "Fatigue Fit"
        case .sessionSpecificity: return "Session Identity"
        case .recoveryBias: return "Recovery Bias"
        case .noveltyRotation: return "Novelty Rotation"
        case .defaultRule: return "Default Rule"
        }
    }
}

enum ProgramPrimaryAdaptationGoal: String, Codable {
    case maximalStrength
    case strengthHypertrophy
    case hypertrophy
    case balancedFitness
    case aerobicEndurance
}

enum ProgramProgressionStrategyFamily: String, Codable {
    case strengthSkill
    case mixedStrengthHypertrophy
    case hypertrophyVolume
    case balancedTraining
    case enduranceConditioning
}

enum ProgramWeeklyExposurePriority: String, Codable, CaseIterable {
    case squat
    case hinge
    case horizontalPush
    case verticalPush
    case horizontalPull
    case verticalPull
    case singleLeg
    case trunk
    case aerobicBase
    case threshold
    case interval
    case longEndurance
}

enum ProgramTopSetBackoffPolicy: String, Codable {
    case disabled
    case templateDriven
    /// Mostly straight-set programming with optional opener top/backoff on selected compounds.
    case compoundOpener
}

enum ProgramDefaultDeloadStyle: String, Codable {
    case fixedInterval
    case blockTransition
    case enduranceStepBack
}

enum ProgramRecoveryProfile: String, Codable {
    case conservative
    case moderate
    case robust
}

enum ProgramCardioSessionType: String, Codable, CaseIterable {
    case easyAerobic
    case threshold
    case interval
    case longSession
    case recovery
}

enum ProgramCardioEffortBucket: String, Codable, CaseIterable {
    case low
    case moderate
    case high
}

enum ProgramCardioProgressionMethod: String, Codable {
    /// Progress primarily via longer total session duration.
    case duration
    /// Progress by adding interval repetitions while work/rest remains mostly stable.
    case intervalCount
    /// Progress by reducing rest relative to work.
    case intervalDensity
    /// Progress by extending each work repetition duration.
    case workBlockDuration
}

struct ProgramCardioWorkRestProgression: Codable {
    let initialIntervals: Int
    let intervalStep: Int
    let stepEveryWorkingWeeks: Int
    let maxIntervals: Int
    let initialWorkSeconds: Int
    let workSecondsStep: Int
    let initialRestSeconds: Int
    let restSecondsStep: Int
}

struct ProgramCardioSessionRule: Codable {
    let sessionType: ProgramCardioSessionType
    let targetRPE: Double
    let progressionMethod: ProgramCardioProgressionMethod
    let baseDurationMinutes: Int
    let durationStepPerWorkingWeek: Int
    let deloadDurationScale: Double
    /// Used only for interval-oriented sessions.
    let workRestProgression: ProgramCardioWorkRestProgression?
}

struct ProgramCardioProgrammingProfile: Codable {
    /// Percent of total weekly endurance work by session type (0...1).
    let weeklyDistribution: [ProgramCardioSessionType: Double]
    /// Target low/moderate/high effort split (0...1), used to preserve intensity balance.
    let targetEffortDistribution: [ProgramCardioEffortBucket: Double]
    /// Session-type specific progression and effort rules.
    let sessionRules: [ProgramCardioSessionType: ProgramCardioSessionRule]
}

struct ProgramFocusProgrammingProfile: Codable {
    let focus: ProgramFocus
    let primaryAdaptationGoal: ProgramPrimaryAdaptationGoal
    let progressionStrategyFamily: ProgramProgressionStrategyFamily
    let weeklyExposurePriorities: [ProgramWeeklyExposurePriority]
    let topSetBackoffPolicy: ProgramTopSetBackoffPolicy
    let defaultDeloadStyle: ProgramDefaultDeloadStyle
    let recoveryProfile: ProgramRecoveryProfile
    let cardioProgrammingProfile: ProgramCardioProgrammingProfile?
}

enum ProgramFocusProgrammingProfileLibrary {
    static func profile(for focus: ProgramFocus) -> ProgramFocusProgrammingProfile {
        switch focus {
        case .increaseMaxSquat:
            return ProgramFocusProgrammingProfile(
                focus: focus,
                primaryAdaptationGoal: .maximalStrength,
                progressionStrategyFamily: .strengthSkill,
                weeklyExposurePriorities: [.squat, .hinge, .trunk],
                topSetBackoffPolicy: .templateDriven,
                defaultDeloadStyle: .fixedInterval,
                recoveryProfile: .moderate,
                cardioProgrammingProfile: nil
            )
        case .increaseMaxBench:
            return ProgramFocusProgrammingProfile(
                focus: focus,
                primaryAdaptationGoal: .maximalStrength,
                progressionStrategyFamily: .strengthSkill,
                weeklyExposurePriorities: [.horizontalPush, .verticalPush, .horizontalPull, .trunk],
                topSetBackoffPolicy: .templateDriven,
                defaultDeloadStyle: .fixedInterval,
                recoveryProfile: .moderate,
                cardioProgrammingProfile: nil
            )
        case .increaseMaxDeadlift:
            return ProgramFocusProgrammingProfile(
                focus: focus,
                primaryAdaptationGoal: .maximalStrength,
                progressionStrategyFamily: .strengthSkill,
                weeklyExposurePriorities: [.hinge, .squat, .trunk],
                topSetBackoffPolicy: .templateDriven,
                defaultDeloadStyle: .fixedInterval,
                recoveryProfile: .moderate,
                cardioProgrammingProfile: nil
            )
        case .powerlifting:
            return ProgramFocusProgrammingProfile(
                focus: focus,
                primaryAdaptationGoal: .maximalStrength,
                progressionStrategyFamily: .strengthSkill,
                weeklyExposurePriorities: [.squat, .horizontalPush, .hinge, .horizontalPull],
                topSetBackoffPolicy: .templateDriven,
                defaultDeloadStyle: .fixedInterval,
                recoveryProfile: .moderate,
                cardioProgrammingProfile: nil
            )
        case .generalFitness:
            return ProgramFocusProgrammingProfile(
                focus: focus,
                primaryAdaptationGoal: .balancedFitness,
                progressionStrategyFamily: .balancedTraining,
                weeklyExposurePriorities: [.squat, .hinge, .horizontalPush, .horizontalPull, .singleLeg, .trunk],
                topSetBackoffPolicy: .templateDriven,
                defaultDeloadStyle: .fixedInterval,
                recoveryProfile: .moderate,
                cardioProgrammingProfile: nil
            )
        case .fullBody:
            return ProgramFocusProgrammingProfile(
                focus: focus,
                primaryAdaptationGoal: .balancedFitness,
                progressionStrategyFamily: .balancedTraining,
                weeklyExposurePriorities: [.squat, .hinge, .horizontalPush, .verticalPush, .horizontalPull, .verticalPull, .trunk],
                topSetBackoffPolicy: .templateDriven,
                defaultDeloadStyle: .fixedInterval,
                recoveryProfile: .conservative,
                cardioProgrammingProfile: nil
            )
        case .pushPull:
            return ProgramFocusProgrammingProfile(
                focus: focus,
                primaryAdaptationGoal: .balancedFitness,
                progressionStrategyFamily: .balancedTraining,
                weeklyExposurePriorities: [.horizontalPush, .verticalPush, .horizontalPull, .verticalPull, .hinge, .singleLeg],
                topSetBackoffPolicy: .templateDriven,
                defaultDeloadStyle: .fixedInterval,
                recoveryProfile: .moderate,
                cardioProgrammingProfile: nil
            )
        case .fiveByFive:
            return ProgramFocusProgrammingProfile(
                focus: focus,
                primaryAdaptationGoal: .maximalStrength,
                progressionStrategyFamily: .strengthSkill,
                weeklyExposurePriorities: [.squat, .horizontalPush, .hinge, .horizontalPull],
                topSetBackoffPolicy: .templateDriven,
                defaultDeloadStyle: .fixedInterval,
                recoveryProfile: .moderate,
                cardioProgrammingProfile: nil
            )
        case .powerbuilding:
            return ProgramFocusProgrammingProfile(
                focus: focus,
                primaryAdaptationGoal: .strengthHypertrophy,
                progressionStrategyFamily: .mixedStrengthHypertrophy,
                weeklyExposurePriorities: [.squat, .horizontalPush, .hinge, .horizontalPull, .verticalPush, .verticalPull],
                topSetBackoffPolicy: .templateDriven,
                defaultDeloadStyle: .fixedInterval,
                recoveryProfile: .robust,
                cardioProgrammingProfile: nil
            )
        case .bodybuilding:
            return ProgramFocusProgrammingProfile(
                focus: focus,
                primaryAdaptationGoal: .hypertrophy,
                progressionStrategyFamily: .hypertrophyVolume,
                weeklyExposurePriorities: [.horizontalPush, .verticalPush, .horizontalPull, .verticalPull, .singleLeg, .trunk],
                topSetBackoffPolicy: .compoundOpener,
                defaultDeloadStyle: .fixedInterval,
                recoveryProfile: .robust,
                cardioProgrammingProfile: nil
            )
        case .cardioEndurance:
            return ProgramFocusProgrammingProfile(
                focus: focus,
                primaryAdaptationGoal: .aerobicEndurance,
                progressionStrategyFamily: .enduranceConditioning,
                weeklyExposurePriorities: [.aerobicBase, .threshold, .interval, .longEndurance],
                topSetBackoffPolicy: .disabled,
                defaultDeloadStyle: .enduranceStepBack,
                recoveryProfile: .moderate,
                cardioProgrammingProfile: ProgramCardioProgrammingProfile(
                    weeklyDistribution: [
                        .easyAerobic: 0.50,
                        .threshold: 0.20,
                        .interval: 0.10,
                        .longSession: 0.15,
                        .recovery: 0.05,
                    ],
                    targetEffortDistribution: [
                        .low: 0.80,
                        .moderate: 0.12,
                        .high: 0.08,
                    ],
                    sessionRules: [
                        .easyAerobic: .init(
                            sessionType: .easyAerobic,
                            targetRPE: 6.0,
                            progressionMethod: .duration,
                            baseDurationMinutes: 32,
                            durationStepPerWorkingWeek: 3,
                            deloadDurationScale: 0.72,
                            workRestProgression: nil
                        ),
                        .threshold: .init(
                            sessionType: .threshold,
                            targetRPE: 7.6,
                            progressionMethod: .workBlockDuration,
                            baseDurationMinutes: 30,
                            durationStepPerWorkingWeek: 2,
                            deloadDurationScale: 0.75,
                            workRestProgression: .init(
                                initialIntervals: 3,
                                intervalStep: 0,
                                stepEveryWorkingWeeks: 2,
                                maxIntervals: 4,
                                initialWorkSeconds: 360,
                                workSecondsStep: 30,
                                initialRestSeconds: 180,
                                restSecondsStep: -15
                            )
                        ),
                        .interval: .init(
                            sessionType: .interval,
                            targetRPE: 8.8,
                            progressionMethod: .intervalCount,
                            baseDurationMinutes: 22,
                            durationStepPerWorkingWeek: 1,
                            deloadDurationScale: 0.70,
                            workRestProgression: .init(
                                initialIntervals: 5,
                                intervalStep: 1,
                                stepEveryWorkingWeeks: 1,
                                maxIntervals: 9,
                                initialWorkSeconds: 120,
                                workSecondsStep: 0,
                                initialRestSeconds: 120,
                                restSecondsStep: -10
                            )
                        ),
                        .longSession: .init(
                            sessionType: .longSession,
                            targetRPE: 6.2,
                            progressionMethod: .duration,
                            baseDurationMinutes: 46,
                            durationStepPerWorkingWeek: 4,
                            deloadDurationScale: 0.74,
                            workRestProgression: nil
                        ),
                        .recovery: .init(
                            sessionType: .recovery,
                            targetRPE: 4.8,
                            progressionMethod: .duration,
                            baseDurationMinutes: 24,
                            durationStepPerWorkingWeek: 2,
                            deloadDurationScale: 0.68,
                            workRestProgression: nil
                        ),
                    ]
                )
            )
        }
    }
}
