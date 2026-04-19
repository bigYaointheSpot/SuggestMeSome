import Foundation

struct TrainingPreferencesSnapshot: Codable, Equatable {
    var globalWeightUnitRawValue: String
    var defaultRestTimerSeconds: Int
    var coachPreferredDaysBitmask: Int
}

enum TrainingPreferencesStore {
    static let stableID = "training-preferences::primary"
    private static let initialSyncLastModifiedAt = Date(timeIntervalSince1970: 0)

    private enum Key {
        static let globalWeightUnit = "globalWeightUnit"
        static let defaultRestTimerSeconds = "defaultRestTimerSeconds"
        static let coachPreferredDays = "coachPreferredDays"
        static let syncVersion = "cloudsync.trainingPreferences.version"
        static let syncLastModifiedAt = "cloudsync.trainingPreferences.lastModifiedAt"
        static let syncDeletedAt = "cloudsync.trainingPreferences.deletedAt"
    }

    static func snapshot(userDefaults: UserDefaults = .standard) -> TrainingPreferencesSnapshot {
        TrainingPreferencesSnapshot(
            globalWeightUnitRawValue: userDefaults.string(forKey: Key.globalWeightUnit) ?? WeightUnit.lbs.rawValue,
            defaultRestTimerSeconds: userDefaults.object(forKey: Key.defaultRestTimerSeconds) as? Int ?? 90,
            coachPreferredDaysBitmask: userDefaults.object(forKey: Key.coachPreferredDays) as? Int ?? 42
        )
    }

    static func metadata(userDefaults: UserDefaults = .standard) -> SyncRecordMetadataDTO {
        let version = max(1, userDefaults.object(forKey: Key.syncVersion) as? Int ?? 1)
        let lastModifiedAt = Date(
            timeIntervalSince1970: userDefaults.object(forKey: Key.syncLastModifiedAt) as? Double ?? initialSyncLastModifiedAt.timeIntervalSince1970
        )
        let deletedAt: Date?
        if let deletedAtSeconds = userDefaults.object(forKey: Key.syncDeletedAt) as? Double {
            deletedAt = Date(timeIntervalSince1970: deletedAtSeconds)
        } else {
            deletedAt = nil
        }

        return SyncRecordMetadataDTO(
            stableID: stableID,
            version: version,
            lastModifiedAt: lastModifiedAt,
            deletedAt: deletedAt
        )
    }

    static func currentSyncDTO(userDefaults: UserDefaults = .standard) -> TrainingPreferencesSyncDTO {
        let current = snapshot(userDefaults: userDefaults)
        return TrainingPreferencesSyncDTO(
            metadata: metadata(userDefaults: userDefaults),
            globalWeightUnitRawValue: current.globalWeightUnitRawValue,
            defaultRestTimerSeconds: current.defaultRestTimerSeconds,
            coachPreferredDaysBitmask: current.coachPreferredDaysBitmask
        )
    }

    static func markUpdated(
        userDefaults: UserDefaults = .standard,
        at date: Date = .now
    ) {
        let previousVersion = max(1, userDefaults.object(forKey: Key.syncVersion) as? Int ?? 1)
        userDefaults.set(previousVersion + 1, forKey: Key.syncVersion)
        userDefaults.set(date.timeIntervalSince1970, forKey: Key.syncLastModifiedAt)
        userDefaults.removeObject(forKey: Key.syncDeletedAt)
    }

    static func apply(
        _ payload: TrainingPreferencesSyncDTO,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(payload.globalWeightUnitRawValue, forKey: Key.globalWeightUnit)
        userDefaults.set(payload.defaultRestTimerSeconds, forKey: Key.defaultRestTimerSeconds)
        userDefaults.set(payload.coachPreferredDaysBitmask, forKey: Key.coachPreferredDays)
        userDefaults.set(payload.metadata.version, forKey: Key.syncVersion)
        userDefaults.set(payload.metadata.lastModifiedAt.timeIntervalSince1970, forKey: Key.syncLastModifiedAt)
        if let deletedAt = payload.metadata.deletedAt {
            userDefaults.set(deletedAt.timeIntervalSince1970, forKey: Key.syncDeletedAt)
        } else {
            userDefaults.removeObject(forKey: Key.syncDeletedAt)
        }
    }
}
