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

    let seedData: [(group: String, exercises: [String])] = [
        ("Chest",     ["Bench Press", "Incline Bench", "Decline Bench", "Dumbbell Flyes", "Cable Flyes", "Push-ups"]),
        ("Back",      ["Deadlift", "Barbell Row", "Lat Pulldown", "Pull-ups", "Seated Cable Row", "T-Bar Row"]),
        ("Shoulders", ["DB Shoulder Press", "Overhead Press", "Lateral Raises", "Front Raises", "Face Pulls", "Reverse Flyes"]),
        ("Arms",      ["Barbell Curl", "Hammer Curl", "Tricep Pushdown", "Skull Crushers", "Preacher Curl", "Dips"]),
        ("Legs",      ["Back Squats", "Front Squat", "Leg Press", "Romanian Deadlift", "Leg Curl", "Leg Extension", "Calf Raises", "Bulgarian Split Squat"]),
        ("Core",      ["Plank", "Crunches", "Russian Twists", "Hanging Leg Raises", "Ab Rollout", "Cable Woodchops"])
    ]

    for entry in seedData {
        let group = MuscleGroup(name: entry.group)
        context.insert(group)
        for name in entry.exercises {
            let exercise = Exercise(name: name, muscleGroup: group)
            context.insert(exercise)
        }
    }

    UserDefaults.standard.set(true, forKey: "hasSeededDefaultData")
}

/// Evaluates all sets in a saved workout and upserts PersonalRecord entries
/// where the new weight exceeds the previous best for that exercise + rep count.
func updatePersonalRecords(for workout: Workout, context: ModelContext) {
    let workoutDate = workout.date

    for entry in workout.exerciseEntries {
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
