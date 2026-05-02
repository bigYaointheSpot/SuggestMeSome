import Foundation
import Observation
import SwiftData

enum CloudSyncPhase: String, Codable, Equatable {
    case signedOut
    case consentRequired
    case idle
    case bootstrapping
    case pushing
    case pulling
    case error

    var title: String {
        switch self {
        case .signedOut:
            return "Signed Out"
        case .consentRequired:
            return "Consent Needed"
        case .idle:
            return "Up to Date"
        case .bootstrapping:
            return "Bootstrapping"
        case .pushing:
            return "Uploading"
        case .pulling:
            return "Downloading"
        case .error:
            return "Needs Attention"
        }
    }
}

@MainActor
@Observable
final class CloudSyncManager {
    static let shared = CloudSyncManager()

    private let backendClient: CloudBackendClient
    private let tokenStore: CloudSessionTokenStore
    private let stateStore: CloudSyncStateStore

    private var modelContext: ModelContext?
    private var userDefaults: UserDefaults
    private var currentAccountState: AccountBackendContractState = .empty
    private var isSyncInFlight = false
    private var pendingSyncReasons: [String] = []
    private var lastAccountStateRefreshAt: Date?
    private let accountStateRefreshInterval: TimeInterval = 300

    private(set) var phase: CloudSyncPhase = .signedOut
    private(set) var lastSuccessfulSyncAt: Date?
    private(set) var recentActivity: [CloudSyncActivityRecord]
    private(set) var lastErrorMessage: String?
    private(set) var currentAccountEmail: String?

    init(
        backendClient: CloudBackendClient = HTTPCloudBackendClient(),
        tokenStore: CloudSessionTokenStore = KeychainCloudSessionTokenStore.shared,
        stateStore: CloudSyncStateStore = CloudSyncStateStore(),
        userDefaults: UserDefaults = .standard
    ) {
        self.backendClient = backendClient
        self.tokenStore = tokenStore
        self.stateStore = stateStore
        self.userDefaults = userDefaults
        self.lastSuccessfulSyncAt = stateStore.lastSuccessfulSyncAt()
        self.recentActivity = stateStore.activity()
    }

    var statusSummary: String {
        guard AppBuildEnvironment.enablesProductionCloudFeatures else {
            return ComplianceConfiguration.v1LocalReleaseDisclosure
        }

        switch phase {
        case .signedOut:
            return "Connect an account to sync training history across devices."
        case .consentRequired:
            return ComplianceConfiguration.consumerHealthConsentRequiredCopy
        case .idle:
            if let lastSuccessfulSyncAt {
                return "Last synced \(lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened))."
            }
            return "Ready to sync."
        case .bootstrapping:
            return "Creating your first cloud snapshot."
        case .pushing:
            return "Uploading local changes."
        case .pulling:
            return "Downloading remote updates."
        case .error:
            return lastErrorMessage ?? "Cloud sync needs attention."
        }
    }

    func configure(
        modelContext: ModelContext,
        userDefaults: UserDefaults = .standard
    ) {
        guard AppBuildEnvironment.enablesProductionCloudFeatures else {
            phase = .signedOut
            lastErrorMessage = nil
            currentAccountEmail = nil
            return
        }

        self.modelContext = modelContext
        self.userDefaults = userDefaults
        self.lastSuccessfulSyncAt = stateStore.lastSuccessfulSyncAt()
        self.recentActivity = stateStore.activity()
    }

    func handleAccountStateDidChange(_ state: AccountBackendContractState) async {
        guard AppBuildEnvironment.enablesProductionCloudFeatures else {
            currentAccountState = .empty
            currentAccountEmail = nil
            phase = .signedOut
            lastErrorMessage = nil
            pendingSyncReasons.removeAll()
            return
        }

        currentAccountState = state
        lastAccountStateRefreshAt = Date()
        currentAccountEmail = state.knownAccounts.first(where: { $0.id == state.currentAccountID })?.email

        guard state.currentAccountID != nil else {
            phase = .signedOut
            lastErrorMessage = nil
            pendingSyncReasons.removeAll()
            return
        }

        guard modelContext != nil else { return }
        guard state.hasActiveConsumerHealthConsentForCurrentAccount else {
            setConsentRequiredPhase()
            return
        }
        if !stateStore.isBootstrapped(accountID: state.currentAccountID) {
            await sync(reason: "Bootstrap cloud sync", preferBootstrap: true)
        } else {
            phase = .idle
        }
    }

