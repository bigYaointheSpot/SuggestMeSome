//
//  AdaptiveCoachingModels.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData

// MARK: - Adaptive Enums

/// Coarse qualitative band for an exercise outcome score.
enum PerformanceScore: String, Codable {
    case severeUnderperformance
    case underperformance
    case onTarget
    case overperformance
    case exceptionalPerformance
    case insufficientData
}

/// Weekly or exercise-level inferred fatigue state from performance-only inputs.
enum FatigueStatus: String, Codable {
    case low
    case manageable
    case elevated
    case high
    case critical
}

/// Directional status for a lift-specific trend.
enum LiftTrendStatus: String, Codable {
    case improving
    case stable
    case declining
    case volatile
    case insufficientData
}

/// Planned adaptation category generated from weekly analysis and trend signals.
enum ProposalType: String, Codable {
    case increaseLoad
    case decreaseLoad
    case increaseVolume
    case decreaseVolume
    case deload
    case variationSwap
}

/// Lifecycle state for an adaptation proposal.
enum ProposalStatus: String, Codable {
    case draft
    case pendingUserConfirmation
    case pendingAutoApply
    case confirmed
    case rejected
    case autoApplied
    case expired
    case superseded
}

/// Principal reason attached to a proposal, adjustment, or history event.
enum AdjustmentReason: String, Codable {
    case topSetBeatTarget
    case topSetMissedTarget
    case accessoryOutperformance
    case accessoryUnderperformance
    case fatigueAccumulation
    case fatigueResolved
    case positiveLiftTrend
    case negativeLiftTrend
    case plateauDetected
    case lowAdherence
    case standaloneTrendSupport
    case programSignalPriority
}

/// Relative confidence of a workout-derived signal used by weekly analysis.
enum WorkoutSignalConfidence: String, Codable {
    case high
    case medium
    case low
}

/// Source classification for workout-derived adaptation signals.
enum WorkoutSignalSource: String, Codable {
    case programLinked
    case standalone
}

/// Type of overlay patch persisted for future-session resolution.
enum OverlayAdjustmentType: String, Codable {
    case load
    case volume
    case reps
    case variationSwap
    case deload
}

/// Lifecycle status of a persisted overlay.
enum OverlayStatus: String, Codable {
    case active
    case superseded
    case reverted
    case expired
}

/// Explainability timeline event classification.
enum AdaptationEventType: String, Codable {
    case weeklyAnalysisFinalized
    case trendUpdated
    case proposalCreated
    case proposalConfirmed
    case proposalRejected
    case overlayApplied
    case overlaySuperseded
}

// MARK: - Non-persisted Helpers

/// Default weighting used when combining program and standalone workout signals.
struct AdaptiveSignalWeights {
    static let programWorkout = 1.0
    static let standaloneWorkout = 0.6
}

/// Lightweight date window helper used by analysis services.
struct AnalysisWeekWindow {
    let weekStartDate: Date
    let weekEndDate: Date
}

// MARK: - Persisted Models

/// Exercise-level prescribed-versus-actual snapshot and scored outcome signal.
@Model
final class ExercisePerformanceOutcome {
    var id: UUID
    var createdAt: Date

    var analysis: WeeklyTrainingAnalysis?
    var programRun: ProgramRun?
    var workout: Workout?
    var exerciseEntry: ExerciseEntry?

    var workoutDate: Date
    var programWeekNumber: Int?
    var programSessionNumber: Int?
    var sourceProgramSessionExerciseID: UUID?

    var exerciseName: String
    var canonicalLiftKey: String?
    var signalSource: WorkoutSignalSource
    var signalConfidence: WorkoutSignalConfidence
    /// Numeric weight used in aggregations. Program-linked workouts should default higher.
    var signalWeight: Double

    // Prescribed snapshot
    var prescribedSets: Int?
    var prescribedReps: Int?
    var prescribedWeight: Double?
    var prescribedWeightUnit: String?
    var prescribedTargetPercentage1RM: Double?
    var prescribedTargetRPE: Double?
    var prescribedTargetRIR: Double?
    var prescribedWorkingSetStyle: ProgramWorkingSetStyle?
    var prescribedTargetEffortType: ProgramTargetEffortType?

