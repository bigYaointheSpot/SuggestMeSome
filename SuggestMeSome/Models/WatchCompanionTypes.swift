//
//  WatchCompanionTypes.swift
//  SuggestMeSome
//
//  Feature 8 Prompt 7 — Non-persisted shared watch payload and status types.
//

import Foundation

struct WatchWorkoutLaunchPayload: Codable, Equatable {
    let workoutID: UUID
    let startedAt: Date
    let programRunID: UUID?
    let programWeekNumber: Int?
    let programSessionNumber: Int?
    let sessionPlanKind: WatchSessionPlanKind?
    let lifecycleState: WatchWorkoutLifecycleState?
    let usesLinkedWatchHealthSession: Bool?
    let sessionSourceLabels: [String]?
    let sessionVersionStableID: String?

    init(
        workoutID: UUID,
        startedAt: Date,
        programRunID: UUID? = nil,
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        lifecycleState: WatchWorkoutLifecycleState? = nil,
        usesLinkedWatchHealthSession: Bool? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil
    ) {
        self.workoutID = workoutID
        self.startedAt = startedAt
        self.programRunID = programRunID
        self.programWeekNumber = programWeekNumber
        self.programSessionNumber = programSessionNumber
        self.sessionPlanKind = sessionPlanKind
        self.lifecycleState = lifecycleState
        self.usesLinkedWatchHealthSession = usesLinkedWatchHealthSession
        self.sessionSourceLabels = sessionSourceLabels
        self.sessionVersionStableID = sessionVersionStableID
    }
}

struct WatchWorkoutProgressSnapshot: Codable, Equatable {
    let workoutID: UUID
    let elapsedSeconds: Int
    let completedExercises: Int
    let totalExercises: Int
    let capturedAt: Date
}

enum WatchCompanionActivationState: String, Codable, Equatable {
    case notActivated
    case inactive
    case activated
    case unknown
}

enum WatchCompanionAvailability: String, Codable {
    case unsupported
    case statusPending
    case notPaired
    case pairedNoCompanionApp
    case companionInstalled
    case reachable
}

struct WatchCompanionStatus: Codable, Equatable {
    let availability: WatchCompanionAvailability
    let activationState: WatchCompanionActivationState
    let isPaired: Bool
    let isCompanionAppInstalled: Bool
    let isReachable: Bool
    let message: String
    let checkedAt: Date
    let lastWatchContactAt: Date?
    let lastPayloadReplayAt: Date?

    static func unsupported(checkedAt: Date = Date()) -> WatchCompanionStatus {
        WatchCompanionStatus(
            availability: .unsupported,
            activationState: .unknown,
            isPaired: false,
            isCompanionAppInstalled: false,
            isReachable: false,
            message: "Apple Watch status is unavailable on this device.",
            checkedAt: checkedAt,
            lastWatchContactAt: nil,
            lastPayloadReplayAt: nil
        )
    }
}

struct WatchCompanionSessionSnapshot: Equatable {
    let isSupported: Bool
    let activationState: WatchCompanionActivationState
    let isPaired: Bool
    let isWatchAppInstalled: Bool
    let isReachable: Bool

    static let unsupported = WatchCompanionSessionSnapshot(
        isSupported: false,
        activationState: .unknown,
        isPaired: false,
        isWatchAppInstalled: false,
        isReachable: false
    )
}

struct WatchCompanionEvidence: Equatable {
    var lastConfirmedInstallAt: Date?
    var lastWatchContactAt: Date?
    var lastPayloadReplayAt: Date?

    var hasConfirmedCompanion: Bool {
        lastConfirmedInstallAt != nil || lastWatchContactAt != nil
    }

    mutating func recordInstalledCompanion(at date: Date) {
        lastConfirmedInstallAt = max(lastConfirmedInstallAt ?? .distantPast, date)
    }

    mutating func recordWatchContact(at date: Date) {
        let resolvedDate = max(lastWatchContactAt ?? .distantPast, date)
        lastWatchContactAt = resolvedDate
        recordInstalledCompanion(at: resolvedDate)
    }

    mutating func recordPayloadReplay(at date: Date) {
        lastPayloadReplayAt = max(lastPayloadReplayAt ?? .distantPast, date)
    }
}

enum WatchCompanionStatusResolver {
    static let heartbeatConfirmationWindow: TimeInterval = 24 * 60 * 60

    static func makeStatus(
        from snapshot: WatchCompanionSessionSnapshot,
        evidence: WatchCompanionEvidence,
        checkedAt: Date
    ) -> WatchCompanionStatus {
        guard snapshot.isSupported else {
            return .unsupported(checkedAt: checkedAt)
        }

        let companionConfirmed = confirmedCompanionInstalled(
            snapshot: snapshot,
            evidence: evidence,
            referenceDate: checkedAt
        )

        let availability: WatchCompanionAvailability
        let message: String

        switch snapshot.activationState {
        case .notActivated, .inactive, .unknown:
            availability = .statusPending
            message = companionConfirmed
                ? "Reconnecting to the previously confirmed watch companion."
                : "Watch connectivity is still activating."

        case .activated:
            if !snapshot.isPaired {
                availability = .notPaired
                message = "No paired Apple Watch detected."
            } else if companionConfirmed == false {
                availability = .pairedNoCompanionApp
                message = "Watch is paired, but the companion app has not been confirmed yet."
            } else if snapshot.isReachable {
                availability = .reachable
                message = "Watch companion is connected and reachable."
            } else {
                availability = .companionInstalled
                message = "Watch is paired and the companion app is installed."
            }
        }

        return WatchCompanionStatus(
            availability: availability,
            activationState: snapshot.activationState,
            isPaired: snapshot.isPaired,
            isCompanionAppInstalled: snapshot.isWatchAppInstalled,
            isReachable: snapshot.isReachable,
            message: message,
            checkedAt: checkedAt,
            lastWatchContactAt: evidence.lastWatchContactAt,
            lastPayloadReplayAt: evidence.lastPayloadReplayAt
        )
    }

    static func canSendPayloads(
        with snapshot: WatchCompanionSessionSnapshot,
        evidence: WatchCompanionEvidence,
        now: Date
    ) -> Bool {
        guard snapshot.isSupported, snapshot.activationState == .activated else {
            return false
        }

        return confirmedCompanionInstalled(
            snapshot: snapshot,
            evidence: evidence,
            referenceDate: now
        )
    }

    static func confirmedCompanionInstalled(
        snapshot: WatchCompanionSessionSnapshot,
        evidence: WatchCompanionEvidence,
        referenceDate: Date
    ) -> Bool {
        if snapshot.activationState == .activated, snapshot.isWatchAppInstalled {
            return true
        }

        guard let lastWatchContactAt = evidence.lastWatchContactAt else {
            return evidence.hasConfirmedCompanion && snapshot.activationState != .activated
        }

        return referenceDate.timeIntervalSince(lastWatchContactAt) <= heartbeatConfirmationWindow
    }
}
