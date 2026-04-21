import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature19CollaborationFoundationTests {

    @Test func deepLinkRoutesMapIntoExistingTabs() {
        #expect(AppDeepLinkRoute(url: URL(string: "suggestmesome://collaboration")!) == .collaborationHub)
        #expect(AppDeepLinkRoute(url: URL(string: "suggestmesome://assignment/assignment-1")!)?.targetTab == .programs)
        #expect(AppDeepLinkRoute(url: URL(string: "suggestmesome://note/note-1")!)?.targetTab == .dailyCoach)
        #expect(AppDeepLinkRoute(url: URL(string: "suggestmesome://insight/insight-1")!)?.targetTab == .dashboard)
        #expect(AppDeepLinkRoute.fromNotificationUserInfo([
            "deepLinkTarget": "notificationPreferences"
        ]) == .notificationPreferences)
    }

    @Test func localCollaborationCacheStoreReplacesCollections() throws {
        let container = try makeInMemoryContainer()
        let store = LocalCollaborationCacheStore(modelContext: container.mainContext)

        try store.replaceRelationships(with: [
            CoachRelationshipDTO(
                stableID: "relationship-1",
                createdAt: day(1),
                updatedAt: day(2),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                invitedByAccountID: uuid(1),
                visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                unreadCoachNoteCount: 2,
                pendingAssignmentCount: 1,
                latestInsightSnapshotAt: day(2)
            )
        ])
        try store.replaceBlueprints(with: [
            SavedProgramBlueprintDTO(
                stableID: "blueprint-1",
                createdAt: day(1),
                updatedAt: day(2),
                name: "Strength Block",
                focusText: "Strength",
                notesText: "Top set emphasis",
                tags: ["strength", "barbell"],
                durationWeeks: 8,
                sessionsPerWeek: 4,
                sourceProgramStableID: "program-1",
                createdByAccountID: uuid(1),
                createdByDisplayName: "Coach Alex",
                trainingProgramSnapshotJSON: "{\"name\":\"Strength Block\"}",
                lastSharedAt: nil
            )
        ])
        try store.replaceNotificationPreference(with: NotificationPreferenceDTO(
            stableID: "notification-preferences::primary",
            updatedAt: day(3),
            coachInvitesEnabled: true,
            assignmentUpdatesEnabled: true,
            coachNotesEnabled: true,
            missedSessionNudgesEnabled: false,
            checkInRemindersEnabled: true,
            pendingProposalRemindersEnabled: true,
            weeklyDigestsEnabled: true
        ))

        let snapshot = try store.loadSnapshot()
        #expect(snapshot.relationships.count == 1)
        #expect(snapshot.relationships.first?.coachDisplayName == "Coach Alex")
        #expect(snapshot.blueprints.first?.tags == ["strength", "barbell"])
        #expect(snapshot.notificationPreference?.missedSessionNudgesEnabled == false)
    }

    @Test func collaborationCoordinatorRefreshesAndCachesServerState() async throws {
        let container = try makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: "Feature19Refresh.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let tokenStore = InMemoryCloudSessionTokenStore(tokens: feature19Tokens())
        let collaborationClient = MockCollaborationClient()
        collaborationClient.relationships = [
            CoachRelationshipDTO(
                stableID: "relationship-1",
                createdAt: day(1),
                updatedAt: day(2),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                invitedByAccountID: uuid(1),
                visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                unreadCoachNoteCount: 1,
                pendingAssignmentCount: 1,
                latestInsightSnapshotAt: day(2)
            )
        ]
        collaborationClient.invites = [
            CoachInviteDTO(
                stableID: "invite-1",
                createdAt: day(1),
                updatedAt: day(1),
                expiresAt: day(10),
                statusRawValue: CoachInviteStatus.pending.rawValue,
                inviterAccountID: uuid(1),
                inviterDisplayName: "Coach Alex",
                inviterRoleRawValue: CollaborationRole.coach.rawValue,
                inviteeAccountID: nil,
                inviteeEmail: "athlete@example.com",
                inviteeDisplayName: "Athlete Sam",
                relationshipStableID: nil,
                visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                noteText: "Want to work together?"
            )
        ]
        collaborationClient.assignments = [
            ProgramAssignmentDTO(
                stableID: "assignment-1",
                createdAt: day(2),
                updatedAt: day(2),
                relationshipStableID: "relationship-1",
                blueprintStableID: "blueprint-1",
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                statusRawValue: ProgramAssignmentStatus.pending.rawValue,
                notesText: "Start Monday",
                startGuidance: "Focus on bar speed",
                importedTrainingProgramStableID: nil,
                importedProgramRunStableID: nil,
                respondedAt: nil,
                archivedAt: nil
            )
        ]
        collaborationClient.notes = [
            CoachNoteDTO(
                stableID: "note-1",
                createdAt: day(2),
                updatedAt: day(2),
                relationshipStableID: "relationship-1",
                authorAccountID: uuid(1),
                authorDisplayName: "Coach Alex",
                recipientAccountID: uuid(2),
                recipientDisplayName: "Athlete Sam",
                bodyText: "Take the first session conservatively.",
                anchorKindRawValue: CoachNoteAnchorKind.general.rawValue,
                anchoredWorkoutStableID: nil,
                anchoredProgramRunStableID: nil,
                anchoredWeekStart: nil,
                anchoredWeekEnd: nil,
                eventSummaryText: "New block kickoff",
                priorityRawValue: CollaborationInsightPriority.medium.rawValue,
                isUnread: true,
                requiresReview: false
            )
        ]
        collaborationClient.notificationPreference = NotificationPreferenceDTO(
            stableID: "notification-preferences::primary",
            updatedAt: day(3),
            coachInvitesEnabled: true,
            assignmentUpdatesEnabled: true,
            coachNotesEnabled: true,
            missedSessionNudgesEnabled: true,
            checkInRemindersEnabled: true,
            pendingProposalRemindersEnabled: true,
            weeklyDigestsEnabled: true
        )
        collaborationClient.snapshots = [
            InsightSnapshotDTO(
                stableID: "snapshot-1",
                createdAt: day(2),
                updatedAt: day(3),
                relationshipStableID: "relationship-1",
                accountID: uuid(2),
                accountDisplayName: "Athlete Sam",
                activeProgramName: "Strength Block",
                syncFreshnessAt: day(3),
                lastWorkoutAt: day(2),
                recentAdherenceScore: 91,
                fatigueStatusRawValue: "managed",
                pendingProposalCount: 1,
                unreadCoachNoteCount: 1,
                prMomentumSummary: "Up",
                liftTrendSummary: "Bench trending up",
                fatigueRunwaySummary: "Good runway",
                completionRiskSummary: "Low",
                reviewPriorityText: "Monitor squat fatigue",
                headline: "Good adherence heading into week 2.",
                summaryText: "Bench and squat signals are stable, with one pending proposal to review.",
                detailText: nil,
                priorityRawValue: CollaborationInsightPriority.medium.rawValue
            )
        ]
        collaborationClient.digests = [
            WeeklyDigestDTO(
                stableID: "digest-1",
                createdAt: day(3),
                updatedAt: day(3),
                weekStart: day(0),
                weekEnd: day(6),
                audienceRawValue: WeeklyDigestAudience.athlete.rawValue,
                relationshipStableID: "relationship-1",
                accountID: uuid(2),
                titleText: "Week 1 Digest",
                summaryText: "Strong start with one readiness dip.",
                highlightsText: "Bench volume completed, sleep dipped twice.",
                reviewPrioritiesText: "Watch Friday fatigue.",
                isUnread: true
            )
        ]
        collaborationClient.blueprints = [
            SavedProgramBlueprintDTO(
                stableID: "blueprint-1",
                createdAt: day(1),
                updatedAt: day(1),
                name: "Strength Block",
                focusText: "Strength",
                notesText: nil,
                tags: ["strength"],
                durationWeeks: 8,
                sessionsPerWeek: 4,
                sourceProgramStableID: "program-1",
                createdByAccountID: uuid(1),
                createdByDisplayName: "Coach Alex",
                trainingProgramSnapshotJSON: "{\"name\":\"Strength Block\"}",
                lastSharedAt: nil
            )
        ]
        collaborationClient.programShares = []
        collaborationClient.progressShares = []

        let coordinator = CollaborationCoordinator(
            collaborationClient: collaborationClient,
            backendClient: MockCloudBackendClient(),
            tokenStore: tokenStore,
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)

        await coordinator.handleAccountStateDidChange(feature19SignedInState())

        #expect(coordinator.phase == .idle)
        #expect(coordinator.relationships.count == 1)
        #expect(coordinator.pendingInvites.count == 1)
        #expect(coordinator.inboxAssignments.count == 1)
        #expect(coordinator.unreadCoachNotes.count == 1)
        #expect(coordinator.athleteFacingSnapshots.count == 1)
        #expect(coordinator.weeklyDigests.count == 1)
        #expect(coordinator.blueprints.count == 1)
    }

    @Test func collaborationCoordinatorSeparatesIncomingAndOutgoingInvites() async throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature19InviteModes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tokenStore = InMemoryCloudSessionTokenStore(tokens: feature19Tokens())
        let collaborationClient = MockCollaborationClient()
        collaborationClient.invites = [
            CoachInviteDTO(
                stableID: "invite-incoming-account",
                createdAt: day(1),
                updatedAt: day(2),
                expiresAt: day(10),
                statusRawValue: CoachInviteStatus.pending.rawValue,
                inviterAccountID: uuid(1),
                inviterDisplayName: "Coach Alex",
                inviterRoleRawValue: CollaborationRole.coach.rawValue,
                inviteeAccountID: uuid(2),
                inviteeEmail: "athlete@example.com",
                inviteeDisplayName: "Athlete Sam",
                relationshipStableID: nil,
                visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                noteText: nil
            ),
            CoachInviteDTO(
                stableID: "invite-incoming-email",
                createdAt: day(2),
                updatedAt: day(3),
                expiresAt: day(10),
                statusRawValue: CoachInviteStatus.pending.rawValue,
                inviterAccountID: uuid(1),
                inviterDisplayName: "Coach Alex",
                inviterRoleRawValue: CollaborationRole.coach.rawValue,
                inviteeAccountID: nil,
                inviteeEmail: "Athlete@Example.com",
                inviteeDisplayName: "Athlete Sam",
                relationshipStableID: nil,
                visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                noteText: nil
            ),
            CoachInviteDTO(
                stableID: "invite-outgoing",
                createdAt: day(3),
                updatedAt: day(4),
                expiresAt: day(10),
                statusRawValue: CoachInviteStatus.pending.rawValue,
                inviterAccountID: uuid(2),
                inviterDisplayName: "Athlete Sam",
                inviterRoleRawValue: CollaborationRole.athlete.rawValue,
                inviteeAccountID: nil,
                inviteeEmail: "coach@example.com",
                inviteeDisplayName: "Coach Alex",
                relationshipStableID: nil,
                visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                noteText: nil
            )
        ]

        let coordinator = CollaborationCoordinator(
            collaborationClient: collaborationClient,
            backendClient: MockCloudBackendClient(),
            tokenStore: tokenStore,
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)

        await coordinator.handleAccountStateDidChange(feature19SignedInState())

        #expect(coordinator.athleteRelationships.isEmpty)
        #expect(coordinator.shouldShowMyCoachEmptyState == false)
        #expect(coordinator.incomingPendingInvites.map(\.stableID) == [
            "invite-incoming-email",
            "invite-incoming-account"
        ])
        #expect(coordinator.outgoingPendingInvites.map(\.stableID) == ["invite-outgoing"])
        #expect(
            coordinator.invitePresentationMode(for: coordinator.incomingPendingInvites[0]) == .incomingPending
        )
        #expect(
            coordinator.invitePresentationMode(for: coordinator.outgoingPendingInvites[0]) == .outgoingPending
        )
    }

    @Test func assignmentInboxOnlyIncludesPendingAthleteAssignments() async throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature19Assignments.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tokenStore = InMemoryCloudSessionTokenStore(tokens: feature19Tokens())
        let collaborationClient = MockCollaborationClient()
        // Seed relationships alongside assignments so the refresh payload is
        // internally consistent — replaceAll sweeps dependents whose parent
        // isn't in the fresh relationship set.
        collaborationClient.relationships = [
            CoachRelationshipDTO(
                stableID: "relationship-1",
                createdAt: day(1),
                updatedAt: day(2),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                invitedByAccountID: uuid(1),
                visibilityScopeBitmask: 0,
                unreadCoachNoteCount: 0,
                pendingAssignmentCount: 0,
                latestInsightSnapshotAt: nil
            ),
            CoachRelationshipDTO(
                stableID: "relationship-2",
                createdAt: day(1),
                updatedAt: day(2),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(3),
                athleteDisplayName: "Athlete Jordan",
                invitedByAccountID: uuid(1),
                visibilityScopeBitmask: 0,
                unreadCoachNoteCount: 0,
                pendingAssignmentCount: 0,
                latestInsightSnapshotAt: nil
            )
        ]
        collaborationClient.assignments = [
            ProgramAssignmentDTO(
                stableID: "assignment-pending",
                createdAt: day(1),
                updatedAt: day(4),
                relationshipStableID: "relationship-1",
                blueprintStableID: "blueprint-1",
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                statusRawValue: ProgramAssignmentStatus.pending.rawValue,
                notesText: nil,
                startGuidance: nil,
                importedTrainingProgramStableID: nil,
                importedProgramRunStableID: nil,
                respondedAt: nil,
                archivedAt: nil
            ),
            ProgramAssignmentDTO(
                stableID: "assignment-accepted",
                createdAt: day(1),
                updatedAt: day(3),
                relationshipStableID: "relationship-1",
                blueprintStableID: "blueprint-1",
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                statusRawValue: ProgramAssignmentStatus.accepted.rawValue,
                notesText: nil,
                startGuidance: nil,
                importedTrainingProgramStableID: "program-1",
                importedProgramRunStableID: "run-1",
                respondedAt: day(3),
                archivedAt: nil
            ),
            ProgramAssignmentDTO(
                stableID: "assignment-other-athlete",
                createdAt: day(1),
                updatedAt: day(2),
                relationshipStableID: "relationship-2",
                blueprintStableID: "blueprint-2",
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(3),
                athleteDisplayName: "Athlete Jordan",
                statusRawValue: ProgramAssignmentStatus.pending.rawValue,
                notesText: nil,
                startGuidance: nil,
                importedTrainingProgramStableID: nil,
                importedProgramRunStableID: nil,
                respondedAt: nil,
                archivedAt: nil
            )
        ]

        let coordinator = CollaborationCoordinator(
            collaborationClient: collaborationClient,
            backendClient: MockCloudBackendClient(),
            tokenStore: tokenStore,
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)

        await coordinator.handleAccountStateDidChange(feature19SignedInState())

        #expect(coordinator.inboxAssignments.map(\.stableID) == ["assignment-pending"])
        #expect(coordinator.canActOnAssignment(coordinator.inboxAssignments[0]))
        #expect(
            coordinator.canActOnAssignment(
                coordinator.assignments.first { $0.stableID == "assignment-accepted" }!
            ) == false
        )
    }

    @Test func collaborationCoordinatorGatesCoachNotesByRelationshipRole() throws {
        let container = try makeInMemoryContainer()
        let coordinator = CollaborationCoordinator(
            collaborationClient: MockCollaborationClient(),
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: UserDefaults(suiteName: "Feature19Roles.\(UUID().uuidString)")!),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)

        let relationship = CoachRelationship(
            stableID: "relationship-1",
            statusRawValue: CoachRelationshipStatus.active.rawValue,
            coachAccountID: uuid(1),
            coachDisplayName: "Coach Alex",
            athleteAccountID: uuid(2),
            athleteDisplayName: "Athlete Sam",
            visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes)
        )

        coordinator.hydrateAccountState(feature19SignedInState())
        #expect(coordinator.canWriteCoachNote(for: relationship) == false)

        coordinator.hydrateAccountState(feature19CoachState())
        #expect(coordinator.canWriteCoachNote(for: relationship))
    }

    @Test func collaborationCoordinatorHydratesWithoutRefreshingAndForegroundRefreshesOnce() async throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature19Lifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let collaborationClient = MockCollaborationClient()
        let coordinator = CollaborationCoordinator(
            collaborationClient: collaborationClient,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)

        coordinator.hydrateAccountState(feature19SignedInState())
        #expect(collaborationClient.totalRefreshFetchCount == 0)

        await coordinator.handleAccountStateDidChange(feature19SignedInState())
        #expect(collaborationClient.totalRefreshFetchCount == 0)

        await coordinator.refreshOnAppDidBecomeActive()
        #expect(collaborationClient.totalRefreshFetchCount == 11)

        await coordinator.handleAccountStateDidChange(feature19SignedInState())
        #expect(collaborationClient.totalRefreshFetchCount == 11)
    }

    @Test func collaborationCoordinatorCoalescesOverlappingRefreshes() async throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature19RefreshCoalesce.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let collaborationClient = MockCollaborationClient()
        collaborationClient.refreshDelayNanoseconds = 50_000_000

        let coordinator = CollaborationCoordinator(
            collaborationClient: collaborationClient,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)
        coordinator.hydrateAccountState(feature19SignedInState())

        async let firstRefresh: Void = coordinator.refreshAll(reason: "First foreground refresh")
        async let secondRefresh: Void = coordinator.refreshAll(reason: "Second foreground refresh")
        _ = await (firstRefresh, secondRefresh)

        #expect(collaborationClient.totalRefreshFetchCount == 11)
    }

    @Test func collaborationCoordinatorSkipsUnchangedPushRegistration() async throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature19PushRegistration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let collaborationClient = MockCollaborationClient()
        let coordinator = CollaborationCoordinator(
            collaborationClient: collaborationClient,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)
        coordinator.hydrateAccountState(feature19SignedInState())

        await coordinator.handlePushAuthorizationStateChange(.authorized, deviceToken: "device-token")
        await coordinator.handlePushAuthorizationStateChange(.authorized, deviceToken: "device-token")

        #expect(collaborationClient.registerDeviceCallCount == 1)
    }

    @Test func localCollaborationCacheStoreReplaceAllSavesOnceAndPreservesOrdering() throws {
        let container = try makeInMemoryContainer()
        var saveCount = 0
        let store = LocalCollaborationCacheStore(
            modelContext: container.mainContext,
            saveHandler: {
                saveCount += 1
                try container.mainContext.save()
            }
        )

        try store.replaceAll(
            with: CollaborationFullRefreshPayload(
                relationships: [
                    CoachRelationshipDTO(
                        stableID: "relationship-newer",
                        createdAt: day(1),
                        updatedAt: day(4),
                        statusRawValue: CoachRelationshipStatus.active.rawValue,
                        coachAccountID: uuid(1),
                        coachDisplayName: "Coach Alex",
                        athleteAccountID: uuid(2),
                        athleteDisplayName: "Athlete Sam",
                        invitedByAccountID: uuid(1),
                        visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                        unreadCoachNoteCount: 1,
                        pendingAssignmentCount: 0,
                        latestInsightSnapshotAt: day(4)
                    ),
                    CoachRelationshipDTO(
                        stableID: "relationship-older",
                        createdAt: day(1),
                        updatedAt: day(2),
                        statusRawValue: CoachRelationshipStatus.active.rawValue,
                        coachAccountID: uuid(3),
                        coachDisplayName: "Coach Drew",
                        athleteAccountID: uuid(2),
                        athleteDisplayName: "Athlete Sam",
                        invitedByAccountID: uuid(3),
                        visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                        unreadCoachNoteCount: 0,
                        pendingAssignmentCount: 0,
                        latestInsightSnapshotAt: nil
                    )
                ],
                invites: [],
                assignments: [],
                notes: [
                    CoachNoteDTO(
                        stableID: "note-unread",
                        createdAt: day(1),
                        updatedAt: day(2),
                        relationshipStableID: "relationship-newer",
                        authorAccountID: uuid(1),
                        authorDisplayName: "Coach Alex",
                        recipientAccountID: uuid(2),
                        recipientDisplayName: "Athlete Sam",
                        bodyText: "Unread note",
                        anchorKindRawValue: CoachNoteAnchorKind.general.rawValue,
                        anchoredWorkoutStableID: nil,
                        anchoredProgramRunStableID: nil,
                        anchoredWeekStart: nil,
                        anchoredWeekEnd: nil,
                        eventSummaryText: nil,
                        priorityRawValue: CollaborationInsightPriority.medium.rawValue,
                        isUnread: true,
                        requiresReview: false
                    ),
                    CoachNoteDTO(
                        stableID: "note-read-newer",
                        createdAt: day(1),
                        updatedAt: day(4),
                        relationshipStableID: "relationship-newer",
                        authorAccountID: uuid(1),
                        authorDisplayName: "Coach Alex",
                        recipientAccountID: uuid(2),
                        recipientDisplayName: "Athlete Sam",
                        bodyText: "Read note",
                        anchorKindRawValue: CoachNoteAnchorKind.general.rawValue,
                        anchoredWorkoutStableID: nil,
                        anchoredProgramRunStableID: nil,
                        anchoredWeekStart: nil,
                        anchoredWeekEnd: nil,
                        eventSummaryText: nil,
                        priorityRawValue: CollaborationInsightPriority.medium.rawValue,
                        isUnread: false,
                        requiresReview: false
                    )
                ],
                notificationPreference: NotificationPreferenceDTO(
                    stableID: "notification-preferences::primary",
                    updatedAt: day(3),
                    coachInvitesEnabled: true,
                    assignmentUpdatesEnabled: true,
                    coachNotesEnabled: true,
                    missedSessionNudgesEnabled: true,
                    checkInRemindersEnabled: true,
                    pendingProposalRemindersEnabled: true,
                    weeklyDigestsEnabled: true
                ),
                insightSnapshots: [],
                weeklyDigests: [],
                blueprints: [],
                programShares: [],
                progressShares: []
            )
        )

        let snapshot = try store.loadSnapshot()
        #expect(saveCount == 1)
        #expect(snapshot.relationships.map(\.stableID) == ["relationship-newer", "relationship-older"])
        #expect(snapshot.notes.map(\.stableID) == ["note-unread", "note-read-newer"])
    }

    @Test func collaborationCoordinatorSaveBlueprintEncodesProgramAndRefreshesLibrary() async throws {
        let container = try makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: "Feature19Blueprint.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let tokenStore = InMemoryCloudSessionTokenStore(tokens: feature19Tokens())
        let collaborationClient = MockCollaborationClient()
        collaborationClient.notificationPreference = NotificationPreferenceDTO(
            stableID: "notification-preferences::primary",
            updatedAt: day(1),
            coachInvitesEnabled: true,
            assignmentUpdatesEnabled: true,
            coachNotesEnabled: true,
            missedSessionNudgesEnabled: true,
            checkInRemindersEnabled: true,
            pendingProposalRemindersEnabled: true,
            weeklyDigestsEnabled: true
        )
        let coordinator = CollaborationCoordinator(
            collaborationClient: collaborationClient,
            backendClient: MockCloudBackendClient(),
            tokenStore: tokenStore,
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)
        await coordinator.handleAccountStateDidChange(feature19SignedInState())

        let program = TrainingProgram(
            id: uuid(20),
            syncStableID: "program-local-1",
            syncVersion: 2,
            syncLastModifiedAt: day(2),
            name: "Peaking Block",
            lengthInWeeks: 6,
            sessionsPerWeek: 4,
            createdDate: day(1),
            source: .aiGenerated,
            descriptionText: "Low-fatigue peaking"
        )
        container.mainContext.insert(program)
        try container.mainContext.save()

        await coordinator.saveBlueprint(
            from: program,
            focusText: "Peaking",
            notesText: "Taper into test week",
            tags: ["peaking", "low fatigue"]
        )

        #expect(collaborationClient.savedBlueprintRequests.count == 1)
        #expect(collaborationClient.savedBlueprintRequests[0].name == "Peaking Block")
        #expect(collaborationClient.savedBlueprintRequests[0].trainingProgramSnapshotJSON.contains("Peaking Block"))
        #expect(coordinator.blueprints.count == 1)
        #expect(coordinator.blueprints.first?.focusText == "Peaking")
        #expect(coordinator.blueprints.first?.tags == ["peaking", "low fatigue"])
    }

    @Test func lastErrorMessageClearsAfterSuccessfulRecovery() async throws {
        let container = try makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: "Feature19Recovery.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let collaborationClient = MockCollaborationClient()
        let coordinator = CollaborationCoordinator(
            collaborationClient: collaborationClient,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)
        coordinator.hydrateAccountState(feature19SignedInState())

        // First call fails — error banner should appear.
        collaborationClient.throwOnNextUpdatePreferences = true
        await coordinator.updateNotificationPreferences(
            NotificationPreferenceUpdateRequest(
                coachInvitesEnabled: true,
                assignmentUpdatesEnabled: true,
                coachNotesEnabled: true,
                missedSessionNudgesEnabled: true,
                checkInRemindersEnabled: true,
                pendingProposalRemindersEnabled: true,
                weeklyDigestsEnabled: true
            )
        )
        #expect(coordinator.lastErrorMessage != nil)
        #expect(coordinator.endpointError(.notificationPreferences) != nil)

        // Retry succeeds — aggregate banner should clear alongside the endpoint.
        await coordinator.updateNotificationPreferences(
            NotificationPreferenceUpdateRequest(
                coachInvitesEnabled: true,
                assignmentUpdatesEnabled: true,
                coachNotesEnabled: true,
                missedSessionNudgesEnabled: true,
                checkInRemindersEnabled: true,
                pendingProposalRemindersEnabled: true,
                weeklyDigestsEnabled: true
            )
        )
        #expect(coordinator.lastErrorMessage == nil)
        #expect(coordinator.endpointError(.notificationPreferences) == nil)
    }

    @Test func cacheDedupKeepsNewestPerStableID() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: "Feature19Dedup.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let sharedStableID = "relationship-dup"
        let older = CoachRelationship(
            stableID: sharedStableID,
            createdAt: day(1),
            updatedAt: day(1),
            statusRawValue: CoachRelationshipStatus.invited.rawValue,
            coachAccountID: uuid(1),
            coachDisplayName: "Coach (stale)",
            athleteAccountID: uuid(2),
            athleteDisplayName: "Athlete Sam",
            visibilityScopeBitmask: 0
        )
        let newer = CoachRelationship(
            stableID: sharedStableID,
            createdAt: day(1),
            updatedAt: day(5),
            statusRawValue: CoachRelationshipStatus.active.rawValue,
            coachAccountID: uuid(1),
            coachDisplayName: "Coach (fresh)",
            athleteAccountID: uuid(2),
            athleteDisplayName: "Athlete Sam",
            visibilityScopeBitmask: 0
        )
        // Insert without saving to avoid tripping the new @Attribute(.unique)
        // constraint; the migrator runs against the in-memory state and
        // removes the duplicate before any save.
        context.insert(older)
        context.insert(newer)

        let report = CollaborationCacheMigrator.dedupIfNeeded(
            context: context,
            userDefaults: defaults
        )

        #expect(report.didRun)
        #expect(report.removedCountsByModel["CoachRelationship"] == 1)

        let remaining = try context.fetch(FetchDescriptor<CoachRelationship>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.coachDisplayName == "Coach (fresh)")

        // Subsequent call is a no-op thanks to the @AppStorage flag.
        let secondReport = CollaborationCacheMigrator.dedupIfNeeded(
            context: context,
            userDefaults: defaults
        )
        #expect(secondReport == .skipped)
    }

    @Test func uniqueStableIDRejectsDuplicateInsertOnSave() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let first = CoachNote(
            stableID: "note-unique",
            createdAt: day(1),
            updatedAt: day(1),
            relationshipStableID: "relationship-1",
            authorAccountID: uuid(1),
            authorDisplayName: "Coach Alex",
            recipientAccountID: uuid(2),
            recipientDisplayName: "Athlete Sam",
            bodyText: "First",
            anchorKindRawValue: CoachNoteAnchorKind.general.rawValue,
            priorityRawValue: CollaborationInsightPriority.medium.rawValue,
            isUnread: true,
            requiresReview: false
        )
        context.insert(first)
        try context.save()

        let duplicate = CoachNote(
            stableID: "note-unique",
            createdAt: day(1),
            updatedAt: day(2),
            relationshipStableID: "relationship-1",
            authorAccountID: uuid(1),
            authorDisplayName: "Coach Alex",
            recipientAccountID: uuid(2),
            recipientDisplayName: "Athlete Sam",
            bodyText: "Second",
            anchorKindRawValue: CoachNoteAnchorKind.general.rawValue,
            priorityRawValue: CollaborationInsightPriority.medium.rawValue,
            isUnread: true,
            requiresReview: false
        )
        context.insert(duplicate)
        try context.save()

        // SwiftData's @Attribute(.unique) coalesces duplicates into the
        // single row keyed by stableID instead of preserving both.
        let rows = try context.fetch(FetchDescriptor<CoachNote>(
            predicate: #Predicate { $0.stableID == "note-unique" }
        ))
        #expect(rows.count == 1)
    }

    @Test func deleteRelationshipCascadeRemovesDependents() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let store = LocalCollaborationCacheStore(modelContext: context)

        try store.replaceRelationships(with: [
            CoachRelationshipDTO(
                stableID: "relationship-cascade",
                createdAt: day(1),
                updatedAt: day(2),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                invitedByAccountID: uuid(1),
                visibilityScopeBitmask: 0,
                unreadCoachNoteCount: 0,
                pendingAssignmentCount: 0,
                latestInsightSnapshotAt: nil
            )
        ])
        try store.replaceAssignments(with: [
            ProgramAssignmentDTO(
                stableID: "assignment-1",
                createdAt: day(2),
                updatedAt: day(2),
                relationshipStableID: "relationship-cascade",
                blueprintStableID: "blueprint-1",
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                statusRawValue: ProgramAssignmentStatus.pending.rawValue,
                notesText: nil,
                startGuidance: nil,
                importedTrainingProgramStableID: nil,
                importedProgramRunStableID: nil,
                respondedAt: nil,
                archivedAt: nil
            )
        ])
        try store.replaceNotes(with: [
            CoachNoteDTO(
                stableID: "note-1",
                createdAt: day(2),
                updatedAt: day(2),
                relationshipStableID: "relationship-cascade",
                authorAccountID: uuid(1),
                authorDisplayName: "Coach Alex",
                recipientAccountID: uuid(2),
                recipientDisplayName: "Athlete Sam",
                bodyText: "Stay sharp",
                anchorKindRawValue: CoachNoteAnchorKind.general.rawValue,
                anchoredWorkoutStableID: nil,
                anchoredProgramRunStableID: nil,
                anchoredWeekStart: nil,
                anchoredWeekEnd: nil,
                eventSummaryText: nil,
                priorityRawValue: CollaborationInsightPriority.medium.rawValue,
                isUnread: true,
                requiresReview: false
            )
        ])

        try store.deleteRelationshipCascade(stableID: "relationship-cascade")

        let remainingRelationships = try context.fetch(FetchDescriptor<CoachRelationship>())
        let remainingAssignments = try context.fetch(FetchDescriptor<ProgramAssignment>())
        let remainingNotes = try context.fetch(FetchDescriptor<CoachNote>())
        #expect(remainingRelationships.isEmpty)
        #expect(remainingAssignments.isEmpty)
        #expect(remainingNotes.isEmpty)
    }

    @Test func fullRefreshSweepsOrphanedDependents() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let store = LocalCollaborationCacheStore(modelContext: context)

        // Seed: one relationship with a note, assignment, and insight.
        try store.replaceRelationships(with: [
            CoachRelationshipDTO(
                stableID: "relationship-keep",
                createdAt: day(1),
                updatedAt: day(2),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                invitedByAccountID: uuid(1),
                visibilityScopeBitmask: 0,
                unreadCoachNoteCount: 0,
                pendingAssignmentCount: 0,
                latestInsightSnapshotAt: nil
            ),
            CoachRelationshipDTO(
                stableID: "relationship-drop",
                createdAt: day(1),
                updatedAt: day(2),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(3),
                coachDisplayName: "Coach Jamie",
                athleteAccountID: uuid(4),
                athleteDisplayName: "Athlete Taylor",
                invitedByAccountID: uuid(3),
                visibilityScopeBitmask: 0,
                unreadCoachNoteCount: 0,
                pendingAssignmentCount: 0,
                latestInsightSnapshotAt: nil
            )
        ])
        try store.replaceNotes(with: [
            CoachNoteDTO(
                stableID: "note-keep",
                createdAt: day(2),
                updatedAt: day(2),
                relationshipStableID: "relationship-keep",
                authorAccountID: uuid(1),
                authorDisplayName: "Coach Alex",
                recipientAccountID: uuid(2),
                recipientDisplayName: "Athlete Sam",
                bodyText: "Keep going",
                anchorKindRawValue: CoachNoteAnchorKind.general.rawValue,
                anchoredWorkoutStableID: nil,
                anchoredProgramRunStableID: nil,
                anchoredWeekStart: nil,
                anchoredWeekEnd: nil,
                eventSummaryText: nil,
                priorityRawValue: CollaborationInsightPriority.medium.rawValue,
                isUnread: true,
                requiresReview: false
            ),
            CoachNoteDTO(
                stableID: "note-orphan",
                createdAt: day(2),
                updatedAt: day(2),
                relationshipStableID: "relationship-drop",
                authorAccountID: uuid(3),
                authorDisplayName: "Coach Jamie",
                recipientAccountID: uuid(4),
                recipientDisplayName: "Athlete Taylor",
                bodyText: "Will be swept",
                anchorKindRawValue: CoachNoteAnchorKind.general.rawValue,
                anchoredWorkoutStableID: nil,
                anchoredProgramRunStableID: nil,
                anchoredWeekStart: nil,
                anchoredWeekEnd: nil,
                eventSummaryText: nil,
                priorityRawValue: CollaborationInsightPriority.medium.rawValue,
                isUnread: true,
                requiresReview: false
            )
        ])

        // Full refresh only mentions the keep relationship and its note.
        try store.replaceAll(with: CollaborationFullRefreshPayload(
            relationships: [
                CoachRelationshipDTO(
                    stableID: "relationship-keep",
                    createdAt: day(1),
                    updatedAt: day(3),
                    statusRawValue: CoachRelationshipStatus.active.rawValue,
                    coachAccountID: uuid(1),
                    coachDisplayName: "Coach Alex",
                    athleteAccountID: uuid(2),
                    athleteDisplayName: "Athlete Sam",
                    invitedByAccountID: uuid(1),
                    visibilityScopeBitmask: 0,
                    unreadCoachNoteCount: 0,
                    pendingAssignmentCount: 0,
                    latestInsightSnapshotAt: nil
                )
            ],
            invites: [],
            assignments: [],
            notes: [
                CoachNoteDTO(
                    stableID: "note-keep",
                    createdAt: day(2),
                    updatedAt: day(3),
                    relationshipStableID: "relationship-keep",
                    authorAccountID: uuid(1),
                    authorDisplayName: "Coach Alex",
                    recipientAccountID: uuid(2),
                    recipientDisplayName: "Athlete Sam",
                    bodyText: "Keep going",
                    anchorKindRawValue: CoachNoteAnchorKind.general.rawValue,
                    anchoredWorkoutStableID: nil,
                    anchoredProgramRunStableID: nil,
                    anchoredWeekStart: nil,
                    anchoredWeekEnd: nil,
                    eventSummaryText: nil,
                    priorityRawValue: CollaborationInsightPriority.medium.rawValue,
                    isUnread: true,
                    requiresReview: false
                )
            ],
            notificationPreference: nil,
            insightSnapshots: [],
            weeklyDigests: [],
            blueprints: [],
            programShares: [],
            progressShares: []
        ))

        let remainingRelationships = try context.fetch(FetchDescriptor<CoachRelationship>())
        let remainingNotes = try context.fetch(FetchDescriptor<CoachNote>())
        #expect(remainingRelationships.map(\.stableID) == ["relationship-keep"])
        #expect(remainingNotes.map(\.stableID) == ["note-keep"])
    }

    @Test func coachOnlyMutationGatesWithoutPremium() async throws {
        let container = try makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: "Feature19Gate.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let collaborationClient = MockCollaborationClient()
        let coordinator = CollaborationCoordinator(
            collaborationClient: collaborationClient,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .free }
        )
        coordinator.configure(modelContext: container.mainContext)
        coordinator.hydrateAccountState(feature19SignedInState())

        await coordinator.createCoachInvite(
            inviteeEmail: "athlete@example.com",
            noteText: nil,
            inviterRole: .coach,
            scopes: []
        )

        // Gate rejects the call: no network fire, error surfaces, banner set.
        #expect(collaborationClient.invites.isEmpty)
        #expect(coordinator.endpointError(.invites) == "Coach collaboration requires Premium Unlock.")
        #expect(coordinator.lastErrorMessage == "Coach collaboration requires Premium Unlock.")
    }

    @Test func refreshCoalescerSharesInFlightTask() async {
        let coalescer = CollaborationRefreshCoalescer()
        let runCount = ActorCounter()

        async let first: Void = coalescer.coalesce {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await runCount.increment()
        }
        // Small delay so the first coalesce call registers its Task before
        // the second arrives and sees it in flight.
        try? await Task.sleep(nanoseconds: 5_000_000)
        async let second: Void = coalescer.coalesce {
            await runCount.increment()
        }
        _ = await (first, second)

        // Only the first closure executes; the second piggybacks on the
        // in-flight Task and returns without re-running the work.
        #expect(await runCount.value == 1)
    }

    @Test func pushRegistrationErrorAppearsInRecentActivity() async throws {
        let container = try makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: "Feature19PushActivity.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let coordinator = CollaborationCoordinator(
            collaborationClient: MockCollaborationClient(),
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)
        coordinator.hydrateAccountState(feature19SignedInState())

        await coordinator.recordPushRegistrationError("APNs registration failed")

        #expect(coordinator.endpointError(.pushRegistration) == "APNs registration failed")
        #expect(coordinator.lastErrorMessage == "APNs registration failed")
        #expect(coordinator.recentActivity.contains { $0.message == "APNs registration failed" && $0.level == .error })
    }

    // MARK: - Feature 20 Phase 4g closeout tests

    @Test func refreshErrorRecoversOnNextRefresh() async throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature20RefreshRecovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client = MockCollaborationClient()
        client.relationships = [
            CoachRelationshipDTO(
                stableID: "rel-recovery",
                createdAt: day(1),
                updatedAt: day(2),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                invitedByAccountID: uuid(1),
                visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                unreadCoachNoteCount: 0,
                pendingAssignmentCount: 0,
                latestInsightSnapshotAt: day(2)
            )
        ]
        client.throwOnNextFetchRelationships = true

        let coordinator = CollaborationCoordinator(
            collaborationClient: client,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)

        // Initial refresh: the relationships fetch throws once, which currently
        // bubbles up through performRefresh's try-await chain and lands on the
        // .refresh endpoint. The coordinator surfaces the error and leaves
        // the cache empty.
        await coordinator.handleAccountStateDidChange(feature19SignedInState())
        #expect(coordinator.endpointError(.refresh) != nil)
        #expect(coordinator.phase == .error)
        #expect(coordinator.relationships.isEmpty)

        // Second refresh: flag auto-resets on the first throw, so the retry
        // succeeds end-to-end. The refresh error clears and the seeded
        // relationship flows through to the observable state.
        await coordinator.refreshAll(reason: "Retry after transient failure", force: true)
        #expect(coordinator.endpointError(.refresh) == nil)
        #expect(coordinator.relationships.count == 1)
    }

    @Test func accountSwitchClearsPriorAccountRelationships() async throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature20AccountSwitch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client = MockCollaborationClient()
        client.relationships = [
            CoachRelationshipDTO(
                stableID: "rel-account-a",
                createdAt: day(1),
                updatedAt: day(2),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                invitedByAccountID: uuid(1),
                visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                unreadCoachNoteCount: 0,
                pendingAssignmentCount: 0,
                latestInsightSnapshotAt: day(2)
            )
        ]

        let coordinator = CollaborationCoordinator(
            collaborationClient: client,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)

        // Account A (athlete uuid(2)) signs in and loads its relationship.
        await coordinator.handleAccountStateDidChange(feature19SignedInState())
        #expect(coordinator.relationships.map(\.stableID) == ["rel-account-a"])

        // Account B (coach uuid(1)) signs in with a different relationship.
        // The coordinator must wipe A's cache before loading B's data so
        // no stale row leaks across the account boundary.
        client.relationships = [
            CoachRelationshipDTO(
                stableID: "rel-account-b",
                createdAt: day(5),
                updatedAt: day(6),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(4),
                athleteDisplayName: "Athlete Jamie",
                invitedByAccountID: uuid(1),
                visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                unreadCoachNoteCount: 0,
                pendingAssignmentCount: 0,
                latestInsightSnapshotAt: day(6)
            )
        ]
        await coordinator.handleAccountStateDidChange(feature19CoachState())

        #expect(coordinator.relationships.map(\.stableID) == ["rel-account-b"])
        #expect(!coordinator.relationships.contains { $0.stableID == "rel-account-a" })
    }

    @Test func roleFlipRepartitionsRelationshipBuckets() async throws {
        // Same relationship seed, two different current-account IDs. When the
        // logged-in account is uuid(1) (the coach), the relationship sits in
        // coachRelationships; when it flips to uuid(2) (the athlete on that
        // same relationship), the bucket should swap.
        let container = try makeInMemoryContainer()
        let suiteName = "Feature20RoleFlip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client = MockCollaborationClient()
        client.relationships = [
            CoachRelationshipDTO(
                stableID: "rel-shared",
                createdAt: day(1),
                updatedAt: day(2),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2),
                athleteDisplayName: "Athlete Sam",
                invitedByAccountID: uuid(1),
                visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                unreadCoachNoteCount: 0,
                pendingAssignmentCount: 0,
                latestInsightSnapshotAt: day(2)
            )
        ]

        let coordinator = CollaborationCoordinator(
            collaborationClient: client,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)

        // uuid(1) signs in — they're the coach on this relationship.
        await coordinator.handleAccountStateDidChange(feature19CoachState())
        #expect(coordinator.coachRelationships.count == 1)
        #expect(coordinator.athleteRelationships.isEmpty)

        // Flip to uuid(2) — same relationship, now viewed as the athlete.
        // The derived buckets must repartition so the UI shows a coach,
        // not an athlete, on the My Coach surface.
        await coordinator.handleAccountStateDidChange(feature19SignedInState())
        #expect(coordinator.coachRelationships.isEmpty)
        #expect(coordinator.athleteRelationships.count == 1)
    }

    @Test func pushTokenChurnDoesNotDoubleRegisterIdenticalTokens() async throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature20PushChurn.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client = MockCollaborationClient()
        let coordinator = CollaborationCoordinator(
            collaborationClient: client,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)
        coordinator.hydrateAccountState(feature19SignedInState())

        // Same token delivered three times in quick succession — coordinator
        // should dedupe and only hit the server once.
        await coordinator.handlePushAuthorizationStateChange(.authorized, deviceToken: "token-A")
        await coordinator.handlePushAuthorizationStateChange(.authorized, deviceToken: "token-A")
        await coordinator.handlePushAuthorizationStateChange(.authorized, deviceToken: "token-A")
        #expect(client.registerDeviceCallCount == 1)

        // Token rotates — a second register call is required so the server
        // has the fresh token for this device.
        await coordinator.handlePushAuthorizationStateChange(.authorized, deviceToken: "token-B")
        #expect(client.registerDeviceCallCount == 2)

        // Duplicate of the rotated token — still de-duped.
        await coordinator.handlePushAuthorizationStateChange(.authorized, deviceToken: "token-B")
        #expect(client.registerDeviceCallCount == 2)
    }

    @Test func batchFiveHundredRelationshipColdLoadStaysUnderTwoSeconds() async throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature20BatchPerf.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client = MockCollaborationClient()
        // 500 relationships — worst-case roster size the coordinator should
        // still load from cold without blowing the 2-second budget the
        // cloud team committed to.
        client.relationships = (0..<500).map { index in
            CoachRelationshipDTO(
                stableID: "rel-batch-\(index)",
                createdAt: day(TimeInterval(index)),
                updatedAt: day(TimeInterval(index + 1)),
                statusRawValue: CoachRelationshipStatus.active.rawValue,
                coachAccountID: uuid(1),
                coachDisplayName: "Coach Alex",
                athleteAccountID: uuid(2 + index),
                athleteDisplayName: "Athlete #\(index)",
                invitedByAccountID: uuid(1),
                visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: CollaborationVisibilityScope.defaultInviteScopes),
                unreadCoachNoteCount: 0,
                pendingAssignmentCount: 0,
                latestInsightSnapshotAt: day(TimeInterval(index + 1))
            )
        }

        let coordinator = CollaborationCoordinator(
            collaborationClient: client,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked }
        )
        coordinator.configure(modelContext: container.mainContext)

        let startedAt = Date()
        await coordinator.handleAccountStateDidChange(feature19SignedInState())
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(coordinator.relationships.count == 500)
        #expect(elapsed < 2.0, "Cold 500-relationship refresh took \(elapsed)s; budget is 2.0s")
    }

    @Test func hydrateAccountStateUsesFullSnapshotLoad() throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature20HydrateFullLoad.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(suiteName, forKey: "suiteName")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try LocalCollaborationCacheStore(modelContext: container.mainContext).replaceRelationships(
            with: [feature20RelationshipDTO(stableID: "rel-hydrate")]
        )
        let cacheFactory = CountingCollaborationCacheStoreFactory()
        let coordinator = CollaborationCoordinator(
            collaborationClient: MockCollaborationClient(),
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked },
            cacheStoreFactory: cacheFactory.makeStore
        )
        coordinator.configure(modelContext: container.mainContext)

        cacheFactory.reset()
        coordinator.hydrateAccountState(feature19SignedInState())

        #expect(cacheFactory.fullSnapshotLoadCount == 1)
        #expect(cacheFactory.totalSliceLoadCount == 0)
        #expect(coordinator.relationships.map(\.stableID) == ["rel-hydrate"])
    }

    @Test func accountRefreshAndSwitchUseFullSnapshotLoads() async throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature20FullRefreshLoads.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(suiteName, forKey: "suiteName")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client = MockCollaborationClient()
        client.relationships = [feature20RelationshipDTO(stableID: "rel-account-a")]
        let cacheFactory = CountingCollaborationCacheStoreFactory()
        let coordinator = CollaborationCoordinator(
            collaborationClient: client,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked },
            cacheStoreFactory: cacheFactory.makeStore
        )
        coordinator.configure(modelContext: container.mainContext)

        cacheFactory.reset()
        await coordinator.handleAccountStateDidChange(feature19SignedInState())

        #expect(cacheFactory.fullSnapshotLoadCount == 2)
        #expect(cacheFactory.relationshipsSliceLoadCount == 0)
        #expect(cacheFactory.assignmentsSliceLoadCount == 0)
        #expect(cacheFactory.notesSliceLoadCount == 0)
        #expect(cacheFactory.blueprintsSliceLoadCount == 0)
        #expect(cacheFactory.sharesSliceLoadCount == 0)
        #expect(cacheFactory.notificationStateSliceLoadCount <= 1)
        #expect(coordinator.relationships.map(\.stableID) == ["rel-account-a"])

        cacheFactory.reset()
        client.relationships = [feature20RelationshipDTO(
            stableID: "rel-account-b",
            athleteAccountID: uuid(4),
            athleteDisplayName: "Athlete Jamie"
        )]
        await coordinator.handleAccountStateDidChange(feature19CoachState())

        #expect(cacheFactory.fullSnapshotLoadCount == 2)
        #expect(cacheFactory.relationshipsSliceLoadCount == 0)
        #expect(cacheFactory.assignmentsSliceLoadCount == 0)
        #expect(cacheFactory.notesSliceLoadCount == 0)
        #expect(cacheFactory.blueprintsSliceLoadCount == 0)
        #expect(cacheFactory.sharesSliceLoadCount == 0)
        #expect(cacheFactory.notificationStateSliceLoadCount <= 1)
        #expect(coordinator.relationships.map(\.stableID) == ["rel-account-b"])
    }

    @Test func narrowRefreshMutationsUseSliceLoadersWithoutFullSnapshotReloads() async throws {
        let container = try makeInMemoryContainer()
        let suiteName = "Feature20SliceReloads.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(suiteName, forKey: "suiteName")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client = MockCollaborationClient()
        client.relationships = [feature20RelationshipDTO(stableID: "rel-slice")]
        client.blueprints = [feature20BlueprintDTO(stableID: "blueprint-seeded")]
        client.programShares = [feature20ProgramShareDTO(stableID: "program-share-seeded")]
        client.progressShares = [feature20ProgressShareDTO(stableID: "progress-share-seeded")]

        let cacheFactory = CountingCollaborationCacheStoreFactory()
        let coordinator = CollaborationCoordinator(
            collaborationClient: client,
            backendClient: MockCloudBackendClient(),
            tokenStore: InMemoryCloudSessionTokenStore(tokens: feature19Tokens()),
            syncStateStore: CloudSyncStateStore(userDefaults: defaults),
            entitlementStateProvider: { .premiumUnlocked },
            cacheStoreFactory: cacheFactory.makeStore
        )
        coordinator.configure(modelContext: container.mainContext)
        await coordinator.handleAccountStateDidChange(feature19SignedInState())

        let relationship = try #require(coordinator.relationships.first)
        let seededBlueprint = try #require(coordinator.blueprints.first)
        let initialBlueprintIDs = coordinator.blueprints.map(\.stableID)
        let initialProgramShareIDs = coordinator.programShares.map(\.stableID)

        let program = feature20BlueprintSourceProgram()
        container.mainContext.insert(program)
        try container.mainContext.save()

        cacheFactory.reset()

        await coordinator.updateNotificationPreferences(
            NotificationPreferenceUpdateRequest(
                coachInvitesEnabled: true,
                assignmentUpdatesEnabled: true,
                coachNotesEnabled: true,
                missedSessionNudgesEnabled: false,
                checkInRemindersEnabled: true,
                pendingProposalRemindersEnabled: true,
                weeklyDigestsEnabled: true
            )
        )
        await coordinator.handlePushAuthorizationStateChange(.authorized, deviceToken: "slice-token")
        await coordinator.createCoachInvite(
            inviteeEmail: "slice-athlete@example.com",
            noteText: nil,
            inviterRole: .coach,
            scopes: CollaborationVisibilityScope.defaultInviteScopes
        )
        await coordinator.createAssignment(
            relationship: relationship,
            blueprint: seededBlueprint,
            notesText: "Start next Monday",
            startGuidance: "Ramp week one"
        )
        await coordinator.createCoachNote(
            relationship: relationship,
            bodyText: "Keep bar speed high.",
            anchorKind: .general
        )

        #expect(coordinator.blueprints.map(\.stableID) == initialBlueprintIDs)
        #expect(coordinator.programShares.map(\.stableID) == initialProgramShareIDs)

        await coordinator.createProgramShare(
            relationshipStableID: relationship.stableID,
            shareKind: .blueprint,
            blueprintStableID: seededBlueprint.stableID,
            sourceProgramStableID: nil,
            grantedToAccountID: uuid(3),
            messageText: "Take a look at this block."
        )
        await coordinator.createProgressShare(
            relationshipStableID: relationship.stableID,
            shareKind: .prHighlight,
            grantedToAccountID: uuid(3),
            titleText: "Bench PR",
            subtitleText: nil,
            summaryText: "New 5RM",
            payloadJSON: "{\"pr\":true}"
        )
        await coordinator.saveBlueprint(
            from: program,
            focusText: "Strength",
            notesText: "Wave load the compounds.",
            tags: ["strength", "feature20"]
        )

        #expect(cacheFactory.fullSnapshotLoadCount == 0)
        #expect(cacheFactory.relationshipsSliceLoadCount == 3)
        #expect(cacheFactory.assignmentsSliceLoadCount == 1)
        #expect(cacheFactory.notesSliceLoadCount == 1)
        #expect(cacheFactory.notificationStateSliceLoadCount == 2)
        #expect(cacheFactory.blueprintsSliceLoadCount == 1)
        #expect(cacheFactory.sharesSliceLoadCount == 2)
    }

    private actor ActorCounter {
        private(set) var value: Int = 0
        func increment() { value += 1 }
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            CoachRelationship.self,
            CoachInvite.self,
            ProgramAssignment.self,
            CoachNote.self,
            NotificationPreference.self,
            DevicePushRegistration.self,
            InsightSnapshot.self,
            WeeklyDigest.self,
            SavedProgramBlueprint.self,
            ProgramShareGrant.self,
            ProgressShareCard.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private final class MockCollaborationClient: CloudCollaborationClient {
    var relationships: [CoachRelationshipDTO] = []
    var invites: [CoachInviteDTO] = []
    var assignments: [ProgramAssignmentDTO] = []
    var notes: [CoachNoteDTO] = []
    var notificationPreference = NotificationPreferenceDTO(
        stableID: "notification-preferences::primary",
        updatedAt: Date(),
        coachInvitesEnabled: true,
        assignmentUpdatesEnabled: true,
        coachNotesEnabled: true,
        missedSessionNudgesEnabled: true,
        checkInRemindersEnabled: true,
        pendingProposalRemindersEnabled: true,
        weeklyDigestsEnabled: true
    )
    var deviceRegistration = DevicePushRegistrationDTO(
        stableID: "push-registration::device",
        updatedAt: Date(),
        deviceID: "device-1",
        pushToken: nil,
        authorizationStatusRawValue: CollaborationPushAuthorizationState.notDetermined.rawValue,
        lastRegisteredAt: nil,
        lastErrorMessage: nil
    )
    var snapshots: [InsightSnapshotDTO] = []
    var roster: [InsightSnapshotDTO] = []
    var digests: [WeeklyDigestDTO] = []
    var blueprints: [SavedProgramBlueprintDTO] = []
    var programShares: [ProgramShareGrantDTO] = []
    var progressShares: [ProgressShareCardDTO] = []
    var savedBlueprintRequests: [SavedProgramBlueprintCreateRequest] = []
    var refreshDelayNanoseconds: UInt64 = 0
    var relationshipFetchCount = 0
    var inviteFetchCount = 0
    var assignmentFetchCount = 0
    var noteFetchCount = 0
    var notificationPreferenceFetchCount = 0
    var insightSnapshotFetchCount = 0
    var weeklyDigestFetchCount = 0
    var blueprintFetchCount = 0
    var programShareFetchCount = 0
    var progressShareFetchCount = 0
    var rosterFetchCount = 0
    var registerDeviceCallCount = 0
    /// When true, the next `updateNotificationPreferences` call throws and
    /// the flag auto-resets so the retry can succeed. Used to verify
    /// error-recovery behavior without having to fail every call.
    var throwOnNextUpdatePreferences = false
    /// One-shot throw flag used by the Phase 4g refresh-recovery test to
    /// fail a single endpoint (relationships) so the coordinator records
    /// an endpoint error while the other endpoints succeed. Auto-resets
    /// on throw so the follow-up refresh can verify recovery.
    var throwOnNextFetchRelationships = false

    var totalRefreshFetchCount: Int {
        relationshipFetchCount +
            inviteFetchCount +
            assignmentFetchCount +
            noteFetchCount +
            notificationPreferenceFetchCount +
            insightSnapshotFetchCount +
            weeklyDigestFetchCount +
            blueprintFetchCount +
            programShareFetchCount +
            progressShareFetchCount +
            rosterFetchCount
    }

    func fetchRelationships(accessToken: String) async throws -> [CoachRelationshipDTO] {
        if throwOnNextFetchRelationships {
            throwOnNextFetchRelationships = false
            relationshipFetchCount += 1
            throw MockError.unused
        }
        return try await delayedFetch(&relationshipFetchCount, value: relationships)
    }
    func fetchInvites(accessToken: String) async throws -> [CoachInviteDTO] {
        try await delayedFetch(&inviteFetchCount, value: invites)
    }
    func createInvite(_ request: CoachInviteCreateRequest, accessToken: String) async throws -> CoachInviteDTO {
        let dto = CoachInviteDTO(
            stableID: "invite-\(invites.count + 1)",
            createdAt: Date(),
            updatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86_400),
            statusRawValue: CoachInviteStatus.pending.rawValue,
            inviterAccountID: uuid(1),
            inviterDisplayName: "Coach Alex",
            inviterRoleRawValue: request.inviterRoleRawValue,
            inviteeAccountID: nil,
            inviteeEmail: request.inviteeEmail,
            inviteeDisplayName: nil,
            relationshipStableID: nil,
            visibilityScopeBitmask: request.visibilityScopeBitmask,
            noteText: request.noteText
        )
        invites.insert(dto, at: 0)
        return dto
    }
    func respondToInvite(stableID: String, request: CoachInviteActionRequest, accessToken: String) async throws -> CoachInviteDTO {
        var invite = invites.first { $0.stableID == stableID }!
        invite.statusRawValue = request.actionRawValue
        invites = invites.map { $0.stableID == stableID ? invite : $0 }
        return invite
    }
    func revokeInvite(stableID: String, accessToken: String) async throws -> CoachInviteDTO {
        try await respondToInvite(stableID: stableID, request: CoachInviteActionRequest(actionRawValue: CoachInviteStatus.revoked.rawValue), accessToken: accessToken)
    }
    func updateRelationshipScopes(stableID: String, request: RelationshipScopeUpdateRequest, accessToken: String) async throws -> CoachRelationshipDTO {
        var relationship = relationships.first { $0.stableID == stableID }!
        relationship.visibilityScopeBitmask = request.visibilityScopeBitmask
        relationships = relationships.map { $0.stableID == stableID ? relationship : $0 }
        return relationship
    }
    func fetchRoster(accessToken: String) async throws -> [InsightSnapshotDTO] {
        try await delayedFetch(&rosterFetchCount, value: roster)
    }
    func fetchAssignments(accessToken: String) async throws -> [ProgramAssignmentDTO] {
        try await delayedFetch(&assignmentFetchCount, value: assignments)
    }
    func createAssignment(_ request: ProgramAssignmentCreateRequest, accessToken: String) async throws -> ProgramAssignmentDTO {
        let dto = ProgramAssignmentDTO(
            stableID: "assignment-\(assignments.count + 1)",
            createdAt: Date(),
            updatedAt: Date(),
            relationshipStableID: request.relationshipStableID,
            blueprintStableID: request.blueprintStableID,
            coachAccountID: uuid(1),
            coachDisplayName: "Coach Alex",
            athleteAccountID: uuid(2),
            athleteDisplayName: "Athlete Sam",
            statusRawValue: ProgramAssignmentStatus.pending.rawValue,
            notesText: request.notesText,
            startGuidance: request.startGuidance,
            importedTrainingProgramStableID: nil,
            importedProgramRunStableID: nil,
            respondedAt: nil,
            archivedAt: nil
        )
        assignments.insert(dto, at: 0)
        return dto
    }
    func updateAssignmentStatus(stableID: String, request: ProgramAssignmentStatusUpdateRequest, accessToken: String) async throws -> ProgramAssignmentActionResponseDTO {
        var assignment = assignments.first { $0.stableID == stableID }!
        assignment.statusRawValue = request.statusRawValue
        assignments = assignments.map { $0.stableID == stableID ? assignment : $0 }
        return ProgramAssignmentActionResponseDTO(
            assignment: assignment,
            cloneReceipt: request.statusRawValue == ProgramAssignmentStatus.accepted.rawValue
                ? CollaborationCloneReceiptDTO(createdTrainingProgramStableID: "program-imported", createdProgramRunStableID: "run-imported")
                : nil
        )
    }
    func fetchNotes(accessToken: String) async throws -> [CoachNoteDTO] {
        try await delayedFetch(&noteFetchCount, value: notes)
    }
    func createCoachNote(_ request: CoachNoteCreateRequest, accessToken: String) async throws -> CoachNoteDTO {
        let dto = CoachNoteDTO(
            stableID: "note-\(notes.count + 1)",
            createdAt: Date(),
            updatedAt: Date(),
            relationshipStableID: request.relationshipStableID,
            authorAccountID: uuid(1),
            authorDisplayName: "Coach Alex",
            recipientAccountID: uuid(2),
            recipientDisplayName: "Athlete Sam",
            bodyText: request.bodyText,
            anchorKindRawValue: request.anchorKindRawValue,
            anchoredWorkoutStableID: request.anchoredWorkoutStableID,
            anchoredProgramRunStableID: request.anchoredProgramRunStableID,
            anchoredWeekStart: request.anchoredWeekStart,
            anchoredWeekEnd: request.anchoredWeekEnd,
            eventSummaryText: request.eventSummaryText,
            priorityRawValue: request.priorityRawValue,
            isUnread: true,
            requiresReview: request.requiresReview
        )
        notes.insert(dto, at: 0)
        return dto
    }
    func markCoachNoteRead(stableID: String, accessToken: String) async throws -> CoachNoteDTO {
        var note = notes.first { $0.stableID == stableID }!
        note.isUnread = false
        notes = notes.map { $0.stableID == stableID ? note : $0 }
        return note
    }
    func fetchNotificationPreferences(accessToken: String) async throws -> NotificationPreferenceDTO {
        try await delayedFetch(&notificationPreferenceFetchCount, value: notificationPreference)
    }
    func updateNotificationPreferences(_ request: NotificationPreferenceUpdateRequest, accessToken: String) async throws -> NotificationPreferenceDTO {
        if throwOnNextUpdatePreferences {
            throwOnNextUpdatePreferences = false
            throw MockError.unused
        }
        notificationPreference = NotificationPreferenceDTO(
            stableID: notificationPreference.stableID,
            updatedAt: Date(),
            coachInvitesEnabled: request.coachInvitesEnabled,
            assignmentUpdatesEnabled: request.assignmentUpdatesEnabled,
            coachNotesEnabled: request.coachNotesEnabled,
            missedSessionNudgesEnabled: request.missedSessionNudgesEnabled,
            checkInRemindersEnabled: request.checkInRemindersEnabled,
            pendingProposalRemindersEnabled: request.pendingProposalRemindersEnabled,
            weeklyDigestsEnabled: request.weeklyDigestsEnabled
        )
        return notificationPreference
    }
    func registerDevice(_ request: DevicePushRegistrationRequest, accessToken: String) async throws -> DevicePushRegistrationDTO {
        registerDeviceCallCount += 1
        deviceRegistration = DevicePushRegistrationDTO(
            stableID: "push-registration::\(request.deviceID)",
            updatedAt: Date(),
            deviceID: request.deviceID,
            pushToken: request.pushToken,
            authorizationStatusRawValue: request.authorizationStatusRawValue,
            lastRegisteredAt: Date(),
            lastErrorMessage: nil
        )
        return deviceRegistration
    }
    func fetchInsightSnapshots(accessToken: String) async throws -> [InsightSnapshotDTO] {
        try await delayedFetch(&insightSnapshotFetchCount, value: snapshots)
    }
    func fetchWeeklyDigests(accessToken: String) async throws -> [WeeklyDigestDTO] {
        try await delayedFetch(&weeklyDigestFetchCount, value: digests)
    }
    func fetchBlueprints(accessToken: String) async throws -> [SavedProgramBlueprintDTO] {
        try await delayedFetch(&blueprintFetchCount, value: blueprints)
    }
    func saveBlueprint(_ request: SavedProgramBlueprintCreateRequest, accessToken: String) async throws -> SavedProgramBlueprintDTO {
        savedBlueprintRequests.append(request)
        let dto = SavedProgramBlueprintDTO(
            stableID: "blueprint-\(blueprints.count + 1)",
            createdAt: Date(),
            updatedAt: Date(),
            name: request.name,
            focusText: request.focusText,
            notesText: request.notesText,
            tags: request.tags,
            durationWeeks: request.durationWeeks,
            sessionsPerWeek: request.sessionsPerWeek,
            sourceProgramStableID: request.sourceProgramStableID,
            createdByAccountID: uuid(1),
            createdByDisplayName: "Coach Alex",
            trainingProgramSnapshotJSON: request.trainingProgramSnapshotJSON,
            lastSharedAt: nil
        )
        blueprints = [dto]
        return dto
    }
    func fetchProgramShares(accessToken: String) async throws -> [ProgramShareGrantDTO] {
        try await delayedFetch(&programShareFetchCount, value: programShares)
    }
    func createProgramShare(_ request: ProgramShareGrantCreateRequest, accessToken: String) async throws -> ProgramShareGrantDTO {
        let dto = ProgramShareGrantDTO(
            stableID: "program-share-\(programShares.count + 1)",
            createdAt: Date(),
            updatedAt: Date(),
            relationshipStableID: request.relationshipStableID,
            shareKindRawValue: request.shareKindRawValue,
            statusRawValue: ShareGrantStatus.active.rawValue,
            blueprintStableID: request.blueprintStableID,
            sourceProgramStableID: request.sourceProgramStableID,
            grantedByAccountID: uuid(1),
            grantedByDisplayName: "Coach Alex",
            grantedToAccountID: request.grantedToAccountID,
            grantedToDisplayName: "Athlete Sam",
            messageText: request.messageText
        )
        programShares.insert(dto, at: 0)
        return dto
    }
    func revokeProgramShare(stableID: String, accessToken: String) async throws -> ProgramShareGrantDTO {
        var share = programShares.first { $0.stableID == stableID }!
        share.statusRawValue = ShareGrantStatus.revoked.rawValue
        programShares = programShares.map { $0.stableID == stableID ? share : $0 }
        return share
    }
    func fetchProgressShares(accessToken: String) async throws -> [ProgressShareCardDTO] {
        try await delayedFetch(&progressShareFetchCount, value: progressShares)
    }
    func createProgressShare(_ request: ProgressShareCardCreateRequest, accessToken: String) async throws -> ProgressShareCardDTO {
        let dto = ProgressShareCardDTO(
            stableID: "progress-share-\(progressShares.count + 1)",
            createdAt: Date(),
            updatedAt: Date(),
            relationshipStableID: request.relationshipStableID,
            shareKindRawValue: request.shareKindRawValue,
            statusRawValue: ShareGrantStatus.active.rawValue,
            grantedByAccountID: uuid(1),
            grantedByDisplayName: "Coach Alex",
            grantedToAccountID: request.grantedToAccountID,
            grantedToDisplayName: "Athlete Sam",
            titleText: request.titleText,
            subtitleText: request.subtitleText,
            summaryText: request.summaryText,
            payloadJSON: request.payloadJSON
        )
        progressShares.insert(dto, at: 0)
        return dto
    }
    func revokeProgressShare(stableID: String, accessToken: String) async throws -> ProgressShareCardDTO {
        var share = progressShares.first { $0.stableID == stableID }!
        share.statusRawValue = ShareGrantStatus.revoked.rawValue
        progressShares = progressShares.map { $0.stableID == stableID ? share : $0 }
        return share
    }

    private func delayedFetch<Value>(
        _ counter: inout Int,
        value: Value
    ) async throws -> Value {
        counter += 1
        if refreshDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: refreshDelayNanoseconds)
        }
        return value
    }
}

