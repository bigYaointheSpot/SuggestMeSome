//
//  WatchRootView.swift
//  SuggestMeSomeWatch
//
//  Feature 12 Prompt 5 — Execution-first watch root flow.
//
//  Three-mode switcher: live workout > session completion > Today Plan.
//  Matches the Smart Stack direction: active execution wins when
//  present, a polished completion moment follows a saved workout, and
//  Today Plan fills the surface when nothing else is active.
//

import SwiftUI

struct WatchRootView: View {
    @ObservedObject var presentationState: WatchRootPresentationState
    let liveWorkoutState: WatchLiveWorkoutState
    let passiveContextState: WatchPassiveContextState
    let connectionState: WatchConnectionState
    let onExecutionAction: (WatchWorkoutExecutionActionDTO) -> Void
    let onDismissCompletion: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch presentationState.rootMode {
                case .activeWorkout:
                    WatchActiveWorkoutRoot(
                        liveWorkoutState: liveWorkoutState,
                        connectionState: connectionState,
                        onExecutionAction: onExecutionAction
                    )
                case .sessionCompletion:
                    WatchSessionCompletionRoot(
                        passiveContextState: passiveContextState,
                        connectionState: connectionState,
                        onDismiss: onDismissCompletion
                    )
                case .todayPlan:
                    WatchTodayPlanRoot(
                        passiveContextState: passiveContextState,
                        connectionState: connectionState
                    )
                }
            }
            .navigationTitle("SuggestMeSome")
        }
        .tint(WatchPalette.primary)
    }
}

private struct WatchActiveWorkoutRoot: View {
    @ObservedObject var liveWorkoutState: WatchLiveWorkoutState
    @ObservedObject var connectionState: WatchConnectionState
    let onExecutionAction: (WatchWorkoutExecutionActionDTO) -> Void

    var body: some View {
        WatchActiveWorkoutView(
            liveWorkout: liveWorkoutState.liveWorkout,
            progressSnapshot: liveWorkoutState.progressSnapshot,
            currentContext: liveWorkoutState.currentContext,
            watchMetrics: liveWorkoutState.latestWatchMetrics,
            isLinkedHealthSessionActive: liveWorkoutState.latestWatchMetrics?.isLinkedHealthSessionActive == true,
            sessionStatus: connectionState.sessionStatus,
            onExecutionAction: onExecutionAction
        )
    }
}

private struct WatchSessionCompletionRoot: View {
    @ObservedObject var passiveContextState: WatchPassiveContextState
    @ObservedObject var connectionState: WatchConnectionState
    let onDismiss: () -> Void

    var body: some View {
        if let completion = passiveContextState.completion {
            WatchSessionCompletionView(
                completion: completion,
                sessionStatus: connectionState.sessionStatus,
                onDismiss: onDismiss
            )
        } else {
            WatchTodayPlanView(
                todayPlan: passiveContextState.todayPlan,
                liveWorkout: nil,
                completion: nil,
                sessionStatus: connectionState.sessionStatus
            )
        }
    }
}

private struct WatchTodayPlanRoot: View {
    @ObservedObject var passiveContextState: WatchPassiveContextState
    @ObservedObject var connectionState: WatchConnectionState

    var body: some View {
        WatchTodayPlanView(
            todayPlan: passiveContextState.todayPlan,
            liveWorkout: nil,
            completion: passiveContextState.completion,
            sessionStatus: connectionState.sessionStatus
        )
    }
}
