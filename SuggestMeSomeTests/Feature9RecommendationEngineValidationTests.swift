import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature9RecommendationEngineValidationTests {

    @Test func surpriseModeRecommendationIsDeterministicForSameInputs() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let allGroups = makeSeededMuscleGroups(context: context)
        let service = SuggestMeSomeRecommendationService(context: context)

        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .surpriseMe,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 55,
            intensity: 3
        )

        let first = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)
        let second = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)

        #expect(first.mode == second.mode)
        #expect(first.goal == second.goal)
        #expect(first.candidateAnchorLifts == second.candidateAnchorLifts)
        #expect(first.recommendedMovementPriorities == second.recommendedMovementPriorities)
    }

    @Test func recentHardBenchExposureAvoidsHeavyBenchRecommendation() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let allGroups = makeSeededMuscleGroups(context: context)
        insertHardExposureWorkout(
            context: context,
            date: hoursAgo(12),
            exerciseName: "Bench Press",
            reps: 5,
            weight: 235
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

        #expect(recommendation.candidateAnchorLifts.contains(where: { $0.caseInsensitiveCompare("Bench Press") == .orderedSame }) == false)
        // Summary should mention Bench Press conflict (wording may vary by prompt)
        #expect(recommendation.summary.contains("Bench Press"), "Summary should reference the blocked lift")
    }

    @Test func overlapAndProgramConflictBiasesTowardRecoveryMode() throws {
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

        #expect(recommendation.mode == .recovery)
        #expect(recommendation.rationale.contains("Active program next session"))
    }

    @Test func recommendationFlagsUnbuildableWhenDurationTooShort() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let allGroups = makeSeededMuscleGroups(context: context)
        let service = SuggestMeSomeRecommendationService(context: context)

        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .upper,
            goal: .generalFitness,
            equipmentProfile: .hotelGym,
            durationMinutes: 15,
            intensity: 3
        )

        let recommendation = service.recommendSession(configuration: configuration, allMuscleGroups: allGroups)

        #expect(recommendation.isBuildableIntoWorkout == false)
        #expect(recommendation.request == nil)
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
