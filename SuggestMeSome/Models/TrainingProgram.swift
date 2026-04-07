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
    /// Generation model metadata for explainability and future adaptive progression.
    var progressionModel: ProgramProgressionModel?
    /// True when mapped variation loads (source lift × multiplier) were used.
    var usedLiftMapping: Bool?
    /// True when accessory selection used weekly volume balancing.
    var usedVolumeBalancing: Bool?
    /// True when accessory selection used fatigue-aware budgets.
    var usedFatigueBalancing: Bool?
    /// True when top set + backoff generation logic was applied to at least one lift.
    var usedTopSetBackoff: Bool?

    @Relationship(deleteRule: .cascade, inverse: \ProgramWeekTemplate.program)
    var weeks: [ProgramWeekTemplate] = []

    init(
        id: UUID = UUID(),
        name: String,
        lengthInWeeks: Int,
        sessionsPerWeek: Int,
        createdDate: Date = Date(),
        source: ProgramSource = .userCreated,
        descriptionText: String? = nil,
        progressionModel: ProgramProgressionModel? = nil,
        usedLiftMapping: Bool? = nil,
        usedVolumeBalancing: Bool? = nil,
        usedFatigueBalancing: Bool? = nil,
        usedTopSetBackoff: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.lengthInWeeks = lengthInWeeks
        self.sessionsPerWeek = sessionsPerWeek
        self.createdDate = createdDate
        self.source = source
        self.descriptionText = descriptionText
        self.progressionModel = progressionModel
        self.usedLiftMapping = usedLiftMapping
        self.usedVolumeBalancing = usedVolumeBalancing
        self.usedFatigueBalancing = usedFatigueBalancing
        self.usedTopSetBackoff = usedTopSetBackoff
    }
}
