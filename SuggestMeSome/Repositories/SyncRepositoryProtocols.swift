import Foundation

struct WorkoutSyncUpsertSummary: Equatable {
    var affectedExerciseNames: Set<String> = []
    var didChangeWorkouts = false
}

protocol WorkoutSyncRepository {
    func fetchWorkoutPayloads(since: Date?, includeDeleted: Bool) throws -> [WorkoutSyncDTO]
    func upsertWorkoutPayloads(_ payloads: [WorkoutSyncDTO]) throws -> WorkoutSyncUpsertSummary
    func markWorkoutDeleted(stableID: String, deletedAt: Date) throws
}

protocol ProgramSyncRepository {
    func fetchTrainingProgramPayloads(since: Date?) throws -> [TrainingProgramSyncDTO]
    func upsertTrainingProgramPayloads(_ payloads: [TrainingProgramSyncDTO]) throws
    func fetchProgramRunPayloads(since: Date?) throws -> [ProgramRunSyncDTO]
    func upsertProgramRunPayloads(_ payloads: [ProgramRunSyncDTO]) throws
}

protocol DailyCoachSyncRepository {
    func fetchDailyCheckInPayloads(since: Date?) throws -> [DailyCoachCheckInSyncDTO]
    func upsertDailyCheckInPayloads(_ payloads: [DailyCoachCheckInSyncDTO]) throws
    func fetchWeeklyReviewPayloads(since: Date?) throws -> [DailyCoachWeeklyReviewSyncDTO]
    func upsertWeeklyReviewPayloads(_ payloads: [DailyCoachWeeklyReviewSyncDTO]) throws
}

protocol AdaptiveSyncRepository {
    func fetchWeeklyTrainingAnalysisPayloads(since: Date?) throws -> [WeeklyTrainingAnalysisSyncDTO]
    func upsertWeeklyTrainingAnalysisPayloads(_ payloads: [WeeklyTrainingAnalysisSyncDTO]) throws
    func fetchLiftPerformanceTrendPayloads(since: Date?) throws -> [LiftPerformanceTrendSyncDTO]
    func upsertLiftPerformanceTrendPayloads(_ payloads: [LiftPerformanceTrendSyncDTO]) throws
    func fetchAdaptationProposalPayloads(since: Date?) throws -> [AdaptationProposalSyncDTO]
    func upsertAdaptationProposalPayloads(_ payloads: [AdaptationProposalSyncDTO]) throws
    func fetchAppliedOverlayPayloads(since: Date?) throws -> [AppliedProgramOverlaySyncDTO]
    func upsertAppliedOverlayPayloads(_ payloads: [AppliedProgramOverlaySyncDTO]) throws
    func fetchAdaptationEventPayloads(since: Date?) throws -> [AdaptationEventHistorySyncDTO]
    func upsertAdaptationEventPayloads(_ payloads: [AdaptationEventHistorySyncDTO]) throws
}

protocol TrainingPreferencesSyncRepository {
    func fetchTrainingPreferencesPayload(since: Date?) throws -> TrainingPreferencesSyncDTO?
    func upsertTrainingPreferencesPayload(_ payload: TrainingPreferencesSyncDTO) throws
}

protocol HealthKitSummarySyncRepository {
    func fetchHealthKitSummaryPayloads(since: Date?) throws -> [HealthKitDailySummarySyncDTO]
    func upsertHealthKitSummaryPayloads(_ payloads: [HealthKitDailySummarySyncDTO]) throws
}
