//
//  Feature20CollaborationStoresTests.swift
//  SuggestMeSomeTests
//
//  Focused coverage for the five @Observable sub-stores extracted out
//  of CollaborationCoordinator in Feature 20 Prompt 2. Each test drives
//  an `apply(...)` → derived-view → `clear()` cycle in isolation so the
//  memoized filter behavior (via CachedDerivation) stays verifiable
//  without standing up the full coordinator.
//

import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature20CollaborationStoresTests {

    // MARK: - Relationships store

    @Test func relationshipsStorePartitionsByRole() {
        let accountID = UUID()
        let store = CollaborationRelationshipsStore(
            currentAccountIDProvider: { accountID },
            currentAccountEmailProvider: { nil }
        )

        let coachRel = CoachRelationship(
            stableID: "rel-coach",
            statusRawValue: CoachRelationshipStatus.active.rawValue,
            coachAccountID: accountID,
            coachDisplayName: "Self",
            athleteAccountID: UUID(),
            athleteDisplayName: "Athlete A",
            visibilityScopeBitmask: 0
        )
        let athleteRel = CoachRelationship(
            stableID: "rel-athlete",
            statusRawValue: CoachRelationshipStatus.active.rawValue,
            coachAccountID: UUID(),
            coachDisplayName: "Coach B",
            athleteAccountID: accountID,
            athleteDisplayName: "Self",
            visibilityScopeBitmask: 0
        )
        store.apply(relationships: [coachRel, athleteRel], invites: [])

        #expect(store.coachRelationships.map(\.stableID) == ["rel-coach"])
        #expect(store.athleteRelationships.map(\.stableID) == ["rel-athlete"])
    }

    @Test func relationshipsStoreClassifiesIncomingVsOutgoingInvites() {
        let accountID = UUID()
        let store = CollaborationRelationshipsStore(
            currentAccountIDProvider: { accountID },
            currentAccountEmailProvider: { "me@example.com" }
        )

        let incomingByID = CoachInvite(
            stableID: "invite-incoming-id",
            statusRawValue: CoachInviteStatus.pending.rawValue,
            inviterAccountID: UUID(),
            inviterDisplayName: "Coach X",
            inviterRoleRawValue: CollaborationRole.coach.rawValue,
            inviteeEmail: "other@example.com",
            visibilityScopeBitmask: 0
        )
        incomingByID.inviteeAccountID = accountID
        let incomingByEmail = CoachInvite(
            stableID: "invite-incoming-email",
            statusRawValue: CoachInviteStatus.pending.rawValue,
            inviterAccountID: UUID(),
            inviterDisplayName: "Coach Y",
            inviterRoleRawValue: CollaborationRole.coach.rawValue,
            inviteeEmail: "  ME@example.com  ",
            visibilityScopeBitmask: 0
        )
        let outgoing = CoachInvite(
            stableID: "invite-outgoing",
            statusRawValue: CoachInviteStatus.pending.rawValue,
            inviterAccountID: accountID,
            inviterDisplayName: "Self",
            inviterRoleRawValue: CollaborationRole.coach.rawValue,
            inviteeEmail: "target@example.com",
            visibilityScopeBitmask: 0
        )
        let accepted = CoachInvite(
            stableID: "invite-accepted",
            statusRawValue: CoachInviteStatus.accepted.rawValue,
            inviterAccountID: accountID,
            inviterDisplayName: "Self",
            inviterRoleRawValue: CollaborationRole.coach.rawValue,
            inviteeEmail: "target@example.com",
            visibilityScopeBitmask: 0
        )

        store.apply(
            relationships: [],
            invites: [incomingByID, incomingByEmail, outgoing, accepted]
        )

        #expect(Set(store.incomingPendingInvites.map(\.stableID)) == ["invite-incoming-id", "invite-incoming-email"])
        #expect(store.outgoingPendingInvites.map(\.stableID) == ["invite-outgoing"])
        #expect(store.pendingInvites.count == 3)
    }

    @Test func relationshipsStoreClearResetsState() {
        let store = CollaborationRelationshipsStore(
            currentAccountIDProvider: { nil },
            currentAccountEmailProvider: { nil }
        )
        let rel = CoachRelationship(
            stableID: "r",
            statusRawValue: CoachRelationshipStatus.active.rawValue,
            coachAccountID: UUID(),
            coachDisplayName: "C",
            athleteAccountID: UUID(),
            athleteDisplayName: "A",
            visibilityScopeBitmask: 0
        )
        store.apply(relationships: [rel], invites: [])
        #expect(store.relationships.count == 1)
        store.clear()
        #expect(store.relationships.isEmpty)
        #expect(store.invites.isEmpty)
    }

    // MARK: - Assignments store

    @Test func assignmentsStoreInboxFiltersByAthleteAndPendingStatus() {
        let accountID = UUID()
        let otherAccount = UUID()
        let store = CollaborationAssignmentsStore(
            currentAccountIDProvider: { accountID }
        )

        let pendingMine = ProgramAssignment(
            stableID: "assign-mine-pending",
            relationshipStableID: "rel-1",
            blueprintStableID: "bp-1",
            coachAccountID: otherAccount,
            coachDisplayName: "Coach",
            athleteAccountID: accountID,
            athleteDisplayName: "Me",
            statusRawValue: ProgramAssignmentStatus.pending.rawValue
        )
        let acceptedMine = ProgramAssignment(
            stableID: "assign-mine-accepted",
            relationshipStableID: "rel-1",
            blueprintStableID: "bp-1",
            coachAccountID: otherAccount,
            coachDisplayName: "Coach",
            athleteAccountID: accountID,
            athleteDisplayName: "Me",
            statusRawValue: ProgramAssignmentStatus.accepted.rawValue
        )
        let pendingSomeoneElse = ProgramAssignment(
            stableID: "assign-other-pending",
            relationshipStableID: "rel-2",
            blueprintStableID: "bp-1",
            coachAccountID: accountID,
            coachDisplayName: "Me",
            athleteAccountID: otherAccount,
            athleteDisplayName: "Someone",
            statusRawValue: ProgramAssignmentStatus.pending.rawValue
        )

        store.apply(assignments: [pendingMine, acceptedMine, pendingSomeoneElse])

        #expect(store.inboxAssignments.map(\.stableID) == ["assign-mine-pending"])
        #expect(store.canActOnAssignment(pendingMine))
        #expect(!store.canActOnAssignment(acceptedMine))
        #expect(!store.canActOnAssignment(pendingSomeoneElse))
    }

    // MARK: - Notes store

    @Test func notesStoreUnreadFilterMatchesSource() {
        let store = CollaborationNotesStore()
        let unread = CoachNote(
            stableID: "note-unread",
            relationshipStableID: "rel-1",
            authorAccountID: UUID(),
            authorDisplayName: "Coach",
            recipientAccountID: UUID(),
            recipientDisplayName: "Athlete",
            bodyText: "Hi",
            anchorKindRawValue: CoachNoteAnchorKind.general.rawValue
        )
        unread.isUnread = true
        let read = CoachNote(
            stableID: "note-read",
            relationshipStableID: "rel-1",
            authorAccountID: UUID(),
            authorDisplayName: "Coach",
            recipientAccountID: UUID(),
            recipientDisplayName: "Athlete",
            bodyText: "Hi again",
            anchorKindRawValue: CoachNoteAnchorKind.general.rawValue
        )
        read.isUnread = false

        store.apply(notes: [unread, read])
        #expect(store.unreadCoachNotes.map(\.stableID) == ["note-unread"])

        store.clear()
        #expect(store.notes.isEmpty)
        #expect(store.unreadCoachNotes.isEmpty)
    }

    // MARK: - Insights store

    @Test func insightsStoreRosterSnapshotsMatchCoachRelationshipIDs() {
        let accountID = UUID()
        var coachIDs: Set<String> = ["rel-a", "rel-b"]
        let store = CollaborationInsightsStore(
            currentAccountIDProvider: { accountID },
            coachRelationshipIDsProvider: { coachIDs }
        )

        let matchingA = InsightSnapshot(
            stableID: "snap-a",
            accountID: UUID(),
            accountDisplayName: "Athlete A",
            headline: "Good",
            summaryText: "Adherent"
        )
        matchingA.relationshipStableID = "rel-a"
        let matchingB = InsightSnapshot(
            stableID: "snap-b",
            accountID: UUID(),
            accountDisplayName: "Athlete B",
            headline: "Watchful",
            summaryText: "Fatigue"
        )
        matchingB.relationshipStableID = "rel-b"
        let orphan = InsightSnapshot(
            stableID: "snap-orphan",
            accountID: UUID(),
            accountDisplayName: "Drop",
            headline: "Gone",
            summaryText: "Gone"
        )
        orphan.relationshipStableID = "rel-c"
        let selfFacing = InsightSnapshot(
            stableID: "snap-self",
            accountID: accountID,
            accountDisplayName: "Me",
            headline: "Self",
            summaryText: "Self view"
        )

        store.apply(
            insightSnapshots: [matchingA, matchingB, orphan, selfFacing],
            weeklyDigests: []
        )

        #expect(Set(store.coachRosterSnapshots.map(\.stableID)) == ["snap-a", "snap-b"])
        #expect(store.athleteFacingSnapshots.map(\.stableID) == ["snap-self"])

        // Shrinking the coach-relationship set must recompute the filter —
        // the cache invalidates only on `apply`/`clear`, so re-apply.
        coachIDs = ["rel-a"]
        store.apply(
            insightSnapshots: [matchingA, matchingB, orphan, selfFacing],
            weeklyDigests: []
        )
        #expect(store.coachRosterSnapshots.map(\.stableID) == ["snap-a"])
    }

    // MARK: - Blueprints + Shares

    @Test func blueprintsStoreApplyAndClearRoundTrip() {
        let store = CollaborationBlueprintsStore()
        let blueprint = SavedProgramBlueprint(
            stableID: "bp-1",
            name: "Peaking Block",
            durationWeeks: 8,
            sessionsPerWeek: 4,
            trainingProgramSnapshotJSON: "{}"
        )
        store.apply(blueprints: [blueprint])
        #expect(store.blueprints.map(\.stableID) == ["bp-1"])
        store.clear()
        #expect(store.blueprints.isEmpty)
    }

    @Test func sharesStoreTracksBothProgramAndProgress() {
        let store = CollaborationSharesStore()
        let programShare = ProgramShareGrant(
            stableID: "ps-1",
            shareKindRawValue: ProgramShareKind.blueprint.rawValue,
            statusRawValue: ShareGrantStatus.active.rawValue,
            grantedByAccountID: UUID(),
            grantedByDisplayName: "Me",
            grantedToAccountID: UUID(),
            grantedToDisplayName: "Coach"
        )
        let progressShare = ProgressShareCard(
            stableID: "prog-1",
            shareKindRawValue: ProgressShareKind.completedBlockSummary.rawValue,
            statusRawValue: ShareGrantStatus.active.rawValue,
            grantedByAccountID: UUID(),
            grantedByDisplayName: "Me",
            grantedToAccountID: UUID(),
            grantedToDisplayName: "Coach",
            titleText: "Block 1",
            summaryText: "Solid",
            payloadJSON: "{}"
        )
        store.apply(programShares: [programShare], progressShares: [progressShare])
        #expect(store.programShares.map(\.stableID) == ["ps-1"])
        #expect(store.progressShares.map(\.stableID) == ["prog-1"])
        store.clear()
        #expect(store.programShares.isEmpty)
        #expect(store.progressShares.isEmpty)
    }
}
