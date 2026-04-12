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
    func importLast90Days(context: ModelContext, referenceDate: Date = Date()) async throws -> HealthKitWorkoutImportResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitWorkoutImportError.healthDataUnavailable
        }
        if healthStore.authorizationStatus(for: HealthKitTypeCatalog.workoutType) == .sharingDenied {
            throw HealthKitWorkoutImportError.workoutReadDenied
        }

        let window = makeWindow(referenceDate: referenceDate)
        let samples = await fetchWorkouts(start: window.start, end: window.end)
        let importableWorkouts = samples.filter { isSupportedForImport(activityType: $0.workoutActivityType) }

        let snapshots = importableWorkouts.map { sample in
            HealthKitImportedWorkoutSnapshot(
                externalIdentifier: sample.uuid.uuidString,
                startDate: sample.startDate,
                durationSeconds: max(0, Int(sample.duration.rounded())),
                caloriesBurned: caloriesBurned(from: sample),
                sourceDisplayName: sourceDisplayLabel(for: sample),
                activityTypeIdentifier: String(sample.workoutActivityType.rawValue),
                activityTypeDisplayName: activityDisplayLabel(for: sample.workoutActivityType)
            )
        }

        let upsert = try upsertImportedWorkouts(
            context: context,
            snapshots: snapshots
        )
        return HealthKitWorkoutImportResult(
            scanned: importableWorkouts.count,
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
        let existingWorkouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        var existingByExternalIdentifier: [String: Workout] = [:]
        for workout in existingWorkouts {
            guard let id = workout.sourceExternalIdentifier, !id.isEmpty else { continue }
            existingByExternalIdentifier[id] = workout
        }

        var insertedCount = 0
        var updatedCount = 0
        for snapshot in snapshots {
            if let existing = existingByExternalIdentifier[snapshot.externalIdentifier] {
                existing.sourceType = .healthKitImported
                existing.sourceExternalIdentifier = snapshot.externalIdentifier
                existing.sourceDisplayName = snapshot.sourceDisplayName
                existing.sourceWorkoutTypeIdentifier = snapshot.activityTypeIdentifier
                existing.sourceWorkoutTypeDisplayName = snapshot.activityTypeDisplayName
                if existing.sourceImportedAt == nil {
                    existing.sourceImportedAt = importedAt
                }
                existing.markSyncUpdated(at: importedAt)
                updatedCount += 1
                continue
            }

            let workout = Workout(
                date: snapshot.startDate,
                startTime: snapshot.startDate,
                durationSeconds: snapshot.durationSeconds,
                caloriesBurned: snapshot.caloriesBurned,
                comments: nil,
                sourceType: .healthKitImported,
                sourceExternalIdentifier: snapshot.externalIdentifier,
                sourceDisplayName: snapshot.sourceDisplayName,
                sourceWorkoutTypeIdentifier: snapshot.activityTypeIdentifier,
                sourceWorkoutTypeDisplayName: snapshot.activityTypeDisplayName,
                sourceImportedAt: importedAt
            )
            context.insert(workout)
            existingByExternalIdentifier[snapshot.externalIdentifier] = workout
            insertedCount += 1
        }

        try context.save()
        return (inserted: insertedCount, updated: updatedCount)
    }

    private func makeWindow(referenceDate: Date) -> (start: Date, end: Date) {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -89, to: todayStart) ?? todayStart
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        return (start: start, end: tomorrowStart)
    }

    private func fetchWorkouts(start: Date, end: Date) async -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HealthKitTypeCatalog.workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func caloriesBurned(from workout: HKWorkout) -> Int? {
        guard let totalEnergy = workout.totalEnergyBurned else { return nil }
        return Int(totalEnergy.doubleValue(for: .kilocalorie()).rounded())
    }

    private func isSupportedForImport(activityType: HKWorkoutActivityType) -> Bool {
        activityType == .traditionalStrengthTraining || isCardioWorkoutType(activityType)
    }

    private func isCardioWorkoutType(_ activityType: HKWorkoutActivityType) -> Bool {
        switch activityType {
        case .running,
             .walking,
             .cycling,
             .swimming,
             .hiking,
             .elliptical,
             .stairClimbing,
             .rowing,
             .jumpRope,
             .mixedCardio,
             .highIntensityIntervalTraining,
             .wheelchairWalkPace,
             .wheelchairRunPace,
             .handCycling,
             .crossTraining:
            return true
        default:
            return false
        }
    }

    private func sourceDisplayLabel(for workout: HKWorkout) -> String {
        if let deviceName = workout.device?.name, !deviceName.isEmpty {
            let lowercased = deviceName.lowercased()
            if lowercased.contains("apple watch") || lowercased.contains("watch") {
                return "Apple Watch"
            }
            return deviceName
        }

        let sourceName = workout.sourceRevision.source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceName.isEmpty {
            return sourceName
        }
        return "HealthKit"
    }

    private func activityDisplayLabel(for activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .traditionalStrengthTraining: return "Traditional Strength Training"
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        case .rowing: return "Rowing"
        case .jumpRope: return "Jump Rope"
        case .mixedCardio: return "Mixed Cardio"
        case .highIntensityIntervalTraining: return "HIIT"
        case .wheelchairWalkPace: return "Wheelchair Walk Pace"
        case .wheelchairRunPace: return "Wheelchair Run Pace"
        case .handCycling: return "Hand Cycling"
        case .crossTraining: return "Cross Training"
        default: return "Workout"
        }
    }
}
