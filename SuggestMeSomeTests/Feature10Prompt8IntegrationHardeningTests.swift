//
//  Feature10Prompt8IntegrationHardeningTests.swift
//  SuggestMeSomeTests
//
//  Feature 10 Prompt 8 — integration hardening and regression coverage.
//
//  Covers:
//  - run-scoped coach context loading through the repository/query seam
//  - pending proposal status filtering for SuggestMeSome coach context
//  - Today Plan to watch snapshot source-of-truth mapping
//  - five-focus profile matrix continuity
//

import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature10Prompt8IntegrationHardeningTests {

    @Test func coachContextLoaderUsesRunScopedRepositorySignals() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let runA = makeRun(name: "Run A", stableID: "run-a", startOffset: -14)
        let runB = makeRun(name: "Run B", stableID: "run-b", startOffset: -7)
        context.insert(runA.program!)
        context.insert(runA)
        context.insert(runB.program!)
        context.insert(runB)

        context.insert(makeAnalysis(run: runA, status: .high, weekOffset: -7))
        context.insert(makeAnalysis(run: runB, status: .critical, weekOffset: -6))
        context.insert(makeOverlay(run: runA, summary: "Run A deload active", status: .active, dayOffset: -2))
        context.insert(makeOverlay(run: runA, summary: "Run A superseded", status: .superseded, dayOffset: -1))
        context.insert(makeOverlay(run: runB, summary: "Run B deload active", status: .active, dayOffset: -1))

        context.insert(makeProposal(run: runA, status: .pendingAutoApply, priority: 90, summary: "Run A auto swap", type: .variationSwap))
        context.insert(makeProposal(run: runA, status: .pendingUserConfirmation, priority: 80, summary: "Run A user deload", type: .deload))
        context.insert(makeProposal(run: runA, status: .confirmed, priority: 100, summary: "Run A confirmed", type: .deload))
        context.insert(makeProposal(run: runB, status: .pendingUserConfirmation, priority: 95, summary: "Run B pending", type: .deload))

        try context.save()

        let loader = SuggestMeSomeCoachContextLoader(context: context)
        let coachContext = loader.loadContext(todayCheckIn: nil, activeRun: runA)

        #expect(coachContext.fatigueStatus == .high)
        #expect(coachContext.activeOverlaySummaries == ["Run A deload active"])
        #expect(coachContext.pendingProposals.map(\.summaryText) == ["Run A auto swap", "Run A user deload"])
    }

    @Test func pendingCoachContextProposalQueryKeepsStandaloneAndRunScopesSeparate() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let run = makeRun(name: "Scoped", stableID: "run-scoped", startOffset: -7)
        context.insert(run.program!)
        context.insert(run)

        context.insert(makeProposal(run: run, status: .pendingUserConfirmation, priority: 50, summary: "Run scoped", type: .deload))
        context.insert(makeProposal(run: nil, status: .pendingAutoApply, priority: 90, summary: "Standalone auto", type: .variationSwap))
        context.insert(makeProposal(run: nil, status: .rejected, priority: 100, summary: "Standalone rejected", type: .deload))
        try context.save()

        let scoped = ReadQueryRepository.pendingCoachContextProposals(for: run, context: context)
        let standalone = ReadQueryRepository.pendingCoachContextProposals(for: nil, context: context)

        #expect(scoped.map(\.summaryText) == ["Run scoped"])
        #expect(standalone.map(\.summaryText) == ["Standalone auto"])
    }

    @Test func todayPlanEngineOutputMapsVerbatimIntoWatchSnapshot() {
        let run = makeRun(name: "Feature 10 Program", stableID: "run-watch-10", startOffset: -7)
        let checkIn = DailyCoachCheckIn(
            date: day(0),
            sleepQuality: 2,
            soreness: 4,
            energy: 2,
            stress: 4,
            availableTimeMinutes: 45
        )
        let insight = ObjectiveRecoveryInsight(
            status: .caution,
            compactSummary: "HRV below baseline",
            detailSummary: "HRV below baseline; keep today conservative.",
            evaluatedMetricsCount: 2
        )

        let plan = TodayPlanEngine.buildPlan(
            checkIn: checkIn,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 1,
            recentWorkouts: [],
            objectiveRecoveryInsight: insight,
            completedWorkoutCountForRun: 0
        )

        let snapshot = WatchPayloadMapper.makeTodayPlanSnapshot(
            from: plan,
            programRunStableID: run.resolvedSyncStableID,
            generatedAt: day(0)
        )

        #expect(snapshot.compactSummary == plan.recommendation.compactSummary)
        #expect(snapshot.primarySuggestionText == plan.recommendation.primarySuggestion.compactText)
        #expect(snapshot.confidence == plan.confidence.rawValue)
        #expect(snapshot.activeSourceLabels == plan.attribution.activeSourceLabels)
        #expect(snapshot.whatChangedToday == plan.whatChangedToday)
        #expect(snapshot.pendingProposalCount == plan.recommendation.pendingProposalCount)
        #expect(snapshot.programName == "Feature 10 Program")
        #expect(snapshot.programRunStableID == "run-watch-10")
        #expect(snapshot.programWeekNumber == plan.recommendation.nextProgramSession?.weekNumber)
        #expect(snapshot.programSessionNumber == plan.recommendation.nextProgramSession?.sessionNumber)
    }

    @Test func fivePrimaryFocusProfilesRemainSupportedWithoutPriorityDrift() {
        let expectedFocuses: [ProgramFocus] = [
            .powerlifting,
            .bodybuilding,
            .powerbuilding,
            .generalFitness,
            .fullBody,
        ]

        let profiles = expectedFocuses.map(ProgramFocusProgrammingProfileLibrary.profile(for:))

        #expect(Set(profiles.map(\.focus)) == Set(expectedFocuses))
        #expect(profiles.allSatisfy { $0.topSetBackoffPolicy != .disabled })
        #expect(profiles.first { $0.focus == .powerlifting }?.primaryAdaptationGoal == .maximalStrength)
        #expect(profiles.first { $0.focus == .bodybuilding }?.primaryAdaptationGoal == .hypertrophy)
        #expect(profiles.first { $0.focus == .powerbuilding }?.primaryAdaptationGoal == .strengthHypertrophy)
        #expect(profiles.first { $0.focus == .generalFitness }?.primaryAdaptationGoal == .balancedFitness)
        #expect(profiles.first { $0.focus == .fullBody }?.primaryAdaptationGoal == .balancedFitness)
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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeRun(name: String, stableID: String, startOffset: Int) -> ProgramRun {
        let program = TrainingProgram(
            syncStableID: "\(stableID)-program",
            name: name,
            lengthInWeeks: 4,
            sessionsPerWeek: 3,
            source: .aiGenerated
        )
        let exercise = ProgramSessionExercise(
            exerciseName: "Back Squats",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 5,
            prescribedWeight: 225,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet
        )
        let session = ProgramSessionTemplate(sessionNumber: 1, sessionName: "Lower A")
        session.exercises = [exercise]
        exercise.session = session

        let week = ProgramWeekTemplate(weekNumber: 1)
        week.sessions = [session]
        session.week = week

        program.weeks = [week]
        week.program = program

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
            adjustmentReason: .fatigueAccumulation,
            summaryText: summary
        )
    }

    private func day(_ offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 4, day: 12, hour: 12)) ?? Date()
        return calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }
}
