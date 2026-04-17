import Foundation
import SwiftData

@MainActor
final class LocalSyncRepository:
    WorkoutSyncRepository,
    ProgramSyncRepository,
    DailyCoachSyncRepository,
    AdaptiveSyncRepository,
    HealthKitSummarySyncRepository {
    private let context: LocalSyncStoreContext

    init(modelContext: ModelContext) {
        self.context = LocalSyncStoreContext(modelContext: modelContext)
    }

    func fetchWorkoutPayloads(since: Date?, includeDeleted: Bool = false) throws -> [WorkoutSyncDTO] {
        try LocalWorkoutSyncStore(context: context)
            .fetchWorkoutPayloads(since: since, includeDeleted: includeDeleted)
    }

    func upsertWorkoutPayloads(_ payloads: [WorkoutSyncDTO]) throws {
        try LocalWorkoutSyncStore(context: context).upsertWorkoutPayloads(payloads)
    }

    func markWorkoutDeleted(stableID: String, deletedAt: Date = Date()) throws {
        try LocalWorkoutSyncStore(context: context).markWorkoutDeleted(
            stableID: stableID,
            deletedAt: deletedAt
        )
    }

    func fetchTrainingProgramPayloads(since: Date?) throws -> [TrainingProgramSyncDTO] {
        try LocalProgramSyncStore(context: context).fetchTrainingProgramPayloads(since: since)
    }

    func upsertTrainingProgramPayloads(_ payloads: [TrainingProgramSyncDTO]) throws {
        try LocalProgramSyncStore(context: context).upsertTrainingProgramPayloads(payloads)
    }

    func fetchProgramRunPayloads(since: Date?) throws -> [ProgramRunSyncDTO] {
        try LocalProgramSyncStore(context: context).fetchProgramRunPayloads(since: since)
    }

    func upsertProgramRunPayloads(_ payloads: [ProgramRunSyncDTO]) throws {
        try LocalProgramSyncStore(context: context).upsertProgramRunPayloads(payloads)
    }

    func fetchDailyCheckInPayloads(since: Date?) throws -> [DailyCoachCheckInSyncDTO] {
        try LocalDailyCoachSyncStore(context: context).fetchDailyCheckInPayloads(since: since)
    }

    func upsertDailyCheckInPayloads(_ payloads: [DailyCoachCheckInSyncDTO]) throws {
        try LocalDailyCoachSyncStore(context: context).upsertDailyCheckInPayloads(payloads)
    }

    func fetchWeeklyReviewPayloads(since: Date?) throws -> [DailyCoachWeeklyReviewSyncDTO] {
        try LocalDailyCoachSyncStore(context: context).fetchWeeklyReviewPayloads(since: since)
    }

    func upsertWeeklyReviewPayloads(_ payloads: [DailyCoachWeeklyReviewSyncDTO]) throws {
        try LocalDailyCoachSyncStore(context: context).upsertWeeklyReviewPayloads(payloads)
    }

    func fetchAdaptationProposalPayloads(since: Date?) throws -> [AdaptationProposalSyncDTO] {
        try LocalAdaptiveSyncStore(context: context).fetchAdaptationProposalPayloads(since: since)
    }

    func upsertAdaptationProposalPayloads(_ payloads: [AdaptationProposalSyncDTO]) throws {
        try LocalAdaptiveSyncStore(context: context).upsertAdaptationProposalPayloads(payloads)
    }

    func fetchAppliedOverlayPayloads(since: Date?) throws -> [AppliedProgramOverlaySyncDTO] {
        try LocalAdaptiveSyncStore(context: context).fetchAppliedOverlayPayloads(since: since)
    }

    func upsertAppliedOverlayPayloads(_ payloads: [AppliedProgramOverlaySyncDTO]) throws {
        try LocalAdaptiveSyncStore(context: context).upsertAppliedOverlayPayloads(payloads)
    }

    func fetchHealthKitSummaryPayloads(since: Date?) throws -> [HealthKitDailySummarySyncDTO] {
        try LocalHealthKitSummarySyncStore(context: context).fetchHealthKitSummaryPayloads(since: since)
    }

    func upsertHealthKitSummaryPayloads(_ payloads: [HealthKitDailySummarySyncDTO]) throws {
        try LocalHealthKitSummarySyncStore(context: context).upsertHealthKitSummaryPayloads(payloads)
    }
}
