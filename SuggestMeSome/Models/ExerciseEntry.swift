//
//  ExerciseEntry.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import Foundation
import SwiftData

@Model
final class ExerciseEntry {
    var id: UUID
    /// Snapshot of the exercise name at the time of logging.
    var exerciseName: String
    var unit: WeightUnit
    var orderIndex: Int
    var workout: Workout?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.exerciseEntry)
    var sets: [SetEntry] = []

    init(
        id: UUID = UUID(),
        exerciseName: String,
        unit: WeightUnit,
        orderIndex: Int
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.unit = unit
        self.orderIndex = orderIndex
    }
}
