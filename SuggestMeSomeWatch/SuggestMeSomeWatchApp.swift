//
//  SuggestMeSomeWatchApp.swift
//  SuggestMeSomeWatch
//
//  Feature 12 Prompt 1 - Real watchOS companion app entry point.
//

import SwiftUI

@main
struct SuggestMeSomeWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var container = WatchCompanionContainer.live()

    var body: some Scene {
        WindowGroup {
            WatchRootView(
                presentationState: container.sessionStore.presentationState,
                liveWorkoutState: container.sessionStore.liveWorkoutState,
                passiveContextState: container.sessionStore.passiveContextState,
                connectionState: container.sessionStore.connectionState,
                onExecutionAction: container.sessionStore.sendExecutionAction,
                onDismissCompletion: container.sessionStore.dismissCompletion
            )
                .onAppear {
                    container.sessionStore.sendPresenceHeartbeat()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    container.sessionStore.sendPresenceHeartbeat()
                }
        }
    }
}
