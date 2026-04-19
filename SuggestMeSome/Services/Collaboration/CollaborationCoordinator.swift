import Foundation
import Observation
import SwiftData

enum InvitePresentationMode: Equatable {
    case incomingPending
    case outgoingPending
    case readOnly
}

enum CollaborationSyncPhase: String, Equatable {
    case signedOut
    case idle
    case loading
    case error

    var title: String {
        switch self {
        case .signedOut:
            return "Signed Out"
        case .idle:
            return "Up to Date"
        case .loading:
            return "Refreshing"
        case .error:
            return "Needs Attention"
        }
    }
}

enum CollaborationActivityLevel: String, Equatable {
    case info
    case warning
    case error
}

struct CollaborationActivityRecord: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let level: CollaborationActivityLevel
    let message: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        level: CollaborationActivityLevel,
        message: String
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.message = message
    }
}

@MainActor
@Observable
final class CollaborationCoordinator {
    static let shared = CollaborationCoordinator()

    private let collaborationClient: CloudCollaborationClient
    private let backendClient: CloudBackendClient
    private let tokenStore: CloudSessionTokenStore
    private let syncStateStore: CloudSyncStateStore

    private var modelContext: ModelContext?
    private var currentAccountState: AccountBackendContractState = .empty
    private weak var cloudSyncManager: CloudSyncManager?
    private var refreshTask: Task<Void, Never>?
    private var refreshTaskToken = 0
    private var lastSuccessfulRefreshAt: Date?

    private let automaticRefreshMinimumInterval: TimeInterval = 15

    private(set) var phase: CollaborationSyncPhase = .signedOut
    private(set) var relationships: [CoachRelationship] = []
    private(set) var invites: [CoachInvite] = []
    private(set) var assignments: [ProgramAssignment] = []
    private(set) var notes: [CoachNote] = []
    private(set) var notificationPreference: NotificationPreference?
    private(set) var deviceRegistration: DevicePushRegistration?
    private(set) var insightSnapshots: [InsightSnapshot] = []
    private(set) var weeklyDigests: [WeeklyDigest] = []
    private(set) var blueprints: [SavedProgramBlueprint] = []
    private(set) var programShares: [ProgramShareGrant] = []
    private(set) var progressShares: [ProgressShareCard] = []
    private(set) var pushAuthorizationState: CollaborationPushAuthorizationState = .notDetermined
    private(set) var lastErrorMessage: String?
    private(set) var statusMessage: String?
    private(set) var recentActivity: [CollaborationActivityRecord] = []

    init(
        collaborationClient: CloudCollaborationClient? = nil,
        backendClient: CloudBackendClient? = nil,
        tokenStore: CloudSessionTokenStore? = nil,
        syncStateStore: CloudSyncStateStore? = nil
    ) {
        self.collaborationClient = collaborationClient ?? HTTPCloudCollaborationClient()
        self.backendClient = backendClient ?? HTTPCloudBackendClient()
        self.tokenStore = tokenStore ?? KeychainCloudSessionTokenStore.shared
        self.syncStateStore = syncStateStore ?? CloudSyncStateStore()
    }

    var currentAccountID: UUID? {
        currentAccountState.currentAccountID
    }

    var currentAccountEmail: String? {
        guard let currentAccountID else { return nil }
        return normalizedEmail(
            currentAccountState.knownAccounts.first { $0.id == currentAccountID }?.email
        )
    }

    var statusSummary: String {
        switch phase {
        case .signedOut:
            return "Connect an account to use coach collaboration, deterministic cloud insights, and private sharing."
        case .idle:
            return statusMessage ?? "Coach collaboration is ready."
        case .loading:
            return "Refreshing collaboration, assignments, insights, and sharing state."
        case .error:
            return lastErrorMessage ?? "Coach collaboration needs attention."
        }
    }

    var coachRelationships: [CoachRelationship] {
        relationships.filter { $0.currentRole(for: currentAccountID) == .coach }
    }

    var athleteRelationships: [CoachRelationship] {
        relationships.filter { $0.currentRole(for: currentAccountID) == .athlete }
    }

    var pendingInvites: [CoachInvite] {
        invites.filter { $0.status == .pending }
    }

    var incomingPendingInvites: [CoachInvite] {
        invites.filter { invitePresentationMode(for: $0) == .incomingPending }
    }

    var outgoingPendingInvites: [CoachInvite] {
        invites.filter { invitePresentationMode(for: $0) == .outgoingPending }
    }