    func syncOnAppDidBecomeActive() async {
        guard AppBuildEnvironment.enablesProductionCloudFeatures else { return }
        await sync(reason: "App became active", preferBootstrap: false)
    }

    func retryNow() async {
        guard AppBuildEnvironment.enablesProductionCloudFeatures else { return }
        await sync(reason: "Manual retry", preferBootstrap: false)
    }

    func notifyLocalMutation(_ reason: String) {
        guard AppBuildEnvironment.enablesProductionCloudFeatures else { return }
        guard currentAccountState.currentAccountID != nil else { return }
        Task { @MainActor in
            await self.sync(reason: reason, preferBootstrap: false)
        }
    }

    func captureDeletedWorkouts(_ workouts: [Workout], at deletedAt: Date = .now) {
        guard AppBuildEnvironment.enablesProductionCloudFeatures else { return }
        guard !workouts.isEmpty else { return }
        let payload = CloudSyncBatchPayload(
            workouts: workouts.map { tombstoneWorkout($0, deletedAt: deletedAt) }
        )
        enqueuePending(payload: payload, reason: "Queued workout deletion sync")
    }

    func captureDeletedProgramGraph(
        programs: [TrainingProgram] = [],
        programRuns: [ProgramRun] = [],
        checkIns: [DailyCoachCheckIn] = [],
        weeklyReviews: [DailyCoachWeeklyReview] = [],
        analyses: [WeeklyTrainingAnalysis] = [],
        trends: [LiftPerformanceTrend] = [],
        proposals: [AdaptationProposal] = [],
        overlays: [AppliedProgramOverlay] = [],
        events: [AdaptationEventHistory] = [],
        at deletedAt: Date = .now
    ) {
        guard AppBuildEnvironment.enablesProductionCloudFeatures else { return }
        let payload = CloudSyncBatchPayload(
            workouts: [],
            trainingPrograms: programs.map { tombstoneProgram($0, deletedAt: deletedAt) },
            programRuns: programRuns.map { tombstoneProgramRun($0, deletedAt: deletedAt) },
            dailyCoachCheckIns: checkIns.map { tombstoneCheckIn($0, deletedAt: deletedAt) },
            dailyCoachWeeklyReviews: weeklyReviews.map { tombstoneWeeklyReview($0, deletedAt: deletedAt) },
            weeklyTrainingAnalyses: analyses.map { tombstoneWeeklyAnalysis($0, deletedAt: deletedAt) },
            liftPerformanceTrends: trends.map { tombstoneLiftTrend($0, deletedAt: deletedAt) },
            adaptationProposals: proposals.map { tombstoneProposal($0, deletedAt: deletedAt) },
            appliedProgramOverlays: overlays.map { tombstoneOverlay($0, deletedAt: deletedAt) },
            adaptationEvents: events.map { tombstoneEvent($0, deletedAt: deletedAt) },
            trainingPreferences: nil
        )
        enqueuePending(payload: payload, reason: "Queued program history deletion sync")
    }

    private func enqueuePending(payload: CloudSyncBatchPayload, reason: String) {
        guard AppBuildEnvironment.enablesProductionCloudFeatures else { return }
        guard currentAccountState.currentAccountID != nil else { return }
        guard !payload.isEmpty else { return }
        stateStore.enqueuePendingBatch(
            PendingCloudSyncBatch(
                reason: reason,
                payload: payload
            )
        )
        appendActivity(.info, reason)
        notifyLocalMutation(reason)
    }

