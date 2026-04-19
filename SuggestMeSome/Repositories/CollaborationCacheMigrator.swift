//
//  CollaborationCacheMigrator.swift
//  SuggestMeSome
//
//  One-shot cleanup that de-duplicates collaboration cache rows before the
//  @Attribute(.unique) constraint on stableID is enforced. Runs inside the
//  existing blocking startup maintenance path, gated by a single
//  @AppStorage flag so it only executes once per install. Existing rows
//  should never contain duplicates in practice (server writes are
//  stableID-keyed), but shipping the migrator ahead of the uniqueness
//  constraint protects users whose cache drifted before this version.
//

import Foundation
import SwiftData

/// One-shot cleanup that de-duplicates collaboration cache rows ahead of
/// the `@Attribute(.unique)` constraint on every collaboration model's
/// `stableID`.
///
/// Runs inside `PersistenceMaintenanceCoordinator.runBlockingStartupMaintenance`,
/// gated by the `collaboration.cacheDedupV1` `@AppStorage` flag so it
/// executes at most once per install. Each per-model pass keeps the row
/// with the newest `updatedAt` (ties resolve by first-seen) and deletes
/// the rest, then a single `ModelContext.save()` commits the cleanup.
/// Existing rows should never contain duplicates in practice — server
/// writes are stableID-keyed and the coordinator's `replaceAll(...)`
/// upserts by stableID — but shipping this migrator ahead of the unique
/// constraint protects users whose cache drifted before the constraint
/// landed.
///
/// ## Bumping the version
/// If a future schema change needs to re-run the cleanup pass, bump the
/// `dedupFlagKey` suffix (V1 → V2) so previously-migrated installs run
/// through the logic again.
enum CollaborationCacheMigrator {
    /// UserDefaults key tracking whether the dedup pass has already run.
    /// Bump the version suffix (V1 → V2) if the migration logic ever needs
    /// to re-run for a future schema change.
    static let dedupFlagKey = "collaboration.cacheDedupV1"

    /// Result summary returned to the caller so startup maintenance can
    /// log or audit the behavior.
    struct Report: Equatable {
        var didRun: Bool
        var removedCountsByModel: [String: Int]

        static let skipped = Report(didRun: false, removedCountsByModel: [:])
    }

