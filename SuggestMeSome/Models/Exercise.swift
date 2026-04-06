//
//  Exercise.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import Foundation
import SwiftData

@Model
final class Exercise {
    var name: String
    var exerciseType: ExerciseType = ExerciseType.isolation
    var muscleGroup: MuscleGroup?

    var baseTimeMinutes: Int {
        switch exerciseType {
        case .compound:  return 30
        case .accessory: return 15
        case .isolation: return 10
        case .cardio:    return 0
        }
    }

    init(name: String, exerciseType: ExerciseType = .isolation, muscleGroup: MuscleGroup? = nil) {
        self.name = name
        self.exerciseType = exerciseType
        self.muscleGroup = muscleGroup
    }
}
