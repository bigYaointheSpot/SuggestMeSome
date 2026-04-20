//
//  CollaborationInsightsStore.swift
//  SuggestMeSome
//
//  Owns InsightSnapshot + WeeklyDigest state plus the expensive
//  roster-filter derivation (Set-build + filter across thousands of
//  snapshots for heavy coach accounts). This was the single most
//  expensive derived property on the coordinator; caching it here
//  keeps the filter off the SwiftUI body-invocation hot path.
//
//  Depends on coach-relationship IDs from
//  CollaborationRelationshipsStore via a closure so the sub-stores stay
//  decoupled — the insight roster set is "relationship IDs where the
//  signed-in user is the coach".
//

import Foundation

@MainActor
@Observable
final class CollaborationInsightsStore {
    private(set) var insightSnapshots: [InsightSnapshot] = []
    private(set) var weeklyDigests: [WeeklyDigest] = []

    @ObservationIgnored private let currentAccountIDProvider: @MainActor () -> UUID?
    @ObservationIgnored private let coachRelationshipIDsProvider: @MainActor () -> Set<String>

    @ObservationIgnored private let coachRosterSnapshotsCache = CachedDerivation<[InsightSnapshot]>()

    init(
        currentAccountIDProvider: @MainActor @escaping () -> UUID?,
        coachRelationshipIDsProvider: @MainActor @escaping () -> Set<String>
    ) {
        self.currentAccountIDProvider = currentAccountIDProvider
        self.coachRelationshipIDsProvider = coachRelationshipIDsProvider
    }

    // MARK: - State updates

    func apply(insightSnapshots: [InsightSnapshot], weeklyDigests: [WeeklyDigest]) {
        self.insightSnapshots = insightSnapshots
        self.weeklyDigests = weeklyDigests
        coachRosterSnapshotsCache.invalidate()
    }

    func clear() {
        insightSnapshots = []
        weeklyDigests = []
        coachRosterSnapshotsCache.invalidate()
    }

    // MARK: - Derived views

    var coachRosterSnapshots: [InsightSnapshot] {
        coachRosterSnapshotsCache.get {
            let coachRelationshipIDs = coachRelationshipIDsProvider()
            return insightSnapshots.filter { snapshot in
                if let relationshipStableID = snapshot.relationshipStableID {
                    return coachRelationshipIDs.contains(relationshipStableID)
                }
                return false
            }
        }
    }

    var athleteFacingSnapshots: [InsightSnapshot] {
        let accountID = currentAccountIDProvider()
        return insightSnapshots.filter { $0.accountID == accountID }
    }

    var unreadDigests: [WeeklyDigest] {
        weeklyDigests.filter(\.isUnread)
    }
}