@MainActor
private final class CountingCollaborationCacheStoreFactory {
    private let counters = CollaborationCacheStoreLoadCounters()

    var fullSnapshotLoadCount: Int { counters.fullSnapshotLoadCount }
    var relationshipsSliceLoadCount: Int { counters.relationshipsSliceLoadCount }
    var assignmentsSliceLoadCount: Int { counters.assignmentsSliceLoadCount }
    var notesSliceLoadCount: Int { counters.notesSliceLoadCount }
    var notificationStateSliceLoadCount: Int { counters.notificationStateSliceLoadCount }
    var insightsSliceLoadCount: Int { counters.insightsSliceLoadCount }
    var blueprintsSliceLoadCount: Int { counters.blueprintsSliceLoadCount }
    var sharesSliceLoadCount: Int { counters.sharesSliceLoadCount }

    var totalSliceLoadCount: Int {
        relationshipsSliceLoadCount +
            assignmentsSliceLoadCount +
            notesSliceLoadCount +
            notificationStateSliceLoadCount +
            insightsSliceLoadCount +
            blueprintsSliceLoadCount +
            sharesSliceLoadCount
    }

    func makeStore(modelContext: ModelContext) -> any CollaborationCacheStoring {
        CountingCollaborationCacheStore(
            base: LocalCollaborationCacheStore(modelContext: modelContext),
            counters: counters
        )
    }