    private func sync(reason: String, preferBootstrap: Bool) async {
        guard !isSyncInFlight else {
            queueFollowUpSync(reason)
            return
        }
        guard let modelContext else { return }
        guard currentAccountState.currentAccountID != nil else {
            phase = .signedOut
            return
        }
        guard currentAccountState.hasActiveConsumerHealthConsentForCurrentAccount else {
            setConsentRequiredPhase()
            return
        }

        isSyncInFlight = true
        defer {
            isSyncInFlight = false
            if phase != .error, currentAccountState.currentAccountID != nil {
                phase = phase == .consentRequired || !currentAccountState.hasActiveConsumerHealthConsentForCurrentAccount
                    ? .consentRequired
                    : .idle
            }
            scheduleFollowUpSyncIfNeeded()
        }

        do {
            let accessToken = try await validAccessToken()
            guard currentAccountState.hasActiveConsumerHealthConsentForCurrentAccount else {
                setConsentRequiredPhase()
                return
            }
            if preferBootstrap || !stateStore.isBootstrapped(accountID: currentAccountState.currentAccountID) {
                phase = .bootstrapping
                try await performBootstrap(accessToken: accessToken, context: modelContext)
                appendActivity(.info, "Bootstrap finished")
            } else {
                try await performIncrementalSync(accessToken: accessToken, context: modelContext)
                appendActivity(.info, reason)
            }
            lastErrorMessage = nil
        } catch {
            if error.isCloudConsentRequiredResponse {
                setConsentRequiredPhase()
                appendActivity(.warning, ComplianceConfiguration.consumerHealthConsentMissingMessage)
            } else {
                phase = .error
                lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                appendActivity(.error, lastErrorMessage ?? "Cloud sync failed")
            }
        }
    }

    private func performBootstrap(
        accessToken: String,
        context: ModelContext
    ) async throws {
        let repository = localRepository(context: context)
        let request = CloudSyncBootstrapRequest(
            deviceID: stateStore.deviceID(),
            payload: try buildFullPayload(repository: repository)
        )
        let response = try await backendClient.bootstrap(request, accessToken: accessToken)
        try applyPullResponse(response, repository: repository, context: context)
        stateStore.setBootstrappedAccountID(currentAccountState.currentAccountID)
    }

    private func performIncrementalSync(
        accessToken: String,
        context: ModelContext
    ) async throws {
        let repository = localRepository(context: context)
        let pendingBatches = stateStore.pendingBatches()
        let submittedPendingBatchIDs = Set(pendingBatches.map(\.id))
        let payload = mergePendingBatches(
            pendingBatches,
            into: try buildIncrementalPayload(repository: repository)
        )

        if !payload.isEmpty {
            phase = .pushing
            let request = CloudSyncPushRequest(
                deviceID: stateStore.deviceID(),
                batchID: UUID(),
                payload: payload
            )
            let response = try await backendClient.push(request, accessToken: accessToken)
            guard response.acceptedBatchID == request.batchID else {
                throw CloudBackendClientError.invalidResponse
            }
            try applyAuthoritativePayload(
                response.payload,
                repository: repository,
                context: context
            )
            appendWarnings(response.warnings)
            stateStore.removePendingBatches(ids: submittedPendingBatchIDs)
        }

        phase = .pulling
        let pullResponse = try await backendClient.pull(
            CloudSyncPullRequest(
                deviceID: stateStore.deviceID(),
                cursors: stateStore.cursors()
            ),
            accessToken: accessToken
        )
        try applyPullResponse(pullResponse, repository: repository, context: context)
    }

