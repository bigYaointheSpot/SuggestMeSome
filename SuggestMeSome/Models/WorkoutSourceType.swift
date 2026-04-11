//
//  WorkoutSourceType.swift
//  SuggestMeSome
//
//  Feature 8 — Workout source classification.
//

import Foundation

enum WorkoutSourceType: String, Codable, CaseIterable {
    case loggedInApp
    case healthKitImported
}