    func reset() {
        counters.reset()
    }
}

@MainActor
private final class CountingCollaborationCacheStore: CollaborationCacheStoring {
    private let base: LocalCollaborationCacheStore
    private let counters: CollaborationCacheStoreLoadCounters

    init(
        base: LocalCollaborationCacheStore,
        counters: CollaborationCacheStoreLoadCounters
    ) {
        self.base = base
        self.counters = counters
    }

    func loadSnapshot() throws -> CollaborationCacheSnapshot {
        counters.fullSnapshotLoadCount += 1
        return try base.loadSnapshot()
    }

    func loadRelationshipsAndInvites() throws -> CollaborationRelationshipsCacheSlice {
        counters.relationshipsSliceLoadCount += 1
        return try base.loadRelationshipsAndInvites()
    }

    func loadAssignments() throws -> [ProgramAssignment] {
        counters.assignmentsSliceLoadCount += 1
        return try base.loadAssignments()
    }

    func loadNotes() throws -> [CoachNote] {
        counters.notesSliceLoadCount += 1
        return try base.loadNotes()
    }

    func loadNotificationState() throws -> CollaborationNotificationStateCacheSlice {
        counters.notificationStateSliceLoadCount += 1
        return try base.loadNotificationState()
    }

    func loadInsightsAndDigests() throws -> CollaborationInsightsCacheSlice {
        counters.insightsSliceLoadCount += 1
        return try base.loadInsightsAndDigests()
    }

