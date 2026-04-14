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
    @ObservedObject var store: WatchCompanionSessionStore

    var body: some View {
        NavigationStack {
            Group {
                switch store.rootMode {
                case .activeWorkout:
                    WatchActiveWorkoutView(
                        liveWorkout: store.liveWorkout,
                        progressSnapshot: store.progressSnapshot,
                        currentContext: store.currentContext,
                        sessionStatus: store.sessionStatus,
                        onExecutionAction: store.sendExecutionAction
                    )
                case .sessionCompletion:
                    if let completion = store.completion {
                        WatchSessionCompletionView(
                            completion: completion,
                            sessionStatus: store.sessionStatus,
                            onDismiss: store.dismissCompletion
                        )
                    } else {
                        WatchTodayPlanView(
                            todayPlan: store.todayPlan,
                            liveWorkout: store.liveWorkout,
                            completion: nil,
                            sessionStatus: store.sessionStatus
                        )
                    }
                case .todayPlan:
                    WatchTodayPlanView(
                        todayPlan: store.todayPlan,
                        liveWorkout: store.liveWorkout,
                        completion: store.completion,
                        sessionStatus: store.sessionStatus
                    )
                }
            }
            .navigationTitle("SuggestMeSome")
        }
        .tint(WatchPalette.primary)
    }
}
