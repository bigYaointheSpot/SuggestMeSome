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

struct BlockingStartupMaintenanceReport: Equatable {
    let previousSchemaVersion: Int?
    let currentSchemaVersion: Int
    let performedSteps: [String]
    let shouldRunDeferredSyncMetadataAudit: Bool
}

struct DeferredStartupSyncAuditReport: Equatable {
    let didRunSyncMetadataAudit: Bool
    let syncAuditReport: SyncMetadataAuditReport
}

enum PersistenceMaintenanceCoordinator {
    static let schemaVersionDefaultsKey = "persistence.schemaVersion"
    static let lastAuditAtDefaultsKey = "persistence.lastAuditAt"
    static let syncAuditIntervalDays = 7
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SuggestMeSome",
        category: "PersistenceMaintenance"
    )

    @MainActor
    static func runStartupMaintenance(
        context: ModelContext,
        userDefaults: UserDefaults = .standard,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> PersistenceMaintenanceReport {
        let previousSchemaVersion = storedSchemaVersion(userDefaults: userDefaults)
        let lastAuditAt = storedLastAuditAt(userDefaults: userDefaults)
        let blockingReport = runBlockingStartupMaintenance(
            context: context,
            userDefaults: userDefaults,
            now: now,
            calendar: calendar
        )
        let deferredAuditReport = runDeferredStartupSyncAuditIfNeeded(
            context: context,
            shouldRunSyncAudit: blockingReport.shouldRunDeferredSyncMetadataAudit,
            userDefaults: userDefaults,
            now: now
        )
        let report = PersistenceMaintenanceReport(
            previousSchemaVersion: previousSchemaVersion,
            currentSchemaVersion: blockingReport.currentSchemaVersion,
            performedSteps: blockingReport.performedSteps + [
                deferredAuditReport.didRunSyncMetadataAudit
                ? "syncMetadataAuditAndRepair"
                : "syncMetadataAuditSkipped"
            ],
            didRunSyncMetadataAudit: deferredAuditReport.didRunSyncMetadataAudit,
            syncAuditReport: deferredAuditReport.syncAuditReport
        )
        logStartupMaintenance(
            report: report,
            lastAuditAt: lastAuditAt,
            elapsedMilliseconds: nil
        )
        return report
    }

    @MainActor
    static func runBlockingStartupMaintenance(
        context: ModelContext,
        userDefaults: UserDefaults = .standard,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> BlockingStartupMaintenanceReport {
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

        userDefaults.set(PersistenceSchemaVersion.current, forKey: schemaVersionDefaultsKey)

        let performedSteps = [
            "seedDefaultDataIfNeeded",
            "migrateExerciseTypesIfNeeded",
            "migrateExercisesV2IfNeeded",
        ]
        let report = BlockingStartupMaintenanceReport(
            previousSchemaVersion: previousSchemaVersion,
            currentSchemaVersion: PersistenceSchemaVersion.current,
            performedSteps: performedSteps,
            shouldRunDeferredSyncMetadataAudit: shouldRunSyncAudit
        )
        logBlockingStartupMaintenance(
            report: report,
            lastAuditAt: lastAuditAt,
            elapsedMilliseconds: (ProcessInfo.processInfo.systemUptime - maintenanceStartedAt) * 1_000
        )

        return report
    }

    static func runDeferredStartupSyncAuditIfNeeded(
        context: ModelContext,
        shouldRunSyncAudit: Bool,
        userDefaults: UserDefaults = .standard,
        now: Date = .now
    ) -> DeferredStartupSyncAuditReport {
        guard shouldRunSyncAudit else {
            return DeferredStartupSyncAuditReport(
                didRunSyncMetadataAudit: false,
                syncAuditReport: .skipped(auditedAt: now)
            )
        }

        let syncAuditReport = SyncMetadataAuditService.auditAndRepair(
            context: context,
            auditedAt: now
        )
        userDefaults.set(now.timeIntervalSince1970, forKey: lastAuditAtDefaultsKey)

        return DeferredStartupSyncAuditReport(
            didRunSyncMetadataAudit: true,
            syncAuditReport: syncAuditReport
        )
    }

    static func runDeferredStartupSyncAuditIfNeeded(
        container: ModelContainer,
        shouldRunSyncAudit: Bool,
        userDefaults: UserDefaults = .standard,
        now: Date = .now,
        makeContext: (ModelContainer) -> ModelContext = { ModelContext($0) },
        auditRunner: (ModelContext, Date) -> SyncMetadataAuditReport = { context, auditedAt in
            SyncMetadataAuditService.auditAndRepair(
                context: context,
                auditedAt: auditedAt
            )
        }
    ) -> DeferredStartupSyncAuditReport {
        guard shouldRunSyncAudit else {
            return DeferredStartupSyncAuditReport(
                didRunSyncMetadataAudit: false,
                syncAuditReport: .skipped(auditedAt: now)
            )
        }

        let context = makeContext(container)
        let syncAuditReport = auditRunner(context, now)
        userDefaults.set(now.timeIntervalSince1970, forKey: lastAuditAtDefaultsKey)

        return DeferredStartupSyncAuditReport(
            didRunSyncMetadataAudit: true,
            syncAuditReport: syncAuditReport
        )
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
        guard let nextScheduledAuditAt = calendar.date(
            byAdding: .day,
            value: syncAuditIntervalDays,
            to: lastAuditAt
        ) else {
            return true
        }
        return now >= nextScheduledAuditAt
    }

    private static func logBlockingStartupMaintenance(
        report: BlockingStartupMaintenanceReport,
        lastAuditAt: Date?,
        elapsedMilliseconds: Double
    ) {
        #if DEBUG
        let roundedMilliseconds = Int(elapsedMilliseconds.rounded())
        logger.debug(
            "blocking startup maintenance completed in \(roundedMilliseconds)ms; deferredAudit=\(report.shouldRunDeferredSyncMetadataAudit) previousSchemaVersion=\(report.previousSchemaVersion ?? -1) lastAuditAt=\(lastAuditAt?.timeIntervalSince1970 ?? -1)"
        )
        #endif
    }

    private static func logStartupMaintenance(
        report: PersistenceMaintenanceReport,
        lastAuditAt: Date?,
        elapsedMilliseconds: Double?
    ) {
        #if DEBUG
        if let elapsedMilliseconds {
            let roundedMilliseconds = Int(elapsedMilliseconds.rounded())
            logger.debug(
                "startup maintenance completed in \(roundedMilliseconds)ms; auditRan=\(report.didRunSyncMetadataAudit) previousSchemaVersion=\(report.previousSchemaVersion ?? -1) lastAuditAt=\(lastAuditAt?.timeIntervalSince1970 ?? -1)"
            )
        } else {
            logger.debug(
                "startup maintenance completed; auditRan=\(report.didRunSyncMetadataAudit) previousSchemaVersion=\(report.previousSchemaVersion ?? -1) lastAuditAt=\(lastAuditAt?.timeIntervalSince1970 ?? -1)"
            )
        }
        #endif
    }
}
