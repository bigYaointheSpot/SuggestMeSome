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
    case consentRequired
    case idle
    case loading
    case error

    var title: String {
        switch self {
        case .signedOut:
            return "Signed Out"
        case .consentRequired:
            return "Consent Needed"
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
    // Only `hasAnyCollaboration` remains coordinator-owned — it aggregates
    // across every sub-store so there's no natural home for it below.
    // Invalidation hooks alongside the stores in `loadCache()` and
    // `clearInMemoryState()`.

    @ObservationIgnored private let hasAnyCollaborationCache = CachedDerivation<Bool>()

    private func invalidateDerivedCaches() {
        hasAnyCollaborationCache.invalidate()
    }

    // MARK: - Sub-stores

    /// Owns CoachRelationship + CoachInvite state, the role-partitioned
    /// and invite-direction derived views, and the invite-presentation
    /// helpers. The coordinator's `relationships` / `invites` / derived
    /// view properties forward to it so existing call sites read through.
    @ObservationIgnored private lazy var relationshipsStore = CollaborationRelationshipsStore(
        currentAccountIDProvider: { [weak self] in self?.currentAccountID },
        currentAccountEmailProvider: { [weak self] in self?.currentAccountEmail }
    )

    /// Owns ProgramAssignment state and the trainee-facing inbox filter.
    @ObservationIgnored private lazy var assignmentsStore = CollaborationAssignmentsStore(
        currentAccountIDProvider: { [weak self] in self?.currentAccountID }
    )

    /// Owns CoachNote state and the unread-note filter.
    @ObservationIgnored private let notesStore = CollaborationNotesStore()

    /// Owns InsightSnapshot + WeeklyDigest state and the heavy roster filter.
    /// The coach-relationship provider closure pulls from the relationships
    /// store so both sub-stores stay decoupled while the derived view still
    /// sees fresh data after any relationship refresh.
    @ObservationIgnored private lazy var insightsStore = CollaborationInsightsStore(
        currentAccountIDProvider: { [weak self] in self?.currentAccountID },
        coachRelationshipIDsProvider: { [weak self] in
            guard let self else { return [] }
            return Set(self.relationshipsStore.coachRelationships.map(\.stableID))
        }
    )

    /// Owns SavedProgramBlueprint state.
    @ObservationIgnored private let blueprintsStore = CollaborationBlueprintsStore()

    /// Owns ProgramShareGrant + ProgressShareCard state.
    @ObservationIgnored private let sharesStore = CollaborationSharesStore()

    private(set) var phase: CollaborationSyncPhase = .signedOut
    var relationships: [CoachRelationship] { relationshipsStore.relationships }
    var invites: [CoachInvite] { relationshipsStore.invites }
    var assignments: [ProgramAssignment] { assignmentsStore.assignments }
    var notes: [CoachNote] { notesStore.notes }
    private(set) var notificationPreference: NotificationPreference?
    private(set) var deviceRegistration: DevicePushRegistration?
    var insightSnapshots: [InsightSnapshot] { insightsStore.insightSnapshots }
    var weeklyDigests: [WeeklyDigest] { insightsStore.weeklyDigests }
    var blueprints: [SavedProgramBlueprint] { blueprintsStore.blueprints }
    var programShares: [ProgramShareGrant] { sharesStore.programShares }
    var progressShares: [ProgressShareCard] { sharesStore.progressShares }
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
    private let cacheStoreFactory: @MainActor (ModelContext) -> any CollaborationCacheStoring

    init(
        collaborationClient: CloudCollaborationClient? = nil,
        backendClient: CloudBackendClient? = nil,
        tokenStore: CloudSessionTokenStore? = nil,
        syncStateStore: CloudSyncStateStore? = nil,
        entitlementStateProvider: (@MainActor () -> EntitlementState)? = nil,
        cacheStoreFactory: (@MainActor (ModelContext) -> any CollaborationCacheStoring)? = nil
    ) {
        self.collaborationClient = collaborationClient ?? HTTPCloudCollaborationClient()
        self.backendClient = backendClient ?? HTTPCloudBackendClient()
        self.tokenStore = tokenStore ?? KeychainCloudSessionTokenStore.shared
        self.syncStateStore = syncStateStore ?? CloudSyncStateStore()
        self.entitlementStateProvider = entitlementStateProvider ?? { PurchaseManager.shared.entitlementState }
        self.cacheStoreFactory = cacheStoreFactory ?? { modelContext in
            LocalCollaborationCacheStore(modelContext: modelContext)
        }
    }

    private func cacheStore(for modelContext: ModelContext) -> any CollaborationCacheStoring {
        cacheStoreFactory(modelContext)
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

    private func ensureConsumerHealthConsent(for endpoint: CollaborationEndpoint) -> Bool {
        guard currentAccountState.hasActiveConsumerHealthConsentForCurrentAccount else {
            errorTracker.recordErrorMessage(
                endpoint,
                message: ComplianceConfiguration.consumerHealthConsentMissingMessage
            )
            return false
        }
        return true
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
        case .consentRequired:
            return ComplianceConfiguration.consumerHealthConsentRequiredCopy
        case .idle:
            return statusMessage ?? "Coach collaboration is ready."
        case .loading:
            return "Refreshing collaboration, assignments, insights, and sharing state."
        case .error:
            return lastErrorMessage ?? "Coach collaboration needs attention."
        }
    }

    var coachRelationships: [CoachRelationship] { relationshipsStore.coachRelationships }
    var athleteRelationships: [CoachRelationship] { relationshipsStore.athleteRelationships }
    var pendingInvites: [CoachInvite] { relationshipsStore.pendingInvites }
    var incomingPendingInvites: [CoachInvite] { relationshipsStore.incomingPendingInvites }
    var outgoingPendingInvites: [CoachInvite] { relationshipsStore.outgoingPendingInvites }

    var inboxAssignments: [ProgramAssignment] { assignmentsStore.inboxAssignments }

    var coachRosterSnapshots: [InsightSnapshot] { insightsStore.coachRosterSnapshots }
    var athleteFacingSnapshots: [InsightSnapshot] { insightsStore.athleteFacingSnapshots }

    var unreadCoachNotes: [CoachNote] { notesStore.unreadCoachNotes }

    var unreadDigests: [WeeklyDigest] { insightsStore.unreadDigests }

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
        let hadConsent = currentAccountState.hasActiveConsumerHealthConsentForCurrentAccount
        currentAccountState = state

        guard state.currentAccountID != nil else {
            clearInMemoryState()
            phase = .signedOut
            statusMessage = nil
            errorTracker.clearAllErrors()
            return
        }

        loadCache()
        if state.hasActiveConsumerHealthConsentForCurrentAccount == false {
            phase = .consentRequired
            statusMessage = ComplianceConfiguration.consumerHealthConsentRequiredCopy
            return
        }
        if phase == .signedOut || phase == .consentRequired || !hadConsent {
            phase = .idle
            statusMessage = nil
        }
    }

    func handleAccountStateDidChange(_ state: AccountBackendContractState) async {
        let previousAccountID = currentAccountState.currentAccountID
        let hadConsent = currentAccountState.hasActiveConsumerHealthConsentForCurrentAccount
        let nextAccountID = state.currentAccountID
        let accountChanged = previousAccountID != nextAccountID

        if accountChanged,
           previousAccountID != nil,
           nextAccountID != nil,
           let modelContext {
            try? cacheStore(for: modelContext).clearAll()
            clearInMemoryState()
        }

        hydrateAccountState(state)

        guard nextAccountID != nil else {
            clearInMemoryState()
            if let modelContext {
                try? cacheStore(for: modelContext).clearAll()
            }
            phase = .signedOut
            statusMessage = nil
            errorTracker.clearAllErrors()
            return
        }

        guard state.hasActiveConsumerHealthConsentForCurrentAccount else {
            phase = .consentRequired
            statusMessage = ComplianceConfiguration.consumerHealthConsentRequiredCopy
            return
        }

        guard accountChanged || !hadConsent else { return }

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
        guard currentAccountState.hasActiveConsumerHealthConsentForCurrentAccount else {
            phase = .consentRequired
            statusMessage = ComplianceConfiguration.consumerHealthConsentRequiredCopy
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
            let store = cacheStore(for: modelContext)
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
        relationshipsStore.canWriteCoachNote(for: relationship)
    }

    func canActOnAssignment(_ assignment: ProgramAssignment) -> Bool {
        assignmentsStore.canActOnAssignment(assignment)
    }

    func invitePresentationMode(for invite: CoachInvite) -> InvitePresentationMode {
        relationshipsStore.invitePresentationMode(for: invite)
    }

    private func syncPushRegistrationIfNeeded(deviceToken: String?) async {
        guard currentAccountID != nil else { return }
        guard let modelContext else { return }
        guard currentAccountState.hasActiveConsumerHealthConsentForCurrentAccount else {
            phase = .consentRequired
            return
        }
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
            let store = cacheStore(for: modelContext)
            try store.replaceDeviceRegistration(with: registration)
            applyNotificationState(try store.loadNotificationState())
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
        let store = cacheStore(for: modelContext)
        try? store.replaceDeviceRegistration(with: registration)
        if let notificationState = try? store.loadNotificationState() {
            applyNotificationState(notificationState)
        }
    }

    func updateNotificationPreferences(
        _ update: NotificationPreferenceUpdateRequest
    ) async {
        guard let modelContext else { return }
        guard ensurePremiumAccess(for: .notificationPreferences) else { return }
        guard ensureConsumerHealthConsent(for: .notificationPreferences) else { return }
        do {
            let accessToken = try await validAccessToken()
            let dto = try await collaborationClient.updateNotificationPreferences(
                update,
                accessToken: accessToken
            )
            let store = cacheStore(for: modelContext)
            try store.replaceNotificationPreference(with: dto)
            applyNotificationState(try store.loadNotificationState())
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
        guard ensureConsumerHealthConsent(for: .invites) else { return }
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
        guard ensureConsumerHealthConsent(for: .invites) else { return }
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
        guard ensureConsumerHealthConsent(for: .invites) else { return }
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
        guard ensureConsumerHealthConsent(for: .relationships) else { return }
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
        guard ensureConsumerHealthConsent(for: .blueprints) else { return }
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
        guard ensureConsumerHealthConsent(for: .assignments) else { return }
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
        guard ensureConsumerHealthConsent(for: .assignments) else { return }
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
        guard ensureConsumerHealthConsent(for: .notes) else { return }
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
        guard ensureConsumerHealthConsent(for: .notes) else { return }
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
        guard ensureConsumerHealthConsent(for: .programShares) else { return }
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
        guard ensureConsumerHealthConsent(for: .programShares) else { return }
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
        guard ensureConsumerHealthConsent(for: .progressShares) else { return }
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
        guard ensureConsumerHealthConsent(for: .progressShares) else { return }
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
        let store = cacheStore(for: context)
        let relationships = try await collaborationClient.fetchRelationships(accessToken: accessToken)
        try store.replaceRelationships(with: relationships)
        applyRelationshipsAndInvites(try store.loadRelationshipsAndInvites())
    }

    private func refreshInvites(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let store = cacheStore(for: context)
        let invites = try await collaborationClient.fetchInvites(accessToken: accessToken)
        try store.replaceInvites(with: invites)
        applyRelationshipsAndInvites(try store.loadRelationshipsAndInvites())
    }

    private func refreshAssignments(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let store = cacheStore(for: context)
        let assignments = try await collaborationClient.fetchAssignments(accessToken: accessToken)
        try store.replaceAssignments(with: assignments)
        applyAssignments(try store.loadAssignments())
    }

    private func refreshNotes(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let store = cacheStore(for: context)
        let notes = try await collaborationClient.fetchNotes(accessToken: accessToken)
        try store.replaceNotes(with: notes)
        applyNotes(try store.loadNotes())
    }

    private func refreshBlueprints(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let store = cacheStore(for: context)
        let blueprints = try await collaborationClient.fetchBlueprints(accessToken: accessToken)
        try store.replaceBlueprints(with: blueprints)
        applyBlueprints(try store.loadBlueprints())
    }

    private func refreshProgramShares(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let store = cacheStore(for: context)
        let shares = try await collaborationClient.fetchProgramShares(accessToken: accessToken)
        try store.replaceProgramShares(with: shares)
        applyShares(try store.loadShares())
    }

    private func refreshProgressShares(
        using accessToken: String,
        context: ModelContext
    ) async throws {
        let store = cacheStore(for: context)
        let shares = try await collaborationClient.fetchProgressShares(accessToken: accessToken)
        try store.replaceProgressShares(with: shares)
        applyShares(try store.loadShares())
    }

    private func loadCache() {
        guard let modelContext else { return }
        guard let snapshot = try? cacheStore(for: modelContext).loadSnapshot() else {
            return
        }
        applyCacheSnapshot(snapshot)
    }

    private func applyCacheSnapshot(_ snapshot: CollaborationCacheSnapshot) {
        applyRelationshipsAndInvites(
            CollaborationRelationshipsCacheSlice(
                relationships: snapshot.relationships,
                invites: snapshot.invites
            ),
            invalidateDerived: false
        )
        applyAssignments(snapshot.assignments, invalidateDerived: false)
        applyNotes(snapshot.notes, invalidateDerived: false)
        applyNotificationState(
            CollaborationNotificationStateCacheSlice(
                notificationPreference: snapshot.notificationPreference,
                deviceRegistration: snapshot.deviceRegistration
            ),
            invalidateDerived: false
        )
        applyInsightsAndDigests(
            CollaborationInsightsCacheSlice(
                insightSnapshots: snapshot.insightSnapshots,
                weeklyDigests: snapshot.weeklyDigests
            ),
            invalidateDerived: false
        )
        applyBlueprints(snapshot.blueprints, invalidateDerived: false)
        applyShares(
            CollaborationSharesCacheSlice(
                programShares: snapshot.programShares,
                progressShares: snapshot.progressShares
            ),
            invalidateDerived: false
        )
        invalidateDerivedCaches()
    }

    private func applyRelationshipsAndInvites(
        _ slice: CollaborationRelationshipsCacheSlice,
        invalidateDerived: Bool = true
    ) {
        relationshipsStore.apply(
            relationships: slice.relationships,
            invites: slice.invites
        )
        if invalidateDerived {
            invalidateDerivedCaches()
        }
    }

    private func applyAssignments(
        _ assignments: [ProgramAssignment],
        invalidateDerived: Bool = true
    ) {
        assignmentsStore.apply(assignments: assignments)
        if invalidateDerived {
            invalidateDerivedCaches()
        }
    }

    private func applyNotes(
        _ notes: [CoachNote],
        invalidateDerived: Bool = true
    ) {
        notesStore.apply(notes: notes)
        if invalidateDerived {
            invalidateDerivedCaches()
        }
    }

    private func applyNotificationState(
        _ state: CollaborationNotificationStateCacheSlice,
        invalidateDerived: Bool = true
    ) {
        notificationPreference = state.notificationPreference
        deviceRegistration = state.deviceRegistration
        if invalidateDerived {
            invalidateDerivedCaches()
        }
    }

    private func applyInsightsAndDigests(
        _ slice: CollaborationInsightsCacheSlice,
        invalidateDerived: Bool = true
    ) {
        insightsStore.apply(
            insightSnapshots: slice.insightSnapshots,
            weeklyDigests: slice.weeklyDigests
        )
        if invalidateDerived {
            invalidateDerivedCaches()
        }
    }

    private func applyBlueprints(
        _ blueprints: [SavedProgramBlueprint],
        invalidateDerived: Bool = true
    ) {
        blueprintsStore.apply(blueprints: blueprints)
        if invalidateDerived {
            invalidateDerivedCaches()
        }
    }

    private func applyShares(
        _ slice: CollaborationSharesCacheSlice,
        invalidateDerived: Bool = true
    ) {
        sharesStore.apply(
            programShares: slice.programShares,
            progressShares: slice.progressShares
        )
        if invalidateDerived {
            invalidateDerivedCaches()
        }
    }

    private func clearInMemoryState() {
        relationshipsStore.clear()
        assignmentsStore.clear()
        notesStore.clear()
        notificationPreference = nil
        deviceRegistration = nil
        insightsStore.clear()
        blueprintsStore.clear()
        sharesStore.clear()
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
        relationshipsStore.isIncomingInvite(invite)
    }

    private func normalizedEmail(_ email: String?) -> String? {
        CollaborationRelationshipsStore.normalizedEmail(email)
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
