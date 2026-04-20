//
//  CollaborationRelationshipsStore.swift
//  SuggestMeSome
//
//  Owns CoachRelationship + CoachInvite state, the role-partitioned and
//  invite-direction derived views, and the invite-presentation helpers.
//  Lives behind CollaborationCoordinator's facade so existing call sites
//  keep reading `coordinator.relationships` / `coordinator.invites` /
//  `coordinator.coachRelationships` etc. unchanged.
//
//  ## Invalidation triggers
//  Derived-view caches (`CachedDerivation`) invalidate inside `apply(...)`
//  (post-cache-load) and `clear()` (on sign-out). `@Observable` propagates
//  view re-renders transparently when `relationships` / `invites` mutate.
//

import Foundation

@MainActor
@Observable
final class CollaborationRelationshipsStore {
    private(set) var relationships: [CoachRelationship] = []
    private(set) var invites: [CoachInvite] = []

    @ObservationIgnored private let currentAccountIDProvider: @MainActor () -> UUID?
    @ObservationIgnored private let currentAccountEmailProvider: @MainActor () -> String?

    @ObservationIgnored private let coachRelationshipsCache = CachedDerivation<[CoachRelationship]>()
    @ObservationIgnored private let athleteRelationshipsCache = CachedDerivation<[CoachRelationship]>()
    @ObservationIgnored private let incomingPendingInvitesCache = CachedDerivation<[CoachInvite]>()
    @ObservationIgnored private let outgoingPendingInvitesCache = CachedDerivation<[CoachInvite]>()

    init(
        currentAccountIDProvider: @MainActor @escaping () -> UUID?,
        currentAccountEmailProvider: @MainActor @escaping () -> String?
    ) {
        self.currentAccountIDProvider = currentAccountIDProvider
        self.currentAccountEmailProvider = currentAccountEmailProvider
    }

    // MARK: - State updates

    func apply(relationships: [CoachRelationship], invites: [CoachInvite]) {
        self.relationships = relationships
        self.invites = invites
        invalidateDerived()
    }

    func clear() {
        relationships = []
        invites = []
        invalidateDerived()
    }

    // MARK: - Derived views

    var coachRelationships: [CoachRelationship] {
        coachRelationshipsCache.get {
            relationships.filter { $0.currentRole(for: currentAccountIDProvider()) == .coach }
        }
    }

    var athleteRelationships: [CoachRelationship] {
        athleteRelationshipsCache.get {
            relationships.filter { $0.currentRole(for: currentAccountIDProvider()) == .athlete }
        }
    }

    var pendingInvites: [CoachInvite] {
        invites.filter { $0.status == .pending }
    }

    var incomingPendingInvites: [CoachInvite] {
        incomingPendingInvitesCache.get {
            invites.filter { invitePresentationMode(for: $0) == .incomingPending }
        }
    }

    var outgoingPendingInvites: [CoachInvite] {
        outgoingPendingInvitesCache.get {
            invites.filter { invitePresentationMode(for: $0) == .outgoingPending }
        }
    }

    // MARK: - Helpers

    func invitePresentationMode(for invite: CoachInvite) -> InvitePresentationMode {
        guard invite.status == .pending else { return .readOnly }
        if isIncomingInvite(invite) { return .incomingPending }
        if invite.inviterAccountID == currentAccountIDProvider() { return .outgoingPending }
        return .readOnly
    }

    func canWriteCoachNote(for relationship: CoachRelationship) -> Bool {
        relationship.currentRole(for: currentAccountIDProvider()) == .coach
    }

    func isIncomingInvite(_ invite: CoachInvite) -> Bool {
        let currentID = currentAccountIDProvider()
        if invite.inviteeAccountID == currentID { return true }
        guard invite.inviteeAccountID == nil else { return false }
        return Self.normalizedEmail(invite.inviteeEmail) == currentAccountEmailProvider()
    }

    static func normalizedEmail(_ email: String?) -> String? {
        email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func invalidateDerived() {
        coachRelationshipsCache.invalidate()
        athleteRelationshipsCache.invalidate()
        incomingPendingInvitesCache.invalidate()
        outgoingPendingInvitesCache.invalidate()
    }
}
