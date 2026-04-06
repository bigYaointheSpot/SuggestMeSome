//
//  ProgramSessionTemplate.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/6/26.
//

import Foundation
import SwiftData

@Model
final class ProgramSessionTemplate {
    var id: UUID
    /// 1-based session number within the week (range 1–6).
    var sessionNumber: Int

    var week: ProgramWeekTemplate?

    @Relationship(deleteRule: .cascade, inverse: \ProgramSessionExercise.session)
    var exercises: [ProgramSessionExercise] = []

    init(
        id: UUID = UUID(),
        sessionNumber: Int
    ) {
        self.id = id
        self.sessionNumber = sessionNumber
    }
}
