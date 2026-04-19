import Foundation

enum CloudSyncCollection: String, CaseIterable, Codable, Hashable, Identifiable {
    case workouts
    case trainingPrograms
    case programRuns
    case dailyCoachCheckIns
    case dailyCoachWeeklyReviews
    case weeklyTrainingAnalyses
    case liftPerformanceTrends
    case adaptationProposals
    case appliedProgramOverlays
    case adaptationEvents
    case trainingPreferences

    var id: String { rawValue }
}

struct ExercisePerformanceOutcomeSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var createdAt: Date
    var programRunStableID: String?
    var workoutStableID: String?
    var exerciseEntryStableID: String?
    var workoutDate: Date
    var programWeekNumber: Int?
    var programSessionNumber: Int?
    var sourceProgramSessionExerciseID: String?
    var exerciseName: String
    var canonicalLiftKey: String?
    var signalSourceRawValue: String
    var signalConfidenceRawValue: String
    var signalWeight: Double
    var prescribedSets: Int?
    var prescribedReps: Int?
    var prescribedWeight: Double?
    var prescribedWeightUnit: String?
    var prescribedTargetPercentage1RM: Double?
    var prescribedTargetRPE: Double?
    var prescribedTargetRIR: Double?
    var prescribedWorkingSetStyleRawValue: String?
    var prescribedTargetEffortTypeRawValue: String?
    var actualSetCount: Int
    var actualAverageReps: Double?
    var actualAverageWeight: Double?
    var actualTopSetReps: Int?
    var actualTopSetWeight: Double?
    var actualTopSetEstimated1RM: Double?
    var completionRatio: Double?
    var loadDeltaPercent: Double?
    var repsDelta: Double?
    var performanceScoreValue: Double
    var performanceScoreRawValue: String
    var inferredFatigueStatusRawValue: String
    var isTopSetSignal: Bool
    var notes: String?
}

struct WeeklyVolumeMetricSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var muscleRawValue: String
    var plannedHardSets: Double?
    var completedHardSets: Double
    var weightedCompletedHardSets: Double
    var deltaHardSets: Double
}

struct WeeklyTrainingAnalysisSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var createdAt: Date
    var weekStartDate: Date
    var weekEndDate: Date
    var programRunStableID: String?
    var trainingProgramStableID: String?
    var programWeekNumber: Int?
    var focusSnapshotRawValue: String?
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
    var fatigueStatusRawValue: String
    var totalCompletedHardSets: Double
    var totalCompletedTonnage: Double?
    var isFinalized: Bool
    var finalizedAt: Date?
    var outcomes: [ExercisePerformanceOutcomeSyncDTO]
    var volumeMetrics: [WeeklyVolumeMetricSyncDTO]
}

struct LiftTrendSnapshotSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var createdAt: Date
    var analysisStableID: String?
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
    var trendStatusRawValue: String
    var fatigueStatusRawValue: String
    var latestTopSetWeight: Double?
    var latestTopSetReps: Int?
    var latestPerformanceScoreValue: Double?
    var note: String?
}

struct LiftPerformanceTrendSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var updatedAt: Date
    var programRunStableID: String?
    var trainingProgramStableID: String?
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
    var trendStatusRawValue: String
    var fatigueStatusRawValue: String
    var latestTopSetWeight: Double?
    var latestTopSetReps: Int?
    var latestPerformanceScoreValue: Double?
    var lastPerformanceScoreRawValue: String?
    var snapshots: [LiftTrendSnapshotSyncDTO]
}

struct AdaptationEventHistorySyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var timestamp: Date
    var programRunStableID: String?
    var trainingProgramStableID: String?
    var analysisStableID: String?
    var proposalStableID: String?
    var overlayStableID: String?
    var eventTypeRawValue: String
    var analysisWeekNumber: Int?
    var targetLiftKey: String?
    var message: String
    var explanation: String?
    var adjustmentReasonRawValue: String?
    var performanceScoreSnapshotRawValue: String?
    var fatigueStatusSnapshotRawValue: String?
    var liftTrendStatusSnapshotRawValue: String?
    var confidenceSnapshot: Double?
    var requiresUserAction: Bool
    var userActionTaken: Bool
}

struct TrainingPreferencesSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var globalWeightUnitRawValue: String
    var defaultRestTimerSeconds: Int
    var coachPreferredDaysBitmask: Int
}

struct CloudSyncBatchPayload: Codable, Equatable {
    var workouts: [WorkoutSyncDTO] = []
    var trainingPrograms: [TrainingProgramSyncDTO] = []
    var programRuns: [ProgramRunSyncDTO] = []
    var dailyCoachCheckIns: [DailyCoachCheckInSyncDTO] = []
    var dailyCoachWeeklyReviews: [DailyCoachWeeklyReviewSyncDTO] = []
    var weeklyTrainingAnalyses: [WeeklyTrainingAnalysisSyncDTO] = []
    var liftPerformanceTrends: [LiftPerformanceTrendSyncDTO] = []
    var adaptationProposals: [AdaptationProposalSyncDTO] = []
    var appliedProgramOverlays: [AppliedProgramOverlaySyncDTO] = []
    var adaptationEvents: [AdaptationEventHistorySyncDTO] = []
    var trainingPreferences: TrainingPreferencesSyncDTO?

    var isEmpty: Bool {
        workouts.isEmpty &&
        trainingPrograms.isEmpty &&
        programRuns.isEmpty &&
        dailyCoachCheckIns.isEmpty &&
        dailyCoachWeeklyReviews.isEmpty &&
        weeklyTrainingAnalyses.isEmpty &&
        liftPerformanceTrends.isEmpty &&
        adaptationProposals.isEmpty &&
        appliedProgramOverlays.isEmpty &&
        adaptationEvents.isEmpty &&
        trainingPreferences == nil
    }
}

struct CloudAuthExchangeRequest: Codable, Equatable {
    var deviceID: String
    var appleUserID: String
    var identityToken: String
    var authorizationCode: String?
    var email: String?
    var displayName: String?
}

struct CloudSessionTokensDTO: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var accessTokenExpiresAt: Date
}

struct CloudSessionRefreshRequest: Codable, Equatable {
    var deviceID: String
    var refreshToken: String
}

struct CloudAuthSessionResponse: Codable, Equatable {
    var accountState: AccountBackendContractState
    var tokens: CloudSessionTokensDTO
}

struct CloudSyncCollectionCursorDTO: Codable, Equatable {
    var collection: CloudSyncCollection
    var nextCursor: String?
    var lastSuccessfulSyncAt: Date
}

struct CloudSyncWarningDTO: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var collection: CloudSyncCollection
    var message: String
}

struct CloudSyncBootstrapRequest: Codable, Equatable {
    var deviceID: String
    var payload: CloudSyncBatchPayload
}

struct CloudSyncPushRequest: Codable, Equatable {
    var deviceID: String
    var batchID: UUID
    var payload: CloudSyncBatchPayload
}

struct CloudSyncPullRequest: Codable, Equatable {
    var deviceID: String
    var cursors: [CloudSyncCollectionCursorDTO]
}

struct CloudSyncResponse: Codable, Equatable {
    var serverTime: Date
    var payload: CloudSyncBatchPayload
    var cursors: [CloudSyncCollectionCursorDTO]
    var warnings: [CloudSyncWarningDTO] = []
}

struct CloudPrivacyRequestResponse: Codable, Equatable {
    var accountState: AccountBackendContractState
}

struct CloudAccountExportResponse: Codable, Equatable {
    var fileName: String
    var mimeType: String
    var data: Data
}
