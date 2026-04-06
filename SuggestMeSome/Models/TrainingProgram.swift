//
//  TrainingProgram.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/6/26.
//

import Foundation
import SwiftData

enum ProgramSource: String, Codable {
    case userCreated
    case template
    case aiGenerated
}

@Model
final class TrainingProgram {
    var id: UUID
    var name: String
    /// Valid values: 6, 8, 10, 12
    var lengthInWeeks: Int
    /// Valid values: 2–6
    var sessionsPerWeek: Int
    var createdDate: Date
    var source: ProgramSource
    var descriptionText: String?

    @Relationship(deleteRule: .cascade, inverse: \ProgramWeekTemplate.program)
    var weeks: [ProgramWeekTemplate] = []

    init(
        id: UUID = UUID(),
        name: String,
        lengthInWeeks: Int,
        sessionsPerWeek: Int,
        createdDate: Date = Date(),
        source: ProgramSource = .userCreated,
        descriptionText: String? = nil
    ) {
        self.id = id
        self.name = name
        self.lengthInWeeks = lengthInWeeks
        self.sessionsPerWeek = sessionsPerWeek
        self.createdDate = createdDate
        self.source = source
        self.descriptionText = descriptionText
    }
}