    func loadBlueprints() throws -> [SavedProgramBlueprint] {
        counters.blueprintsSliceLoadCount += 1
        return try base.loadBlueprints()
    }

    func loadShares() throws -> CollaborationSharesCacheSlice {
        counters.sharesSliceLoadCount += 1
        return try base.loadShares()
    }

    func clearAll() throws {
        try base.clearAll()
    }

    func replaceAll(with payload: CollaborationFullRefreshPayload) throws {
        try base.replaceAll(with: payload)
    }

    func replaceRelationships(with dtos: [CoachRelationshipDTO]) throws {
        try base.replaceRelationships(with: dtos)
    }

    func replaceInvites(with dtos: [CoachInviteDTO]) throws {
        try base.replaceInvites(with: dtos)
    }

    func replaceAssignments(with dtos: [ProgramAssignmentDTO]) throws {
        try base.replaceAssignments(with: dtos)
    }

    func replaceNotes(with dtos: [CoachNoteDTO]) throws {
        try base.replaceNotes(with: dtos)
    }

    func replaceNotificationPreference(with dto: NotificationPreferenceDTO?) throws {
        try base.replaceNotificationPreference(with: dto)
    }

    func replaceDeviceRegistration(with dto: DevicePushRegistrationDTO?) throws {
        try base.replaceDeviceRegistration(with: dto)
    }

