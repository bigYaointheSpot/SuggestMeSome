//
//  ProgramWeekTemplate.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/6/26.
//

import Foundation
import SwiftData

@Model
final class ProgramWeekTemplate {
    var id: UUID
    /// 1-based week number within the program.
    var weekNumber: Int

    var program: TrainingProgram?

    @Relationship(deleteRule: .cascade, inverse: \ProgramSessionTemplate.week)
    var sessions: [ProgramSessionTemplate] = []

    init(
        id: UUID = UUID(),
        weekNumber: Int
    ) {
        self.id = id
        self.weekNumber = weekNumber
    }
}
