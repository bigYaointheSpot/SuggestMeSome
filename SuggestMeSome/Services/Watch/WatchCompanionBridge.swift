//
//  WatchCompanionBridge.swift
//  SuggestMeSome
//
//  Feature 8 Prompt 7 — Optional iOS watch status seam for future companion work.
//

import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

typealias WatchExecutionActionHandler = @MainActor (WatchWorkoutExecutionActionDTO) -> Void

protocol WatchCompanionBridge {
    var latestStatus: WatchCompanionStatus { get }
    var executionActionHandler: WatchExecutionActionHandler? { get set }
    func refreshStatus() async -> WatchCompanionStatus
    func sendWorkoutLaunch(_ payload: WatchWorkoutLaunchPayload) async
    func sendWorkoutProgress(_ snapshot: WatchWorkoutProgressSnapshot) async
    func sendTodayPlanSnapshot(_ snapshot: WatchTodayPlanSnapshot) async
    func sendLiveWorkoutSnapshot(_ snapshot: WatchLiveWorkoutSnapshot) async
    func sendCurrentSessionContext(_ context: WatchCurrentSessionContext) async
    func sendSessionCompletion(_ payload: WatchSessionCompletionPayload) async
}

@MainActor
final class DefaultWatchCompanionBridge: NSObject, WatchCompanionBridge {
    static let shared = DefaultWatchCompanionBridge()

    private(set) var latestStatus: WatchCompanionStatus
    var executionActionHandler: WatchExecutionActionHandler?
    private var watchEvidence = WatchCompanionEvidence()
    private var latestTodayPlanSnapshot: WatchTodayPlanSnapshot?
    private var latestWorkoutLaunchPayload: WatchWorkoutLaunchPayload?
    private var latestWorkoutProgressSnapshot: WatchWorkoutProgressSnapshot?
    private var latestLiveWorkoutSnapshot: WatchLiveWorkoutSnapshot?
    private var latestCurrentSessionContext: WatchCurrentSessionContext?
    private var latestSessionCompletionPayload: WatchSessionCompletionPayload?

#if canImport(WatchConnectivity)
    private let session: WCSession?
#endif

    override init() {
#if canImport(WatchConnectivity)
        if WCSession.isSupported() {
            self.session = WCSession.default
            let checkedAt = Date()
            let snapshot = DefaultWatchCompanionBridge.makeSessionSnapshot(from: WCSession.default)
            var evidence = WatchCompanionEvidence()
            if snapshot.activationState == .activated, snapshot.isWatchAppInstalled {
                evidence.recordInstalledCompanion(at: checkedAt)
            }
            self.watchEvidence = evidence
            self.latestStatus = WatchCompanionStatusResolver.makeStatus(
                from: snapshot,
                evidence: evidence,
                checkedAt: checkedAt
            )
        } else {
            self.session = nil
            self.latestStatus = .unsupported()
        }
#else
        self.latestStatus = .unsupported()
#endif
        super.init()

#if canImport(WatchConnectivity)
        if let session {
            session.delegate = self
            session.activate()
        }
#endif
    }

    func refreshStatus() async -> WatchCompanionStatus {
#if canImport(WatchConnectivity)
        guard let session else {
            latestStatus = .unsupported()
            return latestStatus
        }
        return refreshLatestStatus(from: session, checkedAt: Date())
#else
        latestStatus = .unsupported()
        return latestStatus
#endif
    }

    func sendWorkoutLaunch(_ payload: WatchWorkoutLaunchPayload) async {
        latestWorkoutLaunchPayload = payload
        latestWorkoutProgressSnapshot = nil
        latestLiveWorkoutSnapshot = nil
        latestCurrentSessionContext = nil
        latestSessionCompletionPayload = nil
#if canImport(WatchConnectivity)
        guard let session, canSendPayloads(on: session) else { return }
        guard let message = Self.makeTransferMessage(kind: .workoutLaunch, payload: payload) else { return }
        sendTransferMessage(message, on: session)
#else
        _ = payload
#endif
    }

    func sendWorkoutProgress(_ snapshot: WatchWorkoutProgressSnapshot) async {
        latestWorkoutProgressSnapshot = snapshot
        latestSessionCompletionPayload = nil
#if canImport(WatchConnectivity)
        guard let session, canSendPayloads(on: session) else { return }
        guard let message = Self.makeTransferMessage(kind: .workoutProgress, payload: snapshot) else { return }
        sendTransferMessage(message, on: session)
#else
        _ = snapshot
#endif
    }

    func sendTodayPlanSnapshot(_ snapshot: WatchTodayPlanSnapshot) async {
        latestTodayPlanSnapshot = snapshot
#if canImport(WatchConnectivity)
        sendLatestTodayPlanIfPossible()
#else
        _ = snapshot
#endif
    }

