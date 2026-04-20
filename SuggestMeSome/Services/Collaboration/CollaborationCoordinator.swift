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

enum CollaborationEndpoint: String, Equatable, Hashable {
    case refresh
    case invites
    case relationships
    case assignments
    case notes
    case blueprints
    case programShares
    case progressShares
    case notificationPreferences
    case pushRegistration
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
    private let refreshCoalescer = CollaborationRefreshCoalescer()
    private let errorTracker = CollaborationErrorTracker()
    private var lastSuccessfulRefreshAt: Date?

    private let automaticRefreshMinimumInterval: TimeInterval = 15

    // MARK: - Derived-view caches
    //
    // These @ObservationIgnored holders memoize the filter work used by
    // coachRelationships, athleteRelationships, incomingPendingInvites,
    // outgoingPendingInvites, coachRosterSnapshots, and hasAnyCollaboration
    // so filters don't rerun on every SwiftUI body call. Each holder is
    // invalidated inside `loadCache()` and `clearInMemoryState()` — the
    // only places where the source arrays mutate.

    @ObservationIgnored private let coachRelationshipsCache = CachedDerivation<[CoachRelationship]>()
    @ObservationIgnored private let athleteRelationshipsCache = CachedDerivation<[CoachRelationship]>()
    @ObservationIgnored private let incomingPendingInvitesCache = CachedDerivation<[CoachInvite]>()
    @ObservationIgnored private let outgoingPendingInvitesCache = CachedDerivation<[CoachInvite]>()
    @ObservationIgnored private let coachRosterSnapshotsCache = CachedDerivation<[InsightSnapshot]>()
    @ObservationIgnored private let hasAnyCollaborationCache = CachedDerivation<Bool>()

    private func invalidateDerivedCaches() {
        coachRelationshipsCache.invalidate()
        athleteRelationshipsCache.invalidate()
        incomingPendingInvitesCache.invalidate()
        outgoingPendingInvitesCache.invalidate()
        coachRosterSnapshotsCache.invalidate()
        hasAnyCollaborationCache.invalidate()
    }

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
    private(set) var statusMessage: String?

    /// Aggregate error banner — derived from the shared error tracker so
    /// view observation fires when any endpoint error changes.
    var lastErrorMessage: String? { errorTracker.lastErrorMessage }
    var recentActivity: [CollaborationActivityRecord] { errorTracker.recentActivity }
    var endpointErrors: [CollaborationEndpoint: String] { errorTracker.endpointErrors }

    func endpointError(_ endpoint: CollaborationEndpoint) -> String? {
        errorTracker.endpointError(endpoint)
    }

    private func recordError(_ endpoint: CollaborationEndpoint, _ error: Error) {
        errorTracker.recordError(endpoint, error)
    }

    private func recordErrorMessage(_ endpoint: CollaborationEndpoint, message: String) {
        errorTracker.recordErrorMessage(endpoint, message: message)
    }

    private func clearError(_ endpoint: CollaborationEndpoint) {
        errorTracker.clearError(endpoint)
    }

    /// Resolves the current premium entitlement at gate-check time. Injected
    /// so tests can drive non-premium flows without touching the shared
    /// PurchaseManager singleton.
    private let entitlementStateProvider: @MainActor () -> EntitlementState

    init(
        collaborationClient: CloudCollaborationClient? = nil,
        backendClient: CloudBackendClient? = nil,
        tokenStore: CloudSessionTokenStore? = nil,
        syncStateStore: CloudSyncStateStore? = nil,
        entitlementStateProvider: (@MainActor () -> EntitlementState)? = nil
    ) {
        self.collaborationClient = collaborationClient ?? HTTPCloudCollaborationClient()
        self.backendClient = backendClient ?? HTTPCloudBackendClient()
        self.tokenStore = tokenStore ?? KeychainCloudSessionTokenStore.shared
        self.syncStateStore = syncStateStore ?? CloudSyncStateStore()
        self.entitlementStateProvider = entitlementStateProvider ?? { PurchaseManager.shared.entitlementState }
    }

