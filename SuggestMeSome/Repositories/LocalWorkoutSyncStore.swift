import Foundation
import SwiftData

@MainActor
struct LocalWorkoutSyncStore {
    let context: LocalSyncStoreContext

    func fetchWorkoutPayloads(
        since: Date?,
        includeDeleted: Bool
    ) throws -> [WorkoutSyncDTO] {
        try context.measureSyncExport(
            named: "Workout",
            since: since,
            metadata: "includeDeleted=\(includeDeleted)"
        ) {
            try context.fetchRows(workoutFetchDescriptor(since: since, includeDeleted: includeDeleted))
                .map { $0.toSyncDTO() }
        }
    }

    func upsertWorkoutPayloads(_ payloads: [WorkoutSyncDTO]) throws -> WorkoutSyncUpsertSummary {
        guard !payloads.isEmpty else { return WorkoutSyncUpsertSummary() }

        var existingWorkouts = try context.stableIDMap(for: Workout.self)
        let programRuns = try context.stableIDMap(for: ProgramRun.self)
        var summary = WorkoutSyncUpsertSummary()

        for payload in payloads {
            if payload.metadata.deletedAt != nil {
                if let existing = existingWorkouts[payload.metadata.stableID] {
                    summary.affectedExerciseNames.formUnion(exerciseNames(in: existing))
                    summary.didChangeWorkouts = true
                    context.modelContext.delete(existing)
                    existingWorkouts[payload.metadata.stableID] = nil
                }
                continue
            }

            let programRun = payload.programRunStableID.flatMap { programRuns[$0] }
            summary.affectedExerciseNames.formUnion(exerciseNames(in: payload))
            if let existing = existingWorkouts[payload.metadata.stableID] {
                summary.affectedExerciseNames.formUnion(exerciseNames(in: existing))
                summary.didChangeWorkouts = true
                existing.apply(syncDTO: payload, programRun: programRun)
                try upsertExerciseEntries(payload.exerciseEntries, into: existing)
            } else {
                summary.didChangeWorkouts = true
                let workout = Workout.fromSyncDTO(payload, programRun: programRun)
                context.modelContext.insert(workout)
                insertExerciseGraph(for: workout)
                existingWorkouts[payload.metadata.stableID] = workout
            }
        }

        try context.save()
        return summary
    }

    func markWorkoutDeleted(stableID: String, deletedAt: Date) throws {
        let workouts = try context.fetchRows(Workout.self)
        guard let workout = workouts.first(where: { $0.resolvedSyncStableID == stableID }) else { return }
        workout.markSyncDeleted(at: deletedAt)
        try context.save()
    }

    private func insertExerciseGraph(for workout: Workout) {
        for entry in workout.exerciseEntries {
            entry.workout = workout
            context.modelContext.insert(entry)
            for set in entry.sets {
                set.exerciseEntry = entry
                context.modelContext.insert(set)
            }
        }
    }

    private func upsertExerciseEntries(
        _ payloads: [ExerciseEntrySyncDTO],
        into workout: Workout
    ) throws {
        var existingByID: [String: ExerciseEntry] = [:]
        for entry in workout.exerciseEntries {
            entry.initializeSyncMetadataIfNeeded()
            existingByID[entry.resolvedSyncStableID] = entry
        }

        var incomingIDs: Set<String> = []
        for payload in payloads {
            incomingIDs.insert(payload.metadata.stableID)
            if let existing = existingByID[payload.metadata.stableID] {
                existing.apply(syncDTO: payload)
                existing.workout = workout
                try upsertSets(payload.sets, into: existing)
            } else {
                let entry = ExerciseEntry.fromSyncDTO(payload)
                entry.workout = workout
                context.modelContext.insert(entry)
                for set in entry.sets {
                    set.exerciseEntry = entry
                    context.modelContext.insert(set)
                }
            }
        }

        for stale in workout.exerciseEntries where !incomingIDs.contains(stale.resolvedSyncStableID) {
            context.modelContext.delete(stale)
        }
    }

    private func upsertSets(
        _ payloads: [SetEntrySyncDTO],
        into entry: ExerciseEntry
    ) throws {
        var existingByID: [String: SetEntry] = [:]
        for set in entry.sets {
            set.initializeSyncMetadataIfNeeded()
            existingByID[set.resolvedSyncStableID] = set
        }

        var incomingIDs: Set<String> = []
        for payload in payloads {
            incomingIDs.insert(payload.metadata.stableID)
            if let existing = existingByID[payload.metadata.stableID] {
                existing.apply(syncDTO: payload)
                existing.exerciseEntry = entry
            } else {
                let set = SetEntry.fromSyncDTO(payload)
                set.exerciseEntry = entry
                context.modelContext.insert(set)
            }
        }

        for stale in entry.sets where !incomingIDs.contains(stale.resolvedSyncStableID) {
            context.modelContext.delete(stale)
        }
    }

    private func workoutFetchDescriptor(
        since: Date?,
        includeDeleted: Bool
    ) -> FetchDescriptor<Workout> {
        let sortBy = [SortDescriptor(\Workout.date, order: .reverse)]

        switch (since, includeDeleted) {
        case let (.some(sinceDate), true):
            return FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.syncLastModifiedAt >= sinceDate
                },
                sortBy: sortBy
            )
        case let (.some(sinceDate), false):
            return FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.syncLastModifiedAt >= sinceDate && workout.syncDeletedAt == nil
                },
                sortBy: sortBy
            )
        case (nil, true):
            return FetchDescriptor<Workout>(sortBy: sortBy)
        case (nil, false):
            return FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.syncDeletedAt == nil
                },
                sortBy: sortBy
            )
        }
    }

    private func exerciseNames(in workout: Workout) -> Set<String> {
        Set(workout.exerciseEntries.map(\.exerciseName))
    }

    private func exerciseNames(in payload: WorkoutSyncDTO) -> Set<String> {
        Set(payload.exerciseEntries.map(\.exerciseName))
    }
}