    func sendLiveWorkoutSnapshot(_ snapshot: WatchLiveWorkoutSnapshot) async {
        latestLiveWorkoutSnapshot = snapshot
        latestSessionCompletionPayload = nil
#if canImport(WatchConnectivity)
        guard let session, canSendPayloads(on: session) else { return }
        guard let message = Self.makeContextMessage(kind: .liveWorkoutSnapshot, payload: snapshot) else { return }
        sendContextMessage(message, on: session)
#else
        _ = snapshot
#endif
    }

    func sendCurrentSessionContext(_ context: WatchCurrentSessionContext) async {
        latestCurrentSessionContext = context
        latestSessionCompletionPayload = nil
#if canImport(WatchConnectivity)
        guard let session, canSendPayloads(on: session) else { return }
        guard let message = Self.makeContextMessage(kind: .currentSessionContext, payload: context) else { return }
        sendContextMessage(message, on: session)
#else
        _ = context
#endif
    }

    func sendSessionCompletion(_ payload: WatchSessionCompletionPayload) async {
        latestSessionCompletionPayload = payload
        latestWorkoutLaunchPayload = nil
        latestWorkoutProgressSnapshot = nil
        latestLiveWorkoutSnapshot = nil
        latestCurrentSessionContext = nil
#if canImport(WatchConnectivity)
        guard let session, canSendPayloads(on: session) else { return }
        guard let message = Self.makeContextMessage(kind: .sessionCompletion, payload: payload) else { return }
        sendContextMessage(
            message,
            on: session,
            transferOnForegroundSendFailure: true,
            transferWhenUnreachable: true
        )
#else
        _ = payload
#endif
    }
}

// MARK: - Shared message encoding

extension DefaultWatchCompanionBridge {
    static func makeTransferMessage<Payload: Codable & Equatable>(
        kind: WatchPayloadKind,
        payload: Payload,
        now: Date = Date()
    ) -> [String: Any]? {
        makeBridgeMessage(kind: kind, payload: payload, now: now)
    }

    static func makeContextMessage<Payload: Codable & Equatable>(
        kind: WatchPayloadKind,
        payload: Payload,
        now: Date = Date()
    ) -> [String: Any]? {
        // updateApplicationContext must be property-list-safe. We encode the
        // payload to JSON Data (allowed) and pair it with primitive metadata.
        makeBridgeMessage(kind: kind, payload: payload, now: now)
    }

    static func makeBridgeMessage<Payload: Codable & Equatable>(
        kind: WatchPayloadKind,
        payload: Payload,
        now: Date = Date()
    ) -> [String: Any]? {
        WatchBridgeMessageCodec.makeMessageIfPossible(
            kind: kind,
            payload: payload,
            sentAt: now
        )
    }

    static func encodePayload<Payload: Codable>(_ payload: Payload) -> Data? {
        try? WatchBridgeMessageCodec.encodePayload(payload)
    }

    static func decodePayload<Payload: Codable>(_ type: Payload.Type, from data: Data) -> Payload? {
        try? WatchBridgeMessageCodec.decodePayload(type, from: data)
    }
}

#if canImport(WatchConnectivity)
@MainActor
extension DefaultWatchCompanionBridge: WCSessionDelegate {
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            _ = await refreshStatus()
        }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            _ = await refreshStatus()
            replayLatestSnapshotsIfPossible()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            _ = await refreshStatus()
            replayLatestSnapshotsIfPossible()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            _ = await refreshStatus()
            replayLatestSnapshotsIfPossible()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleIncomingMessage(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            handleIncomingMessage(userInfo)
        }
    }
}

private extension DefaultWatchCompanionBridge {
    func refreshLatestStatus(from session: WCSession, checkedAt: Date) -> WatchCompanionStatus {
        let snapshot = Self.makeSessionSnapshot(from: session)
        if snapshot.activationState == .activated, snapshot.isWatchAppInstalled {
            watchEvidence.recordInstalledCompanion(at: checkedAt)
        }
        latestStatus = WatchCompanionStatusResolver.makeStatus(
            from: snapshot,
            evidence: watchEvidence,
            checkedAt: checkedAt
        )
        return latestStatus
    }

    func canSendPayloads(on session: WCSession, now: Date = Date()) -> Bool {
        WatchCompanionStatusResolver.canSendPayloads(
            with: Self.makeSessionSnapshot(from: session),
            evidence: watchEvidence,
            now: now
        )
    }

    func recordPayloadReplay(at date: Date = Date()) {
        watchEvidence.recordPayloadReplay(at: date)
        if let session {
            latestStatus = WatchCompanionStatusResolver.makeStatus(
                from: Self.makeSessionSnapshot(from: session),
                evidence: watchEvidence,
                checkedAt: date
            )
        } else {
            latestStatus = .unsupported(checkedAt: date)
        }
    }