    var inboxAssignments: [ProgramAssignment] {
        assignments.filter { assignment in
            canActOnAssignment(assignment)
        }
    }

    var coachRosterSnapshots: [InsightSnapshot] {
        let coachRelationshipIDs = Set(coachRelationships.map(\.stableID))
        return insightSnapshots.filter { snapshot in
            if let relationshipStableID = snapshot.relationshipStableID {
                return coachRelationshipIDs.contains(relationshipStableID)
            }
            return false
        }
    }

    var athleteFacingSnapshots: [InsightSnapshot] {
        insightSnapshots.filter { $0.accountID == currentAccountID }
    }

    var unreadCoachNotes: [CoachNote] {
        notes.filter(\.isUnread)
    }

    var unreadDigests: [WeeklyDigest] {
        weeklyDigests.filter(\.isUnread)
    }

    var shouldShowMyCoachEmptyState: Bool {
        athleteRelationships.isEmpty && incomingPendingInvites.isEmpty
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadCache()
    }

    func configure(cloudSyncManager: CloudSyncManager) {
        self.cloudSyncManager = cloudSyncManager
    }

    func hydrateAccountState(_ state: AccountBackendContractState) {
        currentAccountState = state

        guard state.currentAccountID != nil else {
            clearInMemoryState()
            phase = .signedOut
            statusMessage = nil
            lastErrorMessage = nil
            return
        }

        loadCache()
        if phase == .signedOut {
            phase = .idle
        }
    }

    func handleAccountStateDidChange(_ state: AccountBackendContractState) async {
        let previousAccountID = currentAccountState.currentAccountID
        let nextAccountID = state.currentAccountID
        let accountChanged = previousAccountID != nextAccountID

        if accountChanged,
           previousAccountID != nil,
           nextAccountID != nil,
           let modelContext {
            try? LocalCollaborationCacheStore(modelContext: modelContext).clearAll()
            clearInMemoryState()
        }

        hydrateAccountState(state)

        guard nextAccountID != nil else {
            clearInMemoryState()
            if let modelContext {
                try? LocalCollaborationCacheStore(modelContext: modelContext).clearAll()
            }
            phase = .signedOut
            statusMessage = nil
            lastErrorMessage = nil
            return
        }

        guard accountChanged else { return }

        await refreshAll(reason: "Account connected", force: true)
        await syncPushRegistrationIfNeeded(
            deviceToken: PushNotificationManager.shared.deviceTokenHex
        )
    }

    func refreshOnAppDidBecomeActive() async {
        await refreshAll(reason: "App became active", force: false)
    }