    private func buildFullPayload(repository: LocalSyncRepository) throws -> CloudSyncBatchPayload {
        CloudSyncBatchPayload(
            workouts: try repository.fetchWorkoutPayloads(since: nil, includeDeleted: true),
            trainingPrograms: try repository.fetchTrainingProgramPayloads(since: nil),
            programRuns: try repository.fetchProgramRunPayloads(since: nil),
            dailyCoachCheckIns: try repository.fetchDailyCheckInPayloads(since: nil),
            dailyCoachWeeklyReviews: try repository.fetchWeeklyReviewPayloads(since: nil),
            weeklyTrainingAnalyses: try repository.fetchWeeklyTrainingAnalysisPayloads(since: nil),
            liftPerformanceTrends: try repository.fetchLiftPerformanceTrendPayloads(since: nil),
            adaptationProposals: try repository.fetchAdaptationProposalPayloads(since: nil),
            appliedProgramOverlays: try repository.fetchAppliedOverlayPayloads(since: nil),
            adaptationEvents: try repository.fetchAdaptationEventPayloads(since: nil),
            trainingPreferences: try repository.fetchTrainingPreferencesPayload(since: nil)
        )
    }

    private func buildIncrementalPayload(repository: LocalSyncRepository) throws -> CloudSyncBatchPayload {
        let cursors = Dictionary(uniqueKeysWithValues: stateStore.cursors().map { ($0.collection, $0.lastSuccessfulSyncAt) })

        return CloudSyncBatchPayload(
            workouts: try repository.fetchWorkoutPayloads(
                since: cursors[.workouts] ?? lastSuccessfulSyncAt,
                includeDeleted: true
            ),
            trainingPrograms: try repository.fetchTrainingProgramPayloads(since: cursors[.trainingPrograms] ?? lastSuccessfulSyncAt),
            programRuns: try repository.fetchProgramRunPayloads(since: cursors[.programRuns] ?? lastSuccessfulSyncAt),
            dailyCoachCheckIns: try repository.fetchDailyCheckInPayloads(since: cursors[.dailyCoachCheckIns] ?? lastSuccessfulSyncAt),
            dailyCoachWeeklyReviews: try repository.fetchWeeklyReviewPayloads(since: cursors[.dailyCoachWeeklyReviews] ?? lastSuccessfulSyncAt),
            weeklyTrainingAnalyses: try repository.fetchWeeklyTrainingAnalysisPayloads(since: cursors[.weeklyTrainingAnalyses] ?? lastSuccessfulSyncAt),
            liftPerformanceTrends: try repository.fetchLiftPerformanceTrendPayloads(since: cursors[.liftPerformanceTrends] ?? lastSuccessfulSyncAt),
            adaptationProposals: try repository.fetchAdaptationProposalPayloads(since: cursors[.adaptationProposals] ?? lastSuccessfulSyncAt),
            appliedProgramOverlays: try repository.fetchAppliedOverlayPayloads(since: cursors[.appliedProgramOverlays] ?? lastSuccessfulSyncAt),
            adaptationEvents: try repository.fetchAdaptationEventPayloads(since: cursors[.adaptationEvents] ?? lastSuccessfulSyncAt),
            trainingPreferences: try repository.fetchTrainingPreferencesPayload(since: cursors[.trainingPreferences] ?? lastSuccessfulSyncAt)
        )
    }

    private func mergePendingBatches(
        _ pendingBatches: [PendingCloudSyncBatch],
        into payload: CloudSyncBatchPayload
    ) -> CloudSyncBatchPayload {
        pendingBatches.reduce(payload) { partialResult, pending in
            var merged = partialResult
            merged.merge(with: pending.payload)
            return merged
        }
    }

    private func applyPullResponse(
        _ response: CloudSyncResponse,
        repository: LocalSyncRepository,
        context: ModelContext
    ) throws {
        try applyAuthoritativePayload(response.payload, repository: repository, context: context)
        appendWarnings(response.warnings)
        commitPullProgress(response)
    }

