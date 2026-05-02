//
//  DashboardRefreshFingerprinting.swift
//  SuggestMeSome
//
//  Refresh fingerprint helpers extracted from DashboardView in Feature 22 Prompt 1.
//  Behavior is unchanged; this file holds the pure hashing helpers and the
//  DashboardRefreshFingerprint struct so DashboardView can stay focused on UI.
//

import Foundation
import SwiftData

enum ViewRefreshFingerprinting {
    static func combineSyncBacked<Model>(
        _ models: [Model],
        into hasher: inout Hasher,
        stableID: (Model) -> String?,
        id: (Model) -> UUID,
        version: (Model) -> Int,
        modifiedAt: (Model) -> Date
    ) {
        let sortedModels = models.sorted {
            resolvedStableID(for: $0, stableID: stableID, id: id)
                < resolvedStableID(for: $1, stableID: stableID, id: id)
        }
        hasher.combine(sortedModels.count)
        for model in sortedModels {
            hasher.combine(resolvedStableID(for: model, stableID: stableID, id: id))
            hasher.combine(version(model))
            hasher.combine(modifiedAt(model))
        }
    }

    static func combineExercises(_ exercises: [Exercise], into hasher: inout Hasher) {
        let sortedExercises = exercises.sorted { exerciseSortKey(for: $0) < exerciseSortKey(for: $1) }
        hasher.combine(sortedExercises.count)
        for exercise in sortedExercises {
            hasher.combine(String(describing: exercise.persistentModelID))
            hasher.combine(exercise.name)
            hasher.combine(exercise.exerciseType)
            hasher.combine(exercise.muscleGroup.map { String(describing: $0.persistentModelID) })
            hasher.combine(exercise.muscleGroup?.name)
        }
    }

    static func combineLiftTrends(_ liftTrends: [LiftPerformanceTrend], into hasher: inout Hasher) {
        let sortedTrends = liftTrends.sorted {
            resolvedStableID(
                for: $0,
                stableID: { $0.syncStableID },
                id: { $0.id }
            ) < resolvedStableID(
                for: $1,
                stableID: { $0.syncStableID },
                id: { $0.id }
            )
        }
        hasher.combine(sortedTrends.count)
        for trend in sortedTrends {
            hasher.combine(trend.syncStableID ?? trend.id.uuidString)
            hasher.combine(trend.updatedAt)
        }
    }

    private static func resolvedStableID<Model>(
        for model: Model,
        stableID: (Model) -> String?,
        id: (Model) -> UUID
    ) -> String {
        stableID(model) ?? id(model).uuidString
    }

    private static func exerciseSortKey(for exercise: Exercise) -> String {
        [
            exercise.name,
            exercise.exerciseType.rawValue,
            exercise.muscleGroup?.name ?? "",
            String(describing: exercise.persistentModelID)
        ].joined(separator: "::")
    }
}

struct DashboardRefreshFingerprint: Hashable {
    private let value: Int

    init(
        activeProgramRuns: [ProgramRun],
        workouts: [Workout],
        prs: [PersonalRecord],
        exercises: [Exercise],
        weeklyAnalyses: [WeeklyTrainingAnalysis],
        liftTrends: [LiftPerformanceTrend],
        proposals: [AdaptationProposal],
        healthSummaries: [HealthKitDailySummary]
    ) {
        var hasher = Hasher()
        ViewRefreshFingerprinting.combineSyncBacked(
            activeProgramRuns,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            workouts,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            prs,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineExercises(exercises, into: &hasher)
        ViewRefreshFingerprinting.combineSyncBacked(
            weeklyAnalyses,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineLiftTrends(liftTrends, into: &hasher)
        ViewRefreshFingerprinting.combineSyncBacked(
            proposals,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            healthSummaries,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        value = hasher.finalize()
    }
}