    func refreshAll(reason: String = "Manual refresh", force: Bool = true) async {
        guard shouldPerformRefresh(force: force) else { return }

        if let refreshTask {
            await refreshTask.value
            return
        }

        refreshTaskToken += 1
        let taskToken = refreshTaskToken
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(reason: reason)
        }
        refreshTask = task
        await task.value
        if refreshTaskToken == taskToken {
            refreshTask = nil
        }
    }

    private func performRefresh(reason: String) async {
        guard let modelContext else { return }
        guard currentAccountID != nil else {
            phase = .signedOut
            return
        }

        phase = .loading
        statusMessage = nil
        lastErrorMessage = nil

        do {
            let accessToken = try await validAccessToken()

            async let relationshipsTask = collaborationClient.fetchRelationships(accessToken: accessToken)
            async let invitesTask = collaborationClient.fetchInvites(accessToken: accessToken)
            async let rosterTask = collaborationClient.fetchRoster(accessToken: accessToken)
            async let assignmentsTask = collaborationClient.fetchAssignments(accessToken: accessToken)
            async let notesTask = collaborationClient.fetchNotes(accessToken: accessToken)
            async let preferencesTask = collaborationClient.fetchNotificationPreferences(accessToken: accessToken)
            async let snapshotsTask = collaborationClient.fetchInsightSnapshots(accessToken: accessToken)
            async let digestsTask = collaborationClient.fetchWeeklyDigests(accessToken: accessToken)
            async let blueprintsTask = collaborationClient.fetchBlueprints(accessToken: accessToken)
            async let programSharesTask = collaborationClient.fetchProgramShares(accessToken: accessToken)
            async let progressSharesTask = collaborationClient.fetchProgressShares(accessToken: accessToken)

            let relationships = try await relationshipsTask
            let invites = try await invitesTask
            let rosterSnapshots = try await rosterTask
            let assignments = try await assignmentsTask
            let notes = try await notesTask
            let notificationPreference = try await preferencesTask
            let snapshots = try await snapshotsTask
            let digests = try await digestsTask
            let blueprints = try await blueprintsTask
            let programShares = try await programSharesTask
            let progressShares = try await progressSharesTask

            let mergedSnapshots = mergeInsightSnapshots(primary: snapshots, roster: rosterSnapshots)
            let store = LocalCollaborationCacheStore(modelContext: modelContext)
            try store.replaceAll(
                with: CollaborationFullRefreshPayload(
                    relationships: relationships,
                    invites: invites,
                    assignments: assignments,
                    notes: notes,
                    notificationPreference: notificationPreference,
                    insightSnapshots: mergedSnapshots,
                    weeklyDigests: digests,
                    blueprints: blueprints,
                    programShares: programShares,
                    progressShares: progressShares
                )
            )

            loadCache()
            phase = .idle
            statusMessage = reason
            lastSuccessfulRefreshAt = .now
            appendActivity(.info, reason)
        } catch {
            phase = .error
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            appendActivity(.error, lastErrorMessage ?? "Collaboration refresh failed.")
        }
    }

    func requestPushAuthorization() async {
        let granted = await PushNotificationManager.shared.requestAuthorization()
        if granted {
            appendActivity(.info, "Push notifications enabled")
        } else if PushNotificationManager.shared.lastErrorMessage == nil {
            appendActivity(.warning, "Push notifications were not enabled")
        }
    }

    func handlePushAuthorizationStateChange(
        _ authorizationState: CollaborationPushAuthorizationState,
        deviceToken: String?
    ) async {
        pushAuthorizationState = authorizationState
        await syncPushRegistrationIfNeeded(deviceToken: deviceToken)
    }

    func canWriteCoachNote(for relationship: CoachRelationship) -> Bool {
        relationship.currentRole(for: currentAccountID) == .coach
    }

    func canActOnAssignment(_ assignment: ProgramAssignment) -> Bool {
        assignment.athleteAccountID == currentAccountID && assignment.status == .pending
    }

    func invitePresentationMode(for invite: CoachInvite) -> InvitePresentationMode {
        guard invite.status == .pending else { return .readOnly }
        if isIncomingInvite(invite) {
            return .incomingPending
        }
        if invite.inviterAccountID == currentAccountID {
            return .outgoingPending
        }
        return .readOnly
    }

    private func syncPushRegistrationIfNeeded(deviceToken: String?) async {
        guard currentAccountID != nil else { return }
        guard let modelContext else { return }
        guard shouldSyncPushRegistration(deviceToken: deviceToken) else { return }

        do {
            let accessToken = try await validAccessToken()
            let registration = try await collaborationClient.registerDevice(
                DevicePushRegistrationRequest(
                    deviceID: syncStateStore.deviceID(),
                    pushToken: deviceToken,
                    authorizationStatusRawValue: pushAuthorizationState.rawValue
                ),
                accessToken: accessToken
            )
            try LocalCollaborationCacheStore(modelContext: modelContext)
                .replaceDeviceRegistration(with: registration)
            loadCache()
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func recordPushRegistrationError(_ message: String) async {
        lastErrorMessage = message
        appendActivity(.error, message)

        guard let modelContext else { return }
        let registration = DevicePushRegistrationDTO(
            stableID: "push-registration::\(syncStateStore.deviceID())",
            updatedAt: .now,
            deviceID: syncStateStore.deviceID(),
            pushToken: PushNotificationManager.shared.deviceTokenHex,
            authorizationStatusRawValue: pushAuthorizationState.rawValue,
            lastRegisteredAt: nil,
            lastErrorMessage: message
        )
        try? LocalCollaborationCacheStore(modelContext: modelContext)
            .replaceDeviceRegistration(with: registration)
        loadCache()
    }

    func updateNotificationPreferences(
        _ update: NotificationPreferenceUpdateRequest
    ) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            let dto = try await collaborationClient.updateNotificationPreferences(
                update,
                accessToken: accessToken
            )
            try LocalCollaborationCacheStore(modelContext: modelContext)
                .replaceNotificationPreference(with: dto)
            loadCache()
            statusMessage = "Notification preferences updated."
            appendActivity(.info, statusMessage ?? "Notification preferences updated.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func createCoachInvite(
        inviteeEmail: String,
        noteText: String?,
        inviterRole: CollaborationRole,
        scopes: [CollaborationVisibilityScope]
    ) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.createInvite(
                CoachInviteCreateRequest(
                    inviteeEmail: inviteeEmail,
                    noteText: noteText,
                    inviterRoleRawValue: inviterRole.rawValue,
                    visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: scopes)
                ),
                accessToken: accessToken
            )
            try await refreshInvites(using: accessToken, context: modelContext)
            try await refreshRelationships(using: accessToken, context: modelContext)
            statusMessage = "Coach invite sent."
            appendActivity(.info, statusMessage ?? "Coach invite sent.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func respondToInvite(_ invite: CoachInvite, action: CoachInviteStatus) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.respondToInvite(
                stableID: invite.stableID,
                request: CoachInviteActionRequest(actionRawValue: action.rawValue),
                accessToken: accessToken
            )
            try await refreshInvites(using: accessToken, context: modelContext)
            try await refreshRelationships(using: accessToken, context: modelContext)
            statusMessage = "Invite \(action.title.lowercased())."
            appendActivity(.info, statusMessage ?? "Invite updated.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func revokeInvite(_ invite: CoachInvite) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.revokeInvite(
                stableID: invite.stableID,
                accessToken: accessToken
            )
            try await refreshInvites(using: accessToken, context: modelContext)
            statusMessage = "Invite revoked."
            appendActivity(.info, statusMessage ?? "Invite revoked.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func updateRelationshipScopes(
        _ relationship: CoachRelationship,
        scopes: [CollaborationVisibilityScope]
    ) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.updateRelationshipScopes(
                stableID: relationship.stableID,
                request: RelationshipScopeUpdateRequest(
                    visibilityScopeBitmask: CollaborationVisibilityScope.bitmask(for: scopes)
                ),
                accessToken: accessToken
            )
            try await refreshRelationships(using: accessToken, context: modelContext)
            statusMessage = "Visibility scopes updated."
            appendActivity(.info, statusMessage ?? "Visibility scopes updated.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func saveBlueprint(
        from program: TrainingProgram,
        focusText: String?,
        notesText: String?,
        tags: [String]
    ) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            let dto = program.toSyncDTO()
            let encodedProgram = try JSONEncoder.iso8601.encode(dto)
            guard let json = String(data: encodedProgram, encoding: .utf8) else {
                throw CloudBackendClientError.invalidResponse
            }

            _ = try await collaborationClient.saveBlueprint(
                SavedProgramBlueprintCreateRequest(
                    name: program.name,
                    focusText: focusText,
                    notesText: notesText,
                    tags: tags,
                    durationWeeks: program.lengthInWeeks,
                    sessionsPerWeek: program.sessionsPerWeek,
                    sourceProgramStableID: program.resolvedSyncStableID,
                    trainingProgramSnapshotJSON: json
                ),
                accessToken: accessToken
            )
            try await refreshBlueprints(using: accessToken, context: modelContext)
            statusMessage = "Blueprint saved to your library."
            appendActivity(.info, statusMessage ?? "Blueprint saved.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func createAssignment(
        relationship: CoachRelationship,
        blueprint: SavedProgramBlueprint,
        notesText: String?,
        startGuidance: String?
    ) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.createAssignment(
                ProgramAssignmentCreateRequest(
                    relationshipStableID: relationship.stableID,
                    blueprintStableID: blueprint.stableID,
                    notesText: notesText,
                    startGuidance: startGuidance
                ),
                accessToken: accessToken
            )
            try await refreshAssignments(using: accessToken, context: modelContext)
            try await refreshRelationships(using: accessToken, context: modelContext)
            statusMessage = "Assignment sent."
            appendActivity(.info, statusMessage ?? "Assignment sent.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func updateAssignmentStatus(
        _ assignment: ProgramAssignment,
        status: ProgramAssignmentStatus
    ) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            let response = try await collaborationClient.updateAssignmentStatus(
                stableID: assignment.stableID,
                request: ProgramAssignmentStatusUpdateRequest(statusRawValue: status.rawValue),
                accessToken: accessToken
            )
            try await refreshAssignments(using: accessToken, context: modelContext)
            if status == .accepted, response.cloneReceipt != nil {
                await cloudSyncManager?.retryNow()
            }
            statusMessage = "Assignment \(status.title.lowercased())."
            appendActivity(.info, statusMessage ?? "Assignment updated.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func createCoachNote(
        relationship: CoachRelationship,
        bodyText: String,
        anchorKind: CoachNoteAnchorKind,
        anchoredWorkoutStableID: String? = nil,
        anchoredProgramRunStableID: String? = nil,
        anchoredWeekStart: Date? = nil,
        anchoredWeekEnd: Date? = nil,
        eventSummaryText: String? = nil,
        priority: CollaborationInsightPriority = .medium,
        requiresReview: Bool = false
    ) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.createCoachNote(
                CoachNoteCreateRequest(
                    relationshipStableID: relationship.stableID,
                    bodyText: bodyText,
                    anchorKindRawValue: anchorKind.rawValue,
                    anchoredWorkoutStableID: anchoredWorkoutStableID,
                    anchoredProgramRunStableID: anchoredProgramRunStableID,
                    anchoredWeekStart: anchoredWeekStart,
                    anchoredWeekEnd: anchoredWeekEnd,
                    eventSummaryText: eventSummaryText,
                    priorityRawValue: priority.rawValue,
                    requiresReview: requiresReview
                ),
                accessToken: accessToken
            )
            try await refreshNotes(using: accessToken, context: modelContext)
            statusMessage = "Coach note sent."
            appendActivity(.info, statusMessage ?? "Coach note sent.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func markNoteRead(_ note: CoachNote) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.markCoachNoteRead(
                stableID: note.stableID,
                accessToken: accessToken
            )
            try await refreshNotes(using: accessToken, context: modelContext)
            try await refreshRelationships(using: accessToken, context: modelContext)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func createProgramShare(
        relationshipStableID: String?,
        shareKind: ProgramShareKind,
        blueprintStableID: String?,
        sourceProgramStableID: String?,
        grantedToAccountID: UUID,
        messageText: String?
    ) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.createProgramShare(
                ProgramShareGrantCreateRequest(
                    relationshipStableID: relationshipStableID,
                    shareKindRawValue: shareKind.rawValue,
                    blueprintStableID: blueprintStableID,
                    sourceProgramStableID: sourceProgramStableID,
                    grantedToAccountID: grantedToAccountID,
                    messageText: messageText
                ),
                accessToken: accessToken
            )
            try await refreshProgramShares(using: accessToken, context: modelContext)
            statusMessage = "Program shared privately."
            appendActivity(.info, statusMessage ?? "Program shared privately.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func revokeProgramShare(_ share: ProgramShareGrant) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.revokeProgramShare(
                stableID: share.stableID,
                accessToken: accessToken
            )
            try await refreshProgramShares(using: accessToken, context: modelContext)
            statusMessage = "Program share revoked."
            appendActivity(.info, statusMessage ?? "Program share revoked.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func createProgressShare(
        relationshipStableID: String?,
        shareKind: ProgressShareKind,
        grantedToAccountID: UUID,
        titleText: String,
        subtitleText: String?,
        summaryText: String,
        payloadJSON: String
    ) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.createProgressShare(
                ProgressShareCardCreateRequest(
                    relationshipStableID: relationshipStableID,
                    shareKindRawValue: shareKind.rawValue,
                    grantedToAccountID: grantedToAccountID,
                    titleText: titleText,
                    subtitleText: subtitleText,
                    summaryText: summaryText,
                    payloadJSON: payloadJSON
                ),
                accessToken: accessToken
            )
            try await refreshProgressShares(using: accessToken, context: modelContext)
            statusMessage = "Progress shared privately."
            appendActivity(.info, statusMessage ?? "Progress shared privately.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func revokeProgressShare(_ share: ProgressShareCard) async {
        guard let modelContext else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.revokeProgressShare(
                stableID: share.stableID,
                accessToken: accessToken
            )
            try await refreshProgressShares(using: accessToken, context: modelContext)
            statusMessage = "Progress share revoked."
            appendActivity(.info, statusMessage ?? "Progress share revoked.")
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refreshRelationships(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let relationships = try await collaborationClient.fetchRelationships(accessToken: accessToken)
        try LocalCollaborationCacheStore(modelContext: context)
            .replaceRelationships(with: relationships)
        loadCache()
    }

    private func refreshInvites(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let invites = try await collaborationClient.fetchInvites(accessToken: accessToken)
        try LocalCollaborationCacheStore(modelContext: context)
            .replaceInvites(with: invites)
        loadCache()
    }

    private func refreshAssignments(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let assignments = try await collaborationClient.fetchAssignments(accessToken: accessToken)
        try LocalCollaborationCacheStore(modelContext: context)
            .replaceAssignments(with: assignments)
        loadCache()
    }

    private func refreshNotes(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let notes = try await collaborationClient.fetchNotes(accessToken: accessToken)
        try LocalCollaborationCacheStore(modelContext: context)
            .replaceNotes(with: notes)
        loadCache()
    }

    private func refreshBlueprints(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let blueprints = try await collaborationClient.fetchBlueprints(accessToken: accessToken)
        try LocalCollaborationCacheStore(modelContext: context)
            .replaceBlueprints(with: blueprints)
        loadCache()
    }

    private func refreshProgramShares(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let shares = try await collaborationClient.fetchProgramShares(accessToken: accessToken)
        try LocalCollaborationCacheStore(modelContext: context)
            .replaceProgramShares(with: shares)
        loadCache()
    }

    private func refreshProgressShares(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let shares = try await collaborationClient.fetchProgressShares(accessToken: accessToken)
        try LocalCollaborationCacheStore(modelContext: context)
            .replaceProgressShares(with: shares)
        loadCache()
    }

    private func loadCache() {
        guard let modelContext else { return }
        guard let snapshot = try? LocalCollaborationCacheStore(modelContext: modelContext).loadSnapshot() else {
            return
        }

        relationships = snapshot.relationships
        invites = snapshot.invites
        assignments = snapshot.assignments
        notes = snapshot.notes
        notificationPreference = snapshot.notificationPreference
        deviceRegistration = snapshot.deviceRegistration
        insightSnapshots = snapshot.insightSnapshots
        weeklyDigests = snapshot.weeklyDigests
        blueprints = snapshot.blueprints
        programShares = snapshot.programShares
        progressShares = snapshot.progressShares
    }

    private func clearInMemoryState() {
        relationships = []
        invites = []
        assignments = []
        notes = []
        notificationPreference = nil
        deviceRegistration = nil
        insightSnapshots = []
        weeklyDigests = []
        blueprints = []
        programShares = []
        progressShares = []
    }

    private func appendActivity(_ level: CollaborationActivityLevel, _ message: String) {
        recentActivity.insert(
            CollaborationActivityRecord(level: level, message: message),
            at: 0
        )
        recentActivity = Array(recentActivity.prefix(20))
    }

    private func shouldPerformRefresh(force: Bool) -> Bool {
        if force {
            return true
        }
        if phase == .error {
            return true
        }
        guard let lastSuccessfulRefreshAt else {
            return true
        }
        return Date().timeIntervalSince(lastSuccessfulRefreshAt) >= automaticRefreshMinimumInterval
    }

    private func shouldSyncPushRegistration(deviceToken: String?) -> Bool {
        guard let deviceRegistration else {
            return true
        }

        return deviceRegistration.deviceID != syncStateStore.deviceID()
            || deviceRegistration.pushToken != deviceToken
            || deviceRegistration.authorizationStatusRawValue != pushAuthorizationState.rawValue
            || deviceRegistration.lastRegisteredAt == nil
            || deviceRegistration.lastErrorMessage != nil
    }

    private func isIncomingInvite(_ invite: CoachInvite) -> Bool {
        if invite.inviteeAccountID == currentAccountID {
            return true
        }

        guard invite.inviteeAccountID == nil else {
            return false
        }

        return normalizedEmail(invite.inviteeEmail) == currentAccountEmail
    }

    private func normalizedEmail(_ email: String?) -> String? {
        email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func validAccessToken() async throws -> String {
        guard let tokens = tokenStore.loadTokens() else {
            throw CloudBackendClientError.missingSession
        }

        if tokens.accessTokenExpiresAt > Date().addingTimeInterval(60) {
            return tokens.accessToken
        }

        let refreshed = try await backendClient.refreshSession(
            CloudSessionRefreshRequest(
                deviceID: syncStateStore.deviceID(),
                refreshToken: tokens.refreshToken
            )
        )
        tokenStore.saveTokens(refreshed.tokens)
        currentAccountState = refreshed.accountState
        return refreshed.tokens.accessToken
    }

    private func mergeInsightSnapshots(
        primary: [InsightSnapshotDTO],
        roster: [InsightSnapshotDTO]
    ) -> [InsightSnapshotDTO] {
        var mergedByID = Dictionary(uniqueKeysWithValues: primary.map { ($0.stableID, $0) })
        for snapshot in roster {
            mergedByID[snapshot.stableID] = snapshot
        }
        return Array(mergedByID.values)
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
