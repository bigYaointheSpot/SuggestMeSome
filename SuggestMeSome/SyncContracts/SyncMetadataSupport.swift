import Foundation

protocol SyncTrackableModel: AnyObject {
    var id: UUID { get }
    var syncStableID: String? { get set }
    var syncVersion: Int { get set }
    var syncLastModifiedAt: Date { get set }
}

protocol SyncTombstoneTrackable: AnyObject {
    var syncDeletedAt: Date? { get set }
}

extension SyncTrackableModel {
    var resolvedSyncStableID: String {
        let trimmed = syncStableID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return id.uuidString
    }

    func initializeSyncMetadataIfNeeded(at date: Date = Date()) {
        if syncStableID?.isEmpty != false {
            syncStableID = id.uuidString
        }
        if syncVersion < 1 {
            syncVersion = 1
        }
        if syncLastModifiedAt == .distantPast {
            syncLastModifiedAt = date
        }
    }

    func markSyncUpdated(at date: Date = Date()) {
        initializeSyncMetadataIfNeeded(at: date)
        syncVersion = max(1, syncVersion) + 1
        syncLastModifiedAt = date
    }

    @discardableResult
    func repairSyncMetadataIfNeeded(at date: Date = Date()) -> Bool {
        var didRepair = false

        let trimmedStableID = syncStableID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if syncStableID != trimmedStableID {
            syncStableID = trimmedStableID
            didRepair = true
        }
        if trimmedStableID?.isEmpty != false {
            syncStableID = id.uuidString
            didRepair = true
        }
        if syncVersion < 1 {
            syncVersion = 1
            didRepair = true
        }
        if syncLastModifiedAt == .distantPast {
            syncLastModifiedAt = date
            didRepair = true
        }
        if let tombstone = self as? any SyncTombstoneTrackable,
           let deletedAt = tombstone.syncDeletedAt,
           syncLastModifiedAt < deletedAt {
            syncLastModifiedAt = deletedAt
            didRepair = true
        }

        if didRepair {
            syncVersion = max(1, syncVersion) + 1
            syncLastModifiedAt = max(syncLastModifiedAt, date)
        }

        return didRepair
    }

    func assignReplacementSyncStableID(_ stableID: String, at date: Date = Date()) {
        syncStableID = stableID
        syncVersion = max(1, syncVersion) + 1
        syncLastModifiedAt = date
    }
}

extension SyncTrackableModel where Self: SyncTombstoneTrackable {
    func markSyncDeleted(at date: Date = Date()) {
        syncDeletedAt = date
        markSyncUpdated(at: date)
    }
}

extension Workout: SyncTrackableModel, SyncTombstoneTrackable {}
extension ExerciseEntry: SyncTrackableModel {}
extension SetEntry: SyncTrackableModel {}
extension PersonalRecord: SyncTrackableModel {}
extension TrainingProgram: SyncTrackableModel, SyncTombstoneTrackable {}
extension ProgramRun: SyncTrackableModel, SyncTombstoneTrackable {}
extension ProgramSessionExercise: SyncTrackableModel {}
extension DailyCoachCheckIn: SyncTrackableModel, SyncTombstoneTrackable {}
extension DailyCoachWeeklyReview: SyncTrackableModel, SyncTombstoneTrackable {}
extension WeeklyTrainingAnalysis: SyncTrackableModel, SyncTombstoneTrackable {}
extension LiftPerformanceTrend: SyncTrackableModel, SyncTombstoneTrackable {}
extension AdaptationProposal: SyncTrackableModel, SyncTombstoneTrackable {}
extension AppliedProgramOverlay: SyncTrackableModel, SyncTombstoneTrackable {}
extension AppliedOverlayAdjustment: SyncTrackableModel {}
extension AdaptationEventHistory: SyncTrackableModel, SyncTombstoneTrackable {}
extension HealthKitDailySummary: SyncTrackableModel {}
