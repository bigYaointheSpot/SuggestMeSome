//
//  Feature11Prompt7IntegrationHardeningTests.swift
//  SuggestMeSomeTests
//
//  Feature 11 Prompt 7 — Integration hardening and regression pass.
//

import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature11Prompt7IntegrationHardeningTests {

    @Test func startAsPlannedDoesNotMasqueradeAsOverlayAdjustedWhenOverlayExists() {
        let rec = makeRecommendation(type: .runAsPlanned)

        let planned = TodayPlanActionCoordinator.resolveLaunch(
            request: .startAsPlanned,
            recommendation: rec,
            hasOverlayAffectingToday: true
        )
        let approved = TodayPlanActionCoordinator.resolveLaunch(
            request: .startApprovedVersion,
            recommendation: rec,
            hasOverlayAffectingToday: true
        )

        #expect(planned.path == .planned)
        #expect(planned.source == .plannedPrescription)
        #expect(approved.path == .approvedOverlayAdjusted)
        #expect(approved.source == .approvedOverlay)
    }

    @Test func executionSourceLabelsSeparatePendingAndAppliedSources() {
        let plan = makePlan(
            labels: ["Manual Check-In", "Program", "Approved Overlays", "Proposals", "Health Data"],
            usedProgram: true
        )
        let planned = TodayPlanLaunchResolution(
            path: .planned,
            source: .plannedPrescription,
            usesPreparedDraft: false
        )
        let overlay = TodayPlanLaunchResolution(
            path: .approvedOverlayAdjusted,
            source: .approvedOverlay,
            usesPreparedDraft: false
        )

        let plannedLabels = TodayPlanActionCoordinator.executionSourceLabels(
            plan: plan,
            resolution: planned,
            hasRelevantPendingProposal: true
        )
        let overlayLabels = TodayPlanActionCoordinator.executionSourceLabels(
            plan: plan,
            resolution: overlay,
            hasRelevantPendingProposal: true
        )

        #expect(plannedLabels.contains("Base Program"))
        #expect(plannedLabels.contains("Pending Proposal Not Applied"))
        #expect(!plannedLabels.contains("Approved Overlays"))
        #expect(!plannedLabels.contains("Proposals"))
        #expect(overlayLabels.contains("Approved Overlay"))
        #expect(!overlayLabels.contains("Base Program"))
    }

    @Test func overlayResolutionKeepsBaseRowsAndExplainabilityMetadataIntact() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let fixture = makeProgramFixture(context: context)

        let overlay = AppliedProgramOverlay(
            programRun: fixture.run,
            trainingProgram: fixture.program,
            effectiveWeekStart: 1,
            effectiveWeekEnd: 1,
            overlayStatus: .active,
            appliedByUserConfirmation: true,
            adjustmentReason: .programSignalPriority,
            summaryText: "Approved set trim"
        )
        let adjustment = AppliedOverlayAdjustment(
            overlay: overlay,
            sequence: 0,
            targetProgramSessionExerciseID: fixture.primary.id,
            targetWeekNumber: 1,
            targetSessionNumber: 1,
            adjustmentType: .volume,
            setDelta: -1,
            adjustmentReason: .programSignalPriority
        )
        overlay.adjustments = [adjustment]
        context.insert(overlay)
        context.insert(adjustment)
        try context.save()

        let baseRows = ProgramOverlayResolutionService.baseExercises(
            for: fixture.run,
            week: 1,
            session: 1
        )
        let resolvedRows = ProgramOverlayResolutionService.resolvedExercises(
            for: fixture.run,
            week: 1,
            session: 1,
            context: context
        )

        #expect(baseRows.first?.targetSets == 3)
        #expect(resolvedRows.first?.targetSets == 2)
        #expect(fixture.primary.targetSets == 3)
        #expect(resolvedRows.first?.explainabilityPurpose == .volumeFill)
        #expect(resolvedRows.first?.explainabilitySelectionReason == .recoveryBias)
        #expect(resolvedRows.first?.syncStableID == fixture.primary.syncStableID)
    }

    @Test func todayPlanUsesCompletedSessionKeysForNextProgramSessionContinuity() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let fixture = makeProgramFixture(context: context)

        let completed: Set<ProgramSessionCompletionKey> = [
            ProgramSessionCompletionKey(weekNumber: 1, sessionNumber: 1)
        ]
        let plan = TodayPlanEngine.buildPlan(
            checkIn: nil,
            activeRun: fixture.run,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil,
            completedSessions: completed,
            completedWorkoutCountForRun: 1
        )

        #expect(plan.recommendation.nextProgramSession?.weekNumber == 1)
        #expect(plan.recommendation.nextProgramSession?.sessionNumber == 2)
        #expect(plan.whyToday.contains("Week 1, Session 2"))
    }

    @Test func latestWeeklyAnalysisDoesNotBleedAcrossProgramAndStandaloneContexts() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let fixture = makeProgramFixture(context: context)
        let otherRun = ProgramRun(startDate: Date(), isCompleted: false)
        otherRun.program = fixture.program
        context.insert(otherRun)

        let targetAnalysis = WeeklyTrainingAnalysis(
            createdAt: Date(timeIntervalSince1970: 2_000),
            weekStartDate: Date(timeIntervalSince1970: 1_000),
            weekEndDate: Date(timeIntervalSince1970: 1_600),
            programRun: fixture.run,
            trainingProgram: fixture.program,
            fatigueStatus: .manageable,
            isFinalized: true
        )
        let unrelatedNewerProgramAnalysis = WeeklyTrainingAnalysis(
            createdAt: Date(timeIntervalSince1970: 3_000),
            weekStartDate: Date(timeIntervalSince1970: 2_000),
            weekEndDate: Date(timeIntervalSince1970: 2_600),
            programRun: otherRun,
            trainingProgram: fixture.program,
            fatigueStatus: .critical,
            isFinalized: true
        )
        let standaloneAnalysis = WeeklyTrainingAnalysis(
            createdAt: Date(timeIntervalSince1970: 4_000),
            weekStartDate: Date(timeIntervalSince1970: 3_000),
            weekEndDate: Date(timeIntervalSince1970: 3_600),
            programRun: nil,
            trainingProgram: nil,
            fatigueStatus: .elevated,
            isFinalized: true
        )

        let runScoped = TrainingContextQueryService.latestWeeklyAnalysis(
            for: fixture.run,
            in: [unrelatedNewerProgramAnalysis, standaloneAnalysis, targetAnalysis]
        )
        let standaloneScoped = TrainingContextQueryService.latestWeeklyAnalysis(
            for: nil,
            in: [unrelatedNewerProgramAnalysis, standaloneAnalysis, targetAnalysis]
        )

        #expect(runScoped?.id == targetAnalysis.id)
        #expect(standaloneScoped?.id == standaloneAnalysis.id)
    }

    @Test func watchLaunchLiveAndCurrentContextCarrySameExecutionVersion() async throws {
        let bridge = MockWatchCompanionBridge()
        let coordinator = WatchSessionCoordinator(bridge: bridge)
        let workoutID = UUID()
        let entries = [makePartialEntry(name: "Bench Press", orderIndex: 0)]
        let versionID = "run-hardening::w1s1::overlay"
        let sourceLabels = ["Program", "Approved Overlay"]

        await coordinator.broadcastWorkoutLaunch(
            workoutID: workoutID,
            startedAt: Date(timeIntervalSince1970: 1_700_700_000),
            programRunID: UUID(),
            programWeekNumber: 1,
            programSessionNumber: 1,
            sessionPlanKind: .overlayAdjusted,
            sessionSourceLabels: sourceLabels,
            sessionVersionStableID: versionID
        )
        await coordinator.broadcastLiveWorkout(
            workoutID: workoutID,
            elapsedSeconds: 0,
            entries: entries,
            sessionLabel: "Week 1, Session 1",
            programRunStableID: "run-hardening",
            programWeekNumber: 1,
            programSessionNumber: 1,
            sessionPlanKind: .overlayAdjusted,
            sessionSourceLabels: sourceLabels,
            sessionVersionStableID: versionID
        )
        await coordinator.broadcastCurrentSessionContext(
            workoutID: workoutID,
            entries: entries,
            sessionPlanKind: .overlayAdjusted,
            sessionSourceLabels: sourceLabels,
            sessionVersionStableID: versionID
        )

        let launch = try unwrap(bridge.launchPayloads.first)
        let live = try unwrap(bridge.liveSnapshots.first)
        let current = try unwrap(bridge.sessionContexts.first)

        #expect(launch.sessionVersionStableID == versionID)
        #expect(live.sessionVersionStableID == versionID)
        #expect(current.sessionVersionStableID == versionID)
        #expect(live.totalExercises == 1)
        #expect(current.exerciseName == "Bench Press")
        #expect(current.currentSetNumber == 1)
    }

    // MARK: - Helpers

    private func makeProgramFixture(context: ModelContext) -> (
        program: TrainingProgram,
        run: ProgramRun,
        primary: ProgramSessionExercise
    ) {
        let program = TrainingProgram(
            name: "Hardening Program",
            lengthInWeeks: 1,
            sessionsPerWeek: 2,
            createdDate: Date(),
            source: .aiGenerated
        )
        let week = ProgramWeekTemplate(weekNumber: 1)
        let session1 = ProgramSessionTemplate(sessionNumber: 1, sessionName: "Primary")
        let session2 = ProgramSessionTemplate(sessionNumber: 2, sessionName: "Secondary")
        let primary = ProgramSessionExercise(
            syncStableID: "primary-row",
            syncVersion: 3,
            exerciseName: "Bench Press",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 5,
            prescribedWeight: 200,
            prescribedWeightUnit: "lbs",
            explainabilityPurpose: .volumeFill,
            explainabilitySelectionReason: .recoveryBias
        )
        let secondary = ProgramSessionExercise(
            exerciseName: "Barbell Row",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 8,
            prescribedWeight: 135,
            prescribedWeightUnit: "lbs",
            explainabilityPurpose: .specificity,
            explainabilitySelectionReason: .sessionSpecificity
        )
        session1.exercises = [primary]
        session2.exercises = [secondary]
        primary.session = session1
        secondary.session = session2
        week.sessions = [session1, session2]
        session1.week = week
        session2.week = week
        program.weeks = [week]
        week.program = program

        let run = ProgramRun(startDate: Date(), isCompleted: false)
        run.program = program

        context.insert(program)
        context.insert(week)
        context.insert(session1)
        context.insert(session2)
        context.insert(primary)
        context.insert(secondary)
        context.insert(run)
        try? context.save()
        return (program, run, primary)
    }

    private func makePlan(labels: [String], usedProgram: Bool) -> TodayPlan {
        TodayPlan(
            recommendation: makeRecommendation(type: .runAsPlanned),
            confidence: .medium,
            confidenceRationale: "test",
            attribution: TodayPlanSourceAttribution(
                manualReadinessInfluence: "test",
                healthKitInfluence: "test",
                programPrescriptionInfluence: "test",
                adaptiveOverlayInfluence: "test",
                recentHistoryInfluence: "test",
                activeSourceLabels: labels,
                influenceFlags: TodayPlanInfluenceFlags(
                    usedActiveProgramContext: usedProgram,
                    usedApprovedOverlayContext: labels.contains("Approved Overlays"),
                    usedPendingProposalContext: labels.contains("Proposals"),
                    usedRuntimeCoachAdjustment: false,
                    usedRecentHistoryContext: labels.contains("Training History"),
                    usedHealthKitRecoveryNudge: labels.contains("Health Data")
                )
            ),
            adherenceRescue: nil,
            whyToday: "test",
            whatChangedToday: "test",
            changeSummary: TodayPlanChangeSummary(
                changeType: .combinedInfluence,
                headline: "test",
                details: ["test"]
            ),
            proposalAwareness: [],
            nextStepGuidance: TodayPlanNextStepGuidance(
                contextMode: usedProgram ? .activeProgram : .standaloneHistoryInformed,
                headline: "test",
                actions: []
            )
        )
    }

    private func makeRecommendation(type: DailySuggestionType) -> DailyCoachRecommendation {
        DailyCoachRecommendation(
            compactSummary: "test",
            expandedDetails: "test",
            primarySuggestion: DailyCoachSuggestionItem(type: type, compactText: "Run session", expandedText: "Run session"),
            secondarySuggestions: [],
            readinessTier: .neutral,
            hasPainFlag: false,
            nextProgramSession: NextProgramSessionInfo(
                weekNumber: 1,
                sessionNumber: 1,
                sessionName: "Primary",
                programName: "Hardening Program"
            ),
            standaloneSessionType: nil,
            pendingProposalCount: 0,
            objectiveRecoveryInsight: nil,
            recommendationSources: [],
            sourceAttributionDetails: ""
        )
    }

    private func makePartialEntry(name: String, orderIndex: Int) -> DraftExerciseEntry {
        DraftExerciseEntry(
            exerciseName: name,
            unit: .lbs,
            orderIndex: orderIndex,
            sets: [DraftSet(setNumber: 1)],
            prescribedTargetReps: 5,
            prescribedWeight: 185,
            prescribedWeightUnit: "lbs"
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
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
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw Prompt7UnwrapError.nilValue }
        return value
    }
}

private enum Prompt7UnwrapError: Error {
    case nilValue
}
