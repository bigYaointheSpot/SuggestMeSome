//
//  MesocycleReviewTypes.swift
//  SuggestMeSome
//
//  Feature 13 — Non-persisted payoff-layer value types for completed blocks.
//

import Foundation

enum MesocyclePerformanceHighlightKind: String, Codable {
    case completion
    case personalRecord
    case liftMomentum
    case exerciseConsistency
    case standaloneSupport
}

enum MesocycleFrictionSignalKind: String, Codable {
    case sparseProgramData
    case missedPlannedSessions
    case duplicateSessionLogs
    case longGapBetweenSessions
    case standaloneDrift
}

enum MesocycleSignalSeverity: String, Codable {
    case low
    case medium
    case high
}

enum MesocycleNextBlockRecommendationKind: String, Codable {
    case repeatFocus
    case consolidateFocus
    case pivotFocus
    case rebuildConsistency
    case addConditioningBias
}

enum MesocycleRecommendationDecision: String, Codable {
    case pending
    case accepted
    case declined
}

struct MesocycleSessionCompletionSummary: Codable, Equatable {
    let plannedSessions: Int
    let completedSessions: Int
    let uniqueCompletedSessions: Int
    let duplicateWorkoutCount: Int
    let missedSessions: Int
}

struct MesocycleWorkoutDurationSummary: Codable, Equatable {
    let programWorkoutCount: Int
    let standaloneWorkoutCount: Int
    let totalWorkoutCount: Int
    let totalDurationSeconds: Int
    let averageDurationSeconds: Int
}

struct MesocyclePersonalRecordSummary: Codable, Equatable {
    let achievedSetCount: Int
    let uniqueExerciseCount: Int
    let notableExercises: [String]
}

struct MesocycleExerciseFrequency: Codable, Equatable {
    let exerciseName: String
    let workoutCount: Int
    let appearancePercentage: Int
}

struct MesocycleExerciseConsistencySummary: Codable, Equatable {
    let repeatedExerciseCount: Int
    let anchorExercises: [MesocycleExerciseFrequency]
    let summaryText: String
}

struct MesocycleMovementPatternCount: Codable, Equatable {
    let pattern: ProgramMovementPattern
    let workoutCount: Int
}

struct MesocycleLiftHighlight: Codable, Equatable {
    let liftKey: String
    let displayName: String
    let firstEstimatedOneRepMaxLbs: Int
    let bestEstimatedOneRepMaxLbs: Int
    let improvementPercentage: Int
    let sourcedFromStandaloneWorkout: Bool
}

struct MesocycleStandaloneWorkoutInfluenceSummary: Codable, Equatable {
    let includedWorkoutCount: Int
    let totalDurationSeconds: Int
    let dominantPatterns: [MesocycleMovementPatternCount]
    let summaryText: String
    let influencePolicyText: String
}

struct MesocycleHeadlineMetrics: Codable, Equatable {
    let sessionSummary: MesocycleSessionCompletionSummary
    let adherencePercentage: Int
    let workoutSummary: MesocycleWorkoutDurationSummary
    let personalRecordSummary: MesocyclePersonalRecordSummary
    let exerciseConsistencySummary: MesocycleExerciseConsistencySummary
}

struct MesocyclePerformanceHighlight: Codable, Equatable {
    let kind: MesocyclePerformanceHighlightKind
    let title: String
    let detail: String
}

struct MesocycleFrictionSignal: Codable, Equatable {
    let kind: MesocycleFrictionSignalKind
    let severity: MesocycleSignalSeverity
    let title: String
    let detail: String
}

struct MesocyclePhaseRecap: Codable, Equatable {
    let title: String
    let weekRangeText: String
    let plannedSessionCount: Int
    let completedSessionCount: Int
    let summaryText: String
}

struct MesocycleRecommendationInputPayload: Codable, Equatable {
    let programRunStableID: String
    let trainingProgramStableID: String?
    let currentFocus: ProgramFocus?
    let inferredCurrentLevel: ProgramLevel
    let progressionModel: ProgramProgressionModel?
    let sessionSummary: MesocycleSessionCompletionSummary
    let workoutSummary: MesocycleWorkoutDurationSummary
    let personalRecordSummary: MesocyclePersonalRecordSummary
    let exerciseConsistencySummary: MesocycleExerciseConsistencySummary
    let liftHighlights: [MesocycleLiftHighlight]
    let movementPatterns: [MesocycleMovementPatternCount]
    let standaloneInfluence: MesocycleStandaloneWorkoutInfluenceSummary
    let frictionSignalKinds: [MesocycleFrictionSignalKind]
}

struct MesocycleOneRepMaxPrefill: Codable, Equatable {
    let exerciseName: String
    let weight: Double
    let unit: WeightUnit
    let sourceSummary: String
}

struct MesocycleNextBlockPrefill: Codable, Equatable {
    let sourceProgramRunStableID: String
    let recommendationStableID: String?
    let focus: ProgramFocus
    let level: ProgramLevel
    let durationWeeks: Int
    let sessionsPerWeek: Int
    let oneRepMaxSuggestions: [MesocycleOneRepMaxPrefill]
    let notes: [String]

    var programGenerationInput: ProgramGenerationInput {
        let oneRepMaxes = Dictionary(
            uniqueKeysWithValues: oneRepMaxSuggestions.map {
                ($0.exerciseName, (weight: $0.weight, unit: $0.unit.rawValue))
            }
        )

        return ProgramGenerationInput(
            focus: focus,
            level: level,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            oneRepMaxes: oneRepMaxes
        )
    }
}

struct MesocycleNextBlockRecommendation: Codable, Equatable {
    let stableID: String
    let rank: Int
    let kind: MesocycleNextBlockRecommendationKind
    let title: String
    let summary: String
    let rationale: [String]
    let targetFocus: ProgramFocus
    let targetFocusDisplayName: String
    let suggestedLevel: ProgramLevel
    let suggestedDurationWeeks: Int
    let suggestedSessionsPerWeek: Int
    let decision: MesocycleRecommendationDecision
    let prefill: MesocycleNextBlockPrefill
}

struct MesocycleReviewSnapshot: Codable, Equatable {
    let reviewStableID: String
    let programRunStableID: String
    let trainingProgramStableID: String?
    let programName: String
    let focus: ProgramFocus?
    let focusDisplayName: String?
    let inferredCurrentLevel: ProgramLevel
    let progressionModel: ProgramProgressionModel?
    let startDate: Date
    let endDate: Date
    let headlineMetrics: MesocycleHeadlineMetrics
    let performanceHighlights: [MesocyclePerformanceHighlight]
    let frictionSignals: [MesocycleFrictionSignal]
    let narrativeSummary: String
    let phaseRecap: [MesocyclePhaseRecap]
    let standaloneInfluence: MesocycleStandaloneWorkoutInfluenceSummary
    let recommendationInput: MesocycleRecommendationInputPayload
    let rankedRecommendations: [MesocycleNextBlockRecommendation]
    let defaultNextBlockPrefill: MesocycleNextBlockPrefill
}