    // Actual snapshot
    var actualSetCount: Int
    var actualAverageReps: Double?
    var actualAverageWeight: Double?
    var actualTopSetReps: Int?
    var actualTopSetWeight: Double?
    var actualTopSetEstimated1RM: Double?

    // Scoring
    var completionRatio: Double?
    var loadDeltaPercent: Double?
    var repsDelta: Double?
    var performanceScoreValue: Double
    var performanceScore: PerformanceScore
    var inferredFatigueStatus: FatigueStatus
    var isTopSetSignal: Bool
    var notes: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        analysis: WeeklyTrainingAnalysis? = nil,
        programRun: ProgramRun? = nil,
        workout: Workout? = nil,
        exerciseEntry: ExerciseEntry? = nil,
        workoutDate: Date = Date(),
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil,
        sourceProgramSessionExerciseID: UUID? = nil,
        exerciseName: String,
        canonicalLiftKey: String? = nil,
        signalSource: WorkoutSignalSource,
        signalConfidence: WorkoutSignalConfidence,
        signalWeight: Double,
        prescribedSets: Int? = nil,
        prescribedReps: Int? = nil,
        prescribedWeight: Double? = nil,
        prescribedWeightUnit: String? = nil,
        prescribedTargetPercentage1RM: Double? = nil,
        prescribedTargetRPE: Double? = nil,
        prescribedTargetRIR: Double? = nil,
        prescribedWorkingSetStyle: ProgramWorkingSetStyle? = nil,
        prescribedTargetEffortType: ProgramTargetEffortType? = nil,
        actualSetCount: Int = 0,
        actualAverageReps: Double? = nil,
        actualAverageWeight: Double? = nil,
        actualTopSetReps: Int? = nil,
        actualTopSetWeight: Double? = nil,
        actualTopSetEstimated1RM: Double? = nil,
        completionRatio: Double? = nil,
        loadDeltaPercent: Double? = nil,
        repsDelta: Double? = nil,
        performanceScoreValue: Double = 0,
        performanceScore: PerformanceScore = .insufficientData,
        inferredFatigueStatus: FatigueStatus = .manageable,
        isTopSetSignal: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.analysis = analysis
        self.programRun = programRun
        self.workout = workout
        self.exerciseEntry = exerciseEntry
        self.workoutDate = workoutDate
        self.programWeekNumber = programWeekNumber
        self.programSessionNumber = programSessionNumber
        self.sourceProgramSessionExerciseID = sourceProgramSessionExerciseID
        self.exerciseName = exerciseName
        self.canonicalLiftKey = canonicalLiftKey
        self.signalSource = signalSource
        self.signalConfidence = signalConfidence
        self.signalWeight = signalWeight
        self.prescribedSets = prescribedSets
        self.prescribedReps = prescribedReps
        self.prescribedWeight = prescribedWeight
        self.prescribedWeightUnit = prescribedWeightUnit
        self.prescribedTargetPercentage1RM = prescribedTargetPercentage1RM
        self.prescribedTargetRPE = prescribedTargetRPE
        self.prescribedTargetRIR = prescribedTargetRIR
        self.prescribedWorkingSetStyle = prescribedWorkingSetStyle
        self.prescribedTargetEffortType = prescribedTargetEffortType
        self.actualSetCount = actualSetCount
        self.actualAverageReps = actualAverageReps
        self.actualAverageWeight = actualAverageWeight
        self.actualTopSetReps = actualTopSetReps
        self.actualTopSetWeight = actualTopSetWeight
        self.actualTopSetEstimated1RM = actualTopSetEstimated1RM
        self.completionRatio = completionRatio
        self.loadDeltaPercent = loadDeltaPercent
        self.repsDelta = repsDelta
        self.performanceScoreValue = performanceScoreValue
        self.performanceScore = performanceScore
        self.inferredFatigueStatus = inferredFatigueStatus
        self.isTopSetSignal = isTopSetSignal
        self.notes = notes
    }
}

/// Per-week rollup that combines outcomes, volume, and inferred fatigue across workout sources.
@Model
final class WeeklyTrainingAnalysis {
    var id: UUID
    var syncStableID: String?
    var syncVersion: Int
    var syncLastModifiedAt: Date
    var syncDeletedAt: Date?
    var createdAt: Date
    var weekStartDate: Date
    var weekEndDate: Date

