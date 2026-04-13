//
//  Feature10Prompt6TodayPlanEngineTests.swift
//  SuggestMeSomeTests
//
//  Feature 10 Prompt 6 — Today Plan Engine, Confidence, and Adherence Rescue Tests
//
//  Covers:
//  - Confidence classification (high / medium / low) for all signal combinations
//  - Source attribution field population (per-source influence descriptions)
//  - Adherence rescue outputs (onTrack, slightlyBehind, significantlyBehind)
//  - AdherenceRescueService.computeSessionsBehind determinism
//  - Explanation generation (whyToday, whatChangedToday)
//  - Deterministic behavior across common coach scenarios
//  - TodayPlanEngine.buildPlan integration scenarios
//

import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

// MARK: - Feature10Prompt6TodayPlanEngineTests

@Suite(.serialized)
@MainActor
struct Feature10Prompt6TodayPlanEngineTests {

    // MARK: - Confidence Classification

    @Test func highConfidenceRequiresProgramHistoryAndCheckIn() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Test Program", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: daysAgo(14))
        run.program = program
        context.insert(run)

        let checkIn = makeCheckIn()
        context.insert(checkIn)

        let recentWorkout = Workout(
            date: daysAgo(3), startTime: daysAgo(3), durationSeconds: 3600
        )
        recentWorkout.programRun = run
        recentWorkout.programWeekNumber = 1
        recentWorkout.programSessionNumber = 1
        context.insert(recentWorkout)

        let (confidence, rationale) = TodayPlanEngine.computeConfidence(
            checkIn: checkIn,
            activeRun: run,
            latestAnalysis: nil,
            recentWorkouts: [recentWorkout],
            completedWorkoutCountForRun: 1
        )