    private func applyAuthoritativePayload(
        _ payload: CloudSyncBatchPayload,
        repository: LocalSyncRepository,
        context: ModelContext
    ) throws {
        try repository.upsertTrainingProgramPayloads(payload.trainingPrograms)
        try repository.upsertProgramRunPayloads(payload.programRuns)
        let workoutSummary = try repository.upsertWorkoutPayloads(payload.workouts)
        try repository.upsertWeeklyTrainingAnalysisPayloads(payload.weeklyTrainingAnalyses)
        try repository.upsertLiftPerformanceTrendPayloads(payload.liftPerformanceTrends)
        try repository.upsertDailyCheckInPayloads(payload.dailyCoachCheckIns)
        try repository.upsertWeeklyReviewPayloads(payload.dailyCoachWeeklyReviews)
        try repository.upsertAdaptationProposalPayloads(payload.adaptationProposals)
        try repository.upsertAppliedOverlayPayloads(payload.appliedProgramOverlays)
        try repository.upsertAdaptationEventPayloads(payload.adaptationEvents)
        if let trainingPreferences = payload.trainingPreferences {
            try repository.upsertTrainingPreferencesPayload(trainingPreferences)
        }

        if workoutSummary.didChangeWorkouts, workoutSummary.affectedExerciseNames.isEmpty == false {
            try PersonalRecordMaintenanceService.recomputePRs(
                for: workoutSummary.affectedExerciseNames,
                context: context
            )
            try context.save()
        }

        if shouldRunAdaptiveBackfill(context: context) {
            try backfillAdaptiveHistory(context: context)
        }
    }

    private func commitPullProgress(_ response: CloudSyncResponse) {
        stateStore.setCursors(response.cursors)
        stateStore.setLastSuccessfulSyncAt(response.serverTime)
        lastSuccessfulSyncAt = response.serverTime
    }

    private func appendWarnings(_ warnings: [CloudSyncWarningDTO]) {
        for warning in warnings {
            appendActivity(.warning, warning.message)
        }
    }

    private func shouldRunAdaptiveBackfill(context: ModelContext) -> Bool {
        let workoutCount = TrainingReadRepository.workoutCount(context: context)
        guard workoutCount > 0 else { return false }

        let analysisCount = (try? context.fetchCount(FetchDescriptor<WeeklyTrainingAnalysis>())) ?? 0
        let outcomeCount = (try? context.fetchCount(FetchDescriptor<ExercisePerformanceOutcome>())) ?? 0
        return analysisCount == 0 && outcomeCount == 0
    }

