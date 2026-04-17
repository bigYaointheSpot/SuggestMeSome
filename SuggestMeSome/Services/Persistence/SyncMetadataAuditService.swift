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
        var seenStableIDs: Set<String> = []
        var repairedRows = 0
        var duplicateStableIDRepairs = 0

        for row in rows {
            let hadRepair = row.repairSyncMetadataIfNeeded(at: auditedAt)

            let resolvedStableID = row.resolvedSyncStableID
            if seenStableIDs.contains(resolvedStableID) {
                row.assignReplacementSyncStableID(row.id.uuidString, at: auditedAt)
                duplicateStableIDRepairs += 1
                repairedRows += hadRepair ? 0 : 1
                seenStableIDs.insert(row.resolvedSyncStableID)
            } else {
                seenStableIDs.insert(resolvedStableID)
                if hadRepair {
                    repairedRows += 1
                }
            }
        }

        return SyncMetadataAuditEntityReport(
            entityName: entityName,
            totalRows: rows.count,
            repairedRows: repairedRows,
            duplicateStableIDRepairs: duplicateStableIDRepairs
        )
    }
}
