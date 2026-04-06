//
//  SetEntry.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import Foundation
import SwiftData

@Model
final class SetEntry {
    var id: UUID
    var setNumber: Int
    var reps: Int
    var weight: Double
    var isPR: Bool
    var exerciseEntry: ExerciseEntry?

    init(
        id: UUID = UUID(),
        setNumber: Int,
        reps: Int,
        weight: Double,
        isPR: Bool = false
    ) {
        self.id = id
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.isPR = isPR
    }
}