    var programRun: ProgramRun?
    var trainingProgram: TrainingProgram?
    var programWeekNumber: Int?
    var focusSnapshot: ProgramFocus?

    var programWorkoutCount: Int
    var standaloneWorkoutCount: Int
    var totalOutcomeCount: Int
    var totalSignalWeight: Double
    var programSignalWeight: Double
    var standaloneSignalWeight: Double

    var weightedPerformanceScore: Double
    var adherenceScore: Double
    var plannedFatigueScore: Double?
    var observedFatigueScore: Double
    var fatigueStatus: FatigueStatus
    var totalCompletedHardSets: Double
    var totalCompletedTonnage: Double?

    var isFinalized: Bool
    var finalizedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ExercisePerformanceOutcome.analysis)
    var outcomes: [ExercisePerformanceOutcome] = []

    @Relationship(deleteRule: .cascade, inverse: \WeeklyVolumeMetric.analysis)
    var volumeMetrics: [WeeklyVolumeMetric] = []

    @Relationship(deleteRule: .nullify, inverse: \AdaptationProposal.sourceAnalysis)
    var proposals: [AdaptationProposal] = []

    @Relationship(deleteRule: .cascade, inverse: \LiftTrendSnapshot.analysis)
    var trendSnapshots: [LiftTrendSnapshot] = []

    init(
        id: UUID = UUID(),
        syncStableID: String? = nil,
        syncVersion: Int = 1,
        syncLastModifiedAt: Date? = nil,
        syncDeletedAt: Date? = nil,
        createdAt: Date = Date(),
        weekStartDate: Date,
        weekEndDate: Date,
        programRun: ProgramRun? = nil,
        trainingProgram: TrainingProgram? = nil,
        programWeekNumber: Int? = nil,
        focusSnapshot: ProgramFocus? = nil,
        programWorkoutCount: Int = 0,
        standaloneWorkoutCount: Int = 0,
        totalOutcomeCount: Int = 0,
        totalSignalWeight: Double = 0,
        programSignalWeight: Double = 0,
        standaloneSignalWeight: Double = 0,
        weightedPerformanceScore: Double = 0,
        adherenceScore: Double = 0,
        plannedFatigueScore: Double? = nil,
        observedFatigueScore: Double = 0,
        fatigueStatus: FatigueStatus = .manageable,
        totalCompletedHardSets: Double = 0,
        totalCompletedTonnage: Double? = nil,
        isFinalized: Bool = false,
        finalizedAt: Date? = nil
    ) {
        self.id = id
        self.syncStableID = syncStableID ?? id.uuidString
        self.syncVersion = max(1, syncVersion)
        self.syncLastModifiedAt = syncLastModifiedAt ?? finalizedAt ?? createdAt
        self.syncDeletedAt = syncDeletedAt
        self.createdAt = createdAt
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.programRun = programRun
        self.trainingProgram = trainingProgram
        self.programWeekNumber = programWeekNumber
        self.focusSnapshot = focusSnapshot
        self.programWorkoutCount = programWorkoutCount
        self.standaloneWorkoutCount = standaloneWorkoutCount
        self.totalOutcomeCount = totalOutcomeCount
        self.totalSignalWeight = totalSignalWeight
        self.programSignalWeight = programSignalWeight
        self.standaloneSignalWeight = standaloneSignalWeight
        self.weightedPerformanceScore = weightedPerformanceScore
        self.adherenceScore = adherenceScore
        self.plannedFatigueScore = plannedFatigueScore
        self.observedFatigueScore = observedFatigueScore
        self.fatigueStatus = fatigueStatus
        self.totalCompletedHardSets = totalCompletedHardSets
        self.totalCompletedTonnage = totalCompletedTonnage
        self.isFinalized = isFinalized
        self.finalizedAt = finalizedAt
    }
}

/// Muscle-group weekly volume totals used by analysis and future recommendation explanations.
@Model
final class WeeklyVolumeMetric {
    var id: UUID
    var analysis: WeeklyTrainingAnalysis?
    var muscle: ProgramVolumeMuscle
    var plannedHardSets: Double?
    var completedHardSets: Double
    var weightedCompletedHardSets: Double
    var deltaHardSets: Double

