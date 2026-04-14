//
//  WatchCompanionContainer.swift
//  SuggestMeSomeWatch
//
//  Lightweight injection point for watch-side session state.
//

import Combine
import Foundation

@MainActor
final class WatchCompanionContainer: ObservableObject {
    let sessionStore: WatchCompanionSessionStore

    init(sessionStore: WatchCompanionSessionStore) {
        self.sessionStore = sessionStore
    }

    static func live() -> WatchCompanionContainer {
        WatchCompanionContainer(sessionStore: WatchCompanionSessionStore())
    }
}
