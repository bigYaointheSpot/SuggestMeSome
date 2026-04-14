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

protocol WatchCompanionBridge {
    var latestStatus: WatchCompanionStatus { get }
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
    private(set) var latestStatus: WatchCompanionStatus

#if canImport(WatchConnectivity)
    private let session: WCSession?
#endif

    override init() {
#if canImport(WatchConnectivity)
        if WCSession.isSupported() {
            self.session = WCSession.default
            self.latestStatus = DefaultWatchCompanionBridge.makeStatus(from: WCSession.default, checkedAt: Date())
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
        let updated = Self.makeStatus(from: session, checkedAt: Date())
        latestStatus = updated
        return updated
#else
        latestStatus = .unsupported()
        return latestStatus
#endif
    }

    func sendWorkoutLaunch(_ payload: WatchWorkoutLaunchPayload) async {
#if canImport(WatchConnectivity)
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        guard let message = Self.makeTransferMessage(kind: .workoutLaunch, payload: payload) else { return }
        session.transferUserInfo(message)
#else
        _ = payload
#endif
    }

    func sendWorkoutProgress(_ snapshot: WatchWorkoutProgressSnapshot) async {
#if canImport(WatchConnectivity)
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        guard let message = Self.makeTransferMessage(kind: .workoutProgress, payload: snapshot) else { return }
        session.transferUserInfo(message)
#else
        _ = snapshot
#endif
    }

    func sendTodayPlanSnapshot(_ snapshot: WatchTodayPlanSnapshot) async {
#if canImport(WatchConnectivity)
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        guard let message = Self.makeContextMessage(kind: .todayPlanSnapshot, payload: snapshot) else { return }
        try? session.updateApplicationContext(message)
#else
        _ = snapshot
#endif
    }

    func sendLiveWorkoutSnapshot(_ snapshot: WatchLiveWorkoutSnapshot) async {
#if canImport(WatchConnectivity)
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        guard let message = Self.makeContextMessage(kind: .liveWorkoutSnapshot, payload: snapshot) else { return }
        try? session.updateApplicationContext(message)
#else
        _ = snapshot
#endif
    }

    func sendCurrentSessionContext(_ context: WatchCurrentSessionContext) async {
#if canImport(WatchConnectivity)
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        guard let message = Self.makeContextMessage(kind: .currentSessionContext, payload: context) else { return }
        try? session.updateApplicationContext(message)
#else
        _ = context
#endif
    }

    func sendSessionCompletion(_ payload: WatchSessionCompletionPayload) async {
#if canImport(WatchConnectivity)
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        guard let message = Self.makeTransferMessage(kind: .sessionCompletion, payload: payload) else { return }
        session.transferUserInfo(message)
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
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
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
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            _ = await refreshStatus()
        }
    }
}

private extension DefaultWatchCompanionBridge {
    static func makeStatus(from session: WCSession, checkedAt: Date) -> WatchCompanionStatus {
        if !session.isPaired {
            return WatchCompanionStatus(
                availability: .notPaired,
                isPaired: false,
                isCompanionAppInstalled: false,
                isReachable: false,
                message: "No paired Apple Watch detected.",
                checkedAt: checkedAt
            )
        }

        if !session.isWatchAppInstalled {
            return WatchCompanionStatus(
                availability: .pairedNoCompanionApp,
                isPaired: true,
                isCompanionAppInstalled: false,
                isReachable: false,
                message: "Watch is paired. Companion app is not installed yet.",
                checkedAt: checkedAt
            )
        }

        if session.isReachable {
            return WatchCompanionStatus(
                availability: .reachable,
                isPaired: true,
                isCompanionAppInstalled: true,
                isReachable: true,
                message: "Watch companion is reachable.",
                checkedAt: checkedAt
            )
        }

        return WatchCompanionStatus(
            availability: .companionInstalled,
            isPaired: true,
            isCompanionAppInstalled: true,
            isReachable: false,
            message: "Watch is paired and companion app is installed.",
            checkedAt: checkedAt
        )
    }
}
#endif
