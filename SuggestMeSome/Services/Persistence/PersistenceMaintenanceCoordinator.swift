import Foundation
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
    let syncAuditReport: SyncMetadataAuditReport
}

@MainActor
enum PersistenceMaintenanceCoordinator {
    static let schemaVersionDefaultsKey = "persistence.schemaVersion"
    static let lastAuditAtDefaultsKey = "persistence.lastAuditAt"

    static func runStartupMaintenance(
        context: ModelContext,
        userDefaults: UserDefaults = .standard,
        now: Date = .now
    ) -> PersistenceMaintenanceReport {
        let previousSchemaVersion = storedSchemaVersion(userDefaults: userDefaults)

        seedDefaultDataIfNeeded(context: context)
        migrateExerciseTypesIfNeeded(context: context)
        migrateExercisesV2IfNeeded(context: context)

        let syncAuditReport = SyncMetadataAuditService.auditAndRepair(
            context: context,
            auditedAt: now
        )

        userDefaults.set(PersistenceSchemaVersion.current, forKey: schemaVersionDefaultsKey)
        userDefaults.set(now.timeIntervalSince1970, forKey: lastAuditAtDefaultsKey)

        return PersistenceMaintenanceReport(
            previousSchemaVersion: previousSchemaVersion,
            currentSchemaVersion: PersistenceSchemaVersion.current,
            performedSteps: [
                "seedDefaultDataIfNeeded",
                "migrateExerciseTypesIfNeeded",
                "migrateExercisesV2IfNeeded",
                "syncMetadataAuditAndRepair",
            ],
            syncAuditReport: syncAuditReport
        )
    }

    static func storedSchemaVersion(userDefaults: UserDefaults = .standard) -> Int? {
        guard userDefaults.object(forKey: schemaVersionDefaultsKey) != nil else {
            return nil
        }
        return userDefaults.integer(forKey: schemaVersionDefaultsKey)
    }
}
