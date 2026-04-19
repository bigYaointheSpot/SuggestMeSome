import Foundation
import SwiftData

@MainActor
struct LocalDailyCoachSyncStore {
    let context: LocalSyncStoreContext

    func fetchDailyCheckInPayloads(since: Date?) throws -> [DailyCoachCheckInSyncDTO] {
        try context.measureSyncExport(named: "DailyCoachCheckIn", since: since) {
            try context.fetchRows(dailyCheckInFetchDescriptor(since: since))
                .map { $0.toSyncDTO() }
        }
    }

    func upsertDailyCheckInPayloads(_ payloads: [DailyCoachCheckInSyncDTO]) throws {
        guard !payloads.isEmpty else { return }

        var checkIns = try context.stableIDMap(for: DailyCoachCheckIn.self)
        let runs = try context.stableIDMap(for: ProgramRun.self)

        for payload in payloads {
            let run = payload.programRunStableID.flatMap { runs[$0] }
            let existing = checkIns[payload.metadata.stableID] ?? dedupeCheckInTarget(
                dayStart: payload.dayStart,
                existing: Array(checkIns.values)
            )

            if payload.metadata.deletedAt != nil {
                if let existing {
                    context.modelContext.delete(existing)
                    checkIns[existing.resolvedSyncStableID] = nil
                }
                continue
            }

            if let existing {
                existing.apply(syncDTO: payload, programRun: run)
                checkIns[payload.metadata.stableID] = existing
            } else {
                let checkIn = DailyCoachCheckIn(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    syncDeletedAt: payload.metadata.deletedAt,
                    date: payload.date,
                    dayStart: payload.dayStart,
                    sleepQuality: payload.sleepQuality,
                    soreness: payload.soreness,
                    energy: payload.energy,
                    stress: payload.stress,
                    availableTimeMinutes: payload.availableTimeMinutes,
                    hasPainOrDiscomfort: payload.hasPainOrDiscomfort,
                    painNotes: payload.painNotes,
                    programRun: run,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt
                )
                context.modelContext.insert(checkIn)
                checkIns[payload.metadata.stableID] = checkIn
            }
        }

        try context.save()
    }

    func fetchWeeklyReviewPayloads(since: Date?) throws -> [DailyCoachWeeklyReviewSyncDTO] {
        try context.measureSyncExport(named: "DailyCoachWeeklyReview", since: since) {
            try context.fetchRows(weeklyReviewFetchDescriptor(since: since))
                .map { $0.toSyncDTO() }
        }
    }

    func upsertWeeklyReviewPayloads(_ payloads: [DailyCoachWeeklyReviewSyncDTO]) throws {
        guard !payloads.isEmpty else { return }

        var reviews = try context.stableIDMap(for: DailyCoachWeeklyReview.self)
        let runs = try context.stableIDMap(for: ProgramRun.self)

        for payload in payloads {
            let run = payload.programRunStableID.flatMap { runs[$0] }
            let existing = reviews[payload.metadata.stableID] ?? dedupeWeeklyReviewTarget(
                payload: payload,
                existing: Array(reviews.values)
            )

            if payload.metadata.deletedAt != nil {
                if let existing {
                    context.modelContext.delete(existing)
                    reviews[existing.resolvedSyncStableID] = nil
                }
                continue
            }

            if let existing {
                existing.apply(syncDTO: payload, programRun: run)
                reviews[payload.metadata.stableID] = existing
            } else {
                let review = DailyCoachWeeklyReview(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    syncDeletedAt: payload.metadata.deletedAt,
                    weekStart: payload.weekStart,
                    weekEnd: payload.weekEnd,
                    isProgramWeek: payload.isProgramWeek,
                    programRun: run,
                    headline: payload.headline,
                    winText: payload.winText,
                    watchoutText: payload.watchoutText,
                    nextActionText: payload.nextActionText,
                    sourceWeeklyAnalysisIDText: payload.sourceWeeklyAnalysisIDText,
                    hasBeenSeen: payload.hasBeenSeen,
                    createdAt: payload.createdAt
                )
                context.modelContext.insert(review)
                reviews[payload.metadata.stableID] = review
            }
        }

        try context.save()
    }

    private func dailyCheckInFetchDescriptor(since: Date?) -> FetchDescriptor<DailyCoachCheckIn> {
        let sortBy = [SortDescriptor(\DailyCoachCheckIn.date, order: .reverse)]
        guard let sinceDate = since else {
            return FetchDescriptor<DailyCoachCheckIn>(
                predicate: #Predicate<DailyCoachCheckIn> { checkIn in
                    checkIn.syncDeletedAt == nil
                },
                sortBy: sortBy
            )
        }
        return FetchDescriptor<DailyCoachCheckIn>(
            predicate: #Predicate<DailyCoachCheckIn> { checkIn in
                checkIn.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }

    private func weeklyReviewFetchDescriptor(since: Date?) -> FetchDescriptor<DailyCoachWeeklyReview> {
        let sortBy = [SortDescriptor(\DailyCoachWeeklyReview.weekStart, order: .reverse)]
        guard let sinceDate = since else {
            return FetchDescriptor<DailyCoachWeeklyReview>(
                predicate: #Predicate<DailyCoachWeeklyReview> { review in
                    review.syncDeletedAt == nil
                },
                sortBy: sortBy
            )
        }
        return FetchDescriptor<DailyCoachWeeklyReview>(
            predicate: #Predicate<DailyCoachWeeklyReview> { review in
                review.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }

    private func dedupeCheckInTarget(
        dayStart: Date,
        existing: [DailyCoachCheckIn]
    ) -> DailyCoachCheckIn? {
        existing.first { $0.dayStart == dayStart }
    }

    private func dedupeWeeklyReviewTarget(
        payload: DailyCoachWeeklyReviewSyncDTO,
        existing: [DailyCoachWeeklyReview]
    ) -> DailyCoachWeeklyReview? {
        existing.first { review in
            review.weekStart == payload.weekStart &&
            review.programRun?.resolvedSyncStableID == payload.programRunStableID
        }
    }
}
