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
    var muscleGroup: MuscleGroup?

    init(name: String, muscleGroup: MuscleGroup? = nil) {
        self.name = name
        self.muscleGroup = muscleGroup
    }
}