    /// Defense-in-depth gate on every collaboration mutation. UI already
    /// wraps these flows in `PremiumFeatureGate`, but we also block them at
    /// the coordinator boundary so a mis-wired view can't bypass the gate
    /// and emit a network call. Gate failures surface through the shared
    /// error tracker so they render via the same InlineErrorBanner pattern
    /// as any other endpoint error.
    private func ensurePremiumAccess(for endpoint: CollaborationEndpoint) -> Bool {
        switch FeatureAccessPolicy.decision(
            for: .coachCollaboration,
            entitlementState: entitlementStateProvider()
        ) {
        case .granted:
            return true
        case .premiumRequired:
            errorTracker.recordErrorMessage(
                endpoint,
                message: "Coach collaboration requires Premium Unlock."
            )
            return false
        }
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
        coachRelationshipsCache.get {
            relationships.filter { $0.currentRole(for: currentAccountID) == .coach }
        }
    }

    var athleteRelationships: [CoachRelationship] {
        athleteRelationshipsCache.get {
            relationships.filter { $0.currentRole(for: currentAccountID) == .athlete }
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

    var inboxAssignments: [ProgramAssignment] {
        assignments.filter { assignment in
            canActOnAssignment(assignment)
        }
    }

    var coachRosterSnapshots: [InsightSnapshot] {
        coachRosterSnapshotsCache.get {
            let coachRelationshipIDs = Set(coachRelationships.map(\.stableID))
            return insightSnapshots.filter { snapshot in
                if let relationshipStableID = snapshot.relationshipStableID {
                    return coachRelationshipIDs.contains(relationshipStableID)
                }
                return false
            }
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

    var hasAnyCollaboration: Bool {
        hasAnyCollaborationCache.get {
            !relationships.isEmpty
                || !incomingPendingInvites.isEmpty
                || !outgoingPendingInvites.isEmpty
                || !unreadCoachNotes.isEmpty
                || !unreadDigests.isEmpty
                || !athleteFacingSnapshots.isEmpty
        }
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
            errorTracker.clearAllErrors()
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
            errorTracker.clearAllErrors()
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

        await refreshCoalescer.coalesce { [weak self] in
            guard let self else { return }
            await self.performRefresh(reason: reason)
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
        clearError(.refresh)

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
            recordError(.refresh, error)
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
        if pushAuthorizationState == .authorized && deviceToken == nil {
            return
        }
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
            clearError(.pushRegistration)
        } catch {
            recordError(.pushRegistration, error)
        }
    }

    func recordPushRegistrationError(_ message: String) async {
        recordErrorMessage(.pushRegistration, message: message)

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
        guard ensurePremiumAccess(for: .notificationPreferences) else { return }
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
            clearError(.notificationPreferences)
        } catch {
            recordError(.notificationPreferences, error)
        }
    }

    func createCoachInvite(
        inviteeEmail: String,
        noteText: String?,
        inviterRole: CollaborationRole,
        scopes: [CollaborationVisibilityScope]
    ) async {
        guard let modelContext else { return }
        guard ensurePremiumAccess(for: .invites) else { return }
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
            clearError(.invites)
        } catch {
            recordError(.invites, error)
        }
    }

    func respondToInvite(_ invite: CoachInvite, action: CoachInviteStatus) async {
        guard let modelContext else { return }
        guard ensurePremiumAccess(for: .invites) else { return }
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
            clearError(.invites)
        } catch {
            recordError(.invites, error)
        }
    }

    func revokeInvite(_ invite: CoachInvite) async {
        guard let modelContext else { return }
        guard ensurePremiumAccess(for: .invites) else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.revokeInvite(
                stableID: invite.stableID,
                accessToken: accessToken
            )
            try await refreshInvites(using: accessToken, context: modelContext)
            statusMessage = "Invite revoked."
            appendActivity(.info, statusMessage ?? "Invite revoked.")
            clearError(.invites)
        } catch {
            recordError(.invites, error)
        }
    }