    /// De-duplicates every collaboration cache table by `stableID`, keeping
    /// the row with the newest `updatedAt` (falling back to the newest
    /// insertion when timestamps tie). Safe to call from the main actor on
    /// the shared `ModelContext`.
    @MainActor
    static func dedupIfNeeded(
        context: ModelContext,
        userDefaults: UserDefaults = .standard
    ) -> Report {
        guard !userDefaults.bool(forKey: dedupFlagKey) else {
            return .skipped
        }

        var removedCountsByModel: [String: Int] = [:]
        dedupCoachRelationships(context: context, removedCountsByModel: &removedCountsByModel)
        dedupCoachInvites(context: context, removedCountsByModel: &removedCountsByModel)
        dedupProgramAssignments(context: context, removedCountsByModel: &removedCountsByModel)
        dedupCoachNotes(context: context, removedCountsByModel: &removedCountsByModel)
        dedupNotificationPreferences(context: context, removedCountsByModel: &removedCountsByModel)
        dedupDevicePushRegistrations(context: context, removedCountsByModel: &removedCountsByModel)
        dedupInsightSnapshots(context: context, removedCountsByModel: &removedCountsByModel)
        dedupWeeklyDigests(context: context, removedCountsByModel: &removedCountsByModel)
        dedupSavedProgramBlueprints(context: context, removedCountsByModel: &removedCountsByModel)
        dedupProgramShareGrants(context: context, removedCountsByModel: &removedCountsByModel)
        dedupProgressShareCards(context: context, removedCountsByModel: &removedCountsByModel)

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Leave the flag unset so the next launch retries. Flipping
                // it here would lock us out of retrying after a transient
                // save failure, risking the @Attribute(.unique) constraint
                // tripping on stale duplicates next launch.
                return Report(didRun: false, removedCountsByModel: [:])
            }
        }

        userDefaults.set(true, forKey: dedupFlagKey)
        return Report(didRun: true, removedCountsByModel: removedCountsByModel)
    }

    // MARK: - Per-model passes

    @MainActor
    private static func dedupCoachRelationships(
        context: ModelContext,
        removedCountsByModel: inout [String: Int]
    ) {
        let rows = (try? context.fetch(FetchDescriptor<CoachRelationship>())) ?? []
        let removed = keepNewestPerStableID(rows: rows, context: context) { $0.stableID } newestBy: { $0.updatedAt }
        if removed > 0 { removedCountsByModel["CoachRelationship"] = removed }
    }

    @MainActor
    private static func dedupCoachInvites(
        context: ModelContext,
        removedCountsByModel: inout [String: Int]
    ) {
        let rows = (try? context.fetch(FetchDescriptor<CoachInvite>())) ?? []
        let removed = keepNewestPerStableID(rows: rows, context: context) { $0.stableID } newestBy: { $0.updatedAt }
        if removed > 0 { removedCountsByModel["CoachInvite"] = removed }
    }

    @MainActor
    private static func dedupProgramAssignments(
        context: ModelContext,
        removedCountsByModel: inout [String: Int]
    ) {
        let rows = (try? context.fetch(FetchDescriptor<ProgramAssignment>())) ?? []
        let removed = keepNewestPerStableID(rows: rows, context: context) { $0.stableID } newestBy: { $0.updatedAt }
        if removed > 0 { removedCountsByModel["ProgramAssignment"] = removed }
    }

    @MainActor
    private static func dedupCoachNotes(
        context: ModelContext,
        removedCountsByModel: inout [String: Int]
    ) {
        let rows = (try? context.fetch(FetchDescriptor<CoachNote>())) ?? []
        let removed = keepNewestPerStableID(rows: rows, context: context) { $0.stableID } newestBy: { $0.updatedAt }
        if removed > 0 { removedCountsByModel["CoachNote"] = removed }
    }

    @MainActor
    private static func dedupNotificationPreferences(
        context: ModelContext,
        removedCountsByModel: inout [String: Int]
    ) {
        let rows = (try? context.fetch(FetchDescriptor<NotificationPreference>())) ?? []
        let removed = keepNewestPerStableID(rows: rows, context: context) { $0.stableID } newestBy: { $0.updatedAt }
        if removed > 0 { removedCountsByModel["NotificationPreference"] = removed }
    }

    @MainActor
    private static func dedupDevicePushRegistrations(
        context: ModelContext,
        removedCountsByModel: inout [String: Int]
    ) {
        let rows = (try? context.fetch(FetchDescriptor<DevicePushRegistration>())) ?? []
        let removed = keepNewestPerStableID(rows: rows, context: context) { $0.stableID } newestBy: { $0.updatedAt }
        if removed > 0 { removedCountsByModel["DevicePushRegistration"] = removed }
    }

    @MainActor
    private static func dedupInsightSnapshots(
        context: ModelContext,
        removedCountsByModel: inout [String: Int]
    ) {
        let rows = (try? context.fetch(FetchDescriptor<InsightSnapshot>())) ?? []
        let removed = keepNewestPerStableID(rows: rows, context: context) { $0.stableID } newestBy: { $0.updatedAt }
        if removed > 0 { removedCountsByModel["InsightSnapshot"] = removed }
    }

    @MainActor
    private static func dedupWeeklyDigests(
        context: ModelContext,
        removedCountsByModel: inout [String: Int]
    ) {
        let rows = (try? context.fetch(FetchDescriptor<WeeklyDigest>())) ?? []
        let removed = keepNewestPerStableID(rows: rows, context: context) { $0.stableID } newestBy: { $0.updatedAt }
        if removed > 0 { removedCountsByModel["WeeklyDigest"] = removed }
    }

    @MainActor
    private static func dedupSavedProgramBlueprints(
        context: ModelContext,
        removedCountsByModel: inout [String: Int]
    ) {
        let rows = (try? context.fetch(FetchDescriptor<SavedProgramBlueprint>())) ?? []
        let removed = keepNewestPerStableID(rows: rows, context: context) { $0.stableID } newestBy: { $0.updatedAt }
        if removed > 0 { removedCountsByModel["SavedProgramBlueprint"] = removed }
    }

    @MainActor
    private static func dedupProgramShareGrants(
        context: ModelContext,
        removedCountsByModel: inout [String: Int]
    ) {
        let rows = (try? context.fetch(FetchDescriptor<ProgramShareGrant>())) ?? []
        let removed = keepNewestPerStableID(rows: rows, context: context) { $0.stableID } newestBy: { $0.updatedAt }
        if removed > 0 { removedCountsByModel["ProgramShareGrant"] = removed }
    }

    @MainActor
    private static func dedupProgressShareCards(
        context: ModelContext,
        removedCountsByModel: inout [String: Int]
    ) {
        let rows = (try? context.fetch(FetchDescriptor<ProgressShareCard>())) ?? []
        let removed = keepNewestPerStableID(rows: rows, context: context) { $0.stableID } newestBy: { $0.updatedAt }
        if removed > 0 { removedCountsByModel["ProgressShareCard"] = removed }
    }

    // MARK: - Shared logic

    @MainActor
    private static func keepNewestPerStableID<T: PersistentModel>(
        rows: [T],
        context: ModelContext,
        stableID: (T) -> String,
        newestBy: (T) -> Date
    ) -> Int {
        guard rows.count > 1 else { return 0 }

        var bestByStableID: [String: T] = [:]
        var duplicates: [T] = []

        for row in rows {
            let key = stableID(row)
            if let existing = bestByStableID[key] {
                if newestBy(row) > newestBy(existing) {
                    duplicates.append(existing)
                    bestByStableID[key] = row
                } else {
                    duplicates.append(row)
                }
            } else {
                bestByStableID[key] = row
            }
        }

        for duplicate in duplicates {
            context.delete(duplicate)
        }

        return duplicates.count
    }
}
