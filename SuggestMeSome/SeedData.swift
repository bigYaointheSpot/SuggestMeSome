//
//  SeedData.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import Foundation
import SwiftData

/// Populates default MuscleGroups and Exercises on first launch only.
/// Guarded by the "hasSeededDefaultData" UserDefaults flag so it never runs twice.
func seedDefaultDataIfNeeded(context: ModelContext) {
    guard !UserDefaults.standard.bool(forKey: "hasSeededDefaultData") else { return }

    let seedData: [(group: String, exercises: [(name: String, type: ExerciseType)])] = [
        ("Chest", [
            ("Bench Press", .compound),
            ("Incline Bench", .compound),
            ("Decline Bench", .isolation),
            ("Dumbbell Flyes", .isolation),
            ("Cable Flyes", .isolation),
            ("Push-ups", .accessory)
        ]),
        ("Back", [
            ("Deadlift", .compound),
            ("Barbell Row", .compound),
            ("Lat Pulldown", .accessory),
            ("Pull-ups", .compound),
            ("Seated Cable Row", .accessory),
            ("T-Bar Row", .accessory)
        ]),
        ("Shoulders", [
            ("DB Shoulder Press", .accessory),
            ("Overhead Press", .compound),
            ("Lateral Raises", .isolation),
            ("Front Raises", .isolation),
            ("Face Pulls", .accessory),
            ("Reverse Flyes", .isolation)
        ]),
        ("Arms", [
            ("Barbell Curl", .isolation),
            ("Hammer Curl", .isolation),
            ("Tricep Pushdown", .isolation),
            ("Skull Crushers", .isolation),
            ("Preacher Curl", .isolation),
            ("Dips", .compound)
        ]),
        ("Legs", [
            ("Back Squats", .compound),
            ("Front Squat", .compound),
            ("Leg Press", .compound),
            ("Romanian Deadlift", .compound),
            ("Leg Curl", .isolation),
            ("Leg Extension", .isolation),
            ("Calf Raises", .isolation),
            ("Bulgarian Split Squat", .compound)
        ]),
        ("Core", [
            ("Plank", .accessory),
            ("Crunches", .accessory),
            ("Russian Twists", .accessory),
            ("Hanging Leg Raises", .accessory),
            ("Ab Rollout", .accessory),
            ("Cable Woodchops", .accessory)
        ]),
        ("Cardio", [
            ("Exercise Bike", .cardio),
            ("Elliptical", .cardio),
            ("Treadmill", .cardio),
            ("Incline Treadmill", .cardio),
            ("Stairmaster", .cardio),
            ("Rowing Machine", .cardio),
            ("Jump Rope", .cardio)
        ])
    ]

    for entry in seedData {
        let group = MuscleGroup(name: entry.group)
        context.insert(group)
        for (name, type) in entry.exercises {
            let exercise = Exercise(name: name, exerciseType: type, muscleGroup: group)
            context.insert(exercise)
        }
    }

    UserDefaults.standard.set(true, forKey: "hasSeededDefaultData")
    // Mark migration done for new installs — types are already correct from seed.
    UserDefaults.standard.set(true, forKey: "hasSeededExerciseTypesV1")
}

/// Updates exerciseType on existing exercises and adds the Cardio group for users
/// who had the app installed before exercise types were introduced.
/// Guarded by "hasSeededExerciseTypesV1" so it only runs once per install.
func migrateExerciseTypesIfNeeded(context: ModelContext) {
    guard !UserDefaults.standard.bool(forKey: "hasSeededExerciseTypesV1") else { return }

    let typeMap: [String: ExerciseType] = [
        // Compound
        "Back Squats": .compound, "Front Squat": .compound, "Deadlift": .compound,
        "Romanian Deadlift": .compound, "Bench Press": .compound, "Incline Bench": .compound,
        "Overhead Press": .compound, "Barbell Row": .compound, "Pull-ups": .compound,
        "Leg Press": .compound, "Bulgarian Split Squat": .compound, "Dips": .compound,
        // Isolation
        "Leg Curl": .isolation, "Leg Extension": .isolation, "Calf Raises": .isolation,
        "Barbell Curl": .isolation, "Hammer Curl": .isolation, "Preacher Curl": .isolation,
        "Tricep Pushdown": .isolation, "Skull Crushers": .isolation, "Cable Flyes": .isolation,
        "Dumbbell Flyes": .isolation, "Decline Bench": .isolation,
        "Lateral Raises": .isolation, "Front Raises": .isolation, "Reverse Flyes": .isolation,
        // Accessory
        "DB Shoulder Press": .accessory, "Face Pulls": .accessory,
        "Lat Pulldown": .accessory, "Seated Cable Row": .accessory, "T-Bar Row": .accessory,
        "Plank": .accessory, "Crunches": .accessory, "Russian Twists": .accessory,
        "Hanging Leg Raises": .accessory, "Ab Rollout": .accessory,
        "Cable Woodchops": .accessory, "Push-ups": .accessory,
    ]

    let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
    for exercise in allExercises {
        if let type = typeMap[exercise.name] {
            exercise.exerciseType = type
        }
    }

    // Add Cardio group only if it doesn't already exist.
    let groupDescriptor = FetchDescriptor<MuscleGroup>(
        predicate: #Predicate { $0.name == "Cardio" }
    )
    if ((try? context.fetch(groupDescriptor)) ?? []).isEmpty {
        let cardioGroup = MuscleGroup(name: "Cardio")
        context.insert(cardioGroup)
        let cardioExercises: [(String, ExerciseType)] = [
            ("Exercise Bike", .cardio), ("Elliptical", .cardio), ("Treadmill", .cardio),
            ("Incline Treadmill", .cardio), ("Stairmaster", .cardio),
            ("Rowing Machine", .cardio), ("Jump Rope", .cardio)
        ]
        for (name, type) in cardioExercises {
            let exercise = Exercise(name: name, exerciseType: type, muscleGroup: cardioGroup)
            context.insert(exercise)
        }
    }

    try? context.save()
    UserDefaults.standard.set(true, forKey: "hasSeededExerciseTypesV1")
}

/// Evaluates all sets in a saved workout and upserts PersonalRecord entries
/// where the new weight exceeds the previous best for that exercise + rep count.
func updatePersonalRecords(for workout: Workout, context: ModelContext) {
    let workoutDate = workout.date

    for entry in workout.exerciseEntries {
        guard !entry.isCardio else { continue }
        let exerciseName = entry.exerciseName
        let unit = entry.unit

        for set in entry.sets {
            let repCount = set.reps
            let weight = set.weight

            let predicate = #Predicate<PersonalRecord> {
                $0.exerciseName == exerciseName && $0.repCount == repCount
            }
            let descriptor = FetchDescriptor<PersonalRecord>(predicate: predicate)
            let existing = (try? context.fetch(descriptor))?.first

            if let record = existing {
                if weight > record.weight {
                    record.weight = weight
                    record.unit = unit
                    record.dateAchieved = workoutDate
                    set.isPR = true
                }
            } else {
                let record = PersonalRecord(
                    exerciseName: exerciseName,
                    repCount: repCount,
                    weight: weight,
                    unit: unit,
                    dateAchieved: workoutDate
                )
                context.insert(record)
                set.isPR = true
            }
        }
    }
}
