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
            clearApplicationSupportDirectory()
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

    private static func clearApplicationSupportDirectory() {
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
        for url in contents {
            try? fileManager.removeItem(at: url)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    seedDefaultDataIfNeeded(context: sharedModelContainer.mainContext)
                    migrateExerciseTypesIfNeeded(context: sharedModelContainer.mainContext)
                    migrateExercisesV2IfNeeded(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
