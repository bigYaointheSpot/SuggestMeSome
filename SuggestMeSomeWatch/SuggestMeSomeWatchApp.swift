//
//  SuggestMeSomeWatchApp.swift
//  SuggestMeSomeWatch
//
//  Feature 12 Prompt 1 - Real watchOS companion app entry point.
//

import SwiftUI

@main
struct SuggestMeSomeWatchApp: App {
    @StateObject private var container = WatchCompanionContainer.live()

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: container.sessionStore)
        }
    }
}
