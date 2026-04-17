import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct BackendDeletionAndPRMaintenanceTests {

    @Test func deletingWorkoutRecomputesPersonalRecords() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let lighterWorkout = insertWorkout(
            date: day(0),
            run: nil,
            entries: [EntrySpec(name: "Bench Press", unit: .lbs, sets: [(5, 185)])],
            context: context
        )
        _ = insertWorkout(
            date: day(1),
            run: nil,
            entries: [EntrySpec(name: "Bench Press", unit: .lbs, sets: [(5, 205)])],
            context: context
        )
        try context.save()

        try PersonalRecordMaintenanceService.recomputePRs(
            for: Set(["Bench Press"]),
            context: context
        )
        try context.save()

        try PersonalRecordMaintenanceService.deleteWorkout(
            try requireWorkout(on: day(1), context: context),
            context: context
        )

        let workouts = try fetchAll(Workout.self, context)
        let records = try fetchAll(PersonalRecord.self, context)

        #expect(workouts.count == 1)
        #expect(workouts.first?.id == lighterWorkout.id)
        #expect(records.count == 1)
        #expect(records.first?.exerciseName == "Bench Press")
        #expect(records.first?.repCount == 5)
        #expect(records.first?.weight == 185)
        #expect(records.first?.dateAchieved == lighterWorkout.date)

        let remainingSet = try #require(workouts.first?.exerciseEntries.first?.sets.first)
        #expect(remainingSet.isPR)
    }

    @Test func deletingProgramRunHistoryRemovesRunScopedDataAndRebuildsPersonalRecords() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let run = ProgramRun(
            startDate: day(0),
            endDate: day(14),
            isCompleted: true
        )
        context.insert(run)

        let standaloneWorkout = insertWorkout(
            date: day(2),
            run: nil,
            entries: [EntrySpec(name: "Bench Press", unit: .lbs, sets: [(5, 185)])],
            context: context
        )
        let runWorkout = insertWorkout(
            date: day(6),
            run: run,
            entries: [EntrySpec(name: "Bench Press", unit: .lbs, sets: [(5, 205)])],
            context: context
        )

        let analysis = WeeklyTrainingAnalysis(
            weekStartDate: day(0),
            weekEndDate: day(6),
            programRun: run,
            programWeekNumber: 1,
            isFinalized: true,
            finalizedAt: day(7)
        )
        context.insert(analysis)

        let linkedOutcome = ExercisePerformanceOutcome(
            analysis: analysis,
            programRun: run,
            workout: runWorkout,
            exerciseEntry: runWorkout.exerciseEntries.first,
            workoutDate: runWorkout.date,
            programWeekNumber: 1,
            programSessionNumber: 1,
            exerciseName: "Bench Press",
            signalSource: .programLinked,
            signalConfidence: .high,
            signalWeight: 1.0,
            actualSetCount: 1,
            actualAverageReps: 5,
            actualAverageWeight: 205,
            actualTopSetReps: 5,
            actualTopSetWeight: 205,
            performanceScoreValue: 0.8,
            performanceScore: .overperformance,
            inferredFatigueStatus: .manageable,
            isTopSetSignal: true
        )
        context.insert(linkedOutcome)

        let orphanOutcome = ExercisePerformanceOutcome(
            programRun: run,
            workout: runWorkout,
            exerciseEntry: runWorkout.exerciseEntries.first,
            workoutDate: runWorkout.date,
            programWeekNumber: 1,
            programSessionNumber: 1,
            exerciseName: "Bench Press",
            signalSource: .programLinked,
            signalConfidence: .high,
            signalWeight: 1.0,
            actualSetCount: 1,
            actualAverageReps: 5,
            actualAverageWeight: 205,
            actualTopSetReps: 5,
            actualTopSetWeight: 205,
            performanceScoreValue: 0.7,
            performanceScore: .onTarget,
            inferredFatigueStatus: .manageable,
            isTopSetSignal: true
        )
        context.insert(orphanOutcome)

        let trend = LiftPerformanceTrend(
            programRun: run,
            canonicalLiftKey: "bench_press",
            liftDisplayName: "Bench Press",
            totalDataPoints: 1,
            programLinkedDataPoints: 1,
            standaloneDataPoints: 0,
            weightedSignalCount: 1.0,
            confidenceScore: 0.9,
            firstObservationDate: day(6),
            lastObservationDate: day(6),
            currentEstimated1RM: 239,
            previousEstimated1RM: 230,
            rollingBestEstimated1RM: 239,
            fourWeekChangePercent: 0.04,
            trendStatus: .improving,
            fatigueStatus: .manageable,
            latestTopSetWeight: 205,
            latestTopSetReps: 5,
            latestPerformanceScoreValue: 0.8,
            lastPerformanceScore: .overperformance
        )
        context.insert(trend)

        let snapshot = LiftTrendSnapshot(
            trend: trend,
            programRun: run,
            canonicalLiftKey: "bench_press",
            liftDisplayName: "Bench Press",
            weekStartDate: day(0),
            weekEndDate: day(6),
            programWeekNumber: 1,
            totalDataPoints: 1,
            programLinkedDataPoints: 1,
            standaloneDataPoints: 0,
            weightedSignalCount: 1.0,
            weightedProgramSignal: 1.0,
            weightedStandaloneSignal: 0,
            confidenceScore: 0.9,
            currentEstimated1RM: 239,
            baselineEstimated1RM: 230,
            rollingBestEstimated1RM: 239,
            changePercent: 0.04,
            trendStatus: .improving,
            fatigueStatus: .manageable,
            latestTopSetWeight: 205,
            latestTopSetReps: 5,
            latestPerformanceScoreValue: 0.8
        )
        context.insert(snapshot)

        let proposal = AdaptationProposal(
            programRun: run,
            proposalType: .increaseLoad,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.82,
            priority: 1,
            targetWeekStart: 2,
            targetSessionNumber: 1,
            targetLiftKey: "bench_press",
            proposedLoadPercentDelta: 0.025,
            adjustmentReason: .positiveLiftTrend,
            summaryText: "Increase load next week"
        )
        context.insert(proposal)

        let overlay = AppliedProgramOverlay(
            programRun: run,
            sourceProposal: proposal,
            effectiveWeekStart: 2,
            overlayStatus: .active,
            appliedByUserConfirmation: true,
            adjustmentReason: .positiveLiftTrend,
            summaryText: "Bench +2.5%"
        )
        context.insert(overlay)

        let overlayAdjustment = AppliedOverlayAdjustment(
            overlay: overlay,
            sequence: 0,
            targetWeekNumber: 2,
            targetSessionNumber: 1,
            adjustmentType: .load,
            loadPercentDelta: 0.025,
            adjustmentReason: .positiveLiftTrend
        )
        context.insert(overlayAdjustment)

        let event = AdaptationEventHistory(
            programRun: run,
            analysis: analysis,
            proposal: proposal,
            overlay: overlay,
            eventType: .proposalCreated,
            analysisWeekNumber: 1,
            targetLiftKey: "bench_press",
            message: "Bench is moving well",
            adjustmentReason: .positiveLiftTrend,
            performanceScoreSnapshot: .overperformance,
            fatigueStatusSnapshot: .manageable,
            liftTrendStatusSnapshot: .improving,
            confidenceSnapshot: 0.82,
            requiresUserAction: true,
            userActionTaken: false
        )
        context.insert(event)

        let checkIn = DailyCoachCheckIn(
            date: day(6),
            availableTimeMinutes: 75,
            programRun: run
        )
        context.insert(checkIn)

        let weeklyReview = DailyCoachWeeklyReview(
            weekStart: day(0),
            weekEnd: day(6),
            isProgramWeek: true,
            programRun: run,
            headline: "Solid week",
            winText: "Bench improved",
            watchoutText: "Fatigue manageable",
            nextActionText: "Keep building"
        )
        context.insert(weeklyReview)

        try context.save()

        try PersonalRecordMaintenanceService.recomputePRs(
            for: Set(["Bench Press"]),
            context: context
        )
        try context.save()

        try TrainingHistoryDeletionService.deleteProgramRunHistory(run, context: context)

        #expect(try fetchAll(ProgramRun.self, context).isEmpty)
        #expect(try fetchAll(WeeklyTrainingAnalysis.self, context).isEmpty)
        #expect(try fetchAll(ExercisePerformanceOutcome.self, context).isEmpty)
        #expect(try fetchAll(LiftPerformanceTrend.self, context).isEmpty)
        #expect(try fetchAll(LiftTrendSnapshot.self, context).isEmpty)
        #expect(try fetchAll(AdaptationProposal.self, context).isEmpty)
        #expect(try fetchAll(AppliedProgramOverlay.self, context).isEmpty)
        #expect(try fetchAll(AppliedOverlayAdjustment.self, context).isEmpty)
        #expect(try fetchAll(AdaptationEventHistory.self, context).isEmpty)
        #expect(try fetchAll(DailyCoachCheckIn.self, context).isEmpty)
        #expect(try fetchAll(DailyCoachWeeklyReview.self, context).isEmpty)

        let workouts = try fetchAll(Workout.self, context)
        let records = try fetchAll(PersonalRecord.self, context)

        #expect(workouts.count == 1)
        #expect(workouts.first?.id == standaloneWorkout.id)
        #expect(records.count == 1)
        #expect(records.first?.weight == 185)
        #expect(records.first?.dateAchieved == standaloneWorkout.date)
        #expect(workouts.first?.exerciseEntries.first?.sets.first?.isPR == true)
    }

    @Test func clearingAllPRDataRemovesRecordsAndResetsFlags() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        _ = insertWorkout(
            date: day(0),
            run: nil,
            entries: [EntrySpec(name: "Bench Press", unit: .lbs, sets: [(5, 185)])],
            context: context
        )
        try context.save()

        try PersonalRecordMaintenanceService.recomputePRs(
            for: Set(["Bench Press"]),
            context: context
        )
        try context.save()

        try PersonalRecordMaintenanceService.clearAllPRData(context: context)

        let records = try fetchAll(PersonalRecord.self, context)
        let sets = try fetchAll(SetEntry.self, context)

        #expect(records.isEmpty)
        #expect(sets.count == 1)
        #expect(sets.first?.isPR == false)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            PersonalRecord.self,
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
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    private func requireWorkout(on date: Date, context: ModelContext) throws -> Workout {
        let workouts = try fetchAll(Workout.self, context)
        return try #require(workouts.first { $0.date == date })
    }

    private func day(_ offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let anchor = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 5, hour: 12, minute: 0, second: 0)
        ) ?? Date()
        return calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }

    @discardableResult
    private func insertWorkout(
        date: Date,
        run: ProgramRun?,
        entries: [EntrySpec],
        context: ModelContext
    ) -> Workout {
        let workout = Workout(
            date: date,
            startTime: date.addingTimeInterval(-3_600),
            durationSeconds: 3_600,
            programRun: run
        )
        context.insert(workout)

        for (entryIndex, spec) in entries.enumerated() {
            let entry = ExerciseEntry(
                exerciseName: spec.name,
                unit: spec.unit,
                orderIndex: entryIndex
            )
            entry.workout = workout
            context.insert(entry)

            for (setIndex, setSpec) in spec.sets.enumerated() {
                let set = SetEntry(
                    setNumber: setIndex + 1,
                    reps: setSpec.reps,
                    weight: setSpec.weight
                )
                set.exerciseEntry = entry
                context.insert(set)
            }
        }

        return workout
    }
}

private struct EntrySpec {
    let name: String
    let unit: WeightUnit
    let sets: [(reps: Int, weight: Double)]
}
