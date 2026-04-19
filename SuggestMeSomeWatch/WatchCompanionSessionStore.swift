//
//  WatchCompanionSessionStore.swift
//  SuggestMeSomeWatch
//
//  Watch-side receiver for transport-safe iPhone payloads.
//

import Combine
import Foundation
import WatchConnectivity

#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class WatchCompanionSessionStore: NSObject {
    let liveWorkoutState = WatchLiveWorkoutState()
    let passiveContextState = WatchPassiveContextState()
    let connectionState = WatchConnectionState()
    let presentationState = WatchRootPresentationState()
    let widgetState: WatchWidgetState
    let workoutSessionController = WatchWorkoutSessionController()

    private var cancellables: Set<AnyCancellable> = []
    private var session: WCSession?
    private let widgetRefreshCoordinator: WatchWidgetRefreshCoordinator
    private var queuedUserInfoEvents: [WatchBridgeMessage] = []
    private var latestAppliedSentAtByKind: [WatchPayloadKind: Date] = [:]
    private var latestAppliedFingerprintByKind: [WatchPayloadKind: WatchPayloadFingerprint] = [:]
    private var latestActiveSentAt: Date?
    private var latestCompletionSentAt: Date?
    private var terminalWorkoutID: UUID?

    override init() {
#if canImport(WidgetKit)
        let initialSnapshot = WatchWidgetSnapshotStore.load()
        self.widgetState = WatchWidgetState(snapshot: initialSnapshot)
        self.widgetRefreshCoordinator = WatchWidgetRefreshCoordinator(
            initialSnapshot: initialSnapshot,
            saveSnapshot: { WatchWidgetSnapshotStore.save($0) },
            reloadTimelines: { WidgetCenter.shared.reloadAllTimelines() }
        )
#else
        let initialSnapshot = WatchWidgetSnapshotStore.load()
        self.widgetState = WatchWidgetState(snapshot: initialSnapshot)
        self.widgetRefreshCoordinator = WatchWidgetRefreshCoordinator(
            initialSnapshot: initialSnapshot,
            saveSnapshot: { WatchWidgetSnapshotStore.save($0) },
            reloadTimelines: {}
        )
#endif
        super.init()
        bindWorkoutSessionController()

        guard WCSession.isSupported() else {
            connectionState.setSessionStatus(.unsupported())
            return
        }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        connectionState.setSessionStatus(
            Self.makeStatus(from: session, message: "Connecting to iPhone.")
        )
        session.activate()
        applyApplicationContext(session.applicationContext)
    }

    func dismissCompletion() {
        passiveContextState.setCompletion(nil)
        refreshPresentationState()
    }

    func sendPresenceHeartbeat() {
        guard let session,
              session.activationState == .activated,
              let message = WatchBridgeMessageCodec.makeMessageIfPossible(
                kind: .watchPresenceHeartbeat,
                payload: WatchPresenceHeartbeatPayload()
              ) else {
            return
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                session.transferUserInfo(message)
                Task { @MainActor in
                    self?.refreshSessionStatus(message: "Watch presence queued for iPhone.")
                }
            }
            refreshSessionStatus(message: "Watch presence sent to iPhone.")
            return
        }

        session.transferUserInfo(message)
        refreshSessionStatus(message: "Watch presence queued for iPhone.")
    }

    private func applyApplicationContext(_ applicationContext: [String: Any]) {
        guard let message = decodeSupportedMessage(from: applicationContext) else { return }
        apply(message)
    }

    private func enqueueUserInfo(_ userInfo: [String: Any]) {
        guard let message = decodeSupportedMessage(from: userInfo) else { return }
        queuedUserInfoEvents.append(message)
        drainQueuedUserInfoEvents()
    }

    private func drainQueuedUserInfoEvents() {
        while !queuedUserInfoEvents.isEmpty {
            let event = queuedUserInfoEvents.removeFirst()
            apply(event)
        }
    }

    private func decodeSupportedMessage(from dictionary: [String: Any]) -> WatchBridgeMessage? {
        guard let message = try? WatchBridgeMessageCodec.decodeMessage(from: dictionary) else { return nil }
        guard message.isSupportedSchemaVersion else { return nil }
        return message
    }

    private func apply(_ message: WatchBridgeMessage) {
        guard shouldAccept(message) else { return }

        switch message.kind {
        case .todayPlanSnapshot:
            applyDecoded(WatchTodayPlanSnapshot.self, from: message) { todayPlan in
                self.passiveContextState.setTodayPlan(todayPlan)
                self.updateWidgetSnapshot(urgency: .deferred) { existing in
                    WatchWidgetSnapshot.mergingTodayPlan(todayPlan, into: existing)
                }
                return true
            }
        case .workoutLaunch:
            applyDecoded(WatchWorkoutLaunchPayload.self, from: message) { launch in
                guard self.acceptsInactiveTerminalState(workoutID: launch.workoutID) else { return false }
                self.resetActivePayloadsIfNeeded(
                    workoutID: launch.workoutID,
                    sessionVersionStableID: launch.sessionVersionStableID
                )
                self.terminalWorkoutID = nil
                self.liveWorkoutState.setWorkoutLaunch(launch)
                self.passiveContextState.setCompletion(nil)
                self.liveWorkoutState.setLatestWatchMetrics(nil)
                self.applyLinkedWorkoutLaunch(launch)
                self.refreshPresentationState()
                return true
            }
        case .workoutProgress:
            applyDecoded(WatchWorkoutProgressSnapshot.self, from: message) { progress in
                guard self.acceptsActivePayload(
                    workoutID: progress.workoutID,
                    sessionVersionStableID: nil
                ) else { return false }
                self.liveWorkoutState.setProgressSnapshot(progress)
                self.passiveContextState.setCompletion(nil)
                self.refreshPresentationState()
                return true
            }
        case .liveWorkoutSnapshot:
            applyDecoded(WatchLiveWorkoutSnapshot.self, from: message) { liveWorkout in
                guard self.acceptsActivePayload(
                    workoutID: liveWorkout.workoutID,
                    sessionVersionStableID: liveWorkout.sessionVersionStableID
                ) else { return false }
                self.liveWorkoutState.setLiveWorkout(liveWorkout)
                self.passiveContextState.setCompletion(nil)
                self.applyLinkedWorkoutLifecycle(
                    workoutID: liveWorkout.workoutID,
                    lifecycleState: liveWorkout.lifecycleState,
                    usesLinkedWatchHealthSession: liveWorkout.usesLinkedWatchHealthSession
                )
                self.updateWidgetSnapshot(urgency: .deferred) { existing in
                    WatchWidgetSnapshot.mergingLiveWorkout(
                        liveWorkout,
                        currentContext: self.liveWorkoutState.currentContext,
                        into: existing
                    )
                }
                self.refreshPresentationState()
                return true
            }
        case .currentSessionContext:
            applyDecoded(WatchCurrentSessionContext.self, from: message) { context in
                guard self.acceptsActivePayload(
                    workoutID: context.workoutID,
                    sessionVersionStableID: context.sessionVersionStableID
                ) else { return false }
                self.liveWorkoutState.setCurrentContext(context)
                self.passiveContextState.setCompletion(nil)
                self.applyLinkedWorkoutLifecycle(
                    workoutID: context.workoutID,
                    lifecycleState: context.lifecycleState,
                    usesLinkedWatchHealthSession: context.usesLinkedWatchHealthSession
                )
                self.updateWidgetSnapshot(urgency: .deferred) { existing in
                    existing.updatingCurrentContext(context)
                }
                self.refreshPresentationState()
                return true
            }
        case .sessionCompletion:
            applyDecoded(WatchSessionCompletionPayload.self, from: message) { completion in
                self.terminalWorkoutID = completion.workoutID
                self.passiveContextState.setCompletion(completion)
                self.liveWorkoutState.clearForCompletion()
                self.workoutSessionController.stop()
                self.updateWidgetSnapshot(urgency: .immediate) { existing in
                    existing.clearingActiveWorkout()
                }
                self.refreshPresentationState()
                return true
            }
        case .watchPresenceHeartbeat:
            return
        case .workoutExecutionAction:
            return
        case .workoutMetrics, .workoutHealthSummary:
            return
        }
    }

    private func shouldAccept(_ message: WatchBridgeMessage) -> Bool {
        let fingerprint = WatchPayloadFingerprint(message: message)
        if latestAppliedFingerprintByKind[message.kind] == fingerprint {
            return false
        }

        if let previous = latestAppliedSentAtByKind[message.kind], message.sentAt < previous {
            return false
        }

        if message.kind.isActiveWorkoutPayload,
           let completionSentAt = latestCompletionSentAt,
           message.sentAt < completionSentAt {
            return false
        }

        if message.kind == .sessionCompletion,
           let activeSentAt = latestActiveSentAt,
           message.sentAt < activeSentAt {
            return false
        }

        return true
    }

    private func markApplied(_ message: WatchBridgeMessage) {
        latestAppliedSentAtByKind[message.kind] = message.sentAt
        latestAppliedFingerprintByKind[message.kind] = WatchPayloadFingerprint(message: message)
        if message.kind.isActiveWorkoutPayload {
            latestActiveSentAt = max(latestActiveSentAt ?? .distantPast, message.sentAt)
        }
        if message.kind == .sessionCompletion {
            latestCompletionSentAt = max(latestCompletionSentAt ?? .distantPast, message.sentAt)
        }
    }

    @discardableResult
    private func applyDecoded<Payload: Decodable>(
        _ type: Payload.Type,
        from message: WatchBridgeMessage,
        apply: (Payload) -> Bool
    ) -> Bool {
        guard let payload = try? WatchBridgeMessageCodec.decodePayload(type, from: message) else { return false }
        guard apply(payload) else { return false }
        markApplied(message)
        refreshSessionStatus(message: "Synced from iPhone.")
        return true
    }

    private func acceptsActivePayload(
        workoutID: UUID,
        sessionVersionStableID: String?
    ) -> Bool {
        guard acceptsInactiveTerminalState(workoutID: workoutID) else { return false }
        guard let activeWorkoutID else { return true }
        guard activeWorkoutID == workoutID else { return false }

        guard let existingVersion = activeSessionVersionStableID,
              let incomingVersion = sessionVersionStableID else {
            return true
        }
        return existingVersion == incomingVersion
    }

    private func acceptsInactiveTerminalState(workoutID: UUID) -> Bool {
        terminalWorkoutID != workoutID
    }

    private func resetActivePayloadsIfNeeded(
        workoutID: UUID,
        sessionVersionStableID: String?
    ) {
        guard let activeWorkoutID else { return }
        let versionChanged: Bool = {
            guard let existingVersion = activeSessionVersionStableID,
                  let sessionVersionStableID else {
                return false
            }
            return existingVersion != sessionVersionStableID
        }()
        guard activeWorkoutID != workoutID || versionChanged else { return }
        liveWorkoutState.resetActivePayloads()
    }

    private var activeWorkoutID: UUID? {
        liveWorkoutState.activeWorkoutID
    }

    private var activeSessionVersionStableID: String? {
        liveWorkoutState.activeSessionVersionStableID
    }

    private func updateWidgetSnapshot(
        urgency: WatchWidgetRefreshUrgency,
        _ transform: (WatchWidgetSnapshot) -> WatchWidgetSnapshot
    ) {
        let updatedSnapshot = transform(widgetState.snapshot)
        guard !updatedSnapshot.matchesWidgetContent(of: widgetState.snapshot) else {
            return
        }

        widgetState.setSnapshot(updatedSnapshot)
        widgetRefreshCoordinator.apply({ _ in updatedSnapshot }, urgency: urgency)
    }

    private func refreshSessionStatus(message: String? = nil) {
        guard let session else {
            connectionState.setSessionStatus(.unsupported())
            return
        }
        connectionState.setSessionStatus(Self.makeStatus(from: session, message: message))
    }

    func sendExecutionAction(_ action: WatchWorkoutExecutionActionDTO) {
        guard let session,
              session.activationState == .activated,
              let message = WatchBridgeMessageCodec.makeMessageIfPossible(
                kind: .workoutExecutionAction,
                payload: action
              ) else {
            return
        }

        // Completion actions must survive flaky reachability. Queue durable
        // delivery even when a live message path is available; the phone
        // dedupes by actionID.
        session.transferUserInfo(message)

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshSessionStatus(message: "Action queued for iPhone.")
                }
            }
            refreshSessionStatus(message: "Sent to iPhone.")
            return
        }

        refreshSessionStatus(message: "Action queued for iPhone.")
    }

    private func bindWorkoutSessionController() {
        workoutSessionController.$latestMetricsPayload
            .compactMap { $0 }
            .sink { [weak self] payload in
                Task { @MainActor in
                    guard let self else { return }
                    self.liveWorkoutState.setLatestWatchMetrics(payload)
                    self.sendMetricsUpdate(payload)
                }
            }
            .store(in: &cancellables)

        workoutSessionController.$latestHealthSummaryPayload
            .compactMap { $0 }
            .sink { [weak self] payload in
                Task { @MainActor in
                    self?.sendHealthSummary(payload)
                }
            }
            .store(in: &cancellables)
    }

    private func applyLinkedWorkoutLaunch(_ launch: WatchWorkoutLaunchPayload) {
        guard launch.usesLinkedWatchHealthSession == true else {
            workoutSessionController.stop(sendHealthSummary: false)
            return
        }
        workoutSessionController.start(launch: launch)
    }

    private func applyLinkedWorkoutLifecycle(
        workoutID: UUID,
        lifecycleState: WatchWorkoutLifecycleState?,
        usesLinkedWatchHealthSession: Bool?
    ) {
        guard usesLinkedWatchHealthSession == true else {
            return
        }
        guard let workoutLaunch = liveWorkoutState.workoutLaunch, workoutLaunch.workoutID == workoutID else {
            return
        }
        if workoutSessionController.latestMetricsPayload?.workoutID != workoutID {
            workoutSessionController.start(
                launch: WatchWorkoutLaunchPayload(
                    workoutID: workoutLaunch.workoutID,
                    startedAt: workoutLaunch.startedAt,
                    programRunID: workoutLaunch.programRunID,
                    programWeekNumber: workoutLaunch.programWeekNumber,
                    programSessionNumber: workoutLaunch.programSessionNumber,
                    sessionPlanKind: workoutLaunch.sessionPlanKind,
                    lifecycleState: lifecycleState ?? workoutLaunch.lifecycleState,
                    usesLinkedWatchHealthSession: workoutLaunch.usesLinkedWatchHealthSession,
                    sessionSourceLabels: workoutLaunch.sessionSourceLabels,
                    sessionVersionStableID: workoutLaunch.sessionVersionStableID
                )
            )
            return
        }
        if let lifecycleState {
            workoutSessionController.apply(lifecycleState: lifecycleState)
        }
    }

    private func sendMetricsUpdate(_ payload: WatchWorkoutMetricsPayload) {
        guard let session,
              session.activationState == .activated,
              let message = WatchBridgeMessageCodec.makeMessageIfPossible(
                kind: .workoutMetrics,
                payload: payload
              ) else {
            return
        }
        guard session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSessionStatus(message: "Metrics queued for iPhone.")
            }
        }
    }

    private func sendHealthSummary(_ payload: WatchWorkoutHealthSummaryPayload) {
        guard let session,
              session.activationState == .activated,
              let message = WatchBridgeMessageCodec.makeMessageIfPossible(
                kind: .workoutHealthSummary,
                payload: payload
              ) else {
            return
        }

        session.transferUserInfo(message)
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshSessionStatus(message: "Workout summary queued for iPhone.")
                }
            }
            refreshSessionStatus(message: "Workout summary sent to iPhone.")
            return
        }

        refreshSessionStatus(message: "Workout summary queued for iPhone.")
    }

    private func refreshPresentationState() {
        presentationState.refresh(
            liveWorkoutState: liveWorkoutState,
            passiveContextState: passiveContextState
        )
    }
}

