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
            syncStateStore: CloudSyncStateStore(userDefaults: defaults)
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
            syncStateStore: CloudSyncStateStore(userDefaults: defaults)
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
            syncStateStore: CloudSyncStateStore(userDefaults: defaults)
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
            syncStateStore: CloudSyncStateStore(userDefaults: UserDefaults(suiteName: "Feature19Roles.\(UUID().uuidString)")!)
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
            syncStateStore: CloudSyncStateStore(userDefaults: defaults)
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
            syncStateStore: CloudSyncStateStore(userDefaults: defaults)
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
            syncStateStore: CloudSyncStateStore(userDefaults: defaults)
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
            syncStateStore: CloudSyncStateStore(userDefaults: defaults)
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
        try await delayedFetch(&relationshipFetchCount, value: relationships)
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

private func day(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_900_000_000 + (offset * 86_400))
}

private func uuid(_ seed: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", seed))!
}
