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
        guard let session else { return }
        guard session.activationState == .activated else { return }
        guard session.isWatchAppInstalled else { return }
        let message: [String: Any] = [
            "event": "workoutLaunch",
            "workoutID": payload.workoutID.uuidString,
            "startedAt": payload.startedAt.timeIntervalSince1970,
            "programRunID": payload.programRunID?.uuidString as Any,
            "programWeekNumber": payload.programWeekNumber as Any,
            "programSessionNumber": payload.programSessionNumber as Any
        ]
        session.transferUserInfo(message)
#else
        _ = payload
#endif
    }

    func sendWorkoutProgress(_ snapshot: WatchWorkoutProgressSnapshot) async {
#if canImport(WatchConnectivity)
        guard let session else { return }
        guard session.activationState == .activated else { return }
        guard session.isWatchAppInstalled else { return }
        let message: [String: Any] = [
            "event": "workoutProgress",
            "workoutID": snapshot.workoutID.uuidString,
            "elapsedSeconds": snapshot.elapsedSeconds,
            "completedExercises": snapshot.completedExercises,
            "totalExercises": snapshot.totalExercises,
            "capturedAt": snapshot.capturedAt.timeIntervalSince1970
        ]
        session.transferUserInfo(message)
#else
        _ = snapshot
#endif
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
