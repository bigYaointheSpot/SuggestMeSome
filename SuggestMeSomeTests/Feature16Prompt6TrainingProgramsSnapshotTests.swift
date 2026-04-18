import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature16Prompt6TrainingProgramsSnapshotTests {

    @Test func programRunListSnapshotOrdersRunsAndBuildsRowMetrics() {
        let activeRun = makeRun(
            name: "Template Run",
            source: .template,
            startDate: day(-7),
            isCompleted: false
        )
        let completedRun = makeRun(
            name: "Smart Run",
            source: .aiGenerated,
            startDate: day(-21),
            isCompleted: true,
            endDate: day(-1)
        )

        let activeWorkout = makeWorkout(
            run: activeRun,
            date: day(-2),
            weekNumber: 1,
            sessionNumber: 1
        )
        let completedWorkout = makeWorkout(
            run: completedRun,
            date: day(-3),
            weekNumber: 1,
            sessionNumber: 1,
            exerciseName: "Bench Press",
            isPR: true
        )
        let personalRecords = [
            PersonalRecord(
                exerciseName: "Bench Press",
                repCount: 5,
                weight: 225,
                unit: .lbs,
                dateAchieved: day(-3)
            )
        ]
        let proposals = [
            AdaptationProposal(
                programRun: activeRun,
                trainingProgram: activeRun.program,
                proposalType: .increaseLoad,
                proposalStatus: .pendingUserConfirmation,
                requiresUserConfirmation: true,
                autoApplyEligible: false,
                confidenceScore: 0.9,
                priority: 90,
                targetWeekStart: 2,
                targetWeekEnd: 2,
                targetSessionNumber: 1,
                adjustmentReason: .positiveLiftTrend,
                summaryText: "Increase next week's top set."
            ),
            AdaptationProposal(
                programRun: activeRun,
                trainingProgram: activeRun.program,
                proposalType: .deload,
                proposalStatus: .confirmed,
                requiresUserConfirmation: true,
                autoApplyEligible: false,
                confidenceScore: 0.5,
                priority: 10,
                targetWeekStart: 3,
                targetWeekEnd: 3,
                targetSessionNumber: 1,
                adjustmentReason: .fatigueAccumulation,
                summaryText: "Already handled."
            ),
        ]
        let events = [
            AdaptationEventHistory(
                programRun: activeRun,
                trainingProgram: activeRun.program,
                eventType: .proposalCreated,
                message: "Proposal created"
            )
        ]

        let snapshot = ProgramRunListSnapshot.build(
            programRuns: [completedRun, activeRun],
            workouts: [activeWorkout, completedWorkout],
            personalRecords: personalRecords,
            proposals: proposals,
            events: events
        )

        #expect(snapshot.orderedRuns.map { $0.id } == [activeRun.id, completedRun.id])

        let activeSnapshot = snapshot.snapshot(for: activeRun)
        #expect(activeSnapshot.completedWorkoutCount == 1)
        #expect(activeSnapshot.totalWorkoutCount == 8)
        #expect(activeSnapshot.pendingProposalCount == 1)
        #expect(activeSnapshot.adaptationEventCount == 1)
        #expect(activeSnapshot.sourceLabel == "Template")
        #expect(activeSnapshot.completedWorkout(weekNumber: 1, sessionNumber: 1, runID: activeRun.id)?.id == activeWorkout.id)

        let completedSnapshot = snapshot.snapshot(for: completedRun)
        #expect(completedSnapshot.sourceLabel == "Smart Generated")
        #expect(completedSnapshot.blockReviewSnapshot != nil)
    }

    @Test func programRunListRefreshTokenChangesWhenOverlayChanges() {
        let run = makeRun(
            name: "Overlay Run",
            source: .aiGenerated,
            startDate: day(-7),
            isCompleted: false
        )
        let baseOverlay = AppliedProgramOverlay(
            programRun: run,
            trainingProgram: run.program,
            effectiveWeekStart: 2,
            appliedByUserConfirmation: true,
            adjustmentReason: .positiveLiftTrend,
            summaryText: "Keep bench work intact"
        )
        let updatedOverlay = AppliedProgramOverlay(
            id: baseOverlay.id,
            syncStableID: baseOverlay.syncStableID,
            syncVersion: baseOverlay.syncVersion + 1,
            appliedAt: baseOverlay.appliedAt.addingTimeInterval(60),
            programRun: run,
            trainingProgram: run.program,
            effectiveWeekStart: 2,
            appliedByUserConfirmation: true,
            adjustmentReason: .positiveLiftTrend,
            summaryText: "Swap the bench variation"
        )

        let initialToken = ProgramRunListSnapshot.refreshToken(
            programRuns: [run],
            workouts: [],
            personalRecords: [],
            proposals: [],
            events: [],
            overlays: [baseOverlay]
        )
        let updatedToken = ProgramRunListSnapshot.refreshToken(
            programRuns: [run],
            workouts: [],
            personalRecords: [],
            proposals: [],
            events: [],
            overlays: [updatedOverlay]
        )

        #expect(initialToken != updatedToken)
    }

    @Test func programSessionPreviewSnapshotLoadsWorkingExerciseAndWarmups() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let run = makeRun(
            name: "Preview Run",
            source: .aiGenerated,
            startDate: day(-2),
            isCompleted: false,
            weeks: 1,
            sessionsPerWeek: 1
        )
        let week = ProgramWeekTemplate(weekNumber: 1)
        let session = ProgramSessionTemplate(sessionNumber: 1)
        let warmup = ProgramSessionExercise(
            exerciseName: "Bench Press",
            orderIndex: 0,
            targetSets: 1,
            targetReps: 5,
            isWarmup: true
        )
        let working = ProgramSessionExercise(
            exerciseName: "Bench Press",
            orderIndex: 1,
            targetSets: 3,
            targetReps: 5,
            targetPercentage1RM: 0.8,
            prescribedWeight: 225,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet
        )

        week.program = run.program
        run.program?.weeks = [week]
        session.week = week
        week.sessions = [session]
        warmup.session = session
        working.session = session
        session.exercises = [warmup, working]

        context.insert(run.program!)
        context.insert(week)
        context.insert(session)
        context.insert(warmup)
        context.insert(working)
        context.insert(run)
        try context.save()

        let snapshot = ProgramSessionPreviewSnapshot.load(
            for: run,
            weekNumber: 1,
            sessionNumber: 1,
            context: context
        )

        #expect(snapshot.workingExercises.count == 1)
        #expect(snapshot.workingExercises.first?.exerciseName == "Bench Press")
        #expect(snapshot.workingExercises.first?.warmupCount == 1)
        #expect(snapshot.workingExercises.first?.detailText.contains("225 lbs") == true)
    }

    private func makeRun(
        name: String,
        source: ProgramSource,
        startDate: Date,
        isCompleted: Bool,
        endDate: Date? = nil,
        weeks: Int = 4,
        sessionsPerWeek: Int = 2
    ) -> ProgramRun {
        let program = TrainingProgram(
            name: name,
            lengthInWeeks: weeks,
            sessionsPerWeek: sessionsPerWeek,
            createdDate: startDate,
            source: source
        )
        let run = ProgramRun(startDate: startDate)
        run.program = program
        run.isCompleted = isCompleted
        run.endDate = endDate
        return run
    }

    private func makeWorkout(
        run: ProgramRun,
        date: Date,
        weekNumber: Int,
        sessionNumber: Int,
        exerciseName: String = "Back Squat",
        isPR: Bool = false
    ) -> Workout {
        let workout = Workout(
            date: date,
            startTime: date,
            durationSeconds: 1_800,
            programRun: run,
            programWeekNumber: weekNumber,
            programSessionNumber: sessionNumber
        )
        let entry = ExerciseEntry(
            exerciseName: exerciseName,
            unit: .lbs,
            orderIndex: 0
        )
        entry.workout = workout
        workout.exerciseEntries = [entry]
        let set = SetEntry(setNumber: 1, reps: 5, weight: 225, isPR: isPR)
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
