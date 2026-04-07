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
    /// Generation metadata for future adaptive progression.
    var isDeloadWeek: Bool
    var progressionPhase: ProgramProgressionPhase?
    /// Planned weekly fatigue score computed from generated prescription.
    var plannedFatigueScore: Double?

    var program: TrainingProgram?

    @Relationship(deleteRule: .cascade, inverse: \ProgramSessionTemplate.week)
    var sessions: [ProgramSessionTemplate] = []

    init(
        id: UUID = UUID(),
        weekNumber: Int,
        isDeloadWeek: Bool = false,
        progressionPhase: ProgramProgressionPhase? = nil,
        plannedFatigueScore: Double? = nil
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.isDeloadWeek = isDeloadWeek
        self.progressionPhase = progressionPhase
        self.plannedFatigueScore = plannedFatigueScore
    }
}
