//
//  WatchCompanionSessionState.swift
//  SuggestMeSomeWatch
//
//  Narrow watch-facing observable state buckets used by the companion app.
//

import Combine
import Foundation

enum WatchCompanionRootMode: Equatable {
    case activeWorkout
    case sessionCompletion
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
final class WatchLiveWorkoutState: ObservableObject {
    @Published private(set) var workoutLaunch: WatchWorkoutLaunchPayload?
    @Published private(set) var progressSnapshot: WatchWorkoutProgressSnapshot?
    @Published private(set) var liveWorkout: WatchLiveWorkoutSnapshot?
    @Published private(set) var currentContext: WatchCurrentSessionContext?
    @Published private(set) var latestWatchMetrics: WatchWorkoutMetricsPayload?

    var hasActiveWorkout: Bool {
        workoutLaunch != nil || liveWorkout != nil || currentContext != nil || progressSnapshot != nil
    }

    var activeWorkoutID: UUID? {
        workoutLaunch?.workoutID ?? liveWorkout?.workoutID ?? currentContext?.workoutID ?? progressSnapshot?.workoutID
    }

    var activeSessionVersionStableID: String? {
        workoutLaunch?.sessionVersionStableID ?? liveWorkout?.sessionVersionStableID ?? currentContext?.sessionVersionStableID
    }

    func setWorkoutLaunch(_ value: WatchWorkoutLaunchPayload?) {
        assignIfChanged(\.workoutLaunch, value)
    }

    func setProgressSnapshot(_ value: WatchWorkoutProgressSnapshot?) {
        assignIfChanged(\.progressSnapshot, value)
    }

    func setLiveWorkout(_ value: WatchLiveWorkoutSnapshot?) {
        assignIfChanged(\.liveWorkout, value)
    }

    func setCurrentContext(_ value: WatchCurrentSessionContext?) {
        assignIfChanged(\.currentContext, value)
    }

    func setLatestWatchMetrics(_ value: WatchWorkoutMetricsPayload?) {
        assignIfChanged(\.latestWatchMetrics, value)
    }

    func resetActivePayloads() {
        setProgressSnapshot(nil)
        setLiveWorkout(nil)
        setCurrentContext(nil)
        setLatestWatchMetrics(nil)
    }

    func clearForCompletion() {
        setWorkoutLaunch(nil)
        setProgressSnapshot(nil)
        setLiveWorkout(nil)
        setCurrentContext(nil)
        setLatestWatchMetrics(nil)
    }

    private func assignIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<WatchLiveWorkoutState, Value>,
        _ value: Value
    ) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }
}

@MainActor
final class WatchPassiveContextState: ObservableObject {
    @Published private(set) var todayPlan: WatchTodayPlanSnapshot?
    @Published private(set) var completion: WatchSessionCompletionPayload?

    func setTodayPlan(_ value: WatchTodayPlanSnapshot?) {
        assignIfChanged(\.todayPlan, value)
    }

    func setCompletion(_ value: WatchSessionCompletionPayload?) {
        assignIfChanged(\.completion, value)
    }

    private func assignIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<WatchPassiveContextState, Value>,
        _ value: Value
    ) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }
}

@MainActor
final class WatchConnectionState: ObservableObject {
    @Published private(set) var sessionStatus = WatchCompanionSessionStatus.unsupported()

    func setSessionStatus(_ value: WatchCompanionSessionStatus) {
        guard sessionStatus != value else { return }
        sessionStatus = value
    }
}

@MainActor
final class WatchWidgetState: ObservableObject {
    @Published private(set) var snapshot: WatchWidgetSnapshot

    init(snapshot: WatchWidgetSnapshot) {
        self.snapshot = snapshot
    }

    func setSnapshot(_ value: WatchWidgetSnapshot) {
        guard snapshot != value else { return }
        snapshot = value
    }
}

@MainActor
final class WatchRootPresentationState: ObservableObject {
    @Published private(set) var rootMode: WatchCompanionRootMode = .todayPlan

    func refresh(
        liveWorkoutState: WatchLiveWorkoutState,
        passiveContextState: WatchPassiveContextState
    ) {
        let nextMode: WatchCompanionRootMode
        if liveWorkoutState.hasActiveWorkout {
            nextMode = .activeWorkout
        } else if passiveContextState.completion != nil {
            nextMode = .sessionCompletion
        } else {
            nextMode = .todayPlan
        }

        guard rootMode != nextMode else { return }
        rootMode = nextMode
    }
}
