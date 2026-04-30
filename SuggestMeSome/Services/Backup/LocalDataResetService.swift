import Foundation
import SwiftData

@MainActor
enum LocalDataResetService {
    static func resetPortableBackupScope(
        context: ModelContext,
        userDefaults: UserDefaults = .standard,
        clearUserDefaults: Bool = true
    ) throws {
        try deleteAllSwiftData(context: context)
        if clearUserDefaults {
            clearPortableBackupUserDefaults(userDefaults)
        }
    }

    static func clearPortableBackupUserDefaults(_ userDefaults: UserDefaults = .standard) {
        PortableBackupPreferences.clear(from: userDefaults)
        userDefaults.removeObject(forKey: LocalContractAuthService.persistenceKey)
        userDefaults.removeObject(forKey: ProductionBackendAuthService.persistenceKey)
        userDefaults.removeObject(forKey: ComplianceStateStore.persistenceKey)
    }

    private static func deleteAllSwiftData(context: ModelContext) throws {
        try deleteAll(SetEntry.self, context: context)
        try deleteAll(ExerciseEntry.self, context: context)
        try deleteAll(Workout.self, context: context)
        try deleteAll(PersonalRecord.self, context: context)

        try deleteAll(ProgramSessionExercise.self, context: context)
        try deleteAll(ProgramSessionTemplate.self, context: context)
        try deleteAll(ProgramWeekTemplate.self, context: context)
        try deleteAll(ProgramRun.self, context: context)
        try deleteAll(TrainingProgram.self, context: context)

        try deleteAll(DailyCoachCheckIn.self, context: context)
        try deleteAll(DailyCoachWeeklyReview.self, context: context)

        try deleteAll(AdaptationEventHistory.self, context: context)
        try deleteAll(AppliedOverlayAdjustment.self, context: context)
        try deleteAll(AppliedProgramOverlay.self, context: context)
        try deleteAll(AdaptationProposal.self, context: context)
        try deleteAll(LiftTrendSnapshot.self, context: context)
        try deleteAll(LiftPerformanceTrend.self, context: context)
        try deleteAll(WeeklyVolumeMetric.self, context: context)
        try deleteAll(ExercisePerformanceOutcome.self, context: context)
        try deleteAll(WeeklyTrainingAnalysis.self, context: context)

        try deleteAll(HealthKitDailySummary.self, context: context)
        try deleteAll(Exercise.self, context: context)
        try deleteAll(MuscleGroup.self, context: context)
    }

    private static func deleteAll<T: PersistentModel>(
        _ type: T.Type,
        context: ModelContext
    ) throws {
        let rows = try context.fetch(FetchDescriptor<T>())
        guard !rows.isEmpty else { return }
        for row in rows {
            context.delete(row)
        }
        try context.save()
    }
}
