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

        let existingWorkouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        var existingByExternalIdentifier: [String: Workout] = [:]
        for workout in existingWorkouts {
            guard let id = workout.sourceExternalIdentifier, !id.isEmpty else { continue }
            existingByExternalIdentifier[id] = workout
        }

        let now = Date()
        var insertedCount = 0
        var updatedCount = 0
        for sample in importableWorkouts {
            let externalID = sample.uuid.uuidString
            let sourceLabel = sourceDisplayLabel(for: sample)
            let activityLabel = activityDisplayLabel(for: sample.workoutActivityType)

            if let existing = existingByExternalIdentifier[externalID] {
                existing.sourceType = .healthKitImported
                existing.sourceExternalIdentifier = externalID
                existing.sourceDisplayName = sourceLabel
                existing.sourceWorkoutTypeIdentifier = String(sample.workoutActivityType.rawValue)
                existing.sourceWorkoutTypeDisplayName = activityLabel
                if existing.sourceImportedAt == nil {
                    existing.sourceImportedAt = now
                }
                updatedCount += 1
                continue
            }

            let workout = Workout(
                date: sample.startDate,
                startTime: sample.startDate,
                durationSeconds: max(0, Int(sample.duration.rounded())),
                caloriesBurned: caloriesBurned(from: sample),
                comments: nil,
                sourceType: .healthKitImported,
                sourceExternalIdentifier: externalID,
                sourceDisplayName: sourceLabel,
                sourceWorkoutTypeIdentifier: String(sample.workoutActivityType.rawValue),
                sourceWorkoutTypeDisplayName: activityLabel,
                sourceImportedAt: now
            )
            context.insert(workout)
            existingByExternalIdentifier[externalID] = workout
            insertedCount += 1
        }

        try context.save()
        return HealthKitWorkoutImportResult(
            scanned: importableWorkouts.count,
            inserted: insertedCount,
            updated: updatedCount
        )
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