    private func backfillAdaptiveHistory(context: ModelContext) throws {
        let workouts = TrainingReadRepository.fetchWorkouts(context: context)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.startTime < rhs.startTime
                }
                return lhs.date < rhs.date
            }

        guard !workouts.isEmpty else { return }

        for workout in workouts where workout.sourceType != .healthKitImported {
            SessionOutcomeInferenceService.persistOutcomes(for: workout, context: context)
        }

        if let latestWorkout = workouts.last {
            WeeklyTrainingAnalysisService.analyzeCompletedWeeks(
                triggeredBy: latestWorkout,
                context: context
            )
        }

        appendActivity(.info, "Backfilled adaptive history from existing workouts")
    }

    private func validAccessToken() async throws -> String {
        guard let tokens = tokenStore.loadTokens() else {
            throw CloudBackendClientError.missingSession
        }

        if tokens.accessTokenExpiresAt > Date().addingTimeInterval(60),
           !shouldRefreshAccountState() {
            return tokens.accessToken
        }

        let refreshed = try await backendClient.refreshSession(
            CloudSessionRefreshRequest(
                deviceID: stateStore.deviceID(),
                refreshToken: tokens.refreshToken
            )
        )
        tokenStore.saveTokens(refreshed.tokens)
        currentAccountState = refreshed.accountState
        lastAccountStateRefreshAt = Date()
        currentAccountEmail = refreshed.accountState.knownAccounts.first(where: {
            $0.id == refreshed.accountState.currentAccountID
        })?.email
        return refreshed.tokens.accessToken
    }

    private func shouldRefreshAccountState(now: Date = Date()) -> Bool {
        guard let lastAccountStateRefreshAt else { return true }
        return now.timeIntervalSince(lastAccountStateRefreshAt) >= accountStateRefreshInterval
    }

    private func localRepository(context: ModelContext) -> LocalSyncRepository {
        LocalSyncRepository(
            modelContext: context,
            userDefaults: userDefaults
        )
    }

    private func appendActivity(_ level: CloudSyncActivityLevel, _ message: String) {
        let record = CloudSyncActivityRecord(level: level, message: message)
        stateStore.appendActivity(record)
        recentActivity = stateStore.activity()
    }

    private func setConsentRequiredPhase() {
        phase = .consentRequired
        lastErrorMessage = nil
    }

    private func queueFollowUpSync(_ reason: String) {
        if pendingSyncReasons.contains(reason) == false {
            pendingSyncReasons.append(reason)
        }
    }

    private func scheduleFollowUpSyncIfNeeded() {
        guard currentAccountState.currentAccountID != nil else {
            pendingSyncReasons.removeAll()
            return
        }
        guard currentAccountState.hasActiveConsumerHealthConsentForCurrentAccount else {
            setConsentRequiredPhase()
            return
        }

        guard pendingSyncReasons.isEmpty == false else { return }
        let reasons = pendingSyncReasons
        pendingSyncReasons.removeAll()

        Task { @MainActor in
            await self.sync(
                reason: reasons.joined(separator: ", "),
                preferBootstrap: false
            )
        }
    }

    private func tombstoneWorkout(_ workout: Workout, deletedAt: Date) -> WorkoutSyncDTO {
        var dto = workout.toSyncDTO()
        dto.metadata = tombstoneMetadata(for: workout, deletedAt: deletedAt)
        return dto
    }

    private func tombstoneProgram(_ program: TrainingProgram, deletedAt: Date) -> TrainingProgramSyncDTO {
        var dto = program.toSyncDTO()
        dto.metadata = tombstoneMetadata(for: program, deletedAt: deletedAt)
        return dto
    }

    private func tombstoneProgramRun(_ run: ProgramRun, deletedAt: Date) -> ProgramRunSyncDTO {
        var dto = run.toSyncDTO()
        dto.metadata = tombstoneMetadata(for: run, deletedAt: deletedAt)
        return dto
    }

    private func tombstoneCheckIn(_ checkIn: DailyCoachCheckIn, deletedAt: Date) -> DailyCoachCheckInSyncDTO {
        var dto = checkIn.toSyncDTO()
        dto.metadata = tombstoneMetadata(for: checkIn, deletedAt: deletedAt)
        return dto
    }

    private func tombstoneWeeklyReview(
        _ review: DailyCoachWeeklyReview,
        deletedAt: Date
    ) -> DailyCoachWeeklyReviewSyncDTO {
        var dto = review.toSyncDTO()
        dto.metadata = tombstoneMetadata(for: review, deletedAt: deletedAt)
        return dto
    }

    private func tombstoneWeeklyAnalysis(
        _ analysis: WeeklyTrainingAnalysis,
        deletedAt: Date
    ) -> WeeklyTrainingAnalysisSyncDTO {
        var dto = analysis.toSyncDTO()
        dto.metadata = tombstoneMetadata(for: analysis, deletedAt: deletedAt)
        return dto
    }

    private func tombstoneLiftTrend(
        _ trend: LiftPerformanceTrend,
        deletedAt: Date
    ) -> LiftPerformanceTrendSyncDTO {
        var dto = trend.toSyncDTO()
        dto.metadata = tombstoneMetadata(for: trend, deletedAt: deletedAt)
        return dto
    }

    private func tombstoneProposal(
        _ proposal: AdaptationProposal,
        deletedAt: Date
    ) -> AdaptationProposalSyncDTO {
        var dto = proposal.toSyncDTO()
        dto.metadata = tombstoneMetadata(for: proposal, deletedAt: deletedAt)
        return dto
    }

    private func tombstoneOverlay(
        _ overlay: AppliedProgramOverlay,
        deletedAt: Date
    ) -> AppliedProgramOverlaySyncDTO {
        var dto = overlay.toSyncDTO()
        dto.metadata = tombstoneMetadata(for: overlay, deletedAt: deletedAt)
        return dto
    }

    private func tombstoneEvent(
        _ event: AdaptationEventHistory,
        deletedAt: Date
    ) -> AdaptationEventHistorySyncDTO {
        var dto = event.toSyncDTO()
        dto.metadata = tombstoneMetadata(for: event, deletedAt: deletedAt)
        return dto
    }

    private func tombstoneMetadata(
        for model: any SyncTrackableModel,
        deletedAt: Date
    ) -> SyncRecordMetadataDTO {
        SyncRecordMetadataDTO(
            stableID: model.resolvedSyncStableID,
            version: max(1, model.syncVersion) + 1,
            lastModifiedAt: deletedAt,
            deletedAt: deletedAt
        )
    }
}