    init(
        id: UUID = UUID(),
        analysis: WeeklyTrainingAnalysis? = nil,
        muscle: ProgramVolumeMuscle,
        plannedHardSets: Double? = nil,
        completedHardSets: Double = 0,
        weightedCompletedHardSets: Double = 0,
        deltaHardSets: Double = 0
    ) {
        self.id = id
        self.analysis = analysis
        self.muscle = muscle
        self.plannedHardSets = plannedHardSets
        self.completedHardSets = completedHardSets
        self.weightedCompletedHardSets = weightedCompletedHardSets
        self.deltaHardSets = deltaHardSets
    }
}

/// Lift-specific rolling trend state used to drive and explain future progression decisions.
@Model
final class LiftPerformanceTrend {
    var id: UUID
    var syncStableID: String?
    var syncVersion: Int
    var syncLastModifiedAt: Date
    var syncDeletedAt: Date?
    var updatedAt: Date

    var programRun: ProgramRun?
    var trainingProgram: TrainingProgram?
    var canonicalLiftKey: String
    var liftDisplayName: String

    var totalDataPoints: Int
    var programLinkedDataPoints: Int
    var standaloneDataPoints: Int
    var weightedSignalCount: Double
    var confidenceScore: Double

    var firstObservationDate: Date
    var lastObservationDate: Date
    var currentEstimated1RM: Double?
    var previousEstimated1RM: Double?
    var rollingBestEstimated1RM: Double?
    var fourWeekChangePercent: Double?
    var trendStatus: LiftTrendStatus
    var fatigueStatus: FatigueStatus

    var latestTopSetWeight: Double?
    var latestTopSetReps: Int?
    var latestPerformanceScoreValue: Double?
    var lastPerformanceScore: PerformanceScore?

    @Relationship(deleteRule: .cascade, inverse: \LiftTrendSnapshot.trend)
    var snapshots: [LiftTrendSnapshot] = []

    init(
        id: UUID = UUID(),
        syncStableID: String? = nil,
        syncVersion: Int = 1,
        syncLastModifiedAt: Date? = nil,
        syncDeletedAt: Date? = nil,
        updatedAt: Date = Date(),
        programRun: ProgramRun? = nil,
        trainingProgram: TrainingProgram? = nil,
        canonicalLiftKey: String,
        liftDisplayName: String,
        totalDataPoints: Int = 0,
        programLinkedDataPoints: Int = 0,
        standaloneDataPoints: Int = 0,
        weightedSignalCount: Double = 0,
        confidenceScore: Double = 0,
        firstObservationDate: Date = Date(),
        lastObservationDate: Date = Date(),
        currentEstimated1RM: Double? = nil,
        previousEstimated1RM: Double? = nil,
        rollingBestEstimated1RM: Double? = nil,
        fourWeekChangePercent: Double? = nil,
        trendStatus: LiftTrendStatus = .insufficientData,
        fatigueStatus: FatigueStatus = .manageable,
        latestTopSetWeight: Double? = nil,
        latestTopSetReps: Int? = nil,
        latestPerformanceScoreValue: Double? = nil,
        lastPerformanceScore: PerformanceScore? = nil
    ) {
        self.id = id
        self.syncStableID = syncStableID ?? id.uuidString
        self.syncVersion = max(1, syncVersion)
        self.syncLastModifiedAt = syncLastModifiedAt ?? updatedAt
        self.syncDeletedAt = syncDeletedAt
        self.updatedAt = updatedAt
        self.programRun = programRun
        self.trainingProgram = trainingProgram
        self.canonicalLiftKey = canonicalLiftKey
        self.liftDisplayName = liftDisplayName
        self.totalDataPoints = totalDataPoints
        self.programLinkedDataPoints = programLinkedDataPoints
        self.standaloneDataPoints = standaloneDataPoints
        self.weightedSignalCount = weightedSignalCount
        self.confidenceScore = confidenceScore
        self.firstObservationDate = firstObservationDate
        self.lastObservationDate = lastObservationDate
        self.currentEstimated1RM = currentEstimated1RM
        self.previousEstimated1RM = previousEstimated1RM
        self.rollingBestEstimated1RM = rollingBestEstimated1RM
        self.fourWeekChangePercent = fourWeekChangePercent
        self.trendStatus = trendStatus
        self.fatigueStatus = fatigueStatus
        self.latestTopSetWeight = latestTopSetWeight
        self.latestTopSetReps = latestTopSetReps
        self.latestPerformanceScoreValue = latestPerformanceScoreValue
        self.lastPerformanceScore = lastPerformanceScore
    }
}

