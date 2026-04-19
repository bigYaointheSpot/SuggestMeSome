import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature16Prompt15ScopedMesocycleReviewTests {

    @Test func scopedMesocycleReviewSnapshotMatchesBroadArrayBuild() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let olderRun = makeRun(
            stableID: "run-older",
            name: "Older Block",
            startDayOffset: -30,
            endDayOffset: -18
        )
        let newerRun = makeRun(
            stableID: "run-newer",
            name: "Newer Block",
            startDayOffset: -14,
            endDayOffset: -1
        )

        let olderProgramWorkout = makeWorkout(
            date: day(-28),
            exerciseName: "Bench Press",
            run: olderRun,
            weekNumber: 1,
            sessionNumber: 1,
            isPR: true
        )
        let newerProgramWorkout = makeWorkout(
            date: day(-10),
            exerciseName: "Bench Press",
            run: newerRun,
            weekNumber: 1,
            sessionNumber: 1,
            isPR: true
        )
        let newerStandaloneWorkout = makeWorkout(
            date: day(-6),
            exerciseName: "Dumbbell Row",
            run: nil,
            weekNumber: nil,
            sessionNumber: nil,
            isPR: false
        )

        let olderRecord = PersonalRecord(
            exerciseName: "Bench Press",
            repCount: 5,
            weight: 205,
            unit: .lbs,
            dateAchieved: day(-27)
        )
        let newerRecord = PersonalRecord(
            exerciseName: "Bench Press",
            repCount: 5,
            weight: 225,
            unit: .lbs,
            dateAchieved: day(-10)
        )

        context.insert(olderRun.program!)
        context.insert(newerRun.program!)
        context.insert(olderRun)
        context.insert(newerRun)
        for workout in [olderProgramWorkout, newerProgramWorkout, newerStandaloneWorkout] {
            context.insert(workout)
            for entry in workout.exerciseEntries {
                context.insert(entry)
                for set in entry.sets {
                    context.insert(set)
                }
            }
        }
        context.insert(olderRecord)
        context.insert(newerRecord)
        try context.save()

        let allWorkouts = TrainingReadRepository.fetchWorkouts(context: context)
        let allRecords = TrainingReadRepository.fetchPersonalRecords(context: context)

        let expected = TrainingContextQueryService.latestCompletedMesocycleReview(
            from: [olderRun, newerRun],
            workouts: allWorkouts,
            personalRecords: allRecords
        )
        let actual = TrainingReadRepository.mesocycleReviewSnapshot(
            for: newerRun,
            context: context
        )

        #expect(actual == expected)
    }

    @Test func scopedLongHorizonSummaryMatchesBroadArrayBuild() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let runOne = makeRun(
            stableID: "run-one",
            name: "Block One",
            startDayOffset: -60,
            endDayOffset: -46
        )
        let runTwo = makeRun(
            stableID: "run-two",
            name: "Block Two",
            startDayOffset: -35,
            endDayOffset: -20
        )
        let runThree = makeRun(
            stableID: "run-three",
            name: "Block Three",
            startDayOffset: -14,
            endDayOffset: -1
        )

        let workouts = [
            makeWorkout(date: day(-58), exerciseName: "Bench Press", run: runOne, weekNumber: 1, sessionNumber: 1, isPR: false),
            makeWorkout(date: day(-54), exerciseName: "Bench Press", run: runOne, weekNumber: 1, sessionNumber: 2, isPR: false),
            makeWorkout(date: day(-50), exerciseName: "Bench Press", run: runOne, weekNumber: 2, sessionNumber: 1, isPR: true),
            makeWorkout(date: day(-47), exerciseName: "Echo Bike", run: nil, weekNumber: nil, sessionNumber: nil, isPR: false, isCardio: true),
            makeWorkout(date: day(-33), exerciseName: "Bench Press", run: runTwo, weekNumber: 1, sessionNumber: 1, isPR: false),
            makeWorkout(date: day(-30), exerciseName: "Bench Press", run: runTwo, weekNumber: 1, sessionNumber: 2, isPR: true),
            makeWorkout(date: day(-24), exerciseName: "Bench Press", run: runTwo, weekNumber: 2, sessionNumber: 1, isPR: false),
            makeWorkout(date: day(-22), exerciseName: "Echo Bike", run: nil, weekNumber: nil, sessionNumber: nil, isPR: false, isCardio: true),
            makeWorkout(date: day(-12), exerciseName: "Bench Press", run: runThree, weekNumber: 1, sessionNumber: 1, isPR: false),
            makeWorkout(date: day(-8), exerciseName: "Bench Press", run: runThree, weekNumber: 1, sessionNumber: 2, isPR: true),
            makeWorkout(date: day(-4), exerciseName: "Bench Press", run: runThree, weekNumber: 2, sessionNumber: 1, isPR: false),
            makeWorkout(date: day(-2), exerciseName: "Echo Bike", run: nil, weekNumber: nil, sessionNumber: nil, isPR: false, isCardio: true),
        ]
        let records = [
            PersonalRecord(
                exerciseName: "Bench Press",
                repCount: 5,
                weight: 215,
                unit: .lbs,
                dateAchieved: day(-50)
            ),
            PersonalRecord(
                exerciseName: "Bench Press",
                repCount: 5,
                weight: 225,
                unit: .lbs,
                dateAchieved: day(-30)
            ),
            PersonalRecord(
                exerciseName: "Bench Press",
                repCount: 5,
                weight: 235,
                unit: .lbs,
                dateAchieved: day(-8)
            ),
        ]

        for run in [runOne, runTwo, runThree] {
            context.insert(run.program!)
            context.insert(run)
        }
        for workout in workouts {
            context.insert(workout)
            for entry in workout.exerciseEntries {
                context.insert(entry)
                for set in entry.sets {
                    context.insert(set)
                }
            }
        }
        for record in records {
            context.insert(record)
        }
        try context.save()

        let allWorkouts = TrainingReadRepository.fetchWorkouts(context: context)
        let allRecords = TrainingReadRepository.fetchPersonalRecords(context: context)

        let expected = TrainingContextQueryService.longHorizonAdaptationSummary(
            endingWith: runThree,
            allRuns: [runOne, runTwo, runThree],
            workouts: allWorkouts,
            personalRecords: allRecords,
            maxBlocks: 3
        )
        let actual = TrainingReadRepository.longHorizonAdaptationSummary(
            endingWith: runThree,
            maxBlocks: 3,
            context: context
        )

        #expect(actual == expected)
    }

    private func makeRun(
        stableID: String,
        name: String,
        startDayOffset: Int,
        endDayOffset: Int
    ) -> ProgramRun {
        let program = TrainingProgram(
            syncStableID: "\(stableID)-program",
            name: name,
            lengthInWeeks: 2,
            sessionsPerWeek: 2,
            createdDate: day(startDayOffset),
            source: .aiGenerated,
            progressionModel: .dup
        )
        let run = ProgramRun(
            syncStableID: stableID,
            startDate: day(startDayOffset),
            endDate: day(endDayOffset),
            isCompleted: true
        )
        run.program = program
        return run
    }

    private func makeWorkout(
        date: Date,
        exerciseName: String,
        run: ProgramRun?,
        weekNumber: Int?,
        sessionNumber: Int?,
        isPR: Bool,
        isCardio: Bool = false
    ) -> Workout {
        let workout = Workout(
            date: date,
            startTime: date,
            durationSeconds: 2_400,
            programRun: run,
            programWeekNumber: weekNumber,
            programSessionNumber: sessionNumber
        )
        let entry = ExerciseEntry(
            exerciseName: exerciseName,
            unit: .lbs,
            orderIndex: 0,
            isCardio: isCardio
        )
        let set = SetEntry(setNumber: 1, reps: isCardio ? 0 : 5, weight: isCardio ? 0 : 225, isPR: isPR)
        entry.workout = workout
        workout.exerciseEntries = [entry]
        set.exerciseEntry = entry
        entry.sets = [set]
        return workout
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
            DailyCoachCheckIn.self,
            DailyCoachWeeklyReview.self,
            HealthKitDailySummary.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
