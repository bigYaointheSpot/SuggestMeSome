import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature16Prompt8DataExportAndReadRepositoryTests {

    @Test func dataExportSummarySnapshotMatchesSeededCountsAndCSVRows() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let chest = MuscleGroup(name: "Chest")
        let bench = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest)
        chest.exercises = [bench]

        let workoutDate = day(-1)
        let workout = Workout(
            date: workoutDate,
            startTime: workoutDate,
            durationSeconds: 3_600
        )
        let entry = ExerciseEntry(
            exerciseName: "Bench Press",
            unit: .lbs,
            orderIndex: 0
        )
        let set = SetEntry(setNumber: 1, reps: 5, weight: 225, isPR: true)
        entry.workout = workout
        workout.exerciseEntries = [entry]
        set.exerciseEntry = entry
        entry.sets = [set]

        let personalRecord = PersonalRecord(
            exerciseName: "Bench Press",
            repCount: 5,
            weight: 225,
            unit: .lbs,
            dateAchieved: workoutDate
        )
        let program = TrainingProgram(
            name: "Export Program",
            lengthInWeeks: 1,
            sessionsPerWeek: 1,
            source: .aiGenerated
        )
        let run = ProgramRun(startDate: workoutDate)
        run.program = program
        let checkIn = DailyCoachCheckIn(date: workoutDate)
        let analysis = WeeklyTrainingAnalysis(
            weekStartDate: workoutDate,
            weekEndDate: workoutDate,
            isFinalized: true
        )
        let proposal = AdaptationProposal(
            programRun: run,
            trainingProgram: program,
            proposalType: .increaseLoad,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.9,
            priority: 90,
            targetWeekStart: 1,
            targetSessionNumber: 1,
            adjustmentReason: .positiveLiftTrend,
            summaryText: "Add 5 lb next week."
        )
        let healthSummary = HealthKitDailySummary(dayStart: workoutDate)

        context.insert(chest)
        context.insert(bench)
        context.insert(workout)
        context.insert(entry)
        context.insert(set)
        context.insert(personalRecord)
        context.insert(program)
        context.insert(run)
        context.insert(checkIn)
        context.insert(analysis)
        context.insert(proposal)
        context.insert(healthSummary)
        try context.save()

        let summary = DataExportReadRepository.summarySnapshot(context: context)
        let csvData = DataExportReadRepository.workoutCSVExportData(context: context)

        #expect(summary.muscleGroupCount == 1)
        #expect(summary.exerciseCount == 1)
        #expect(summary.workoutCount == 1)
        #expect(summary.exerciseEntryCount == 1)
        #expect(summary.setCount == 1)
        #expect(summary.personalRecordCount == 1)
        #expect(summary.trainingProgramCount == 1)
        #expect(summary.programRunCount == 1)
        #expect(summary.dailyCoachCheckInCount == 1)
        #expect(summary.weeklyTrainingAnalysisCount == 1)
        #expect(summary.adaptationProposalCount == 1)
        #expect(summary.healthKitDailySummaryCount == 1)
        #expect(csvData.workoutCount == summary.workoutCount)
        #expect(csvData.exerciseEntryCount == summary.exerciseEntryCount)
        #expect(csvData.setCount == summary.setCount)
        #expect(csvData.rows.count == 1)
        #expect(csvData.rows.first?.exerciseName == "Bench Press")
        #expect(csvData.rows.first?.muscleGroupName == "Chest")
        #expect(csvData.rows.first?.isPersonalRecord == true)
    }

    @Test func preferredUnitAndMesocycleReviewSnapshotUseScopedReads() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let startDate = day(-10)
        let completedDate = day(-1)
        let program = TrainingProgram(
            name: "Completed Block",
            lengthInWeeks: 1,
            sessionsPerWeek: 1,
            source: .aiGenerated
        )
        let run = ProgramRun(startDate: startDate, endDate: completedDate, isCompleted: true)
        run.program = program

        let programWorkout = makeWorkout(
            date: day(-2),
            exerciseName: "Bench Press",
            run: run
        )
        let standaloneInsideWindow = makeWorkout(
            date: day(-5),
            exerciseName: "Dumbbell Row",
            run: nil
        )
        let standaloneOutsideWindow = makeWorkout(
            date: day(-20),
            exerciseName: "Back Squat",
            run: nil
        )

        let olderUnit = PersonalRecord(
            exerciseName: "Bench Press",
            repCount: 5,
            weight: 225,
            unit: .lbs,
            dateAchieved: day(-30)
        )
        let newerUnit = PersonalRecord(
            exerciseName: "Bench Press",
            repCount: 3,
            weight: 100,
            unit: .kg,
            dateAchieved: day(-1)
        )

        context.insert(program)
        context.insert(run)
        for workout in [programWorkout, standaloneInsideWindow, standaloneOutsideWindow] {
            context.insert(workout)
            for entry in workout.exerciseEntries {
                context.insert(entry)
                for set in entry.sets {
                    context.insert(set)
                }
            }
        }
        context.insert(olderUnit)
        context.insert(newerUnit)
        try context.save()

        let preferredUnit = TrainingReadRepository.preferredUnit(
            for: "Bench Press",
            context: context
        )
        let review = TrainingReadRepository.mesocycleReviewSnapshot(
            for: run,
            context: context
        )

        #expect(preferredUnit == .kg)
        #expect(review?.headlineMetrics.workoutSummary.programWorkoutCount == 1)
        #expect(review?.headlineMetrics.workoutSummary.standaloneWorkoutCount == 1)
        #expect(review?.standaloneInfluence.includedWorkoutCount == 1)
    }

    @Test func pendingProposalAndOverlayHelpersReturnOnlyRelevantRows() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Proposal Scope",
            lengthInWeeks: 1,
            sessionsPerWeek: 1,
            source: .aiGenerated
        )
        let run = ProgramRun(startDate: day(-7))
        run.program = program

        let runPending = AdaptationProposal(
            programRun: run,
            trainingProgram: program,
            proposalType: .increaseLoad,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.8,
            priority: 80,
            targetWeekStart: 1,
            targetSessionNumber: 1,
            adjustmentReason: .positiveLiftTrend,
            summaryText: "Increase load."
        )
        let runAutoApply = AdaptationProposal(
            programRun: run,
            trainingProgram: program,
            proposalType: .decreaseLoad,
            proposalStatus: .pendingAutoApply,
            requiresUserConfirmation: false,
            autoApplyEligible: true,
            confidenceScore: 0.4,
            priority: 40,
            targetWeekStart: 1,
            targetSessionNumber: 1,
            adjustmentReason: .fatigueAccumulation,
            summaryText: "Protect recovery."
        )
        let runConfirmed = AdaptationProposal(
            programRun: run,
            trainingProgram: program,
            proposalType: .deload,
            proposalStatus: .confirmed,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.7,
            priority: 20,
            targetWeekStart: 2,
            adjustmentReason: .fatigueAccumulation,
            summaryText: "Already confirmed."
        )
        let standalonePending = AdaptationProposal(
            proposalType: .increaseVolume,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.6,
            priority: 60,
            targetWeekStart: 1,
            adjustmentReason: .lowAdherence,
            summaryText: "Standalone prompt."
        )

        let activeOverlay = AppliedProgramOverlay(
            programRun: run,
            trainingProgram: program,
            effectiveWeekStart: 1,
            overlayStatus: .active,
            appliedByUserConfirmation: true,
            adjustmentReason: .positiveLiftTrend,
            summaryText: "Keep progressing."
        )
        let supersededOverlay = AppliedProgramOverlay(
            programRun: run,
            trainingProgram: program,
            effectiveWeekStart: 1,
            overlayStatus: .superseded,
            appliedByUserConfirmation: true,
            adjustmentReason: .fatigueAccumulation,
            summaryText: "Old guidance."
        )

        context.insert(program)
        context.insert(run)
        for proposal in [runPending, runAutoApply, runConfirmed, standalonePending] {
            context.insert(proposal)
        }
        context.insert(activeOverlay)
        context.insert(supersededOverlay)
        try context.save()

        let pendingUser = TrainingReadRepository.fetchPendingUserProposals(
            for: run,
            context: context
        )
        let allPendingUser = TrainingReadRepository.fetchPendingUserProposals(
            context: context
        )
        let coachContextStandalone = TrainingReadRepository.fetchPendingCoachContextProposals(
            for: nil,
            context: context
        )
        let activeOverlays = TrainingReadRepository.fetchActiveOverlays(
            for: run,
            context: context
        )

        #expect(pendingUser.map(\.id) == [runPending.id])
        #expect(Set(allPendingUser.map(\.id)) == Set([runPending.id, standalonePending.id]))
        #expect(Set(coachContextStandalone.map(\.id)) == Set([standalonePending.id]))
        #expect(activeOverlays.map(\.id) == [activeOverlay.id])
    }

    private func makeWorkout(
        date: Date,
        exerciseName: String,
        run: ProgramRun?
    ) -> Workout {
        let workout = Workout(
            date: date,
            startTime: date,
            durationSeconds: 2_400,
            programRun: run,
            programWeekNumber: run == nil ? nil : 1,
            programSessionNumber: run == nil ? nil : 1
        )
        let entry = ExerciseEntry(
            exerciseName: exerciseName,
            unit: .lbs,
            orderIndex: 0
        )
        let set = SetEntry(setNumber: 1, reps: 5, weight: 225, isPR: false)
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