    func replaceBlueprints(with dtos: [SavedProgramBlueprintDTO]) throws {
        try base.replaceBlueprints(with: dtos)
    }

    func replaceProgramShares(with dtos: [ProgramShareGrantDTO]) throws {
        try base.replaceProgramShares(with: dtos)
    }

    func replaceProgressShares(with dtos: [ProgressShareCardDTO]) throws {
        try base.replaceProgressShares(with: dtos)
    }
}

@MainActor
private final class CollaborationCacheStoreLoadCounters {
    var fullSnapshotLoadCount = 0
    var relationshipsSliceLoadCount = 0
    var assignmentsSliceLoadCount = 0
    var notesSliceLoadCount = 0
    var notificationStateSliceLoadCount = 0
    var insightsSliceLoadCount = 0
    var blueprintsSliceLoadCount = 0
    var sharesSliceLoadCount = 0

    func reset() {
        fullSnapshotLoadCount = 0
        relationshipsSliceLoadCount = 0
        assignmentsSliceLoadCount = 0
        notesSliceLoadCount = 0
        notificationStateSliceLoadCount = 0
        insightsSliceLoadCount = 0
        blueprintsSliceLoadCount = 0
        sharesSliceLoadCount = 0
    }
}

private final class MockCloudBackendClient: CloudBackendClient {
    func exchangeAppleIdentity(_ request: CloudAuthExchangeRequest) async throws -> CloudAuthSessionResponse { throw MockError.unused }
    func refreshSession(_ request: CloudSessionRefreshRequest) async throws -> CloudAuthSessionResponse { throw MockError.unused }
    func bootstrap(_ request: CloudSyncBootstrapRequest, accessToken: String) async throws -> CloudSyncResponse { throw MockError.unused }
    func push(_ request: CloudSyncPushRequest, accessToken: String) async throws -> CloudSyncPushResponse { throw MockError.unused }
    func pull(_ request: CloudSyncPullRequest, accessToken: String) async throws -> CloudSyncResponse { throw MockError.unused }
    func submitPrivacyRequest(_ type: PrivacyRequestType, accessToken: String) async throws -> CloudPrivacyRequestResponse { throw MockError.unused }
    func fetchAccountExport(accessToken: String) async throws -> CloudAccountExportResponse { throw MockError.unused }
    func deleteAccount(accessToken: String) async throws -> CloudPrivacyRequestResponse { throw MockError.unused }
}

