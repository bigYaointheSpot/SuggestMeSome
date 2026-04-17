import Foundation
import SwiftData

@MainActor
struct LocalHealthKitSummarySyncStore {
    let context: LocalSyncStoreContext

    func fetchHealthKitSummaryPayloads(since: Date?) throws -> [HealthKitDailySummarySyncDTO] {
        try context.measureSyncExport(named: "HealthKitDailySummary", since: since) {
            try context.fetchRows(healthKitSummaryFetchDescriptor(since: since))
                .map { $0.toSyncDTO() }
        }
    }

    func upsertHealthKitSummaryPayloads(_ payloads: [HealthKitDailySummarySyncDTO]) throws {
        guard !payloads.isEmpty else { return }

        var summaries = try context.stableIDMap(for: HealthKitDailySummary.self)
        for payload in payloads {
            if let existing = summaries[payload.metadata.stableID] {
                existing.apply(syncDTO: payload)
            } else {
                let row = HealthKitDailySummary(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    dayStart: payload.dayStart,
                    sleepDurationSeconds: payload.sleepDurationSeconds,
                    timeInBedSeconds: payload.timeInBedSeconds,
                    restingHeartRateBPM: payload.restingHeartRateBPM,
                    heartRateVariabilityMS: payload.heartRateVariabilityMS,
                    activeEnergyKilocalories: payload.activeEnergyKilocalories,
                    stepCount: payload.stepCount,
                    bodyMassKilograms: payload.bodyMassKilograms,
                    sourceUpdatedAt: payload.sourceUpdatedAt,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt
                )
                context.modelContext.insert(row)
                summaries[payload.metadata.stableID] = row
            }
        }

        try context.save()
    }

    private func healthKitSummaryFetchDescriptor(since: Date?) -> FetchDescriptor<HealthKitDailySummary> {
        let sortBy = [SortDescriptor(\HealthKitDailySummary.dayStart, order: .reverse)]
        guard let sinceDate = since else {
            return FetchDescriptor<HealthKitDailySummary>(sortBy: sortBy)
        }
        return FetchDescriptor<HealthKitDailySummary>(
            predicate: #Predicate<HealthKitDailySummary> { summary in
                summary.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }
}
