//
//  SuggestMeSomeLiveActivityBundle.swift
//  SuggestMeSomeLiveActivity
//
//  Widget bundle entry point. iOS discovers the widget configurations
//  from this type's `body` — currently just the workout Live Activity.
//  Future bundle entries (home-screen widgets, other live activities)
//  would list alongside WorkoutLiveActivityWidget() inside `body`.
//

import SwiftUI
import WidgetKit

@main
struct SuggestMeSomeLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            WorkoutLiveActivityWidget()
        }
    }
}