private final class InMemoryCloudSessionTokenStore: CloudSessionTokenStore {
    private var tokens: CloudSessionTokensDTO?

    init(tokens: CloudSessionTokensDTO? = nil) {
        self.tokens = tokens
    }

    func loadTokens() -> CloudSessionTokensDTO? {
        tokens
    }

    func saveTokens(_ tokens: CloudSessionTokensDTO) {
        self.tokens = tokens
    }

    func clearTokens() {
        tokens = nil
    }
}

private enum MockError: Error {
    case unused
}

private func feature19SignedInState() -> AccountBackendContractState {
    AccountBackendContractState(
        knownAccounts: [
            UserAccount(
                id: uuid(2),
                appleUserID: "apple-athlete",
                displayName: "Athlete Sam",
                email: "athlete@example.com",
                createdAt: day(0),
                lastSignedInAt: day(1),
                launchMode: .productionBackend
            )
        ],
        currentAccountID: uuid(2),
        privacyRequests: [],
        consumerHealthConsents: []
    )
}

private func feature19CoachState() -> AccountBackendContractState {
    AccountBackendContractState(
        knownAccounts: [
            UserAccount(
                id: uuid(1),
                appleUserID: "apple-coach",
                displayName: "Coach Alex",
                email: "coach@example.com",
                createdAt: day(0),
                lastSignedInAt: day(1),
                launchMode: .productionBackend
            )
        ],
        currentAccountID: uuid(1),
        privacyRequests: [],
        consumerHealthConsents: []
    )
}

