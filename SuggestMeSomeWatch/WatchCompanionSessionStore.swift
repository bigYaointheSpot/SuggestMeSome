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

@MainActor
final class WatchCompanionSessionStore: NSObject, ObservableObject {
    @Published private(set) var todayPlan: WatchTodayPlanSnapshot?
    @Published private(set) var progressSnapshot: WatchWorkoutProgressSnapshot?
    @Published private(set) var liveWorkout: WatchLiveWorkoutSnapshot?
    @Published private(set) var currentContext: WatchCurrentSessionContext?
    @Published private(set) var completion: WatchSessionCompletionPayload?
    @Published private(set) var connectionMessage = "Waiting for iPhone"

    private let decoder: JSONDecoder
    private var session: WCSession?

    override init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
        super.init()

        guard WCSession.isSupported() else {
            connectionMessage = "Apple Watch sync is unavailable."
            return
        }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
        applyTransportMessage(session.applicationContext)
    }

    var rootMode: WatchCompanionRootMode {
        hasActiveWorkout ? .activeWorkout : .todayPlan
    }

    var hasActiveWorkout: Bool {
        liveWorkout != nil || currentContext != nil || progressSnapshot != nil
    }

    private func applyTransportMessage(_ message: [String: Any]) {
        guard let transport = WatchTransportMessage(dictionary: message) else { return }
        guard transport.schemaVersion <= WatchPayloadContractVersion.current else { return }

        switch transport.kind {
        case .todayPlanSnapshot:
            applyDecoded(WatchTodayPlanSnapshot.self, from: transport.payloadJSON) { todayPlan in
                self.todayPlan = todayPlan
            }
        case .workoutProgress:
            applyDecoded(WatchWorkoutProgressSnapshot.self, from: transport.payloadJSON) { progress in
                self.progressSnapshot = progress
                self.completion = nil
            }
        case .liveWorkoutSnapshot:
            applyDecoded(WatchLiveWorkoutSnapshot.self, from: transport.payloadJSON) { liveWorkout in
                self.liveWorkout = liveWorkout
                self.completion = nil
            }
        case .currentSessionContext:
            applyDecoded(WatchCurrentSessionContext.self, from: transport.payloadJSON) { context in
                self.currentContext = context
                self.completion = nil
            }
        case .sessionCompletion:
            applyDecoded(WatchSessionCompletionPayload.self, from: transport.payloadJSON) { completion in
                self.completion = completion
                self.progressSnapshot = nil
                self.liveWorkout = nil
                self.currentContext = nil
            }
        case .workoutLaunch:
            connectionMessage = "Workout started on iPhone."
        }
    }

    private func applyDecoded<Payload: Decodable>(
        _ type: Payload.Type,
        from data: Data,
        apply: (Payload) -> Void
    ) {
        guard let payload = try? decoder.decode(type, from: data) else { return }
        apply(payload)
        connectionMessage = "Synced from iPhone."
    }
}

private struct WatchTransportMessage {
    let schemaVersion: Int
    let kind: WatchPayloadKind
    let payloadJSON: Data

    init?(dictionary: [String: Any]) {
        guard let schemaVersion = dictionary["schemaVersion"] as? Int,
              let kindValue = dictionary["kind"] as? String,
              let kind = WatchPayloadKind(rawValue: kindValue),
              let payloadJSON = dictionary["payloadJSON"] as? Data else {
            return nil
        }
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.payloadJSON = payloadJSON
    }
}

extension WatchCompanionSessionStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                connectionMessage = error.localizedDescription
            } else if activationState == .activated {
                connectionMessage = "Connected to iPhone."
                applyTransportMessage(session.applicationContext)
            } else {
                connectionMessage = "Waiting for iPhone."
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            connectionMessage = session.isReachable ? "iPhone reachable." : "iPhone will sync when available."
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            applyTransportMessage(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            applyTransportMessage(userInfo)
        }
    }
}