    func updateRelationshipScopes(
        _ relationship: CoachRelationship,
        scopes: [CollaborationVisibilityScope]
    ) async {
        guard let modelContext else { return }
        guard ensurePremiumAccess(for: .relationships) else { return }
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
            clearError(.relationships)
        } catch {
            recordError(.relationships, error)
        }
    }

    func saveBlueprint(
        from program: TrainingProgram,
        focusText: String?,
        notesText: String?,
        tags: [String]
    ) async {
        guard let modelContext else { return }
        guard ensurePremiumAccess(for: .blueprints) else { return }
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
            clearError(.blueprints)
        } catch {
            recordError(.blueprints, error)
        }
    }

    func createAssignment(
        relationship: CoachRelationship,
        blueprint: SavedProgramBlueprint,
        notesText: String?,
        startGuidance: String?
    ) async {
        guard let modelContext else { return }
        guard ensurePremiumAccess(for: .assignments) else { return }
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
            clearError(.assignments)
        } catch {
            recordError(.assignments, error)
        }
    }

    func updateAssignmentStatus(
        _ assignment: ProgramAssignment,
        status: ProgramAssignmentStatus
    ) async {
        guard let modelContext else { return }
        guard ensurePremiumAccess(for: .assignments) else { return }
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
            clearError(.assignments)
        } catch {
            recordError(.assignments, error)
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
        guard ensurePremiumAccess(for: .notes) else { return }
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
            clearError(.notes)
        } catch {
            recordError(.notes, error)
        }
    }

    func markNoteRead(_ note: CoachNote) async {
        guard let modelContext else { return }
        guard ensurePremiumAccess(for: .notes) else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.markCoachNoteRead(
                stableID: note.stableID,
                accessToken: accessToken
            )
            try await refreshNotes(using: accessToken, context: modelContext)
            try await refreshRelationships(using: accessToken, context: modelContext)
            clearError(.notes)
        } catch {
            recordError(.notes, error)
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
        guard ensurePremiumAccess(for: .programShares) else { return }
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
            clearError(.programShares)
        } catch {
            recordError(.programShares, error)
        }
    }

    func revokeProgramShare(_ share: ProgramShareGrant) async {
        guard let modelContext else { return }
        guard ensurePremiumAccess(for: .programShares) else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.revokeProgramShare(
                stableID: share.stableID,
                accessToken: accessToken
            )
            try await refreshProgramShares(using: accessToken, context: modelContext)
            statusMessage = "Program share revoked."
            appendActivity(.info, statusMessage ?? "Program share revoked.")
            clearError(.programShares)
        } catch {
            recordError(.programShares, error)
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
        guard ensurePremiumAccess(for: .progressShares) else { return }
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
            clearError(.progressShares)
        } catch {
            recordError(.progressShares, error)
        }
    }

    func revokeProgressShare(_ share: ProgressShareCard) async {
        guard let modelContext else { return }
        guard ensurePremiumAccess(for: .progressShares) else { return }
        do {
            let accessToken = try await validAccessToken()
            _ = try await collaborationClient.revokeProgressShare(
                stableID: share.stableID,
                accessToken: accessToken
            )
            try await refreshProgressShares(using: accessToken, context: modelContext)
            statusMessage = "Progress share revoked."
            appendActivity(.info, statusMessage ?? "Progress share revoked.")
            clearError(.progressShares)
        } catch {
            recordError(.progressShares, error)
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
        invalidateDerivedCaches()
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
        invalidateDerivedCaches()
    }

    private func appendActivity(_ level: CollaborationActivityLevel, _ message: String) {
        errorTracker.logActivity(level, message)
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