private func feature19Tokens() -> CloudSessionTokensDTO {
    CloudSessionTokensDTO(
        accessToken: "feature19-access",
        refreshToken: "feature19-refresh",
        accessTokenExpiresAt: Date().addingTimeInterval(3_600)
    )
}

private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
    defaults.string(forKey: "suiteName") ?? ""
}

private func feature20RelationshipDTO(
    stableID: String,
    athleteAccountID: UUID = uuid(2),
    athleteDisplayName: String = "Athlete Sam"
) -> CoachRelationshipDTO {
    CoachRelationshipDTO(
        stableID: stableID,
        createdAt: day(1),
        updatedAt: day(2),
        statusRawValue: CoachRelationshipStatus.active.rawValue,
        coachAccountID: uuid(1),
        coachDisplayName: "Coach Alex",
        athleteAccountID: athleteAccountID,
        athleteDisplayName: athleteDisplayName,
        invitedByAccountID: uuid(1),
        visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(
            for: CollaborationVisibilityScope.defaultInviteScopes
        ),
        unreadCoachNoteCount: 0,
        pendingAssignmentCount: 0,
        latestInsightSnapshotAt: day(2)
    )
}

private func feature20BlueprintDTO(stableID: String) -> SavedProgramBlueprintDTO {
    SavedProgramBlueprintDTO(
        stableID: stableID,
        createdAt: day(1),
        updatedAt: day(2),
        name: "Seeded Blueprint",
        focusText: "Strength",
        notesText: "Seeded notes",
        tags: ["seeded"],
        durationWeeks: 6,
        sessionsPerWeek: 4,
        sourceProgramStableID: "program-seeded",
        createdByAccountID: uuid(1),
        createdByDisplayName: "Coach Alex",
        trainingProgramSnapshotJSON: "{\"name\":\"Seeded Blueprint\"}",
        lastSharedAt: nil
    )
}

