import Foundation

protocol WorkoutSyncRepository {
    func fetchWorkoutPayloads(since: Date?, includeDeleted: Bool) throws -> [WorkoutSyncDTO]
    func upsertWorkoutPayloads(_ payloads: [WorkoutSyncDTO]) throws
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
    func fetchAdaptationProposalPayloads(since: Date?) throws -> [AdaptationProposalSyncDTO]
    func upsertAdaptationProposalPayloads(_ payloads: [AdaptationProposalSyncDTO]) throws
    func fetchAppliedOverlayPayloads(since: Date?) throws -> [AppliedProgramOverlaySyncDTO]
    func upsertAppliedOverlayPayloads(_ payloads: [AppliedProgramOverlaySyncDTO]) throws
}

protocol HealthKitSummarySyncRepository {
    func fetchHealthKitSummaryPayloads(since: Date?) throws -> [HealthKitDailySummarySyncDTO]
    func upsertHealthKitSummaryPayloads(_ payloads: [HealthKitDailySummarySyncDTO]) throws
}