        #expect(confidence == .high, "Program + program history + check-in → high confidence (got \(confidence))")
        #expect(!rationale.isEmpty)
    }

    @Test func highConfidenceWithProgramAndWeeklyAnalysis() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Test Program", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: Date())
        run.program = program
        context.insert(run)

        let analysis = WeeklyTrainingAnalysis(
            weekStartDate: daysAgo(7), weekEndDate: daysAgo(1),
            fatigueStatus: .manageable, isFinalized: true
        )
        context.insert(analysis)

        let checkIn = makeCheckIn()
        context.insert(checkIn)

        let (confidence, _) = TodayPlanEngine.computeConfidence(
            checkIn: checkIn,
            activeRun: run,
            latestAnalysis: analysis,
            recentWorkouts: [],
            completedWorkoutCountForRun: 0
        )

        #expect(confidence == .high, "Program + weekly analysis + check-in → high confidence")
    }

    @Test func mediumConfidenceProgramWithCheckInNoHistory() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "New Program", lengthInWeeks: 6, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: Date())
        run.program = program
        context.insert(run)

        let checkIn = makeCheckIn()
        context.insert(checkIn)

        let (confidence, rationale) = TodayPlanEngine.computeConfidence(
            checkIn: checkIn,
            activeRun: run,
            latestAnalysis: nil,
            recentWorkouts: [],
            completedWorkoutCountForRun: 0
        )

        #expect(confidence == .medium, "New program run + no history → medium confidence")
        #expect(!rationale.isEmpty)
    }

    @Test func mediumConfidenceStandaloneWithCheckInAndHistory() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let checkIn = makeCheckIn()
        context.insert(checkIn)

        let workouts: [Workout] = (0..<5).map { i in
            let w = Workout(date: daysAgo(i + 1), startTime: daysAgo(i + 1), durationSeconds: 3600)
            context.insert(w)
            return w
        }

        let (confidence, _) = TodayPlanEngine.computeConfidence(
            checkIn: checkIn,
            activeRun: nil,
            latestAnalysis: nil,
            recentWorkouts: workouts,
            completedWorkoutCountForRun: 0
        )

        #expect(confidence == .medium, "Standalone + check-in + ≥3 workouts → medium confidence")
    }

    @Test func lowConfidenceNoCheckInNoAnalysis() {
        let (confidence, rationale) = TodayPlanEngine.computeConfidence(
            checkIn: nil,
            activeRun: nil,
            latestAnalysis: nil,
            recentWorkouts: [],
            completedWorkoutCountForRun: 0
        )

        #expect(confidence == .low, "No check-in + no analysis + no workouts → low confidence")
        #expect(!rationale.isEmpty)
    }

    @Test func lowConfidenceNoCheckInSparseHistory() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let workouts: [Workout] = (0..<2).map { i in
            let w = Workout(date: daysAgo(i + 1), startTime: daysAgo(i + 1), durationSeconds: 3600)
            context.insert(w)
            return w
        }

        let (confidence, _) = TodayPlanEngine.computeConfidence(
            checkIn: nil,
            activeRun: nil,
            latestAnalysis: nil,
            recentWorkouts: workouts,
            completedWorkoutCountForRun: 0
        )

        #expect(confidence == .low, "No check-in + <3 workouts → low confidence")
    }

    // MARK: - Source Attribution

    @Test func attributionIncludesCheckInWhenPresent() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let checkIn = makeCheckIn(availableTimeMinutes: 75)
        context.insert(checkIn)

        let attribution = TodayPlanEngine.buildAttribution(
            checkIn: checkIn,
            activeRun: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        #expect(attribution.manualReadinessInfluence.contains("75"), "Attribution must mention available time")
        #expect(attribution.activeSourceLabels.contains("Manual Check-In"), "Source labels must include Manual Check-In")
    }

    @Test func attributionNotesMissingCheckIn() {
        let attribution = TodayPlanEngine.buildAttribution(
            checkIn: nil,
            activeRun: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        #expect(attribution.manualReadinessInfluence.lowercased().contains("no check-in"), "Attribution must note missing check-in")
        #expect(!attribution.activeSourceLabels.contains("Manual Check-In"), "Source labels must NOT include Manual Check-In when absent")
    }

    @Test func attributionNotesPainFlag() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let checkIn = makeCheckIn(hasPainOrDiscomfort: true)
        context.insert(checkIn)

        let attribution = TodayPlanEngine.buildAttribution(
            checkIn: checkIn,
            activeRun: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        #expect(attribution.manualReadinessInfluence.lowercased().contains("pain"), "Attribution must mention pain flag")
    }

    @Test func attributionIncludesProgramWhenActive() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Squat Focus 8wk", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: Date())
        run.program = program
        context.insert(run)
        let checkIn = makeCheckIn()
        context.insert(checkIn)

        let attribution = TodayPlanEngine.buildAttribution(
            checkIn: nil,
            activeRun: run,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        #expect(attribution.programPrescriptionInfluence.contains("Squat Focus 8wk"), "Attribution must name active program")
        #expect(attribution.activeSourceLabels.contains("Program"), "Source labels must include Program")
    }

    @Test func attributionNotesProposalCount() {
        let attribution = TodayPlanEngine.buildAttribution(
            checkIn: nil,
            activeRun: nil,
            pendingProposalCount: 3,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        #expect(attribution.adaptiveOverlayInfluence.contains("3"), "Attribution must mention pending proposal count")
        #expect(attribution.activeSourceLabels.contains("Proposals"), "Source labels must include Proposals when pending > 0")
    }

    @Test func attributionHealthKitCautionMentioned() {
        let insight = ObjectiveRecoveryInsight(
            status: .caution,
            compactSummary: "HRV below baseline",
            detailSummary: "HRV 15% below 30-day average",
            evaluatedMetricsCount: 2
        )

        let attribution = TodayPlanEngine.buildAttribution(
            checkIn: nil,
            activeRun: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: insight
        )

        #expect(attribution.healthKitInfluence.lowercased().contains("caution"), "Attribution must note HealthKit caution")
        #expect(attribution.activeSourceLabels.contains("Health Data"), "Source labels must include Health Data when insight is available")
    }

    @Test func attributionFlagsMarkProgramOverlayProposalAndHealthInfluence() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Flag Test Program", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let checkIn = makeCheckIn(sleepQuality: 1, soreness: 5, energy: 1, stress: 5)
        context.insert(checkIn)
        let run = ProgramRun(startDate: Date())
        run.program = program
        context.insert(run)

        let proposal = makeProposal(
            run: run,
            type: .decreaseVolume,
            targetWeekStart: 2,
            targetSessionNumber: 2
        )
        context.insert(proposal)

        let overlay = makeOverlay(run: run, weekStart: 1, sessionNumber: 1)
        context.insert(overlay)

        let insight = ObjectiveRecoveryInsight(
            status: .caution,
            compactSummary: "HRV below baseline",
            detailSummary: "HRV 15% below 30-day average",
            evaluatedMetricsCount: 2
        )

        let plan = TodayPlanEngine.buildPlan(
            checkIn: checkIn,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 1,
            pendingProposals: [proposal],
            activeOverlays: [overlay],
            recentWorkouts: [],
            objectiveRecoveryInsight: insight
        )

        #expect(plan.attribution.influenceFlags.usedActiveProgramContext)
        #expect(plan.attribution.influenceFlags.usedApprovedOverlayContext)
        #expect(plan.attribution.influenceFlags.usedPendingProposalContext)
        #expect(plan.attribution.influenceFlags.usedRuntimeCoachAdjustment)
        #expect(plan.attribution.influenceFlags.usedHealthKitRecoveryNudge)
    }

    // MARK: - Adherence Rescue

    @Test func adherenceRescueOnTrackWhenZeroSessionsBehind() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "6-week Plan", lengthInWeeks: 6, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: Date()) // started today — 0 sessions expected
        run.program = program
        context.insert(run)

        let rescue = AdherenceRescueService.evaluate(
            run: run, program: program, completedWorkoutCount: 0
        )

        #expect(rescue?.status == .onTrack, "Day 0 with 0 sessions → on-track")
        #expect(rescue?.sessionsBehindCount == 0)
    }

    @Test func adherenceRescueSlightlyBehindWhenOneSessionMissed() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Test", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: daysAgo(14))
        run.program = program
        context.insert(run)

        // 14 days @ 3/week = floor(2) × 3 = 6 expected; 5 logged → 1 behind
        let behind = AdherenceRescueService.computeSessionsBehind(
            run: run, program: program, completedWorkoutCount: 5
        )

        #expect(behind == 1, "14 days @ 3/week = 6 expected, 5 completed → 1 behind (got \(behind))")

        let status = AdherenceRescueService.adherenceStatus(sessionsBehind: 1)
        if case .slightlyBehind(let count) = status {
            #expect(count == 1)
        } else {
            #expect(Bool(false), "Expected slightlyBehind(1), got \(status)")
        }
    }

    @Test func adherenceRescueSignificantlyBehindWhenMultipleMissed() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Test", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: daysAgo(21))
        run.program = program
        context.insert(run)

        // 21 days @ 3/week = floor(3) × 3 = 9 expected; 5 logged → 4 behind
        let behind = AdherenceRescueService.computeSessionsBehind(
            run: run, program: program, completedWorkoutCount: 5
        )

        #expect(behind == 4, "21 days @ 3/week = 9 expected, 5 completed → 4 behind (got \(behind))")

        let status = AdherenceRescueService.adherenceStatus(sessionsBehind: 4)
        if case .significantlyBehind(let count) = status {
            #expect(count == 4)
        } else {
            #expect(Bool(false), "Expected significantlyBehind(4), got \(status)")
        }
    }

    @Test func adherenceRescueTrimAndResumeForOneSessionBehind() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Trim Test", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: daysAgo(14))
        run.program = program
        context.insert(run)

        let rescue = AdherenceRescueService.evaluate(
            run: run, program: program, completedWorkoutCount: 5
        )

        #expect(rescue?.guidanceType == .trimAndResume, "1 session behind → trimAndResume guidance")
        #expect(!(rescue?.headline.isEmpty ?? true), "Rescue headline must not be empty")
        #expect(!(rescue?.details.isEmpty ?? true), "Rescue details must not be empty")
    }

    @Test func adherenceRescueConservativeResumeForMultipleBehind() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Conservative Test", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: daysAgo(21))
        run.program = program
        context.insert(run)

        let rescue = AdherenceRescueService.evaluate(
            run: run, program: program, completedWorkoutCount: 5
        )

        #expect(rescue?.guidanceType == .conservativeResume, "4 sessions behind → conservativeResume guidance")
        #expect(rescue?.sessionsBehindCount == 4)
    }

    @Test func adherenceRescueNilWhenNoProgramActive() {
        let rescue = AdherenceRescueService.evaluate(
            run: nil, program: nil, completedWorkoutCount: 0
        )
        #expect(rescue == nil, "No active program → nil rescue")
    }

    @Test func adherenceRescueNeverExceedsProgramTotalSessions() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Short", lengthInWeeks: 4, sessionsPerWeek: 2, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        // Total = 8 sessions; started 200 days ago with 0 logged → cap at 8
        let run = ProgramRun(startDate: daysAgo(200))
        run.program = program
        context.insert(run)

        let behind = AdherenceRescueService.computeSessionsBehind(
            run: run, program: program, completedWorkoutCount: 0
        )

        #expect(behind == 8, "Sessions behind must be capped at total program sessions (got \(behind))")
    }

    @Test func adherenceRescueZeroWhenCompletedExceedsExpected() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Ahead", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        // 7 days → expected 3 sessions; logged 5 (ahead of pace)
        let run = ProgramRun(startDate: Date())
        run.program = program
        context.insert(run)

        let behind = AdherenceRescueService.computeSessionsBehind(
            run: run, program: program, completedWorkoutCount: 5
        )

        #expect(behind == 0, "User ahead of pace → 0 sessions behind")
    }

    // MARK: - Explanation Generation

    @Test func whyTodayMentionsPainWhenFlagged() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let checkIn = makeCheckIn(hasPainOrDiscomfort: true)
        context.insert(checkIn)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: checkIn,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(plan.whyToday.lowercased().contains("pain"), "whyToday must mention pain when flagged")
    }

    @Test func whyTodayMentionsStrongReadiness() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        // Strong readiness: composite = (5 + 5 + 5 + 5)/4 = 5.0
        let checkIn = makeCheckIn(sleepQuality: 5, soreness: 1, energy: 5, stress: 1)
        context.insert(checkIn)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: checkIn,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(plan.whyToday.lowercased().contains("strong"), "whyToday must describe strong readiness")
    }

    @Test func whyTodayMentionsLowReadiness() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        // Low readiness: composite = (1 + 1 + 1 + 1)/4 = 1.0
        let checkIn = makeCheckIn(sleepQuality: 1, soreness: 5, energy: 1, stress: 5)
        context.insert(checkIn)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: checkIn,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(plan.whyToday.lowercased().contains("low"), "whyToday must describe low readiness")
    }

    @Test func whyTodayMentionsHealthKitCaution() {
        let insight = ObjectiveRecoveryInsight(
            status: .caution,
            compactSummary: "HRV below baseline",
            detailSummary: "HRV 15% below 30-day average",
            evaluatedMetricsCount: 2
        )
        let plan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: insight
        )
        #expect(
            plan.whyToday.lowercased().contains("caution") || plan.whyToday.lowercased().contains("healthkit"),
            "whyToday must mention HealthKit caution"
        )
    }

    @Test func whatChangedTodayEmptyForNeutralSession() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        // Neutral check-in defaults
        let checkIn = makeCheckIn()
        context.insert(checkIn)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: checkIn,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(plan.whatChangedToday.isEmpty, "No notable signals → empty whatChangedToday")
    }

    @Test func whatChangedTodayMentionsPainWhenFlagged() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let checkIn = makeCheckIn(hasPainOrDiscomfort: true)
        context.insert(checkIn)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: checkIn,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(!plan.whatChangedToday.isEmpty, "Pain flag → non-empty whatChangedToday")
        #expect(plan.whatChangedToday.lowercased().contains("pain"), "whatChangedToday must mention pain")
    }

    @Test func whatChangedTodayMentionsAdherenceBehind() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Adherence Test", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        // 14 days ago → 6 expected, 5 logged → 1 behind
        let run = ProgramRun(startDate: daysAgo(14))
        run.program = program
        context.insert(run)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil,
            completedWorkoutCountForRun: 5
        )
        #expect(!plan.whatChangedToday.isEmpty, "Adherence behind → non-empty whatChangedToday")
        let changedLower = plan.whatChangedToday.lowercased()
        #expect(changedLower.contains("adherence") || changedLower.contains("behind"), "whatChangedToday must mention adherence / behind")
    }

    @Test func whatChangedTodayMentionsPendingProposals() {
        let plan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 2,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(!plan.whatChangedToday.isEmpty, "Pending proposals → non-empty whatChangedToday")
        #expect(plan.whatChangedToday.contains("2"), "whatChangedToday must mention the proposal count")
    }

    @Test func whatChangedTodayClassifiesRuntimeOnlyAdjustment() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checkIn = makeCheckIn(sleepQuality: 1, soreness: 5, energy: 1, stress: 5)
        context.insert(checkIn)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: checkIn,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(plan.changeSummary.changeType == .runtimeOnlyAdjustment)
    }

    @Test func whatChangedTodayClassifiesApprovedOverlayInfluence() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Overlay Test", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: Date())
        run.program = program
        context.insert(run)

        let overlay = makeOverlay(run: run, weekStart: 1, sessionNumber: 1)
        context.insert(overlay)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            pendingProposals: [],
            activeOverlays: [overlay],
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(plan.changeSummary.changeType == .approvedOverlayInfluence)
    }

    @Test func whatChangedTodayClassifiesPendingProposalRelevance() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Proposal Test", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: Date())
        run.program = program
        context.insert(run)
        let checkIn = makeCheckIn()
        context.insert(checkIn)

        let proposal = makeProposal(
            run: run,
            type: .decreaseVolume,
            targetWeekStart: 4,
            targetSessionNumber: 1
        )
        context.insert(proposal)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: checkIn,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 1,
            pendingProposals: [proposal],
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(plan.changeSummary.changeType == .pendingProposalRelevance)
    }

    @Test func proposalAwarenessClassifiesTodayUpcomingAndLongHorizon() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Awareness Program", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: daysAgo(7))
        run.program = program
        context.insert(run)

        let todayProposal = makeProposal(
            run: run,
            type: .decreaseLoad,
            targetWeekStart: 1,
            targetSessionNumber: 1,
            summary: "Today-targeted proposal"
        )
        let upcomingProposal = makeProposal(
            run: run,
            type: .increaseVolume,
            targetWeekStart: 2,
            targetSessionNumber: 2,
            summary: "Upcoming-session proposal"
        )
        let longProposal = makeProposal(
            run: run,
            type: .deload,
            targetWeekStart: 6,
            targetSessionNumber: nil,
            summary: "Long-horizon proposal"
        )
        context.insert(todayProposal)
        context.insert(upcomingProposal)
        context.insert(longProposal)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 3,
            pendingProposals: [todayProposal, upcomingProposal, longProposal],
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        let bySummary = Dictionary(uniqueKeysWithValues: plan.proposalAwareness.map { ($0.summaryText, $0.impact) })
        #expect(bySummary["Today-targeted proposal"] == .affectsToday)
        #expect(bySummary["Upcoming-session proposal"] == .affectsUpcomingSession)
        #expect(bySummary["Long-horizon proposal"] == .affectsLongHorizonProgramming)
    }

    @Test func whyTodayUsesProgramPathWhenProgramActiveAndStandalonePathOtherwise() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Path Test", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: daysAgo(7))
        run.program = program
        context.insert(run)

        let programPlan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(programPlan.whyToday.lowercased().contains("active program"), "Program path should mention active program context")

        let standalonePlan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(standalonePlan.whyToday.lowercased().contains("no active program"), "Standalone path should mention no active program")
    }

    // MARK: - TodayPlanEngine Integration

    @Test func buildPlanReturnsValidPlanForSparsestCase() {
        let plan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )
        #expect(!plan.recommendation.compactSummary.isEmpty)
        #expect(!plan.confidenceRationale.isEmpty)
        #expect(!plan.whyToday.isEmpty)
        #expect(plan.adherenceRescue == nil, "No program → nil adherence rescue")
    }

    @Test func buildPlanNeverSurfacesOnTrackRescue() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Test", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        let run = ProgramRun(startDate: Date()) // started today — 0 behind
        run.program = program
        context.insert(run)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil,
            completedWorkoutCountForRun: 0
        )
        #expect(plan.adherenceRescue == nil, "On-track adherence must NOT be surfaced in the plan")
    }

    @Test func buildPlanSurfacesAdherenceRescueWhenBehind() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Test", lengthInWeeks: 8, sessionsPerWeek: 3, createdDate: Date(), source: .aiGenerated
        )
        context.insert(program)
        // 21 days ago → 9 expected, 5 logged → 4 behind
        let run = ProgramRun(startDate: daysAgo(21))
        run.program = program
        context.insert(run)

        let plan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil,
            completedWorkoutCountForRun: 5
        )
        #expect(plan.adherenceRescue != nil, "4 sessions behind → adherence rescue surfaced")
        #expect(plan.adherenceRescue?.sessionsBehindCount == 4)
        #expect(plan.adherenceRescue?.guidanceType == .conservativeResume)
    }

    @Test func buildPlanIsDeterministicForIdenticalInputs() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let checkIn = makeCheckIn(sleepQuality: 4, soreness: 2, energy: 4, stress: 2)
        context.insert(checkIn)

        let workouts: [Workout] = (0..<5).map { i in
            let w = Workout(date: daysAgo(i + 2), startTime: daysAgo(i + 2), durationSeconds: 3600)
            context.insert(w)
            return w
        }

        let plan1 = TodayPlanEngine.buildPlan(
            checkIn: checkIn, activeRun: nil, latestAnalysis: nil,
            pendingProposalCount: 0, recentWorkouts: workouts, objectiveRecoveryInsight: nil
        )
        let plan2 = TodayPlanEngine.buildPlan(
            checkIn: checkIn, activeRun: nil, latestAnalysis: nil,
            pendingProposalCount: 0, recentWorkouts: workouts, objectiveRecoveryInsight: nil
        )

        #expect(plan1.confidence == plan2.confidence, "Engine must be deterministic — confidence")
        #expect(plan1.whyToday == plan2.whyToday, "Engine must be deterministic — whyToday")
        #expect(plan1.recommendation.compactSummary == plan2.recommendation.compactSummary, "Engine must be deterministic — compactSummary")
    }

    // MARK: - AdherenceStatus Equatable

    @Test func adherenceStatusOnTrackEquality() {
        let s1 = AdherenceStatus.onTrack
        let s2 = AdherenceStatus.onTrack
        #expect(s1 == s2)
    }

    @Test func adherenceStatusSlightlyBehindEquality() {
        let s1 = AdherenceStatus.slightlyBehind(sessionsBehind: 1)
        let s2 = AdherenceStatus.slightlyBehind(sessionsBehind: 1)
        #expect(s1 == s2)
    }

    @Test func adherenceStatusSignificantlyBehindEquality() {
        let s1 = AdherenceStatus.significantlyBehind(sessionsBehind: 3)
        let s2 = AdherenceStatus.significantlyBehind(sessionsBehind: 3)
        #expect(s1 == s2)
    }

    @Test func adherenceStatusDistinctness() {
        #expect(AdherenceStatus.onTrack != AdherenceStatus.slightlyBehind(sessionsBehind: 1))
        #expect(AdherenceStatus.slightlyBehind(sessionsBehind: 1) != AdherenceStatus.slightlyBehind(sessionsBehind: 2))
    }

    // MARK: - Helpers

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    private func makeCheckIn(
        sleepQuality: Int = 3,
        soreness: Int = 2,
        energy: Int = 3,
        stress: Int = 2,
        availableTimeMinutes: Int = 60,
        hasPainOrDiscomfort: Bool = false
    ) -> DailyCoachCheckIn {
        DailyCoachCheckIn(
            date: Calendar.current.startOfDay(for: Date()),
            sleepQuality: sleepQuality,
            soreness: soreness,
            energy: energy,
            stress: stress,
            availableTimeMinutes: availableTimeMinutes,
            hasPainOrDiscomfort: hasPainOrDiscomfort
        )
    }

    private func makeProposal(
        run: ProgramRun?,
        type: ProposalType,
        targetWeekStart: Int,
        targetSessionNumber: Int?,
        summary: String = "Pending adaptation proposal"
    ) -> AdaptationProposal {
        AdaptationProposal(
            programRun: run,
            trainingProgram: run?.program,
            proposalType: type,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.7,
            priority: 75,
            targetWeekStart: targetWeekStart,
            targetWeekEnd: targetWeekStart,
            targetSessionNumber: targetSessionNumber,
            adjustmentReason: .programSignalPriority,
            summaryText: summary
        )
    }

    private func makeOverlay(
        run: ProgramRun,
        weekStart: Int,
        sessionNumber: Int?
    ) -> AppliedProgramOverlay {
        let overlay = AppliedProgramOverlay(
            programRun: run,
            trainingProgram: run.program,
            effectiveWeekStart: weekStart,
            effectiveWeekEnd: weekStart,
            overlayStatus: .active,
            appliedByUserConfirmation: true,
            adjustmentReason: .programSignalPriority,
            summaryText: "Approved overlay"
        )
        if let sessionNumber {
            let adjustment = AppliedOverlayAdjustment(
                overlay: overlay,
                sequence: 0,
                targetWeekNumber: weekStart,
                targetSessionNumber: sessionNumber,
                adjustmentType: .load,
                loadPercentDelta: -0.05,
                adjustmentReason: .programSignalPriority
            )
            overlay.adjustments = [adjustment]
        }
        return overlay
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
}
