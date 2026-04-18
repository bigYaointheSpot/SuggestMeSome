import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
struct Feature15Prompt5CoachVoicePresentationTests {

    @Test func dailyPlanCopySeparatesHeadlineActionAndReason() {
        let plan = makeTodayPlan(
            compact: "Low readiness. Run Week 1, Session 1 conservatively today.",
            primary: "Low readiness - run Week 1, Session 1 and drop one backoff set.",
            expanded: "Keep the session conservative and avoid forcing progression.",
            whyToday: "Readiness is low, recent training is intact, and the program still points to your next lower session.",
            changeSummary: TodayPlanChangeSummary(
                changeType: .runtimeOnlyAdjustment,
                headline: "Daily Coach trimmed the session a bit today.",
                details: ["Low readiness trimmed one backoff set."]
            )
        )

        let copy = CoachPresentationService.dailyPlan(for: plan)

        #expect(copy.headline == "Low readiness. Run Week 1, Session 1 conservatively today.")
        #expect(copy.action == "Low readiness - run Week 1, Session 1 and drop one backoff set.")
        #expect(copy.whyShort == "Daily Coach trimmed the session a bit today.")
        #expect(copy.whyShort != copy.headline)
        #expect(copy.whyShort != copy.action)
        #expect(copy.detailSections.map(\.title) == ["Why this fits", "How to run it", "What changed", "Next step"])
    }

    @Test func sessionRecommendationCopyStaysActionForwardAndCompact() {
        let recommendation = SuggestMeSomeSessionRecommendation(
            title: "Upper Pull Reset",
            summary: "This session keeps your main pull pattern in rotation without piling more pressing stress on top.",
            rationale: "It supports your next planned session while giving your pressing pattern a break. Recent training already pushed upper-body pressing volume high.",
            reasonChips: ["Program-aware", "High recent overlap"],
            wasRedirected: true,
            mode: .pull,
            goal: .strength,
            continuitySummary: "You hit pressing hard recently, so today leans on pulls and bracing work.",
            nextActionGuidance: "Build this session and keep the first pull as the anchor.",
            recommendedMovementPriorities: ["Horizontal pull"],
            candidateExerciseFamilies: ["Rows"],
            candidateAnchorLifts: ["Barbell Row"],
            isBuildableIntoWorkout: true,
            request: nil,
            explanationBundle: nil
        )

        let copy = CoachPresentationService.sessionRecommendation(for: recommendation)

        #expect(copy.headline == recommendation.summary)
        #expect(copy.action == recommendation.nextActionGuidance)
        #expect(copy.whyShort == "You hit pressing hard recently, so today leans on pulls and bracing work.")
        #expect(copy.detailSections.first?.title == "Why this fits")
        #expect(copy.detailSections.first?.items.count == 2)
    }

    @Test func nextBlockAndLongHorizonCopiesStayTight() {
        let nextBlock = makeNextBlockRecommendation()
        let nextBlockCopy = CoachPresentationService.nextBlockRecommendation(for: nextBlock)

        #expect(nextBlockCopy.action == "Run Powerbuilding for 6 weeks at 4x/week.")
        #expect(nextBlockCopy.detailSections.first?.items.count == 2)

        let longHorizon = LongHorizonAdaptationSummary(
            anchorProgramRunStableID: "run-1",
            includedProgramRunStableIDs: ["run-1", "run-2"],
            blockCount: 2,
            includedStandaloneWorkoutCount: 3,
            headline: "You kept training best when the block stayed simple and repeatable.",
            insights: [
                LongHorizonAdaptationInsight(
                    kind: .missedSessionPattern,
                    title: "Missed sessions clustered on the longest weeks",
                    detail: "The 5-day weeks created the most missed sessions."
                ),
                LongHorizonAdaptationInsight(
                    kind: .movementContinuity,
                    title: "Anchors stayed sticky",
                    detail: "Squat and row anchors carried cleanly across both blocks."
                ),
                LongHorizonAdaptationInsight(
                    kind: .toleratedFrequency,
                    title: "Four days held best",
                    detail: "Your adherence stayed highest when the week stayed at four sessions."
                )
            ]
        )

        let longHorizonCopy = CoachPresentationService.longHorizonSummary(for: longHorizon)

        #expect(longHorizonCopy.action == "Lower friction before you try to push the next block harder.")
        #expect(longHorizonCopy.detailSections.first?.items.count == 2)
    }

