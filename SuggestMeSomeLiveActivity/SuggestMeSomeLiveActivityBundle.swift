//
//  SuggestMeSomeLiveActivityBundle.swift
//  SuggestMeSomeLiveActivity
//
//  Created by Alex Yao on 4/20/26.
//

import WidgetKit
import SwiftUI

@main
struct SuggestMeSomeLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            WorkoutLiveActivityWidget()
        }
    }
}
