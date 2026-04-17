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
            if let existing = checkIns[payload.metadata.stableID] {
                existing.apply(syncDTO: payload, programRun: run)
            } else {
                let checkIn = DailyCoachCheckIn(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
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
            if let existing = reviews[payload.metadata.stableID] {
                existing.syncStableID = payload.metadata.stableID
                existing.syncVersion = payload.metadata.version
                existing.syncLastModifiedAt = payload.metadata.lastModifiedAt
                existing.weekStart = payload.weekStart
                existing.weekEnd = payload.weekEnd
                existing.isProgramWeek = payload.isProgramWeek
                existing.programRun = run
                existing.headline = payload.headline
                existing.winText = payload.winText
                existing.watchoutText = payload.watchoutText
                existing.nextActionText = payload.nextActionText
                existing.sourceWeeklyAnalysisIDText = payload.sourceWeeklyAnalysisIDText
                existing.hasBeenSeen = payload.hasBeenSeen
                existing.createdAt = payload.createdAt
            } else {
                let review = DailyCoachWeeklyReview(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
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
            return FetchDescriptor<DailyCoachCheckIn>(sortBy: sortBy)
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
            return FetchDescriptor<DailyCoachWeeklyReview>(sortBy: sortBy)
        }
        return FetchDescriptor<DailyCoachWeeklyReview>(
            predicate: #Predicate<DailyCoachWeeklyReview> { review in
                review.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }
}
