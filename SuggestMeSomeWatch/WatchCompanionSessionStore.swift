//
//  WatchCompanionSessionStore.swift
//  SuggestMeSomeWatch
//
//  Watch-side receiver for transport-safe iPhone payloads.
//

import Combine
import Foundation
import WatchConnectivity

enum WatchCompanionRootMode: Equatable {
    case activeWorkout
    case todayPlan
}

enum WatchCompanionSessionActivationState: String, Equatable {
    case notActivated
    case inactive
    case activated
    case unknown
}

struct WatchCompanionSessionStatus: Equatable {
    let isSupported: Bool
    let activationState: WatchCompanionSessionActivationState
    let isCompanionAppInstalled: Bool
    let isReachable: Bool
    let hasContentPending: Bool
    let message: String
    let checkedAt: Date

    static func unsupported(checkedAt: Date = Date()) -> WatchCompanionSessionStatus {
        WatchCompanionSessionStatus(
            isSupported: false,
            activationState: .unknown,
            isCompanionAppInstalled: false,
            isReachable: false,
            hasContentPending: false,
            message: "Apple Watch sync is unavailable.",
            checkedAt: checkedAt
        )
    }
}

@MainActor
final class WatchCompanionSessionStore: NSObject, ObservableObject {
    @Published private(set) var todayPlan: WatchTodayPlanSnapshot?
    @Published private(set) var workoutLaunch: WatchWorkoutLaunchPayload?
    @Published private(set) var progressSnapshot: WatchWorkoutProgressSnapshot?
    @Published private(set) var liveWorkout: WatchLiveWorkoutSnapshot?
    @Published private(set) var currentContext: WatchCurrentSessionContext?
    @Published private(set) var completion: WatchSessionCompletionPayload?
    @Published private(set) var sessionStatus = WatchCompanionSessionStatus.unsupported()
    @Published private(set) var queuedUserInfoEventCount = 0

    private var session: WCSession?
    private var queuedUserInfoEvents: [WatchBridgeMessage] = []
    private var latestAppliedSentAtByKind: [WatchPayloadKind: Date] = [:]
    private var latestActiveSentAt: Date?
    private var latestCompletionSentAt: Date?

    override init() {
        super.init()

        guard WCSession.isSupported() else {
            sessionStatus = .unsupported()
            return
        }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        sessionStatus = Self.makeStatus(from: session, message: "Connecting to iPhone.")
        session.activate()
        applyApplicationContext(session.applicationContext)
    }

    var rootMode: WatchCompanionRootMode {
        hasActiveWorkout ? .activeWorkout : .todayPlan
    }

    var hasActiveWorkout: Bool {
        workoutLaunch != nil || liveWorkout != nil || currentContext != nil || progressSnapshot != nil
    }

    var connectionMessage: String {
        sessionStatus.message
    }

    private func applyApplicationContext(_ applicationContext: [String: Any]) {
        guard let message = decodeSupportedMessage(from: applicationContext) else { return }
        apply(message)
    }

    private func enqueueUserInfo(_ userInfo: [String: Any]) {
        guard let message = decodeSupportedMessage(from: userInfo) else { return }
        queuedUserInfoEvents.append(message)
        queuedUserInfoEventCount = queuedUserInfoEvents.count
        drainQueuedUserInfoEvents()
    }

    private func drainQueuedUserInfoEvents() {
        while !queuedUserInfoEvents.isEmpty {
            let event = queuedUserInfoEvents.removeFirst()
            queuedUserInfoEventCount = queuedUserInfoEvents.count
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
                self.todayPlan = todayPlan
            }
        case .workoutLaunch:
            applyDecoded(WatchWorkoutLaunchPayload.self, from: message) { launch in
                self.workoutLaunch = launch
                self.completion = nil
            }
        case .workoutProgress:
            applyDecoded(WatchWorkoutProgressSnapshot.self, from: message) { progress in
                self.progressSnapshot = progress
                self.completion = nil
            }
        case .liveWorkoutSnapshot:
            applyDecoded(WatchLiveWorkoutSnapshot.self, from: message) { liveWorkout in
                self.liveWorkout = liveWorkout
                self.completion = nil
            }
        case .currentSessionContext:
            applyDecoded(WatchCurrentSessionContext.self, from: message) { context in
                self.currentContext = context
                self.completion = nil
            }
        case .sessionCompletion:
            applyDecoded(WatchSessionCompletionPayload.self, from: message) { completion in
                self.completion = completion
                self.workoutLaunch = nil
                self.progressSnapshot = nil
                self.liveWorkout = nil
                self.currentContext = nil
            }
        case .workoutExecutionAction:
            return
        }
    }

    private func shouldAccept(_ message: WatchBridgeMessage) -> Bool {
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
        apply: (Payload) -> Void
    ) -> Bool {
        guard let payload = try? WatchBridgeMessageCodec.decodePayload(type, from: message) else { return false }
        apply(payload)
        markApplied(message)
        refreshSessionStatus(message: "Synced from iPhone.")
        return true
    }

    private func refreshSessionStatus(message: String? = nil) {
        guard let session else {
            sessionStatus = .unsupported()
            return
        }
        sessionStatus = Self.makeStatus(from: session, message: message)
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

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                session.transferUserInfo(message)
                Task { @MainActor in
                    self?.refreshSessionStatus(message: "Action queued for iPhone.")
                }
            }
            refreshSessionStatus(message: "Sent to iPhone.")
        } else {
            session.transferUserInfo(message)
            refreshSessionStatus(message: "Action queued for iPhone.")
        }
    }
}

private extension WatchPayloadKind {
    var isActiveWorkoutPayload: Bool {
        switch self {
        case .workoutLaunch, .workoutProgress, .liveWorkoutSnapshot, .currentSessionContext:
            return true
        case .todayPlanSnapshot, .sessionCompletion, .workoutExecutionAction:
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

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            refreshSessionStatus()
            enqueueUserInfo(userInfo)
        }
    }
}
