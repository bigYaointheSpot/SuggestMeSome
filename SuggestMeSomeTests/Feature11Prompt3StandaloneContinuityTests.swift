import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature11Prompt3StandaloneContinuityTests {

    @Test func standaloneTodayPlanMarksHistoryInformedWhenSignalsAreAvailable() throws {
        let checkIn = makeCheckIn()
        let workouts = (0..<4).map { days -> Workout in
            Workout(date: daysAgo(days + 1), startTime: daysAgo(days + 1), durationSeconds: 3200)
        }

        let plan = TodayPlanEngine.buildPlan(
            checkIn: checkIn,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: workouts,
            objectiveRecoveryInsight: nil
        )

        #expect(plan.confidence == .medium)
        #expect(plan.nextStepGuidance.contextMode == .standaloneHistoryInformed)
        #expect(plan.nextStepGuidance.headline.lowercased().contains("history-informed"))
    }

    @Test func standaloneTodayPlanMarksLowConfidenceWhenSignalsAreSparse() {
        let plan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        #expect(plan.confidence == .low)
        #expect(plan.nextStepGuidance.contextMode == .standaloneLowConfidence)
        #expect(plan.nextStepGuidance.headline.lowercased().contains("conservative baseline"))
    }

    @Test func standaloneSuggestMeSomeRecommendationCarriesContinuityAndNextAction() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let groups = makeSeededMuscleGroups(context: context)

        insertStandaloneWorkout(
            context: context,
            date: hoursAgo(10),
            exerciseName: "Bench Press",
            reps: 5,
            weight: 225
        )

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 45,
            intensity: 4
        )

        let rec = service.recommendSession(configuration: config, allMuscleGroups: groups)

        #expect(rec.continuitySummary.lowercased().contains("last standalone session"))
        #expect(rec.continuitySummary.lowercased().contains("session shape is constrained"))
        #expect(!rec.nextActionGuidance.isEmpty)
    }

    @Test func sessionSummaryProvidesStandaloneNextStepGuidance() {
        let workout = Workout(date: hoursAgo(18), startTime: hoursAgo(18), durationSeconds: 3600)
        workout.exerciseEntries = [
            ratedEntry(name: "Bench Press", feedback: .tooHard),
            ratedEntry(name: "Barbell Row", feedback: .tooHard),
            ratedEntry(name: "Overhead Press", feedback: .onTarget)
        ]

        let summary = DailyCoachSessionSummaryService.latestSummary(
            recentWorkouts: [workout],
            latestCheckIn: nil
        )

        #expect(summary != nil)
        #expect(summary?.nextStepText.lowercased().contains("standalone next step") == true)
        #expect(summary?.nextStepText.lowercased().contains("reduce load") == true)
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

    private func makeCheckIn() -> DailyCoachCheckIn {
        DailyCoachCheckIn(
            date: Date(),
            sleepQuality: 4,
            soreness: 3,
            energy: 4,
            stress: 2,
            availableTimeMinutes: 50,
            hasPainOrDiscomfort: false
        )
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

    private func insertStandaloneWorkout(
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

    private func ratedEntry(name: String, feedback: WorkoutEffortFeedback) -> ExerciseEntry {
        let entry = ExerciseEntry(exerciseName: name, unit: .lbs, orderIndex: 0)
        entry.effortFeedback = feedback
        entry.sets = [SetEntry(setNumber: 1, reps: 5, weight: 100)]
        return entry
    }

    private func hoursAgo(_ hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
}
