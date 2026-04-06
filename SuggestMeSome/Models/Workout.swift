//
//  Workout.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import Foundation
import SwiftData

@Model
final class Workout {
    var id: UUID
    var date: Date
    var startTime: Date
    /// Total elapsed time stored in seconds; use `formattedDuration` for display.
    var durationSeconds: Int
    var caloriesBurned: Int?
    var comments: String?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseEntry.workout)
    var exerciseEntries: [ExerciseEntry] = []

    /// The program run this workout belongs to; nil for standalone workouts.
    var programRun: ProgramRun?
    /// The week number within the program run; nil for standalone workouts.
    var programWeekNumber: Int?
    /// The session number within the program week; nil for standalone workouts.
    var programSessionNumber: Int?

    init(
        id: UUID = UUID(),
        date: Date,
        startTime: Date,
        durationSeconds: Int,
        caloriesBurned: Int? = nil,
        comments: String? = nil,
        programRun: ProgramRun? = nil,
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.durationSeconds = durationSeconds
        self.caloriesBurned = caloriesBurned
        self.comments = comments
        self.programRun = programRun
        self.programWeekNumber = programWeekNumber
        self.programSessionNumber = programSessionNumber
    }

    /// Returns duration formatted as hh:mm:ss.
    var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        let s = durationSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
