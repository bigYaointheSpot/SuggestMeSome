import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct BackendScalabilityReadSnapshotTests {

    @Test func coachContextSnapshotScopesRunSignalsAndBoundsRecentHistory() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let run = makeRun(stableID: "run-a", startOffset: 0)
        let otherRun = makeRun(stableID: "run-b", startOffset: -14)
        context.insert(run.program!)
        context.insert(run)
        context.insert(otherRun.program!)
        context.insert(otherRun)

        let olderAnalysis = makeAnalysis(run: run, status: .elevated, weekOffset: 0)
        olderAnalysis.createdAt = day(6)
        let newerAnalysis = makeAnalysis(run: run, status: .high, weekOffset: 7)
        newerAnalysis.createdAt = day(13)
        let unrelatedAnalysis = makeAnalysis(run: otherRun, status: .critical, weekOffset: 9)
        unrelatedAnalysis.createdAt = day(16)
        context.insert(olderAnalysis)
        context.insert(newerAnalysis)
        context.insert(unrelatedAnalysis)

        context.insert(makeOverlay(run: run, summary: "Keep volume reduced", status: .active, dayOffset: 7))
        context.insert(makeOverlay(run: run, summary: "Old inactive overlay", status: .expired, dayOffset: 8))
        context.insert(makeOverlay(run: otherRun, summary: "Wrong run", status: .active, dayOffset: 9))

        context.insert(makeProposal(run: run, status: .pendingUserConfirmation, priority: 90, summary: "User confirm", type: .deload))
        context.insert(makeProposal(run: run, status: .pendingAutoApply, priority: 80, summary: "Auto apply", type: .decreaseVolume))
        context.insert(makeProposal(run: run, status: .confirmed, priority: 95, summary: "Already handled", type: .decreaseLoad))
        context.insert(makeProposal(run: otherRun, status: .pendingUserConfirmation, priority: 100, summary: "Other run", type: .deload))

        for offset in 0..<8 {
            let workout = Workout(
                date: day(offset),
                startTime: day(offset),
                durationSeconds: 1_800,
                programRun: offset.isMultiple(of: 2) ? run : nil
            )
            context.insert(workout)
        }

        try context.save()

        let snapshot = TrainingReadRepository.coachContextSnapshot(
            focusRun: run,
            context: context,
            recentWorkoutLimit: 3,
            proposalLimit: 2
        )

        #expect(snapshot.activeRun?.id == run.id)
        #expect(snapshot.latestFatigueStatus == .high)
        #expect(snapshot.activeOverlaySummaries == ["Keep volume reduced"])
        #expect(snapshot.pendingProposals.count == 2)
        #expect(snapshot.pendingProposals.allSatisfy { $0.programRun?.id == run.id })
        #expect(snapshot.pendingProposals.allSatisfy {
            $0.proposalStatus == .pendingUserConfirmation || $0.proposalStatus == .pendingAutoApply
        })
        #expect(snapshot.recentWorkouts.count == 3)
        #expect(snapshot.recentWorkouts.map(\.date) == snapshot.recentWorkouts.map(\.date).sorted(by: >))
    }

    @Test func programRunProgressSnapshotBuildsCountsAndSessionKeysFromScopedWorkouts() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let run = makeRun(stableID: "progress-run", startOffset: 0)
        context.insert(run.program!)
        context.insert(run)

        context.insert(Workout(
            date: day(0),
            startTime: day(0),
            durationSeconds: 1_500,
            programRun: run,
            programWeekNumber: 1,
            programSessionNumber: 1
        ))
        context.insert(Workout(
            date: day(2),
            startTime: day(2),
            durationSeconds: 1_500,
            programRun: run,
            programWeekNumber: 1,
            programSessionNumber: 2
        ))
        context.insert(Workout(
            date: day(4),
            startTime: day(4),
            durationSeconds: 1_500,
            programRun: run
        ))
        context.insert(Workout(
            date: day(6),
            startTime: day(6),
            durationSeconds: 1_500
        ))
        try context.save()

        let snapshot = TrainingReadRepository.programRunProgressSnapshot(
            for: run,
            context: context
        )

        #expect(snapshot.completedWorkoutCount == 3)
        #expect(snapshot.workouts.count == 3)
        #expect(snapshot.completedSessionKeys == Set([
            ProgramSessionCompletionKey(weekNumber: 1, sessionNumber: 1),
            ProgramSessionCompletionKey(weekNumber: 1, sessionNumber: 2),
        ]))
    }

    @Test func programRunLookupUsesStableIDAndLegacyUUIDFallback() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let stableMatch = makeRun(stableID: "stable-run", startOffset: 0)
        let legacyMatch = makeRun(stableID: UUID().uuidString, startOffset: 2)
        legacyMatch.syncStableID = nil

        context.insert(stableMatch.program!)
        context.insert(stableMatch)
        context.insert(legacyMatch.program!)
        context.insert(legacyMatch)
        try context.save()

        let stableResult = TrainingReadRepository.programRun(
            matchingStableID: "stable-run",
            context: context
        )
        let legacyResult = TrainingReadRepository.programRun(
            matchingStableID: legacyMatch.id.uuidString,
            context: context
        )

        #expect(stableResult?.id == stableMatch.id)
        #expect(legacyResult?.id == legacyMatch.id)
    }

    @Test func adaptiveProposalPipelineSnapshotScopesRunArtifactsAndBoundsOutcomeWindow() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let run = makeRun(stableID: "adaptive-run", startOffset: 0)
        let otherRun = makeRun(stableID: "adaptive-other", startOffset: -7)
        context.insert(run.program!)
        context.insert(run)
        context.insert(otherRun.program!)
        context.insert(otherRun)

        let runAnalysis = makeAnalysis(run: run, status: .manageable, weekOffset: 70)
        let olderRunAnalysis = makeAnalysis(run: run, status: .elevated, weekOffset: 7)
        let otherAnalysis = makeAnalysis(run: otherRun, status: .high, weekOffset: 70)
        context.insert(runAnalysis)
        context.insert(olderRunAnalysis)
        context.insert(otherAnalysis)

        let runWorkout = Workout(date: day(80), startTime: day(80), durationSeconds: 1_800, programRun: run)
        let standaloneWorkout = Workout(date: day(81), startTime: day(81), durationSeconds: 1_500)
        let otherRunWorkout = Workout(date: day(82), startTime: day(82), durationSeconds: 1_500, programRun: otherRun)
        let staleWorkout = Workout(date: day(10), startTime: day(10), durationSeconds: 1_500, programRun: run)
        context.insert(runWorkout)
        context.insert(standaloneWorkout)
        context.insert(otherRunWorkout)
        context.insert(staleWorkout)

        let runOutcome = ExercisePerformanceOutcome(
            analysis: runAnalysis,
            programRun: run,
            workout: runWorkout,
            workoutDate: runWorkout.date,
            exerciseName: "Back Squat",
            canonicalLiftKey: CanonicalLift.squat.rawValue,
            signalSource: .programLinked,
            signalConfidence: .high,
            signalWeight: 1.0,
            actualSetCount: 3,
            actualAverageReps: 5,
            actualAverageWeight: 315,
            actualTopSetReps: 5,
            actualTopSetWeight: 325,
            actualTopSetEstimated1RM: 379,
            performanceScoreValue: 4,
            performanceScore: .onTarget,
            inferredFatigueStatus: .manageable,
            isTopSetSignal: true
        )
        runAnalysis.outcomes.append(runOutcome)

        let standaloneOutcome = ExercisePerformanceOutcome(
            workout: standaloneWorkout,
            workoutDate: standaloneWorkout.date,
            exerciseName: "Front Squat",
            canonicalLiftKey: CanonicalLift.squat.rawValue,
            signalSource: .standalone,
            signalConfidence: .medium,
            signalWeight: 0.7,
            actualSetCount: 3,
            actualAverageReps: 6,
            actualAverageWeight: 235,
            actualTopSetReps: 6,
            actualTopSetWeight: 245,
            actualTopSetEstimated1RM: 294,
            performanceScoreValue: 2,
            performanceScore: .onTarget,
            inferredFatigueStatus: .low,
            isTopSetSignal: true
        )

        let otherOutcome = ExercisePerformanceOutcome(
            analysis: otherAnalysis,
            programRun: otherRun,
            workout: otherRunWorkout,
            workoutDate: otherRunWorkout.date,
            exerciseName: "Bench Press",
            canonicalLiftKey: CanonicalLift.bench.rawValue,
            signalSource: .programLinked,
            signalConfidence: .high,
            signalWeight: 1.0,
            actualSetCount: 3,
            actualAverageReps: 5,
            actualAverageWeight: 225,
            actualTopSetReps: 5,
            actualTopSetWeight: 235,
            actualTopSetEstimated1RM: 274,
            performanceScoreValue: 3,
            performanceScore: .onTarget,
            inferredFatigueStatus: .manageable,
            isTopSetSignal: true
        )
        otherAnalysis.outcomes.append(otherOutcome)

        let staleOutcome = ExercisePerformanceOutcome(
            analysis: olderRunAnalysis,
            programRun: run,
            workout: staleWorkout,
            workoutDate: staleWorkout.date,
            exerciseName: "Back Squat",
            canonicalLiftKey: CanonicalLift.squat.rawValue,
            signalSource: .programLinked,
            signalConfidence: .high,
            signalWeight: 1.0,
            actualSetCount: 3,
            actualAverageReps: 5,
            actualAverageWeight: 285,
            actualTopSetReps: 5,
            actualTopSetWeight: 295,
            actualTopSetEstimated1RM: 344,
            performanceScoreValue: -3,
            performanceScore: .underperformance,
            inferredFatigueStatus: .elevated,
            isTopSetSignal: true
        )
        olderRunAnalysis.outcomes.append(staleOutcome)

        context.insert(runOutcome)
        context.insert(standaloneOutcome)
        context.insert(otherOutcome)
        context.insert(staleOutcome)

        context.insert(LiftPerformanceTrend(programRun: run, trainingProgram: run.program, canonicalLiftKey: "squat", liftDisplayName: "Squat"))
        context.insert(LiftPerformanceTrend(programRun: otherRun, trainingProgram: otherRun.program, canonicalLiftKey: "bench", liftDisplayName: "Bench"))
        context.insert(makeProposal(run: run, status: .pendingUserConfirmation, priority: 90, summary: "run proposal", type: .deload))
        context.insert(makeProposal(run: otherRun, status: .pendingUserConfirmation, priority: 95, summary: "other proposal", type: .deload))
        context.insert(makeOverlay(run: run, summary: "run overlay", status: .active, dayOffset: 81))
        context.insert(makeOverlay(run: otherRun, summary: "other overlay", status: .active, dayOffset: 81))
        context.insert(AdaptationEventHistory(timestamp: day(81), programRun: run, eventType: .proposalCreated, message: "run event"))
        context.insert(AdaptationEventHistory(timestamp: day(81), programRun: otherRun, eventType: .proposalCreated, message: "other event"))
        try context.save()

        let snapshot = TrainingReadRepository.adaptiveProposalPipelineSnapshot(
            for: run,
            referenceDate: day(100),
            context: context,
            outcomeLookbackDays: 84,
            includeStandaloneOutcomes: true
        )

        #expect(snapshot.finalizedAnalyses.map(\.id) == [olderRunAnalysis.id, runAnalysis.id])
        #expect(Set(snapshot.outcomes.map(\.id)) == Set([runOutcome.id, standaloneOutcome.id]))
        #expect(snapshot.performanceTrends.count == 1)
        #expect(snapshot.performanceTrends.allSatisfy { $0.programRun?.id == run.id })
        #expect(snapshot.proposals.count == 1)
        #expect(snapshot.proposals.allSatisfy { $0.programRun?.id == run.id })
        #expect(snapshot.overlays.count == 1)
        #expect(snapshot.overlays.allSatisfy { $0.programRun?.id == run.id })
        #expect(snapshot.events.count == 1)
        #expect(snapshot.events.allSatisfy { $0.programRun?.id == run.id })
    }

    private func makeRun(stableID: String, startOffset: Int) -> ProgramRun {
        let program = TrainingProgram(
            name: "Block \(stableID)",
            lengthInWeeks: 4,
            sessionsPerWeek: 3
        )
        let session = ProgramSessionTemplate(sessionNumber: 1, sessionName: "Session 1")
        let week = ProgramWeekTemplate(weekNumber: 1)
        session.week = week
        week.sessions = [session]
        week.program = program
        program.weeks = [week]

        let run = ProgramRun(syncStableID: stableID, startDate: day(startOffset))
        run.program = program
        return run
    }

    private func makeAnalysis(run: ProgramRun, status: FatigueStatus, weekOffset: Int) -> WeeklyTrainingAnalysis {
        WeeklyTrainingAnalysis(
            weekStartDate: day(weekOffset),
            weekEndDate: day(weekOffset + 6),
            programRun: run,
            trainingProgram: run.program,
            fatigueStatus: status,
            isFinalized: true,
            finalizedAt: day(weekOffset + 7)
        )
    }

    private func makeOverlay(
        run: ProgramRun,
        summary: String,
        status: OverlayStatus,
        dayOffset: Int
    ) -> AppliedProgramOverlay {
        AppliedProgramOverlay(
            appliedAt: day(dayOffset),
            programRun: run,
            trainingProgram: run.program,
            effectiveWeekStart: 1,
            effectiveWeekEnd: 1,
            overlayStatus: status,
            appliedByUserConfirmation: true,
            adjustmentReason: .fatigueAccumulation,
            summaryText: summary
        )
    }

    private func makeProposal(
        run: ProgramRun?,
        status: ProposalStatus,
        priority: Int,
        summary: String,
        type: ProposalType
    ) -> AdaptationProposal {
        AdaptationProposal(
            createdAt: day(-priority),
            programRun: run,
            trainingProgram: run?.program,
            proposalType: type,
            proposalStatus: status,
            requiresUserConfirmation: status == .pendingUserConfirmation,
            autoApplyEligible: status == .pendingAutoApply,
            confidenceScore: 0.8,
            priority: priority,
            targetWeekStart: 1,
            targetWeekEnd: 1,
            adjustmentReason: .fatigueAccumulation,
            summaryText: summary
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Workout.self,
            ProgramRun.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AppliedOverlayAdjustment.self,
            AdaptationEventHistory.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            ExercisePerformanceOutcome.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            ExerciseEntry.self,
            SetEntry.self,
            Exercise.self,
            MuscleGroup.self,
            PersonalRecord.self,
            DailyCoachCheckIn.self,
            DailyCoachWeeklyReview.self,
            HealthKitDailySummary.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func day(_ offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let anchor = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 5, hour: 12, minute: 0, second: 0)
        ) ?? Date()
        return calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }
}