/// Weekly persisted snapshot of a lift trend for explainability and audit history.
@Model
final class LiftTrendSnapshot {
    var id: UUID
    var createdAt: Date

    var trend: LiftPerformanceTrend?
    var analysis: WeeklyTrainingAnalysis?
    var programRun: ProgramRun?
    var trainingProgram: TrainingProgram?

    var canonicalLiftKey: String
    var liftDisplayName: String
    var weekStartDate: Date
    var weekEndDate: Date
    var programWeekNumber: Int?

    var totalDataPoints: Int
    var programLinkedDataPoints: Int
    var standaloneDataPoints: Int
    var weightedSignalCount: Double
    var weightedProgramSignal: Double
    var weightedStandaloneSignal: Double
    var confidenceScore: Double

    var currentEstimated1RM: Double?
    var baselineEstimated1RM: Double?
    var rollingBestEstimated1RM: Double?
    var changePercent: Double?
    var trendStatus: LiftTrendStatus
    var fatigueStatus: FatigueStatus

    var latestTopSetWeight: Double?
    var latestTopSetReps: Int?
    var latestPerformanceScoreValue: Double?
    var note: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        trend: LiftPerformanceTrend? = nil,
        analysis: WeeklyTrainingAnalysis? = nil,
        programRun: ProgramRun? = nil,
        trainingProgram: TrainingProgram? = nil,
        canonicalLiftKey: String,
        liftDisplayName: String,
        weekStartDate: Date,
        weekEndDate: Date,
        programWeekNumber: Int? = nil,
        totalDataPoints: Int = 0,
        programLinkedDataPoints: Int = 0,
        standaloneDataPoints: Int = 0,
        weightedSignalCount: Double = 0,
        weightedProgramSignal: Double = 0,
        weightedStandaloneSignal: Double = 0,
        confidenceScore: Double = 0,
        currentEstimated1RM: Double? = nil,
        baselineEstimated1RM: Double? = nil,
        rollingBestEstimated1RM: Double? = nil,
        changePercent: Double? = nil,
        trendStatus: LiftTrendStatus = .insufficientData,
        fatigueStatus: FatigueStatus = .manageable,
        latestTopSetWeight: Double? = nil,
        latestTopSetReps: Int? = nil,
        latestPerformanceScoreValue: Double? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.trend = trend
        self.analysis = analysis
        self.programRun = programRun
        self.trainingProgram = trainingProgram
        self.canonicalLiftKey = canonicalLiftKey
        self.liftDisplayName = liftDisplayName
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.programWeekNumber = programWeekNumber
        self.totalDataPoints = totalDataPoints
        self.programLinkedDataPoints = programLinkedDataPoints
        self.standaloneDataPoints = standaloneDataPoints
        self.weightedSignalCount = weightedSignalCount
        self.weightedProgramSignal = weightedProgramSignal
        self.weightedStandaloneSignal = weightedStandaloneSignal
        self.confidenceScore = confidenceScore
        self.currentEstimated1RM = currentEstimated1RM
        self.baselineEstimated1RM = baselineEstimated1RM
        self.rollingBestEstimated1RM = rollingBestEstimated1RM
        self.changePercent = changePercent
        self.trendStatus = trendStatus
        self.fatigueStatus = fatigueStatus
        self.latestTopSetWeight = latestTopSetWeight
        self.latestTopSetReps = latestTopSetReps
        self.latestPerformanceScoreValue = latestPerformanceScoreValue
        self.note = note
    }
}

