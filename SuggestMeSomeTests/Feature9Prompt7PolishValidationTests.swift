import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

/// Validation tests for Prompt 7 — SuggestMeSome Polish + Explainability Pass.
/// Covers: reason chips, wasRedirected flag, summary copy improvements,
/// and title deduplication for recovery/conditioning modes.
@Suite(.serialized)
@MainActor
struct Feature9Prompt7PolishValidationTests {

    // MARK: - Reason chips

    @Test func reasonChipsAlwaysIncludeEquipmentAndDuration() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .upper,
            goal: .hypertrophy,
            equipmentProfile: .dumbbellsOnly,
            durationMinutes: 45,
            intensity: 3
        )

        let recommendation = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)

        let chipTexts = recommendation.reasonChips
        #expect(chipTexts.contains("Dumbbells Only"), "Equipment profile chip should always be present")
        #expect(chipTexts.contains("45 min"), "Duration chip should always be present")
        #expect(chipTexts.contains("Intensity 3"), "Intensity chip should always be present")
    }

    @Test func reasonChipsIncludeAvoidedLiftWhenConflictPresent() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        // Insert a recent hard bench exposure
        insertHardExposureWorkout(
            context: context,
            date: hoursAgo(10),
            exerciseName: "Bench Press",
            reps: 5,
            weight: 225
        )

        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        let recommendation = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)

        let hasAvoidedChip = recommendation.reasonChips.contains { $0.contains("avoided") }
        #expect(hasAvoidedChip, "Reason chips should include an 'avoided' chip when a canonical lift is blocked")
    }

    @Test func reasonChipsIncludeModeAdjustedWhenRedirected() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        // Insert enough recent exposure to trigger a redirect
        insertHardExposureWorkout(
            context: context,
            date: hoursAgo(18),
            exerciseName: "Back Squats",
            reps: 5,
            weight: 315
        )

        let run = ProgramRun(startDate: daysAgo(7), isCompleted: false)
        let program = TrainingProgram(name: "Lower Focus", lengthInWeeks: 4, sessionsPerWeek: 2, source: .aiGenerated)
        let week = ProgramWeekTemplate(weekNumber: 1)
        let session = ProgramSessionTemplate(sessionNumber: 1, sessionName: "Lower A")
        let exercise = ProgramSessionExercise(exerciseName: "Back Squats", orderIndex: 0, targetSets: 3, targetReps: 5)
        session.exercises = [exercise]
        week.sessions = [session]
        program.weeks = [week]
        run.program = program
        context.insert(run)
        context.insert(program)
        context.insert(week)
        context.insert(session)
        context.insert(exercise)
        try context.save()

        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 4
        )

        let recommendation = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)

        // If the mode was redirected, wasRedirected should be true and "Mode adjusted" chip should appear
        if recommendation.wasRedirected {
            #expect(recommendation.reasonChips.contains("Mode adjusted"),
                    "When mode is redirected, 'Mode adjusted' chip should be present")
        }
    }

    // MARK: - wasRedirected flag

    @Test func wasRedirectedFalseWhenNoConflictPresent() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .upper,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 3
        )

        let recommendation = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)

        // With no recent hard workouts and no active program, there should be no redirect
        #expect(recommendation.wasRedirected == false,
                "No conflict should mean wasRedirected is false (mode=\(recommendation.mode.title), configured=upper)")
    }

    @Test func wasRedirectedTrueWhenModeChanges() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        insertHardExposureWorkout(
            context: context,
            date: hoursAgo(18),
            exerciseName: "Back Squats",
            reps: 5,
            weight: 315
        )

        let run = ProgramRun(startDate: daysAgo(7), isCompleted: false)
        let program = TrainingProgram(name: "Squat Focus", lengthInWeeks: 4, sessionsPerWeek: 2, source: .aiGenerated)
        let week = ProgramWeekTemplate(weekNumber: 1)
        let session = ProgramSessionTemplate(sessionNumber: 1, sessionName: "Lower A")
        let ex = ProgramSessionExercise(exerciseName: "Back Squats", orderIndex: 0, targetSets: 3, targetReps: 5)
        session.exercises = [ex]
        week.sessions = [session]
        program.weeks = [week]
        run.program = program
        context.insert(run)
        context.insert(program)
        context.insert(week)
        context.insert(session)
        context.insert(ex)
        try context.save()

        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 4
        )

        let recommendation = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)

        if recommendation.mode != .lower {
            #expect(recommendation.wasRedirected == true,
                    "When mode changes from lower due to conflict, wasRedirected should be true")
        }
    }

    // MARK: - Title deduplication

    @Test func recoveryModeDoesNotProduceDuplicateTitleSegments() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .recovery,
            goal: .recovery,
            equipmentProfile: .fullGym,
            durationMinutes: 40,
            intensity: 2
        )

        let recommendation = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)

        // "Recovery · Recovery" should be collapsed to just "Recovery"
        #expect(recommendation.title == "Recovery",
                "Recovery mode + recovery goal should produce title 'Recovery', not 'Recovery · Recovery'")
    }

    @Test func conditioningModeDoesNotProduceDuplicateTitleSegments() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .conditioning,
            goal: .conditioning,
            equipmentProfile: .fullGym,
            durationMinutes: 45,
            intensity: 3
        )

        let recommendation = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)

        #expect(recommendation.title == "Conditioning",
                "Conditioning mode + conditioning goal should produce title 'Conditioning', not 'Conditioning · Conditioning'")
    }

    // MARK: - Summary copy

    @Test func summaryIsDescriptiveWhenNoConflicts() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)

        for mode: SuggestMeSomeSessionMode in [.upper, .lower, .push, .pull, .fullBody, .recovery, .conditioning] {
            let configuration = SuggestMeSomeSessionConfiguration(
                mode: mode,
                goal: .generalFitness,
                equipmentProfile: .fullGym,
                durationMinutes: 60,
                intensity: 3
            )
            let recommendation = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)

            #expect(!recommendation.summary.isEmpty,
                    "Summary should always be non-empty (mode: \(mode.title))")
            // Should NOT start with "Inputs:" (old robotic format)
            #expect(!recommendation.summary.hasPrefix("Inputs:"),
                    "Summary should not start with 'Inputs:' (mode: \(mode.title))")
        }
    }

    @Test func rationaleDoesNotStartWithInputsPrefix() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .hypertrophy,
            equipmentProfile: .homeGym,
            durationMinutes: 60,
            intensity: 3
        )

        let recommendation = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)

        #expect(!recommendation.rationale.hasPrefix("Inputs:"),
                "Rationale should not start with the old 'Inputs:' prefix")
    }

    // MARK: - Helpers

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            ProgramRun.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSeededMuscleGroups(context: ModelContext) -> [MuscleGroup] {
        let chest = MuscleGroup(name: "Chest")
        chest.exercises = [
            Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Incline Bench", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Push-ups", exerciseType: .accessory, muscleGroup: chest),
        ]
        let back = MuscleGroup(name: "Back")
        back.exercises = [
            Exercise(name: "Deadlift", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Barbell Row", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Pull-ups", exerciseType: .compound, muscleGroup: back),
        ]
        let shoulders = MuscleGroup(name: "Shoulders")
        shoulders.exercises = [
            Exercise(name: "Overhead Press", exerciseType: .compound, muscleGroup: shoulders),
            Exercise(name: "DB Shoulder Press", exerciseType: .accessory, muscleGroup: shoulders),
        ]
        let arms = MuscleGroup(name: "Arms")
        arms.exercises = [
            Exercise(name: "Dips", exerciseType: .compound, muscleGroup: arms),
            Exercise(name: "Barbell Curl", exerciseType: .isolation, muscleGroup: arms),
        ]
        let legs = MuscleGroup(name: "Legs")
        legs.exercises = [
            Exercise(name: "Back Squats", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Romanian Deadlift", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Bulgarian Split Squat", exerciseType: .compound, muscleGroup: legs),
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
            Exercise(name: "Rowing Machine", exerciseType: .cardio, muscleGroup: cardio),
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

    private func insertHardExposureWorkout(
        context: ModelContext,
        date: Date,
        exerciseName: String,
        reps: Int,
        weight: Double
    ) {
        let workout = Workout(date: date, startTime: date, durationSeconds: 3600, sourceType: .loggedInApp)
        let entry = ExerciseEntry(exerciseName: exerciseName, unit: .lbs, orderIndex: 0)
        let set = SetEntry(setNumber: 1, reps: reps, weight: weight)
        entry.sets = [set]
        entry.workout = workout
        workout.exerciseEntries = [entry]
        context.insert(workout)
        context.insert(entry)
        context.insert(set)
        try? context.save()
    }

    private func hoursAgo(_ hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
}
