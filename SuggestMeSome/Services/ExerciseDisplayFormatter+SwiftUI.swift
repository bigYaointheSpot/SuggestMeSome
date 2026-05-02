//
//  ExerciseDisplayFormatter+SwiftUI.swift
//  SuggestMeSome
//
//  SwiftUI-tinted extension of the otherwise Foundation-only formatter.
//  Lives in a sibling file so the parent formatter stays importable by
//  unit tests and future headless callers (coach-facing previews,
//  watchOS, server-shared formatters) without dragging in SwiftUI.
//

import SwiftUI

extension ExerciseDisplayFormatter {
    /// Accent color that pairs with `workingSetStyleLabel(for:)` on the
    /// chip capsule. Indigo for heavy top sets, blue for backoffs,
    /// secondary for neutral straight sets, green for cardio. Keeping
    /// the label/color mapping alongside each other here prevents them
    /// from drifting when new styles are added.
    static func workingSetStyleColor(for exercise: ProgramSessionExercise) -> Color {
        if exercise.targetSets == nil { return .green }
        switch exercise.workingSetStyle {
        case .topSet: return DSColor.primaryAction
        case .backoff: return .blue
        case .straight, .none: return .secondary
        }
    }
}