    @Test func watchSnapshotUsesSharedCoachPresentationCopy() {
        let plan = makeTodayPlan(
            compact: "Solid readiness. Run Week 2, Session 3 as planned.",
            primary: "Solid readiness. Run Week 2, Session 3 as planned.",
            expanded: "Nothing is pushing you to change the session up front.",
            whyToday: "Recent training, the active program, and today's check-in all line up.",
            changeSummary: TodayPlanChangeSummary(
                changeType: .noChanges,
                headline: "No notable changes from baseline.",
                details: []
            )
        )

        let snapshot = WatchPayloadMapper.makeTodayPlanSnapshot(from: plan)
        let copy = CoachPresentationService.dailyPlan(for: plan)

        #expect(snapshot.compactSummary == copy.headline)
        #expect(snapshot.primarySuggestionText == copy.action)
    }

    private func makeTodayPlan(
        compact: String,
        primary: String,
        expanded: String,
        whyToday: String,
        changeSummary: TodayPlanChangeSummary
    ) -> TodayPlan {
        TodayPlan(
            recommendation: DailyCoachRecommendation(
                compactSummary: compact,
                expandedDetails: expanded,
                primarySuggestion: DailyCoachSuggestionItem(
                    type: .trimOneBackoffSet,
                    compactText: primary,
                    expandedText: "Keep the main work and trim the least important stress."
                ),
                secondarySuggestions: [
                    DailyCoachSuggestionItem(
                        type: .trimAccessories,
                        compactText: "Trim one accessory if needed.",
                        expandedText: "If the session still feels heavy by the accessory work, cut the lowest-priority movement."
                    )
                ],
                readinessTier: .low,
                hasPainFlag: false,
                nextProgramSession: NextProgramSessionInfo(
                    weekNumber: 1,
                    sessionNumber: 1,
                    sessionName: "Lower A",
                    programName: "Coach Voice Test"
                ),
                standaloneSessionType: nil,
                pendingProposalCount: 1,
                objectiveRecoveryInsight: nil,
                recommendationSources: [.manualCheckIn, .trainingHistory],
                sourceAttributionDetails: "Manual check-in and recent history both influenced the plan."
            ),
            objectiveRecoveryEvaluation: .disabled(),
            confidence: .high,
            confidenceRationale: "Program, readiness, and recent history all aligned.",
            attribution: TodayPlanSourceAttribution(
                manualReadinessInfluence: "Low readiness nudged the session conservative.",
                healthKitInfluence: "No HealthKit nudge today.",
                programPrescriptionInfluence: "The next planned lower session stayed in place.",
                adaptiveOverlayInfluence: "No approved overlay changed today's prescription.",
                recentHistoryInfluence: "Recent adherence kept the same session slot active.",
                activeSourceLabels: ["Manual Check-In", "Program", "Training History"],
                influenceFlags: TodayPlanInfluenceFlags(
                    usedActiveProgramContext: true,
                    usedApprovedOverlayContext: false,
                    usedPendingProposalContext: false,
                    usedRuntimeCoachAdjustment: changeSummary.changeType != .noChanges,
                    usedRecentHistoryContext: true,
                    usedHealthKitRecoveryNudge: false
                )
            ),
            adherenceRescue: nil,
            whyToday: whyToday,
            whatChangedToday: changeSummary.details.joined(separator: " "),
            changeSummary: changeSummary,
            proposalAwareness: [],
            nextStepGuidance: TodayPlanNextStepGuidance(
                contextMode: .activeProgram,
                headline: "Stay with the next programmed lower session.",
                actions: ["Review the top set after warm-ups.", "Trim the last accessory if time runs short."]
            )
        )
    }

    private func makeNextBlockRecommendation() -> MesocycleNextBlockRecommendation {
        let prefill = MesocycleNextBlockPrefill(
            sourceProgramRunStableID: "run-1",
            focus: .powerbuilding,
            level: .intermediate,
            durationWeeks: 6,
            sessionsPerWeek: 4,
            oneRepMaxSuggestions: []
        )

        return MesocycleNextBlockRecommendation(
            stableID: "next-block-1",
            rank: 1,
            kind: .repeatFocus,
            title: "Keep the same focus, but clean up the weekly shape",
            summary: "Powerbuilding still fits best, but the next block should stay tighter and more repeatable.",
            rationale: [
                "You kept the strongest adherence when the week stayed at four sessions.",
                "Your main lifts still progressed inside the current focus.",
                "The last block only needs a small cleanup rather than a full pivot."
            ],
            targetFocus: .powerbuilding,
            targetFocusDisplayName: "Powerbuilding",
            suggestedLevel: .intermediate,
            suggestedDurationWeeks: 6,
            suggestedSessionsPerWeek: 4,
            decision: .pending,
            prefill: prefill,
            isPrimaryRecommendation: true,
            fitScore: 88,
            fitNote: "Strong fit",
            requiresExplicitAcceptance: true,
            explanationBundle: nil
        )
    }
}
