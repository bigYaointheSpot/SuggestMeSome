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

struct ProgramCardioProgrammingProfile: Codable {
    /// Percent of total weekly endurance work by session type (0...1).
    /// This is scaffold metadata for future cardio-specific progression logic.
    let weeklyDistribution: [ProgramCardioSessionType: Double]
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
                topSetBackoffPolicy: .disabled,
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
                    ]
                )
            )
        }
    }
}
