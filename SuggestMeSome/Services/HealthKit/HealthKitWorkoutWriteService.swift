//
//  HealthKitWorkoutWriteService.swift
//  SuggestMeSome
//
//  Feature 8 Prompt 6 — Limited workout summary writeback to HealthKit.
//

import Foundation
import HealthKit

enum HealthKitWorkoutWriteError: Error {
    case healthDataUnavailable
    case workoutWriteNotAuthorized
    case invalidWorkoutTiming
}

struct HealthKitWorkoutWriteResult {
    let writebackIdentifier: String
    let exportedAt: Date
}

@MainActor
protocol HealthKitWorkoutWriting {
    func shouldAttemptWriteback(
        for workout: Workout,
        healthKitEnabled: Bool,
        writebackEnabled: Bool
    ) -> Bool
    func writeWorkoutSummary(_ workout: Workout) async throws -> HealthKitWorkoutWriteResult
}

final class HealthKitWorkoutWriteService {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func shouldAttemptWriteback(
        for workout: Workout,
        healthKitEnabled: Bool,
        writebackEnabled: Bool
    ) -> Bool {
        guard healthKitEnabled, writebackEnabled else { return false }
        guard workout.sourceType == .loggedInApp else { return false }
        guard workout.healthKitExportedAt == nil else { return false }
        guard workout.healthKitWritebackIdentifier?.isEmpty != false else { return false }
        return true
    }

    func writeWorkoutSummary(_ workout: Workout) async throws -> HealthKitWorkoutWriteResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitWorkoutWriteError.healthDataUnavailable
        }
        guard healthStore.authorizationStatus(for: HealthKitTypeCatalog.workoutType) == .sharingAuthorized else {
            throw HealthKitWorkoutWriteError.workoutWriteNotAuthorized
        }

        let duration = max(1, workout.durationSeconds)
        let startDate = workout.startTime
        let endDate = startDate.addingTimeInterval(TimeInterval(duration))
        guard endDate > startDate else {
            throw HealthKitWorkoutWriteError.invalidWorkoutTiming
        }

        let workoutSample = HKWorkout(
            activityType: activityType(for: workout),
            start: startDate,
            end: endDate,
            duration: TimeInterval(duration),
            totalEnergyBurned: activeEnergyQuantity(for: workout),
            totalDistance: nil,
            metadata: nil
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(workoutSample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if !success {
                    continuation.resume(throwing: HealthKitWorkoutWriteError.invalidWorkoutTiming)
                    return
                }
                continuation.resume(returning: ())
            }
        }

        return HealthKitWorkoutWriteResult(
            writebackIdentifier: workoutSample.uuid.uuidString,
            exportedAt: Date()
        )
    }

    private func activeEnergyQuantity(for workout: Workout) -> HKQuantity? {
        guard let calories = workout.caloriesBurned, calories > 0 else { return nil }
        return HKQuantity(unit: .kilocalorie(), doubleValue: Double(calories))
    }

    private func activityType(for workout: Workout) -> HKWorkoutActivityType {
        if isClearlyCardioOnly(workout) {
            return mappedCardioType(from: workout.exerciseEntries)
        }
        return .traditionalStrengthTraining
    }

    private func isClearlyCardioOnly(_ workout: Workout) -> Bool {
        let entries = workout.exerciseEntries
        guard !entries.isEmpty else { return false }
        return entries.allSatisfy(\.isCardio)
    }

    private func mappedCardioType(from entries: [ExerciseEntry]) -> HKWorkoutActivityType {
        let names = entries.map { $0.exerciseName.lowercased() }
        if names.contains(where: { $0.contains("run") || $0.contains("jog") || $0.contains("treadmill") }) {
            return .running
        }
        if names.contains(where: { $0.contains("walk") }) {
            return .walking
        }
        if names.contains(where: { $0.contains("bike") || $0.contains("cycle") || $0.contains("spin") }) {
            return .cycling
        }
        if names.contains(where: { $0.contains("row") }) {
            return .rowing
        }
        if names.contains(where: { $0.contains("swim") }) {
            return .swimming
        }
        if names.contains(where: { $0.contains("elliptical") }) {
            return .elliptical
        }
        if names.contains(where: { $0.contains("stair") }) {
            return .stairClimbing
        }
        if names.contains(where: { $0.contains("jump rope") || $0.contains("rope") }) {
            return .jumpRope
        }
        if names.contains(where: { $0.contains("hiit") }) {
            return .highIntensityIntervalTraining
        }
        return .mixedCardio
    }
}

extension HealthKitWorkoutWriteService: HealthKitWorkoutWriting {}

@MainActor
struct WorkoutSaveHealthKitWritebackCoordinator {
    let writer: HealthKitWorkoutWriting

    init(writer: HealthKitWorkoutWriting? = nil) {
        self.writer = writer ?? HealthKitWorkoutWriteService()
    }

    func scheduleNonFatalWritebackIfEligible(
        for workout: Workout,
        healthKitEnabled: Bool,
        writebackEnabled: Bool,
        persistChanges: @escaping @MainActor () throws -> Void,
        onFailure: @escaping @MainActor (WorkoutSaveSideEffectReport) -> Void
    ) -> WorkoutSaveSideEffectReport {
        guard writer.shouldAttemptWriteback(
            for: workout,
            healthKitEnabled: healthKitEnabled,
            writebackEnabled: writebackEnabled
        ) else {
            return .skipped(.healthKitWriteback, "HealthKit writeback is not eligible for this workout.")
        }

        Task { @MainActor in
            do {
                let result = try await writer.writeWorkoutSummary(workout)
                workout.healthKitWritebackIdentifier = result.writebackIdentifier
                workout.healthKitExportedAt = result.exportedAt
                try persistChanges()
            } catch {
                onFailure(
                    .failed(
                        .healthKitWriteback,
                        error.localizedDescription
                    )
                )
            }
        }

        return .scheduled(.healthKitWriteback, "Queued HealthKit writeback.")
    }

    func performNonFatalWritebackIfEligible(
        for workout: Workout,
        healthKitEnabled: Bool,
        writebackEnabled: Bool,
        persistChanges: @MainActor () throws -> Void
    ) async {
        guard writer.shouldAttemptWriteback(
            for: workout,
            healthKitEnabled: healthKitEnabled,
            writebackEnabled: writebackEnabled
        ) else {
            return
        }

        do {
            let result = try await writer.writeWorkoutSummary(workout)
            workout.healthKitWritebackIdentifier = result.writebackIdentifier
            workout.healthKitExportedAt = result.exportedAt
            try persistChanges()
        } catch {
            return
        }
    }
}
