import Foundation
import SwiftData

struct SyncMetadataAuditEntityReport: Equatable {
    let entityName: String
    let totalRows: Int
    let repairedRows: Int
    let duplicateStableIDRepairs: Int
}

struct SyncMetadataAuditReport: Equatable {
    let auditedAt: Date
    let entityReports: [SyncMetadataAuditEntityReport]

    var totalRows: Int {
        entityReports.map(\.totalRows).reduce(0, +)
    }

    var repairedRows: Int {
        entityReports.map(\.repairedRows).reduce(0, +)
    }

    var duplicateStableIDRepairs: Int {
        entityReports.map(\.duplicateStableIDRepairs).reduce(0, +)
    }
}

@MainActor
enum SyncMetadataAuditService {
    @discardableResult
    static func auditAndRepair(
        context: ModelContext,
        auditedAt: Date = .now
    ) -> SyncMetadataAuditReport {
        let entityReports = [
            audit(Workout.self, named: "Workout", context: context, auditedAt: auditedAt),
            audit(ExerciseEntry.self, named: "ExerciseEntry", context: context, auditedAt: auditedAt),
            audit(SetEntry.self, named: "SetEntry", context: context, auditedAt: auditedAt),
            audit(PersonalRecord.self, named: "PersonalRecord", context: context, auditedAt: auditedAt),
            audit(TrainingProgram.self, named: "TrainingProgram", context: context, auditedAt: auditedAt),
            audit(ProgramRun.self, named: "ProgramRun", context: context, auditedAt: auditedAt),
            audit(ProgramSessionExercise.self, named: "ProgramSessionExercise", context: context, auditedAt: auditedAt),
            audit(DailyCoachCheckIn.self, named: "DailyCoachCheckIn", context: context, auditedAt: auditedAt),
            audit(DailyCoachWeeklyReview.self, named: "DailyCoachWeeklyReview", context: context, auditedAt: auditedAt),
            audit(AdaptationProposal.self, named: "AdaptationProposal", context: context, auditedAt: auditedAt),
            audit(AppliedProgramOverlay.self, named: "AppliedProgramOverlay", context: context, auditedAt: auditedAt),
            audit(AppliedOverlayAdjustment.self, named: "AppliedOverlayAdjustment", context: context, auditedAt: auditedAt),
            audit(HealthKitDailySummary.self, named: "HealthKitDailySummary", context: context, auditedAt: auditedAt),
        ]

        let report = SyncMetadataAuditReport(
            auditedAt: auditedAt,
            entityReports: entityReports
        )

        if report.repairedRows > 0 {
            try? context.save()
        }

        return report
    }

    private static func audit<Model: PersistentModel & SyncTrackableModel>(
        _ type: Model.Type,
        named entityName: String,
        context: ModelContext,
        auditedAt: Date
    ) -> SyncMetadataAuditEntityReport {
        let rows = (try? context.fetch(FetchDescriptor<Model>())) ?? []
        let duplicatePriorityByID = Dictionary(uniqueKeysWithValues: rows.map { row in
            (
                row.id,
                DuplicateResolutionPriority(
                    syncLastModifiedAt: row.syncLastModifiedAt,
                    syncVersion: row.syncVersion,
                    id: row.id
                )
            )
        })
        var repairedRowIDs: Set<UUID> = []
        var duplicateStableIDRepairs = 0

        for row in rows {
            if row.repairSyncMetadataIfNeeded(at: auditedAt) {
                repairedRowIDs.insert(row.id)
            }
        }

        let grouped = Dictionary(grouping: rows, by: \.resolvedSyncStableID)
        for group in grouped.values where group.count > 1 {
            let sorted = group.sorted { lhs, rhs in
                let lhsPriority = duplicatePriorityByID[lhs.id] ?? .init(
                    syncLastModifiedAt: lhs.syncLastModifiedAt,
                    syncVersion: lhs.syncVersion,
                    id: lhs.id
                )
                let rhsPriority = duplicatePriorityByID[rhs.id] ?? .init(
                    syncLastModifiedAt: rhs.syncLastModifiedAt,
                    syncVersion: rhs.syncVersion,
                    id: rhs.id
                )
                return lhsPriority.sortsBefore(rhsPriority)
            }
            guard let keeper = sorted.first else { continue }

            keeper.markSyncUpdated(at: auditedAt)
            repairedRowIDs.insert(keeper.id)

            for duplicate in sorted.dropFirst() {
                duplicate.assignReplacementSyncStableID(duplicate.id.uuidString, at: auditedAt)
                duplicateStableIDRepairs += 1
                repairedRowIDs.insert(duplicate.id)
            }
        }

        return SyncMetadataAuditEntityReport(
            entityName: entityName,
            totalRows: rows.count,
            repairedRows: repairedRowIDs.count,
            duplicateStableIDRepairs: duplicateStableIDRepairs
        )
    }
}

private struct DuplicateResolutionPriority {
    let syncLastModifiedAt: Date
    let syncVersion: Int
    let id: UUID

    func sortsBefore(_ other: DuplicateResolutionPriority) -> Bool {
        if syncLastModifiedAt != other.syncLastModifiedAt {
            return syncLastModifiedAt > other.syncLastModifiedAt
        }
        if syncVersion != other.syncVersion {
            return syncVersion > other.syncVersion
        }
        return id.uuidString < other.id.uuidString
    }
}
