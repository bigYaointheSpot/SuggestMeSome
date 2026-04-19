import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature16Prompt11SettingsReadSummaryTests {

    @Test func workoutCountAndDeleteRangeSummaryMatchTargetedReadWindow() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let workouts = [
            Workout(date: day(-12), startTime: day(-12), durationSeconds: 1_200),
            Workout(date: day(-4), startTime: day(-4), durationSeconds: 1_500),
            Workout(date: day(-1), startTime: day(-1), durationSeconds: 1_800),
        ]
        workouts.forEach { context.insert($0) }
        try context.save()

        let startDate = Calendar.current.startOfDay(for: day(-5))
        let endDate = Calendar.current.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: day(-1)
        ) ?? day(-1)

        let summary = TrainingReadRepository.workoutDeleteRangeSummary(
            from: startDate,
            to: endDate,
            context: context
        )

        #expect(TrainingReadRepository.workoutCount(context: context) == 3)
        #expect(summary.count == 2)
        #expect(summary.earliestDate == workouts[1].date)
        #expect(summary.latestDate == workouts[2].date)
    }

    @Test func exerciseUsageSummaryCountsDistinctWorkoutHistory() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let workoutA = Workout(date: day(-3), startTime: day(-3), durationSeconds: 1_200)
        let workoutB = Workout(date: day(-1), startTime: day(-1), durationSeconds: 1_500)

        let benchPrimary = ExerciseEntry(exerciseName: "Bench Press", unit: .lbs, orderIndex: 0)
        benchPrimary.workout = workoutA
        let benchSecondary = ExerciseEntry(exerciseName: "Bench Press", unit: .lbs, orderIndex: 1)
        benchSecondary.workout = workoutA
        workoutA.exerciseEntries = [benchPrimary, benchSecondary]

        let benchLater = ExerciseEntry(exerciseName: "Bench Press", unit: .lbs, orderIndex: 0)
        benchLater.workout = workoutB
        let rowLater = ExerciseEntry(exerciseName: "Barbell Row", unit: .lbs, orderIndex: 1)
        rowLater.workout = workoutB
        workoutB.exerciseEntries = [benchLater, rowLater]

        context.insert(workoutA)
        context.insert(workoutB)
        try context.save()

        let benchSummary = TrainingReadRepository.exerciseUsageSummary(
            for: "Bench Press",
            context: context
        )
        let rowSummary = TrainingReadRepository.exerciseUsageSummary(
            for: "Barbell Row",
            context: context
        )
        let missingSummary = TrainingReadRepository.exerciseUsageSummary(
            for: "Incline Press",
            context: context
        )

        #expect(benchSummary.exerciseName == "Bench Press")
        #expect(benchSummary.workoutCount == 2)
        #expect(benchSummary.hasUsage)
        #expect(rowSummary.workoutCount == 1)
        #expect(missingSummary.workoutCount == 0)
        #expect(!missingSummary.hasUsage)
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            PersonalRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