private extension WatchPayloadKind {
    var isActiveWorkoutPayload: Bool {
        switch self {
        case .workoutLaunch, .workoutProgress, .liveWorkoutSnapshot, .currentSessionContext:
            return true
        case .todayPlanSnapshot, .sessionCompletion, .workoutExecutionAction, .watchPresenceHeartbeat, .workoutMetrics, .workoutHealthSummary:
            return false
        }
    }
}

private extension WatchCompanionSessionStore {
    static func makeStatus(from session: WCSession, message: String? = nil) -> WatchCompanionSessionStatus {
        let activationState = WatchCompanionSessionActivationState(session.activationState)
        let installed = isCompanionAppInstalled(session)
        let statusMessage = message ?? defaultMessage(
            activationState: activationState,
            isCompanionAppInstalled: installed,
            isReachable: session.isReachable,
            hasContentPending: session.hasContentPending
        )

        return WatchCompanionSessionStatus(
            isSupported: true,
            activationState: activationState,
            isCompanionAppInstalled: installed,
            isReachable: session.isReachable,
            hasContentPending: session.hasContentPending,
            message: statusMessage,
            checkedAt: Date()
        )
    }

    static func isCompanionAppInstalled(_ session: WCSession) -> Bool {
#if os(watchOS)
        session.isCompanionAppInstalled
#else
        true
#endif
    }

    static func defaultMessage(
        activationState: WatchCompanionSessionActivationState,
        isCompanionAppInstalled: Bool,
        isReachable: Bool,
        hasContentPending: Bool
    ) -> String {
        guard isCompanionAppInstalled else {
            return "Install SuggestMeSome on iPhone to sync."
        }
        guard activationState == .activated else {
            return "Waiting for iPhone."
        }
        if isReachable {
            return "iPhone reachable."
        }
        if hasContentPending {
            return "Sync pending with iPhone."
        }
        return "iPhone will sync when available."
    }
}

private extension WatchCompanionSessionActivationState {
    init(_ state: WCSessionActivationState) {
        switch state {
        case .notActivated:
            self = .notActivated
        case .inactive:
            self = .inactive
        case .activated:
            self = .activated
        @unknown default:
            self = .unknown
        }
    }
}

extension WatchCompanionSessionStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            refreshSessionStatus(message: error?.localizedDescription)
            applyApplicationContext(session.applicationContext)
            sendPresenceHeartbeat()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshSessionStatus()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            refreshSessionStatus()
            applyApplicationContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            refreshSessionStatus()
            applyApplicationContext(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            refreshSessionStatus()
            enqueueUserInfo(userInfo)
        }
    }
}
