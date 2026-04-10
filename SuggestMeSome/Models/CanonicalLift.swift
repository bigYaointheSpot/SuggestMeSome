//
//  CanonicalLift.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/10/26.
//

import Foundation

/// The four canonical lift families tracked by adaptive coaching services.
/// Raw values are the stable string keys used internally across all Feature 6 services.
enum CanonicalLift: String, CaseIterable {
    case bench         = "bench"
    case squat         = "squat"
    case deadlift      = "deadlift"
    case overheadPress = "overheadPress"

    /// Human-readable name for display in UI.
    var displayName: String {
        switch self {
        case .bench:         return "Bench Press"
        case .squat:         return "Squat"
        case .deadlift:      return "Deadlift"
        case .overheadPress: return "Overhead Press"
        }
    }

    /// All exercise names that belong to this lift family, as they appear in seed data and
    /// program templates. The first entry is the primary competition/program lift.
    var variationNames: [String] {
        switch self {
        case .bench:
            return [
                "Bench Press",
                "Pause Bench Press",
                "Close Grip Bench Press",
                "Incline Bench",
                "Dumbbell Bench Press",
                "Incline Dumbbell Press",
                "Floor Press",
                "Chest Dip",
            ]
        case .squat:
            return [
                "Back Squats",
                "Front Squat",
                "Pause Squat",
                "Box Squat",
                "Hack Squat",
                "Goblet Squat",
                "Sumo Squat",
            ]
        case .deadlift:
            return [
                "Deadlift",
                "Romanian Deadlift",
                "Sumo Deadlift",
                "Deficit Deadlift",
                "Block Pull",
            ]
        case .overheadPress:
            return [
                "Overhead Press",
                "Barbell Strict Press",
                "DB Shoulder Press",
                "Arnold Press",
                "Machine Shoulder Press",
            ]
        }
    }

    /// Returns the canonical lift for the given exercise name, or nil if it doesn't belong
    /// to any tracked family. Matching is case-insensitive.
    static func from(exerciseName: String) -> CanonicalLift? {
        let lower = exerciseName.lowercased()
        return allCases.first { lift in
            lift.variationNames.contains { $0.lowercased() == lower }
        }
    }
}
