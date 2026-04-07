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
    /// Optional descriptive name shown after the session number, e.g. "Heavy Squat Day".
    var sessionName: String?
    /// Planned fatigue score computed from generated prescription.
    var plannedFatigueScore: Double?

    var week: ProgramWeekTemplate?

    @Relationship(deleteRule: .cascade, inverse: \ProgramSessionExercise.session)
    var exercises: [ProgramSessionExercise] = []

    init(
        id: UUID = UUID(),
        sessionNumber: Int,
        sessionName: String? = nil,
        plannedFatigueScore: Double? = nil
    ) {
        self.id = id
        self.sessionNumber = sessionNumber
        self.sessionName = sessionName
        self.plannedFatigueScore = plannedFatigueScore
    }
}
