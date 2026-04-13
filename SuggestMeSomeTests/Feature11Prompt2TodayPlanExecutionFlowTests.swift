//
//  Feature11Prompt2TodayPlanExecutionFlowTests.swift
//  SuggestMeSomeTests
//
//  Feature 11 Prompt 2 — Today Plan Review, Proposal Confirmation, and Launch Flow
//

import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature11Prompt2TodayPlanExecutionFlowTests {

    @Test func proposalRelevancePrefersTodayThenUpcoming() {
        let today = makeProposal(summary: "Today", priority: 20)
        let upcoming = makeProposal(summary: "Upcoming", priority: 90)
        let long = makeProposal(summary: "Long", priority: 100)

        let plan = makePlan(
            awareness: [
                TodayPlanProposalAwarenessItem(
                    proposalID: long.id,
                    summaryText: long.summaryText,
                    impact: .affectsLongHorizonProgramming,
                    targetDescription: "Week 5"
                ),
                TodayPlanProposalAwarenessItem(
                    proposalID: upcoming.id,
                    summaryText: upcoming.summaryText,
                    impact: .affectsUpcomingSession,
                    targetDescription: "Week 2, Session 2"
                ),
                TodayPlanProposalAwarenessItem(
                    proposalID: today.id,
                    summaryText: today.summaryText,
                    impact: .affectsToday,
                    targetDescription: "Week 1, Session 1"
                ),
            ]
        )

        let selected = TodayPlanActionCoordinator.relevantProposalForTodayPlan(
            pendingProposals: [upcoming, long, today],
            plan: plan
        )
        #expect(selected?.id == today.id)
    }

    @Test func compactReviewDecisionIsStagedBeforeCommit() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = makeProgram()
        context.insert(program)
        let run = ProgramRun(startDate: Date())
        run.program = program
        context.insert(run)

        let proposal = makeProposal(
            run: run,
            summary: "Downshift load",
            proposalType: .decreaseLoad,
            targetWeekStart: 1,
            targetSessionNumber: 1,
            proposedLoadPercentDelta: -0.05
        )
        context.insert(proposal)

        let staged = TodayPlanActionCoordinator.stageDecision(action: .approve, proposal: proposal)
        #expect(staged != nil)
        #expect(proposal.proposalStatus == .pendingUserConfirmation)

        if let staged {
            try TodayPlanActionCoordinator.commitStagedDecision(staged, proposal: proposal, context: context)
        }
        #expect(proposal.proposalStatus == .confirmed)
    }

    @Test func approveAndRejectActionHandlingUsesConfirmationService() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = makeProgram()
        context.insert(program)
        let run = ProgramRun(startDate: Date())
        run.program = program
        context.insert(run)

        let approveProposal = makeProposal(
            run: run,
            summary: "Approve me",
            proposalType: .decreaseLoad,
            targetWeekStart: 1,
            targetSessionNumber: 1,
            proposedLoadPercentDelta: -0.05
        )
        let rejectProposal = makeProposal(
            run: run,
            summary: "Reject me",
            proposalType: .decreaseLoad,
            targetWeekStart: 1,
            targetSessionNumber: 1,
            proposedLoadPercentDelta: -0.08
        )
        context.insert(approveProposal)
        context.insert(rejectProposal)

        if let stagedApprove = TodayPlanActionCoordinator.stageDecision(action: .approve, proposal: approveProposal) {
            try TodayPlanActionCoordinator.commitStagedDecision(stagedApprove, proposal: approveProposal, context: context)
        }
        if let stagedReject = TodayPlanActionCoordinator.stageDecision(action: .reject, proposal: rejectProposal) {
            try TodayPlanActionCoordinator.commitStagedDecision(stagedReject, proposal: rejectProposal, context: context)
        }

        #expect(approveProposal.proposalStatus == .confirmed)
        #expect(rejectProposal.proposalStatus == .rejected)
        #expect(!approveProposal.appliedOverlays.isEmpty)
    }

    @Test func launchPathSelectionChoosesPlannedRuntimeAndApprovedVariants() {
        let plannedRec = makeRecommendation(type: .runAsPlanned)
        let adjustedRec = makeRecommendation(type: .trimAccessories)

        let planned = TodayPlanActionCoordinator.resolveLaunch(
            request: .startAsPlanned,
            recommendation: plannedRec,
            hasOverlayAffectingToday: false
        )
        #expect(planned.path == .planned)
        #expect(planned.source == .plannedPrescription)
        #expect(planned.usesPreparedDraft == false)

        let runtime = TodayPlanActionCoordinator.resolveLaunch(
            request: .startRuntimeAdjusted,
            recommendation: adjustedRec,
            hasOverlayAffectingToday: false
        )
        #expect(runtime.path == .runtimeAdjusted)
        #expect(runtime.source == .runtimeCoachOnly)
        #expect(runtime.usesPreparedDraft == true)

        let approved = TodayPlanActionCoordinator.resolveLaunch(
            request: .startApprovedVersion,
            recommendation: plannedRec,
            hasOverlayAffectingToday: true
        )
        #expect(approved.path == .approvedOverlayAdjusted)
        #expect(approved.source == .approvedOverlay)
        #expect(approved.usesPreparedDraft == false)
    }

    @Test func sourceDistinctionTextCoversPlannedProposalOverlayAndRuntime() {
        let planned = TodayPlanActionCoordinator.sourceDescription(
            source: .plannedPrescription,
            hasRelevantPendingProposal: false
        )
        let pending = TodayPlanActionCoordinator.sourceDescription(
            source: .pendingProposal,
            hasRelevantPendingProposal: true
        )
        let overlay = TodayPlanActionCoordinator.sourceDescription(
            source: .approvedOverlay,
            hasRelevantPendingProposal: false
        )
        let runtime = TodayPlanActionCoordinator.sourceDescription(
            source: .runtimeCoachOnly,
            hasRelevantPendingProposal: false
        )

        #expect(planned.lowercased().contains("base program"))
        #expect(pending.lowercased().contains("pending proposal"))
        #expect(overlay.lowercased().contains("approved overlay"))
        #expect(runtime.lowercased().contains("runtime"))
    }

    // MARK: - Helpers

    private func makePlan(awareness: [TodayPlanProposalAwarenessItem]) -> TodayPlan {
        TodayPlan(
            recommendation: makeRecommendation(type: .runAsPlanned),
            confidence: .medium,
            confidenceRationale: "test",
            attribution: TodayPlanSourceAttribution(
                manualReadinessInfluence: "",
                healthKitInfluence: "",
                programPrescriptionInfluence: "",
                adaptiveOverlayInfluence: "",
                recentHistoryInfluence: "",
                activeSourceLabels: [],
                influenceFlags: TodayPlanInfluenceFlags(
                    usedActiveProgramContext: true,
                    usedApprovedOverlayContext: false,
                    usedPendingProposalContext: true,
                    usedRuntimeCoachAdjustment: false,
                    usedRecentHistoryContext: false,
                    usedHealthKitRecoveryNudge: false
                )
            ),
            adherenceRescue: nil,
            whyToday: "",
            whatChangedToday: "",
            changeSummary: TodayPlanChangeSummary(
                changeType: .pendingProposalRelevance,
                headline: "test",
                details: []
            ),
            proposalAwareness: awareness
        )
    }

    private func makeRecommendation(type: DailySuggestionType) -> DailyCoachRecommendation {
        DailyCoachRecommendation(
            compactSummary: "test",
            expandedDetails: "test",
            primarySuggestion: DailyCoachSuggestionItem(type: type, compactText: "x", expandedText: "y"),
            secondarySuggestions: [],
            readinessTier: .neutral,
            hasPainFlag: false,
            nextProgramSession: NextProgramSessionInfo(
                weekNumber: 1,
                sessionNumber: 1,
                sessionName: "Session",
                programName: "Program"
            ),
            standaloneSessionType: nil,
            pendingProposalCount: 0,
            objectiveRecoveryInsight: nil,
            recommendationSources: [],
            sourceAttributionDetails: ""
        )
    }

    private func makeProgram() -> TrainingProgram {
        TrainingProgram(
            name: "Execution Flow Program",
            lengthInWeeks: 8,
            sessionsPerWeek: 3,
            createdDate: Date(),
            source: .aiGenerated
        )
    }

    private func makeProposal(
        run: ProgramRun? = nil,
        summary: String,
        priority: Int = 80,
        proposalType: ProposalType = .decreaseLoad,
        targetWeekStart: Int = 1,
        targetSessionNumber: Int? = 1,
        proposedLoadPercentDelta: Double? = -0.05
    ) -> AdaptationProposal {
        AdaptationProposal(
            programRun: run,
            trainingProgram: run?.program,
            proposalType: proposalType,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.7,
            priority: priority,
            targetWeekStart: targetWeekStart,
            targetWeekEnd: targetWeekStart,
            targetSessionNumber: targetSessionNumber,
            proposedLoadPercentDelta: proposedLoadPercentDelta,
            adjustmentReason: .programSignalPriority,
            summaryText: summary
        )
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
