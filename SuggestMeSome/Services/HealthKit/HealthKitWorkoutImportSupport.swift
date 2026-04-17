import Foundation
import SwiftData
import HealthKit

enum HealthKitWorkoutImportWindow {
    static func makeLast90Days(
        referenceDate: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -89, to: todayStart) ?? todayStart
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        return (start: start, end: tomorrowStart)
    }
}

enum HealthKitWorkoutImportQueryClient {
    static func fetchWorkouts(
        healthStore: HKHealthStore,
        start: Date,
        end: Date
    ) async -> [HKWorkout] {
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
}

enum HealthKitWorkoutImportMapper {
    static func importSnapshots(from workouts: [HKWorkout]) -> [HealthKitImportedWorkoutSnapshot] {
        workouts
            .filter { isSupportedForImport(activityType: $0.workoutActivityType) }
            .map { workout in
                HealthKitImportedWorkoutSnapshot(
                    externalIdentifier: workout.uuid.uuidString,
                    startDate: workout.startDate,
                    durationSeconds: max(0, Int(workout.duration.rounded())),
                    caloriesBurned: caloriesBurned(from: workout),
                    sourceDisplayName: sourceDisplayLabel(for: workout),
                    activityTypeIdentifier: String(workout.workoutActivityType.rawValue),
                    activityTypeDisplayName: activityDisplayLabel(for: workout.workoutActivityType)
                )
            }
    }

    private static func caloriesBurned(from workout: HKWorkout) -> Int? {
        guard let totalEnergy = workout.totalEnergyBurned else { return nil }
        return Int(totalEnergy.doubleValue(for: .kilocalorie()).rounded())
    }

    private static func isSupportedForImport(activityType: HKWorkoutActivityType) -> Bool {
        activityType == .traditionalStrengthTraining || isCardioWorkoutType(activityType)
    }

    private static func isCardioWorkoutType(_ activityType: HKWorkoutActivityType) -> Bool {
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

    private static func sourceDisplayLabel(for workout: HKWorkout) -> String {
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
        return "Apple Health"
    }

    private static func activityDisplayLabel(for activityType: HKWorkoutActivityType) -> String {
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

enum HealthKitWorkoutImportPersistence {
    @MainActor
    static func upsertImportedWorkouts(
        context: ModelContext,
        snapshots: [HealthKitImportedWorkoutSnapshot],
        importedAt: Date
    ) throws -> (inserted: Int, updated: Int) {
        guard !snapshots.isEmpty else { return (0, 0) }

        let externalIdentifiers = Set(snapshots.map(\.externalIdentifier))
        let existingWorkouts = (try? context.fetch(
            FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.sourceExternalIdentifier != nil
                }
            )
        )) ?? []
        var existingByExternalIdentifier: [String: Workout] = [:]
        for workout in existingWorkouts {
            guard let id = workout.sourceExternalIdentifier,
                  !id.isEmpty,
                  externalIdentifiers.contains(id) else { continue }
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
}