private extension CloudSyncBatchPayload {
    mutating func merge(with other: CloudSyncBatchPayload) {
        workouts = mergePayloads(workouts, other.workouts) { $0.metadata.stableID } metadata: { $0.metadata }
        trainingPrograms = mergePayloads(trainingPrograms, other.trainingPrograms) { $0.metadata.stableID } metadata: { $0.metadata }
        programRuns = mergePayloads(programRuns, other.programRuns) { $0.metadata.stableID } metadata: { $0.metadata }
        dailyCoachCheckIns = mergePayloads(dailyCoachCheckIns, other.dailyCoachCheckIns) { $0.metadata.stableID } metadata: { $0.metadata }
        dailyCoachWeeklyReviews = mergePayloads(dailyCoachWeeklyReviews, other.dailyCoachWeeklyReviews) { $0.metadata.stableID } metadata: { $0.metadata }
        weeklyTrainingAnalyses = mergePayloads(weeklyTrainingAnalyses, other.weeklyTrainingAnalyses) { $0.metadata.stableID } metadata: { $0.metadata }
        liftPerformanceTrends = mergePayloads(liftPerformanceTrends, other.liftPerformanceTrends) { $0.metadata.stableID } metadata: { $0.metadata }
        adaptationProposals = mergePayloads(adaptationProposals, other.adaptationProposals) { $0.metadata.stableID } metadata: { $0.metadata }
        appliedProgramOverlays = mergePayloads(appliedProgramOverlays, other.appliedProgramOverlays) { $0.metadata.stableID } metadata: { $0.metadata }
        adaptationEvents = mergePayloads(adaptationEvents, other.adaptationEvents) { $0.metadata.stableID } metadata: { $0.metadata }

        if let otherTrainingPreferences = other.trainingPreferences {
            if let trainingPreferences {
                self.trainingPreferences = isRemoteMetadataNewer(
                    local: trainingPreferences.metadata,
                    remote: otherTrainingPreferences.metadata
                ) ? otherTrainingPreferences : trainingPreferences
            } else {
                self.trainingPreferences = otherTrainingPreferences
            }
        }
    }
}

private func mergePayloads<T>(
    _ current: [T],
    _ incoming: [T],
    key: (T) -> String,
    metadata: (T) -> SyncRecordMetadataDTO
) -> [T] {
    var map = Dictionary(uniqueKeysWithValues: current.map { (key($0), $0) })
    for item in incoming {
        let stableID = key(item)
        if let existing = map[stableID] {
            map[stableID] = isRemoteMetadataNewer(
                local: metadata(existing),
                remote: metadata(item)
            ) ? item : existing
        } else {
            map[stableID] = item
        }
    }
    return Array(map.values)
}

private func isRemoteMetadataNewer(
    local: SyncRecordMetadataDTO,
    remote: SyncRecordMetadataDTO
) -> Bool {
    if remote.lastModifiedAt != local.lastModifiedAt {
        return remote.lastModifiedAt > local.lastModifiedAt
    }
    if remote.version != local.version {
        return remote.version > local.version
    }
    return remote.deletedAt != nil && local.deletedAt == nil
}