/// Candidate adaptive change generated from weekly analysis and trend inputs.
@Model
final class AdaptationProposal {
    var id: UUID
    /// Stable identifier for cross-device sync contracts.
    var syncStableID: String?
    /// Monotonic version for deterministic merge tie-breaks.
    var syncVersion: Int
    /// Last modified timestamp used by sync conflict policies.
    var syncLastModifiedAt: Date
    var syncDeletedAt: Date?
    var createdAt: Date
    var decidedAt: Date?

    var programRun: ProgramRun?
    var trainingProgram: TrainingProgram?
    var sourceAnalysis: WeeklyTrainingAnalysis?

    var proposalType: ProposalType
    var proposalStatus: ProposalStatus
    var requiresUserConfirmation: Bool
    var autoApplyEligible: Bool
    var confidenceScore: Double
    var priority: Int

    var targetWeekStart: Int
    var targetWeekEnd: Int?
    var targetSessionNumber: Int?
    var targetProgramSessionExerciseID: UUID?
    var targetLiftKey: String?

    var proposedLoadPercentDelta: Double?
    var proposedSetDelta: Int?
    var proposedRepDelta: Int?
    var proposedDeloadFactor: Double?
    var swapFromExerciseName: String?
    var swapToExerciseName: String?

    var adjustmentReason: AdjustmentReason
    var summaryText: String
    var detailText: String?
    var expiresAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \AppliedProgramOverlay.sourceProposal)
    var appliedOverlays: [AppliedProgramOverlay] = []

    init(
        id: UUID = UUID(),
        syncStableID: String? = nil,
        syncVersion: Int = 1,
        syncLastModifiedAt: Date? = nil,
        syncDeletedAt: Date? = nil,
        createdAt: Date = Date(),
        decidedAt: Date? = nil,
        programRun: ProgramRun? = nil,
        trainingProgram: TrainingProgram? = nil,
        sourceAnalysis: WeeklyTrainingAnalysis? = nil,
        proposalType: ProposalType,
        proposalStatus: ProposalStatus = .draft,
        requiresUserConfirmation: Bool,
        autoApplyEligible: Bool = false,
        confidenceScore: Double = 0,
        priority: Int = 0,
        targetWeekStart: Int,
        targetWeekEnd: Int? = nil,
        targetSessionNumber: Int? = nil,
        targetProgramSessionExerciseID: UUID? = nil,
        targetLiftKey: String? = nil,
        proposedLoadPercentDelta: Double? = nil,
        proposedSetDelta: Int? = nil,
        proposedRepDelta: Int? = nil,
        proposedDeloadFactor: Double? = nil,
        swapFromExerciseName: String? = nil,
        swapToExerciseName: String? = nil,
        adjustmentReason: AdjustmentReason,
        summaryText: String,
        detailText: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.syncStableID = syncStableID ?? id.uuidString
        self.syncVersion = max(1, syncVersion)
        self.syncDeletedAt = syncDeletedAt
        self.createdAt = createdAt
        self.decidedAt = decidedAt
        self.programRun = programRun
        self.trainingProgram = trainingProgram
        self.sourceAnalysis = sourceAnalysis
        self.proposalType = proposalType
        self.proposalStatus = proposalStatus
        self.requiresUserConfirmation = requiresUserConfirmation
        self.autoApplyEligible = autoApplyEligible
        self.confidenceScore = confidenceScore
        self.priority = priority
        self.targetWeekStart = targetWeekStart
        self.targetWeekEnd = targetWeekEnd
        self.targetSessionNumber = targetSessionNumber
        self.targetProgramSessionExerciseID = targetProgramSessionExerciseID
        self.targetLiftKey = targetLiftKey
        self.proposedLoadPercentDelta = proposedLoadPercentDelta
        self.proposedSetDelta = proposedSetDelta
        self.proposedRepDelta = proposedRepDelta
        self.proposedDeloadFactor = proposedDeloadFactor
        self.swapFromExerciseName = swapFromExerciseName
        self.swapToExerciseName = swapToExerciseName
        self.adjustmentReason = adjustmentReason
        self.summaryText = summaryText
        self.detailText = detailText
        self.expiresAt = expiresAt
        self.syncLastModifiedAt = syncLastModifiedAt ?? decidedAt ?? createdAt
    }
}

