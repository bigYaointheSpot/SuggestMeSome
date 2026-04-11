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

    // MARK: Feature 8 — Workout source metadata
    /// Where this workout originated (logged directly vs imported).
    var sourceType: WorkoutSourceType
    /// External source identifier (for example, HealthKit UUID string).
    var sourceExternalIdentifier: String?
    /// Human-readable source app/device label shown in future UI.
    var sourceDisplayName: String?
    /// Imported workout activity type identifier (for example HKWorkoutActivityType raw value).
    var sourceWorkoutTypeIdentifier: String?
    /// Human-readable imported workout activity label.
    var sourceWorkoutTypeDisplayName: String?
    /// Timestamp when this workout was imported from an external source.
    var sourceImportedAt: Date?
    /// Timestamp when this workout was exported/written to HealthKit.
    var healthKitExportedAt: Date?
    /// Future writeback tracking identifier returned by HealthKit.
    var healthKitWritebackIdentifier: String?

    init(
        id: UUID = UUID(),
        date: Date,
        startTime: Date,
        durationSeconds: Int,
        caloriesBurned: Int? = nil,
        comments: String? = nil,
        programRun: ProgramRun? = nil,
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil,
        sourceType: WorkoutSourceType = .loggedInApp,
        sourceExternalIdentifier: String? = nil,
        sourceDisplayName: String? = nil,
        sourceWorkoutTypeIdentifier: String? = nil,
        sourceWorkoutTypeDisplayName: String? = nil,
        sourceImportedAt: Date? = nil,
        healthKitExportedAt: Date? = nil,
        healthKitWritebackIdentifier: String? = nil
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
        self.sourceType = sourceType
        self.sourceExternalIdentifier = sourceExternalIdentifier
        self.sourceDisplayName = sourceDisplayName
        self.sourceWorkoutTypeIdentifier = sourceWorkoutTypeIdentifier
        self.sourceWorkoutTypeDisplayName = sourceWorkoutTypeDisplayName
        self.sourceImportedAt = sourceImportedAt
        self.healthKitExportedAt = healthKitExportedAt
        self.healthKitWritebackIdentifier = healthKitWritebackIdentifier
    }

    /// Returns duration formatted as hh:mm:ss.
    var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        let s = durationSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    var isHealthKitImported: Bool {
        sourceType == .healthKitImported
    }

    var sourceBadgeLabel: String? {
        guard isHealthKitImported else { return nil }
        let trimmed = sourceDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return "HealthKit" }
        return trimmed
    }

    var importedWorkoutTypeLabel: String? {
        guard isHealthKitImported else { return nil }
        let trimmed = sourceWorkoutTypeDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }

    var sourceLabel: String {
        switch sourceType {
        case .loggedInApp:
            return "Logged in SuggestMeSome"
        case .healthKitImported:
            return "Imported from HealthKit"
        }
    }

    var hasHealthKitWriteback: Bool {
        healthKitExportedAt != nil || healthKitWritebackIdentifier?.isEmpty == false
    }
}