private func feature20ProgramShareDTO(stableID: String) -> ProgramShareGrantDTO {
    ProgramShareGrantDTO(
        stableID: stableID,
        createdAt: day(1),
        updatedAt: day(2),
        relationshipStableID: "rel-slice",
        shareKindRawValue: ProgramShareKind.blueprint.rawValue,
        statusRawValue: ShareGrantStatus.active.rawValue,
        blueprintStableID: "blueprint-seeded",
        sourceProgramStableID: nil,
        grantedByAccountID: uuid(1),
        grantedByDisplayName: "Coach Alex",
        grantedToAccountID: uuid(3),
        grantedToDisplayName: "Athlete Taylor",
        messageText: "Seeded program share"
    )
}

private func feature20ProgressShareDTO(stableID: String) -> ProgressShareCardDTO {
    ProgressShareCardDTO(
        stableID: stableID,
        createdAt: day(1),
        updatedAt: day(2),
        relationshipStableID: "rel-slice",
        shareKindRawValue: ProgressShareKind.prHighlight.rawValue,
        statusRawValue: ShareGrantStatus.active.rawValue,
        grantedByAccountID: uuid(1),
        grantedByDisplayName: "Coach Alex",
        grantedToAccountID: uuid(3),
        grantedToDisplayName: "Athlete Taylor",
        titleText: "Seeded PR",
        subtitleText: nil,
        summaryText: "Bench PR",
        payloadJSON: "{\"seeded\":true}"
    )
}

private func feature20BlueprintSourceProgram() -> TrainingProgram {
    TrainingProgram(
        id: uuid(40),
        syncStableID: "program-feature20-slice",
        syncVersion: 2,
        syncLastModifiedAt: day(3),
        name: "Feature 20 Slice Source",
        lengthInWeeks: 6,
        sessionsPerWeek: 4,
        createdDate: day(1),
        source: .aiGenerated,
        descriptionText: "Program used to verify blueprint slice refreshes."
    )
}

private func day(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_900_000_000 + (offset * 86_400))
}

private func uuid(_ seed: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", seed))!
}