/// Persisted non-destructive overlay for future session resolution.
@Model
final class AppliedProgramOverlay {
    var id: UUID
    /// Stable identifier for cross-device sync contracts.
    var syncStableID: String?
    /// Monotonic version for deterministic merge tie-breaks.
    var syncVersion: Int
    /// Last modified timestamp used by sync conflict policies.
    var syncLastModifiedAt: Date
    var syncDeletedAt: Date?
    var createdAt: Date
    var appliedAt: Date

    var programRun: ProgramRun?
    var trainingProgram: TrainingProgram?
    var sourceProposal: AdaptationProposal?

    var effectiveWeekStart: Int
    var effectiveWeekEnd: Int?
    var overlayStatus: OverlayStatus
    var appliedByUserConfirmation: Bool
    var adjustmentReason: AdjustmentReason
    var summaryText: String?

    @Relationship(deleteRule: .cascade, inverse: \AppliedOverlayAdjustment.overlay)
    var adjustments: [AppliedOverlayAdjustment] = []

    init(
        id: UUID = UUID(),
        syncStableID: String? = nil,
        syncVersion: Int = 1,
        syncLastModifiedAt: Date? = nil,
        syncDeletedAt: Date? = nil,
        createdAt: Date = Date(),
        appliedAt: Date = Date(),
        programRun: ProgramRun? = nil,
        trainingProgram: TrainingProgram? = nil,
        sourceProposal: AdaptationProposal? = nil,
        effectiveWeekStart: Int,
        effectiveWeekEnd: Int? = nil,
        overlayStatus: OverlayStatus = .active,
        appliedByUserConfirmation: Bool,
        adjustmentReason: AdjustmentReason,
        summaryText: String? = nil
    ) {
        self.id = id
        self.syncStableID = syncStableID ?? id.uuidString
        self.syncVersion = max(1, syncVersion)
        self.syncDeletedAt = syncDeletedAt
        self.createdAt = createdAt
        self.appliedAt = appliedAt
        self.programRun = programRun
        self.trainingProgram = trainingProgram
        self.sourceProposal = sourceProposal
        self.effectiveWeekStart = effectiveWeekStart
        self.effectiveWeekEnd = effectiveWeekEnd
        self.overlayStatus = overlayStatus
        self.appliedByUserConfirmation = appliedByUserConfirmation
        self.adjustmentReason = adjustmentReason
        self.summaryText = summaryText
        self.syncLastModifiedAt = syncLastModifiedAt ?? appliedAt
    }
}

/// One concrete adjustment entry inside an applied overlay.
@Model
final class AppliedOverlayAdjustment {
    var id: UUID
    /// Stable identifier for cross-device sync contracts.
    var syncStableID: String?
    /// Monotonic version for deterministic merge tie-breaks.
    var syncVersion: Int
    /// Last modified timestamp used by sync conflict policies.
    var syncLastModifiedAt: Date
    var overlay: AppliedProgramOverlay?
    var sequence: Int

    var targetProgramSessionExerciseID: UUID?
    var targetWeekNumber: Int?
    var targetSessionNumber: Int?

    var adjustmentType: OverlayAdjustmentType
    var loadPercentDelta: Double?
    var absolutePrescribedWeight: Double?
    var setDelta: Int?
    var absoluteTargetSets: Int?
    var repDelta: Int?
    var absoluteTargetReps: Int?
    var replacementExerciseName: String?

    var adjustmentReason: AdjustmentReason
    var isAutoApplied: Bool