    func sendTransferMessage(
        _ message: [String: Any],
        on session: WCSession,
        queueDurablyWhenUnreachable: Bool = true
    ) {
        recordPayloadReplay()
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                guard queueDurablyWhenUnreachable else { return }
                session.transferUserInfo(message)
            }
            return
        }
        guard queueDurablyWhenUnreachable else { return }
        session.transferUserInfo(message)
    }

    func sendContextMessage(
        _ message: [String: Any],
        on session: WCSession,
        transferOnForegroundSendFailure: Bool = false,
        transferWhenUnreachable: Bool = false
    ) {
        recordPayloadReplay()
        // Keep application context as the durable latest-state channel, but
        // mirror foreground-active updates over sendMessage so the watch UI
        // does not stall behind an optimistic local transition.
        try? session.updateApplicationContext(message)
        guard session.isReachable else {
            guard transferWhenUnreachable else { return }
            session.transferUserInfo(message)
            return
        }
        session.sendMessage(message, replyHandler: nil) { _ in
            guard transferOnForegroundSendFailure else { return }
            session.transferUserInfo(message)
        }
    }

    func replayLatestSnapshotsIfPossible() {
        sendLatestTodayPlanIfPossible()
        sendLatestSessionCompletionIfPossible()
        sendLatestActiveWorkoutIfPossible()
    }

    func sendLatestTodayPlanIfPossible() {
        guard let snapshot = latestTodayPlanSnapshot else { return }
#if canImport(WatchConnectivity)
        guard let session,
              canSendPayloads(on: session),
              let message = Self.makeContextMessage(kind: .todayPlanSnapshot, payload: snapshot) else {
            return
        }
        sendContextMessage(message, on: session)
#endif
    }

    func sendLatestSessionCompletionIfPossible() {
        guard let completion = latestSessionCompletionPayload else { return }
#if canImport(WatchConnectivity)
        guard let session,
              canSendPayloads(on: session),
              let message = Self.makeContextMessage(kind: .sessionCompletion, payload: completion) else {
            return
        }
        sendContextMessage(
            message,
            on: session,
            transferOnForegroundSendFailure: true,
            transferWhenUnreachable: true
        )
#endif
    }

    func sendLatestActiveWorkoutIfPossible() {
#if canImport(WatchConnectivity)
        guard let session,
              canSendPayloads(on: session) else {
            return
        }

        if let payload = latestWorkoutLaunchPayload,
           let message = Self.makeTransferMessage(kind: .workoutLaunch, payload: payload) {
            sendTransferMessage(message, on: session)
        }

        if let snapshot = latestWorkoutProgressSnapshot,
           let message = Self.makeTransferMessage(kind: .workoutProgress, payload: snapshot) {
            sendTransferMessage(message, on: session)
        }

        if let snapshot = latestLiveWorkoutSnapshot,
           let message = Self.makeContextMessage(kind: .liveWorkoutSnapshot, payload: snapshot) {
            sendContextMessage(message, on: session)
        }

        if let context = latestCurrentSessionContext,
           let message = Self.makeContextMessage(kind: .currentSessionContext, payload: context) {
            sendContextMessage(message, on: session)
        }
#endif
    }

    func handleIncomingMessage(_ dictionary: [String: Any]) {
        guard let message = try? WatchBridgeMessageCodec.decodeMessage(from: dictionary),
              message.isSupportedSchemaVersion else {
            return
        }
        switch message.kind {
        case .watchPresenceHeartbeat:
            guard let heartbeat = try? WatchBridgeMessageCodec.decodePayload(
                WatchPresenceHeartbeatPayload.self,
                from: message
            ) else {
                return
            }
            watchEvidence.recordWatchContact(at: max(message.sentAt, heartbeat.sentAt))
            if let session {
                latestStatus = refreshLatestStatus(from: session, checkedAt: Date())
            } else {
                latestStatus = .unsupported()
            }
            replayLatestSnapshotsIfPossible()

        case .workoutExecutionAction:
            guard let action = try? WatchBridgeMessageCodec.decodePayload(
                WatchWorkoutExecutionActionDTO.self,
                from: message
            ) else {
                return
            }
            executionActionHandler?(action)

        case .workoutLaunch,
             .workoutProgress,
             .todayPlanSnapshot,
             .currentSessionContext,
             .liveWorkoutSnapshot,
             .sessionCompletion:
            return
        }
    }

    static func makeSessionSnapshot(from session: WCSession) -> WatchCompanionSessionSnapshot {
        WatchCompanionSessionSnapshot(
            isSupported: true,
            activationState: WatchCompanionActivationState(session.activationState),
            isPaired: session.isPaired,
            isWatchAppInstalled: session.isWatchAppInstalled,
            isReachable: session.isReachable
        )
    }
}

private extension WatchCompanionActivationState {
    init(_ activationState: WCSessionActivationState) {
        switch activationState {
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
#endif
