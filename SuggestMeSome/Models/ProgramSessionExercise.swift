//
//  ProgramSessionExercise.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/6/26.
//

import Foundation
import SwiftData

@Model
final class ProgramSessionExercise {
    var id: UUID
    var exerciseName: String
    /// Display ordering within the session.
    var orderIndex: Int
    /// Prescribed number of sets; nil for user-created programs that leave this blank.
    var targetSets: Int?
    /// Prescribed reps per set; nil for user-created programs that leave this blank.
    var targetReps: Int?

    var session: ProgramSessionTemplate?

    init(
        id: UUID = UUID(),
        exerciseName: String,
        orderIndex: Int,
        targetSets: Int? = nil,
        targetReps: Int? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.targetReps = targetReps
    }
}