    init(
        id: UUID = UUID(),
        syncStableID: String? = nil,
        syncVersion: Int = 1,
        syncLastModifiedAt: Date = Date(),
        overlay: AppliedProgramOverlay? = nil,
        sequence: Int = 0,
        targetProgramSessionExerciseID: UUID? = nil,
        targetWeekNumber: Int? = nil,
        targetSessionNumber: Int? = nil,
        adjustmentType: OverlayAdjustmentType,
        loadPercentDelta: Double? = nil,
        absolutePrescribedWeight: Double? = nil,
        setDelta: Int? = nil,
        absoluteTargetSets: Int? = nil,
        repDelta: Int? = nil,
        absoluteTargetReps: Int? = nil,
        replacementExerciseName: String? = nil,
        adjustmentReason: AdjustmentReason,
        isAutoApplied: Bool = false
    ) {
        self.id = id
        self.syncStableID = syncStableID ?? id.uuidString
        self.syncVersion = max(1, syncVersion)
        self.syncLastModifiedAt = syncLastModifiedAt
        self.overlay = overlay
        self.sequence = sequence
        self.targetProgramSessionExerciseID = targetProgramSessionExerciseID
        self.targetWeekNumber = targetWeekNumber
        self.targetSessionNumber = targetSessionNumber
        self.adjustmentType = adjustmentType
        self.loadPercentDelta = loadPercentDelta
        self.absolutePrescribedWeight = absolutePrescribedWeight
        self.setDelta = setDelta
        self.absoluteTargetSets = absoluteTargetSets
        self.repDelta = repDelta
        self.absoluteTargetReps = absoluteTargetReps
        self.replacementExerciseName = replacementExerciseName
        self.adjustmentReason = adjustmentReason
        self.isAutoApplied = isAutoApplied
    }
}

/// Auditable timeline entry for explainable adaptation behavior and UI history.
@Model
final class AdaptationEventHistory {
    var id: UUID
    var syncStableID: String?
    var syncVersion: Int
    var syncLastModifiedAt: Date
    var syncDeletedAt: Date?
    var timestamp: Date

    var programRun: ProgramRun?
    var trainingProgram: TrainingProgram?
    var analysis: WeeklyTrainingAnalysis?
    var proposal: AdaptationProposal?
    var overlay: AppliedProgramOverlay?

    var eventType: AdaptationEventType
    var analysisWeekNumber: Int?
    var targetLiftKey: String?
    var message: String
    var explanation: String?

    var adjustmentReason: AdjustmentReason?
    var performanceScoreSnapshot: PerformanceScore?
    var fatigueStatusSnapshot: FatigueStatus?
    var liftTrendStatusSnapshot: LiftTrendStatus?
    var confidenceSnapshot: Double?

    var requiresUserAction: Bool
    var userActionTaken: Bool

    init(
        id: UUID = UUID(),
        syncStableID: String? = nil,
        syncVersion: Int = 1,
        syncLastModifiedAt: Date? = nil,
        syncDeletedAt: Date? = nil,
        timestamp: Date = Date(),
        programRun: ProgramRun? = nil,
        trainingProgram: TrainingProgram? = nil,
        analysis: WeeklyTrainingAnalysis? = nil,
        proposal: AdaptationProposal? = nil,
        overlay: AppliedProgramOverlay? = nil,
        eventType: AdaptationEventType,
        analysisWeekNumber: Int? = nil,
        targetLiftKey: String? = nil,
        message: String,
        explanation: String? = nil,
        adjustmentReason: AdjustmentReason? = nil,
        performanceScoreSnapshot: PerformanceScore? = nil,
        fatigueStatusSnapshot: FatigueStatus? = nil,
        liftTrendStatusSnapshot: LiftTrendStatus? = nil,
        confidenceSnapshot: Double? = nil,
        requiresUserAction: Bool = false,
        userActionTaken: Bool = false
    ) {
        self.id = id
        self.syncStableID = syncStableID ?? id.uuidString
        self.syncVersion = max(1, syncVersion)
        self.syncLastModifiedAt = syncLastModifiedAt ?? timestamp
        self.syncDeletedAt = syncDeletedAt
        self.timestamp = timestamp
        self.programRun = programRun
        self.trainingProgram = trainingProgram
        self.analysis = analysis
        self.proposal = proposal
        self.overlay = overlay
        self.eventType = eventType
        self.analysisWeekNumber = analysisWeekNumber
        self.targetLiftKey = targetLiftKey
        self.message = message
        self.explanation = explanation
        self.adjustmentReason = adjustmentReason
        self.performanceScoreSnapshot = performanceScoreSnapshot
        self.fatigueStatusSnapshot = fatigueStatusSnapshot
        self.liftTrendStatusSnapshot = liftTrendStatusSnapshot
        self.confidenceSnapshot = confidenceSnapshot
        self.requiresUserAction = requiresUserAction
        self.userActionTaken = userActionTaken
    }
}
