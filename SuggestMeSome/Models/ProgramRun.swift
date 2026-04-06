//
//  ProgramRun.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/6/26.
//

import Foundation
import SwiftData

@Model
final class ProgramRun {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var isCompleted: Bool

    var program: TrainingProgram?

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.isCompleted = isCompleted
    }
}
