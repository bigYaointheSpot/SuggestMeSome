import Foundation
import OSLog
import SwiftData

enum PersistenceSchemaVersion {
    static let v1 = 1
    static let v2 = 2
    static let current = v2
}

struct PersistenceMaintenanceReport: Equatable {
    let previousSchemaVersion: Int?
    let currentSchemaVersion: Int
    let performedSteps: [String]
    let didRunSyncMetadataAudit: Bool
    let syncAuditReport: SyncMetadataAuditReport
}

@MainActor
enum PersistenceMaintenanceCoordinator {
    static let schemaVersionDefaultsKey = "persistence.schemaVersion"
    static let lastAuditAtDefaultsKey = "persistence.lastAuditAt"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SuggestMeSome",
        category: "PersistenceMaintenance"
    )

    static func runStartupMaintenance(
        context: ModelContext,
        userDefaults: UserDefaults = .standard,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> PersistenceMaintenanceReport {
        let maintenanceStartedAt = ProcessInfo.processInfo.systemUptime
        let previousSchemaVersion = storedSchemaVersion(userDefaults: userDefaults)
        let lastAuditAt = storedLastAuditAt(userDefaults: userDefaults)

        seedDefaultDataIfNeeded(context: context)
        migrateExerciseTypesIfNeeded(context: context)
        migrateExercisesV2IfNeeded(context: context)

        let shouldRunSyncAudit = shouldRunStartupSyncAudit(
            previousSchemaVersion: previousSchemaVersion,
            lastAuditAt: lastAuditAt,
            now: now,
            calendar: calendar
        )
        let syncAuditReport: SyncMetadataAuditReport
        if shouldRunSyncAudit {
            syncAuditReport = SyncMetadataAuditService.auditAndRepair(
                context: context,
                auditedAt: now
            )
            userDefaults.set(now.timeIntervalSince1970, forKey: lastAuditAtDefaultsKey)
        } else {
            syncAuditReport = SyncMetadataAuditReport.skipped(auditedAt: now)
        }

        userDefaults.set(PersistenceSchemaVersion.current, forKey: schemaVersionDefaultsKey)

        let performedSteps = [
            "seedDefaultDataIfNeeded",
            "migrateExerciseTypesIfNeeded",
            "migrateExercisesV2IfNeeded",
            shouldRunSyncAudit ? "syncMetadataAuditAndRepair" : "syncMetadataAuditSkipped",
        ]
        let report = PersistenceMaintenanceReport(
            previousSchemaVersion: previousSchemaVersion,
            currentSchemaVersion: PersistenceSchemaVersion.current,
            performedSteps: performedSteps,
            didRunSyncMetadataAudit: shouldRunSyncAudit,
            syncAuditReport: syncAuditReport
        )
        logStartupMaintenance(
            report: report,
            lastAuditAt: lastAuditAt,
            elapsedMilliseconds: (ProcessInfo.processInfo.systemUptime - maintenanceStartedAt) * 1_000
        )

        return report
    }

    static func storedSchemaVersion(userDefaults: UserDefaults = .standard) -> Int? {
        guard userDefaults.object(forKey: schemaVersionDefaultsKey) != nil else {
            return nil
        }
        return userDefaults.integer(forKey: schemaVersionDefaultsKey)
    }

    static func storedLastAuditAt(userDefaults: UserDefaults = .standard) -> Date? {
        guard userDefaults.object(forKey: lastAuditAtDefaultsKey) != nil else {
            return nil
        }
        return Date(timeIntervalSince1970: userDefaults.double(forKey: lastAuditAtDefaultsKey))
    }

    static func shouldRunStartupSyncAudit(
        previousSchemaVersion: Int?,
        lastAuditAt: Date?,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        if previousSchemaVersion != PersistenceSchemaVersion.current {
            return true
        }
        guard let lastAuditAt else {
            return true
        }
        return !calendar.isDate(lastAuditAt, inSameDayAs: now)
    }

    private static func logStartupMaintenance(
        report: PersistenceMaintenanceReport,
        lastAuditAt: Date?,
        elapsedMilliseconds: Double
    ) {
        #if DEBUG
        let roundedMilliseconds = Int(elapsedMilliseconds.rounded())
        if report.didRunSyncMetadataAudit {
            logger.debug(
                "startup maintenance completed in \(roundedMilliseconds)ms; auditRan=true repairedRows=\(report.syncAuditReport.repairedRows) totalRows=\(report.syncAuditReport.totalRows) previousSchemaVersion=\(report.previousSchemaVersion ?? -1)"
            )
        } else {
            logger.debug(
                "startup maintenance completed in \(roundedMilliseconds)ms; auditRan=false previousSchemaVersion=\(report.previousSchemaVersion ?? -1) lastAuditAt=\(lastAuditAt?.timeIntervalSince1970 ?? -1)"
            )
        }
        #endif
    }
}
