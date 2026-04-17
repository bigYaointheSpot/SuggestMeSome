//
//  HealthKitWorkoutImportService.swift
//  SuggestMeSome
//
//  Feature 8 Prompt 5 — Import HealthKit workouts into local workout history.
//

import Foundation
import SwiftData
import HealthKit

enum HealthKitWorkoutImportError: Error {
    case healthDataUnavailable
    case workoutReadDenied
}

struct HealthKitWorkoutImportResult {
    let scanned: Int
    let inserted: Int
    let updated: Int

    var summaryText: String {
        "Scanned \(scanned), imported \(inserted), updated \(updated)."
    }
}

struct HealthKitImportedWorkoutSnapshot {
    let externalIdentifier: String
    let startDate: Date
    let durationSeconds: Int
    let caloriesBurned: Int?
    let sourceDisplayName: String
    let activityTypeIdentifier: String
    let activityTypeDisplayName: String
}

final class HealthKitWorkoutImportService {
    private let healthStore: HKHealthStore
    private let calendar: Calendar

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        calendar: Calendar = .current
    ) {
        self.healthStore = healthStore
        self.calendar = calendar
    }

    @MainActor
    func importLast90Days(
        context: ModelContext,
        referenceDate: Date = Date()
    ) async throws -> HealthKitWorkoutImportResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitWorkoutImportError.healthDataUnavailable
        }
        if healthStore.authorizationStatus(for: HealthKitTypeCatalog.workoutType) == .sharingDenied {
            throw HealthKitWorkoutImportError.workoutReadDenied
        }

        let window = HealthKitWorkoutImportWindow.makeLast90Days(
            referenceDate: referenceDate,
            calendar: calendar
        )
        let samples = await HealthKitWorkoutImportQueryClient.fetchWorkouts(
            healthStore: healthStore,
            start: window.start,
            end: window.end
        )
        let snapshots = HealthKitWorkoutImportMapper.importSnapshots(from: samples)
        let upsert = try upsertImportedWorkouts(
            context: context,
            snapshots: snapshots
        )

        return HealthKitWorkoutImportResult(
            scanned: snapshots.count,
            inserted: upsert.inserted,
            updated: upsert.updated
        )
    }

    @MainActor
    @discardableResult
    func upsertImportedWorkouts(
        context: ModelContext,
        snapshots: [HealthKitImportedWorkoutSnapshot],
        importedAt: Date = Date()
    ) throws -> (inserted: Int, updated: Int) {
        try HealthKitWorkoutImportPersistence.upsertImportedWorkouts(
            context: context,
            snapshots: snapshots,
            importedAt: importedAt
        )
    }
}
