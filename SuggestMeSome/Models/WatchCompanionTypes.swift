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
    let sessionSourceLabels: [String]?
    let sessionVersionStableID: String?

    init(
        workoutID: UUID,
        startedAt: Date,
        programRunID: UUID? = nil,
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil,
        sessionPlanKind: WatchSessionPlanKind? = nil,
        sessionSourceLabels: [String]? = nil,
        sessionVersionStableID: String? = nil
    ) {
        self.workoutID = workoutID
        self.startedAt = startedAt
        self.programRunID = programRunID
        self.programWeekNumber = programWeekNumber
        self.programSessionNumber = programSessionNumber
        self.sessionPlanKind = sessionPlanKind
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

enum WatchCompanionAvailability: String, Codable {
    case unsupported
    case notPaired
    case pairedNoCompanionApp
    case companionInstalled
    case reachable
}

struct WatchCompanionStatus: Codable, Equatable {
    let availability: WatchCompanionAvailability
    let isPaired: Bool
    let isCompanionAppInstalled: Bool
    let isReachable: Bool
    let message: String
    let checkedAt: Date

    static func unsupported(checkedAt: Date = Date()) -> WatchCompanionStatus {
        WatchCompanionStatus(
            availability: .unsupported,
            isPaired: false,
            isCompanionAppInstalled: false,
            isReachable: false,
            message: "Apple Watch status is unavailable on this device.",
            checkedAt: checkedAt
        )
    }
}
