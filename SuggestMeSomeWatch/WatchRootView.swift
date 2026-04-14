//
//  WatchRootView.swift
//  SuggestMeSomeWatch
//
//  Feature 12 Prompt 3 — Execution-first watch root flow.
//
//  Thin switcher between the premium live workout surface and the polished
//  Today Plan surface. Navigation stays minimal and watch-native — no tab
//  bar bloat, no proposal review, no history. iPhone remains the source of
//  truth; the watch only renders what the bridge delivers.
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
                        sessionStatus: store.sessionStatus
                    )
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
