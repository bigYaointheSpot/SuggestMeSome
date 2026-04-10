//
//  SuggestMeSomeApp.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData

@main
struct SuggestMeSomeApp: App {
    private static let sharedSchema = Schema([
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            PersonalRecord.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            ProgramRun.self,
            ExercisePerformanceOutcome.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AppliedOverlayAdjustment.self,
            AdaptationEventHistory.self,
            // Feature 7 — Daily Coach
            DailyCoachCheckIn.self,
            DailyCoachWeeklyReview.self,
        ])

    var sharedModelContainer: ModelContainer = {
        let persistentConfiguration = ModelConfiguration(
            schema: sharedSchema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: sharedSchema, configurations: [persistentConfiguration])
        } catch {
            // Recovery path for incompatible/corrupted stores after schema updates.
            deleteSwiftDataStoreFiles()
            do {
                return try ModelContainer(for: sharedSchema, configurations: [persistentConfiguration])
            } catch {
                // Last-resort fallback to keep the app launchable instead of crashing.
                let inMemoryConfiguration = ModelConfiguration(
                    schema: sharedSchema,
                    isStoredInMemoryOnly: true
                )
                do {
                    return try ModelContainer(for: sharedSchema, configurations: [inMemoryConfiguration])
                } catch {
                    fatalError("Could not create ModelContainer: \(error)")
                }
            }
        }
    }()

    private static func deleteSwiftDataStoreFiles() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: appSupportURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        let sqliteExtensions: Set<String> = ["sqlite", "sqlite-wal", "sqlite-shm"]
        for url in contents where sqliteExtensions.contains(url.pathExtension) {
            try? fileManager.removeItem(at: url)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    // v1.0: Populates default MuscleGroups and Exercises on first launch.
                    seedDefaultDataIfNeeded(context: sharedModelContainer.mainContext)
                    // v1.1: Backfills exerciseType on existing exercises and adds the Cardio group.
                    migrateExerciseTypesIfNeeded(context: sharedModelContainer.mainContext)
                    // v1.2: Adds expanded exercise library introduced for the AI program generator.
                    migrateExercisesV2IfNeeded(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
