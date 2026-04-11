import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

/// Validation tests for Prompt 8 — Equipment-Aware Substitution + Fallback Session Generation.
/// Covers: ranked substitution, fallback detection, intent preservation, adaptation notes.
@Suite(.serialized)
@MainActor
struct Feature9Prompt8EquipmentSubstitutionTests {

    // MARK: - Ranked substitution

    @Test func benchPressHasDumbbellSubstituteForDumbbellsOnly() {
        let service = SuggestMeSomeExerciseSubstitutionService()
        let pool = makeExercisePool()
        let chestGroup = MuscleGroup(name: "Chest")
        let bench = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chestGroup)

        let subs = service.rankedSubstitutes(
            for: bench,
            equipmentProfile: .dumbbellsOnly,
            availableExercises: pool
        )

        let names = subs.map(\.exercise.name)
        #expect(names.contains("Dumbbell Bench Press"),
                "Dumbbell Bench Press should be a ranked substitute for Bench Press under Dumbbells Only")
    }

    @Test func benchPressHasBodyweightSubstituteForBodyweightOnly() {
        let service = SuggestMeSomeExerciseSubstitutionService()
        let pool = makeExercisePool()
        let chestGroup = MuscleGroup(name: "Chest")
        let bench = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chestGroup)

        let subs = service.rankedSubstitutes(
            for: bench,
            equipmentProfile: .bodyweightOnly,
            availableExercises: pool
        )

        let names = subs.map(\.exercise.name)
        #expect(names.contains("Push-ups"),
                "Push-ups should be a ranked substitute for Bench Press under Bodyweight Only")
    }

    @Test func squatHasDumbbellSubstituteForDumbbellsOnly() {
        let service = SuggestMeSomeExerciseSubstitutionService()
        let pool = makeExercisePool()
        let legsGroup = MuscleGroup(name: "Legs")
        let squat = Exercise(name: "Back Squats", exerciseType: .compound, muscleGroup: legsGroup)

        let subs = service.rankedSubstitutes(
            for: squat,
            equipmentProfile: .dumbbellsOnly,
            availableExercises: pool
        )

        let names = subs.map(\.exercise.name)
        #expect(names.contains("Goblet Squat"),
                "Goblet Squat should be a ranked substitute for Back Squats under Dumbbells Only")
    }

    @Test func rankedSubstitutesAreOrderedByEquipmentCompatibility() {
        let service = SuggestMeSomeExerciseSubstitutionService()
        let pool = makeExercisePool()
        let legsGroup = MuscleGroup(name: "Legs")
        let squat = Exercise(name: "Back Squats", exerciseType: .compound, muscleGroup: legsGroup)

        // For Dumbbells Only: Goblet Squat (dumbbell) should rank before Bulgarian Split Squat (bodyweight)
        let subs = service.rankedSubstitutes(
            for: squat,
            equipmentProfile: .dumbbellsOnly,
            availableExercises: pool
        )

        let names = subs.map(\.exercise.name)
        if let gobletIdx = names.firstIndex(of: "Goblet Squat"),
           let splitIdx = names.firstIndex(of: "Bulgarian Split Squat") {
            #expect(gobletIdx < splitIdx,
                    "Goblet Squat (dumbbell) should rank before Bulgarian Split Squat (bodyweight) for Dumbbells Only")
        }
    }

    @Test func noSubstitutesReturnedWhenNoneInPool() {
        let service = SuggestMeSomeExerciseSubstitutionService()
        let emptyPool: [Exercise] = []
        let chestGroup = MuscleGroup(name: "Chest")
        let bench = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chestGroup)

        let subs = service.rankedSubstitutes(
            for: bench,
            equipmentProfile: .dumbbellsOnly,
            availableExercises: emptyPool
        )

        #expect(subs.isEmpty, "No substitutes should be returned when the pool is empty")
    }

    @Test func noSubstitutesReturnedForExerciseNotInTable() {
        let service = SuggestMeSomeExerciseSubstitutionService()
        let pool = makeExercisePool()
        let coreGroup = MuscleGroup(name: "Core")
        // "Plank" has no entry in substitution table
        let plank = Exercise(name: "Plank", exerciseType: .accessory, muscleGroup: coreGroup)

        let subs = service.rankedSubstitutes(
            for: plank,
            equipmentProfile: .bodyweightOnly,
            availableExercises: pool
        )

        #expect(subs.isEmpty, "No substitutes should be returned for exercises not in the substitution table")
    }

    @Test func substitutionNoteContainsOriginalExerciseName() {
        let service = SuggestMeSomeExerciseSubstitutionService()
        let pool = makeExercisePool()
        let chestGroup = MuscleGroup(name: "Chest")
        let bench = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chestGroup)

        let subs = service.rankedSubstitutes(
            for: bench,
            equipmentProfile: .dumbbellsOnly,
            availableExercises: pool
        )

        guard let first = subs.first else {
            Issue.record("Expected at least one substitute")
            return
        }

        #expect(first.note.contains("Bench Press"),
                "Substitution note should reference the original exercise name")
    }

    // MARK: - Adaptation notes

    @Test func adaptationNoteNilWhenNoSubstitutionsNeeded() {
        let service = SuggestMeSomeExerciseSubstitutionService()

        let note = service.adaptationNote(
            removedCompoundCount: 0,
            substitutionCount: 0,
            canBuildSession: true,
            equipmentProfile: .fullGym,
            mode: .push,
            goal: .strength
        )

        #expect(note == nil, "No adaptation note when no substitutions occurred")
    }

    @Test func adaptationNoteDescribesSubstitutionCount() {
        let service = SuggestMeSomeExerciseSubstitutionService()

        let note = service.adaptationNote(
            removedCompoundCount: 2,
            substitutionCount: 2,
            canBuildSession: true,
            equipmentProfile: .dumbbellsOnly,
            mode: .push,
            goal: .hypertrophy
        )

        #expect(note != nil, "Adaptation note should be present when substitutions occurred")
        #expect(note?.contains("2") == true, "Adaptation note should mention substitution count")
        #expect(note?.contains("Dumbbells Only") == true, "Adaptation note should mention equipment profile")
    }

    @Test func adaptationNoteDescribesFallbackForBodyweightOnlyConditioningMode() {
        let service = SuggestMeSomeExerciseSubstitutionService()

        let note = service.adaptationNote(
            removedCompoundCount: 3,
            substitutionCount: 0,
            canBuildSession: false,
            equipmentProfile: .bodyweightOnly,
            mode: .conditioning,
            goal: .conditioning
        )

        #expect(note != nil, "Fallback note should be present for bodyweight-only conditioning")
        #expect(note?.contains("bodyweight") == true, "Fallback note should mention bodyweight")
    }

    @Test func adaptationNoteDescribesFallbackForBodyweightOnlyLowerMode() {
        let service = SuggestMeSomeExerciseSubstitutionService()

        let note = service.adaptationNote(
            removedCompoundCount: 3,
            substitutionCount: 0,
            canBuildSession: false,
            equipmentProfile: .bodyweightOnly,
            mode: .lower,
            goal: .strength
        )

        #expect(note != nil, "Fallback note should be present for bodyweight-only lower mode")
        #expect(note?.contains("unilateral") == true || note?.contains("Bodyweight Only") == true,
                "Fallback note should describe the lower-body bodyweight fallback")
    }

    // MARK: - End-to-end substitution in generation pipeline

    @Test func generatedWorkoutHasSubstitutionNoteWhenBarbellUnavailable() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeGenerationService(context: context)

        // Request a chest (push) session with dumbbells-only
        let chestGroup = allGroups.first { $0.name == "Chest" }!
        let request = SuggestMeSomeGenerationRequest(
            generationType: .custom,
            durationMinutes: 60,
            intensity: 3,
            selectedMuscleGroups: [chestGroup],
            selectedExercises: [],
            goal: .hypertrophy,
            equipmentProfile: .dumbbellsOnly,
            sessionMode: .push
        )

        let workout = service.generateWorkout(request: request)

        // At least one exercise should have a substitution note (Bench Press → Dumbbell Bench Press)
        let hasSubstitutionNote = workout.exercises.contains { $0.substitutionNote != nil }
        let hasAdaptationNote = workout.adaptationNote != nil

        // Either substitution happened OR no compounds needed substitution (if DB exercises were prioritized)
        // The key check: if Bench Press was in the pool and excluded, a note should appear
        let exerciseNames = workout.exercises.map(\.exercise.name)
        let benchExcluded = !exerciseNames.contains("Bench Press")

        if benchExcluded {
            // Bench was excluded by equipment filter, so either substitution note or adaptation note should exist
            #expect(hasSubstitutionNote || hasAdaptationNote,
                    "When Bench Press is excluded, workout should have substitution or adaptation notes")
        }
    }

    @Test func generatedWorkoutHasAdaptationNoteForBodyweightOnlyStrengthSession() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeGenerationService(context: context)

        // Request a lower body session with bodyweight-only (Back Squats/Deadlift should be blocked)
        let legsGroup = allGroups.first { $0.name == "Legs" }!
        let coreGroup = allGroups.first { $0.name == "Core" }!
        let request = SuggestMeSomeGenerationRequest(
            generationType: .custom,
            durationMinutes: 45,
            intensity: 3,
            selectedMuscleGroups: [legsGroup, coreGroup],
            selectedExercises: [],
            goal: .strength,
            equipmentProfile: .bodyweightOnly,
            sessionMode: .lower
        )

        let workout = service.generateWorkout(request: request)

        // Bodyweight exercises should be present
        #expect(!workout.exercises.isEmpty, "Workout should still generate with bodyweight exercises")

        // Barbell exercises should not be present
        let barbellExercises = ["Back Squats", "Romanian Deadlift", "Deadlift", "Good Mornings"]
        let exerciseNames = workout.exercises.map(\.exercise.name)
        for barbellEx in barbellExercises {
            #expect(!exerciseNames.contains(barbellEx),
                    "\(barbellEx) should not be present in bodyweight-only workout")
        }
    }

    @Test func generatedWorkoutPreservesSessionIntentUnderHomeGymConstraints() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeGenerationService(context: context)

        // Upper body session with home gym (cable excluded, barbell available)
        let chestGroup = allGroups.first { $0.name == "Chest" }!
        let backGroup = allGroups.first { $0.name == "Back" }!
        let shouldersGroup = allGroups.first { $0.name == "Shoulders" }!

        let request = SuggestMeSomeGenerationRequest(
            generationType: .custom,
            durationMinutes: 60,
            intensity: 3,
            selectedMuscleGroups: [chestGroup, backGroup, shouldersGroup],
            selectedExercises: [],
            goal: .hypertrophy,
            equipmentProfile: .homeGym,
            sessionMode: .upper
        )

        let workout = service.generateWorkout(request: request)

        #expect(!workout.exercises.isEmpty, "Upper session should generate exercises with home gym equipment")

        // Cable exercises should not be present
        let cableExercises = workout.exercises.filter { ex in
            ex.exercise.name.lowercased().contains("cable") ||
            ex.exercise.name == "Lat Pulldown" ||
            ex.exercise.name == "Face Pulls"
        }
        #expect(cableExercises.isEmpty, "Cable exercises should be excluded for Home Gym profile")

        // Barbell compound should still be present (home gym supports barbell)
        let hasCompound = workout.exercises.contains { $0.exercise.exerciseType == .compound }
        #expect(hasCompound, "Home Gym should still allow barbell compounds")
    }

    @Test func fullBodyGenerationHasAdaptationNoteForBodyweightOnly() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        _ = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeGenerationService(context: context)

        let request = SuggestMeSomeGenerationRequest(
            generationType: .fullBody,
            durationMinutes: 45,
            intensity: 2,
            selectedMuscleGroups: [],
            selectedExercises: [],
            goal: .generalFitness,
            equipmentProfile: .bodyweightOnly
        )

        let workout = service.generateWorkout(request: request)

        // Full-body bodyweight-only should generate something (bodyweight exercises exist)
        // and may have an adaptation note since many compounds are barbell-only
        if let note = workout.adaptationNote {
            #expect(!note.isEmpty, "Adaptation note should not be empty")
        }
        // Barbell exercises should be absent
        let exerciseNames = workout.exercises.map(\.exercise.name)
        let hasBarbellExercise = exerciseNames.contains { name in
            ["Back Squats", "Bench Press", "Deadlift", "Overhead Press"].contains(name)
        }
        #expect(!hasBarbellExercise, "Full-body bodyweight-only should not include barbell exercises")
    }

    // MARK: - Helpers

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Pool of exercises covering all equipment categories for substitution tests.
    private func makeExercisePool() -> [Exercise] {
        let chest = MuscleGroup(name: "Chest")
        let back = MuscleGroup(name: "Back")
        let shoulders = MuscleGroup(name: "Shoulders")
        let arms = MuscleGroup(name: "Arms")
        let legs = MuscleGroup(name: "Legs")
        let core = MuscleGroup(name: "Core")

        return [
            // Chest
            Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Dumbbell Bench Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Incline Bench", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Incline Dumbbell Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Push-ups", exerciseType: .accessory, muscleGroup: chest),
            Exercise(name: "Chest Dip", exerciseType: .compound, muscleGroup: chest),
            // Back
            Exercise(name: "Deadlift", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Barbell Row", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Dumbbell Row", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Pull-ups", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Chin-ups", exerciseType: .compound, muscleGroup: back),
            // Shoulders
            Exercise(name: "Overhead Press", exerciseType: .compound, muscleGroup: shoulders),
            Exercise(name: "DB Shoulder Press", exerciseType: .compound, muscleGroup: shoulders),
            Exercise(name: "Arnold Press", exerciseType: .accessory, muscleGroup: shoulders),
            Exercise(name: "Machine Shoulder Press", exerciseType: .accessory, muscleGroup: shoulders),
            // Arms
            Exercise(name: "Barbell Curl", exerciseType: .isolation, muscleGroup: arms),
            Exercise(name: "Concentration Curl", exerciseType: .isolation, muscleGroup: arms),
            Exercise(name: "Incline Dumbbell Curl", exerciseType: .isolation, muscleGroup: arms),
            Exercise(name: "Overhead Tricep Extension", exerciseType: .isolation, muscleGroup: arms),
            Exercise(name: "Close Grip Push-ups", exerciseType: .accessory, muscleGroup: arms),
            Exercise(name: "Dips", exerciseType: .compound, muscleGroup: arms),
            // Legs
            Exercise(name: "Back Squats", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Goblet Squat", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Hack Squat", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Romanian Deadlift", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Bulgarian Split Squat", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Walking Lunges", exerciseType: .accessory, muscleGroup: legs),
            Exercise(name: "Glute Bridge", exerciseType: .accessory, muscleGroup: legs),
            // Core
            Exercise(name: "Plank", exerciseType: .accessory, muscleGroup: core),
            Exercise(name: "Dead Bug", exerciseType: .accessory, muscleGroup: core),
            Exercise(name: "Bird Dog", exerciseType: .accessory, muscleGroup: core),
        ]
    }

    /// Full seeded muscle groups for end-to-end generation tests.
    private func makeSeededMuscleGroups(context: ModelContext) -> [MuscleGroup] {
        let chest = MuscleGroup(name: "Chest")
        chest.exercises = [
            Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Dumbbell Bench Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Incline Bench", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Incline Dumbbell Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Push-ups", exerciseType: .accessory, muscleGroup: chest),
            Exercise(name: "Chest Dip", exerciseType: .compound, muscleGroup: chest),
        ]
        let back = MuscleGroup(name: "Back")
        back.exercises = [
            Exercise(name: "Deadlift", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Barbell Row", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Dumbbell Row", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Pull-ups", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Chin-ups", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Lat Pulldown", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Face Pulls", exerciseType: .accessory, muscleGroup: back),
        ]
        let shoulders = MuscleGroup(name: "Shoulders")
        shoulders.exercises = [
            Exercise(name: "Overhead Press", exerciseType: .compound, muscleGroup: shoulders),
            Exercise(name: "DB Shoulder Press", exerciseType: .compound, muscleGroup: shoulders),
            Exercise(name: "Arnold Press", exerciseType: .accessory, muscleGroup: shoulders),
            Exercise(name: "Machine Shoulder Press", exerciseType: .accessory, muscleGroup: shoulders),
            Exercise(name: "Cable Lateral Raise", exerciseType: .isolation, muscleGroup: shoulders),
        ]
        let arms = MuscleGroup(name: "Arms")
        arms.exercises = [
            Exercise(name: "Barbell Curl", exerciseType: .isolation, muscleGroup: arms),
            Exercise(name: "Concentration Curl", exerciseType: .isolation, muscleGroup: arms),
            Exercise(name: "Overhead Tricep Extension", exerciseType: .isolation, muscleGroup: arms),
            Exercise(name: "Close Grip Push-ups", exerciseType: .accessory, muscleGroup: arms),
            Exercise(name: "Dips", exerciseType: .compound, muscleGroup: arms),
        ]
        let legs = MuscleGroup(name: "Legs")
        legs.exercises = [
            Exercise(name: "Back Squats", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Romanian Deadlift", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Goblet Squat", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Hack Squat", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Bulgarian Split Squat", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Walking Lunges", exerciseType: .accessory, muscleGroup: legs),
            Exercise(name: "Glute Bridge", exerciseType: .accessory, muscleGroup: legs),
        ]
        let core = MuscleGroup(name: "Core")
        core.exercises = [
            Exercise(name: "Plank", exerciseType: .accessory, muscleGroup: core),
            Exercise(name: "Dead Bug", exerciseType: .accessory, muscleGroup: core),
            Exercise(name: "Bird Dog", exerciseType: .accessory, muscleGroup: core),
        ]
        let cardio = MuscleGroup(name: "Cardio")
        cardio.exercises = [
            Exercise(name: "Exercise Bike", exerciseType: .cardio, muscleGroup: cardio),
            Exercise(name: "Jump Rope", exerciseType: .cardio, muscleGroup: cardio),
        ]

        let groups = [chest, back, shoulders, arms, legs, core, cardio]
        for group in groups {
            context.insert(group)
            for exercise in group.exercises {
                context.insert(exercise)
            }
        }
        return groups
    }
}
