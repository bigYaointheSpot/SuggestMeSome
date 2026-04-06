//
//  MuscleGroup.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import Foundation
import SwiftData

@Model
final class MuscleGroup {
    var name: String

    @Relationship(deleteRule: .cascade, inverse: \Exercise.muscleGroup)
    var exercises: [Exercise] = []

    init(name: String) {
        self.name = name
    }
}
