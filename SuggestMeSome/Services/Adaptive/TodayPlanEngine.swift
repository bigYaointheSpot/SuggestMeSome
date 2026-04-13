//
//  TodayPlanEngine.swift
//  SuggestMeSome
//
//  Feature 10 Prompt 6 — Today Plan orchestration layer.
//  Single entry point that assembles a TodayPlan from all available coaching
//  signals. Deterministic, non-mutating, and surface-agnostic (iPhone + Watch).
//

import Foundation

// MARK: - TodayPlanEngine

struct TodayPlanEngine {

    // MARK: - Public Entry Point

    /// Build a complete TodayPlan from all available coaching signals.
    ///
    /// All parameters are optional so the engine degrades gracefully when data is absent.
    static func buildPlan(
        checkIn: DailyCoachCheckIn?,
        activeRun: ProgramRun?,
        latestAnalysis: WeeklyTrainingAnalysis?,
        pendingProposalCount: Int,
        pendingProposals: [AdaptationProposal] = [],
        activeOverlays: [AppliedProgramOverlay] = [],
        recentWorkouts: [Workout],
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?,
        completedSessions: Set<ProgramSessionCompletionKey>? = nil,
        completedWorkoutCountForRun: Int = 0
    ) -> TodayPlan {

        // ── Step 1: Core recommendation (existing engine, unchanged) ──────
        let recommendation = DailyCoachRecommendationService.generate(
            checkIn: checkIn,
            activeRun: activeRun,
            latestAnalysis: latestAnalysis,
            pendingProposalCount: pendingProposalCount,
            recentWorkouts: recentWorkouts,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            completedProgramSessions: completedSessions
        )

        // ── Step 2: Confidence scoring ────────────────────────────────────
        let (confidence, confidenceRationale) = computeConfidence(
            checkIn: checkIn,
            activeRun: activeRun,
            latestAnalysis: latestAnalysis,
            recentWorkouts: recentWorkouts,
            completedWorkoutCountForRun: completedWorkoutCountForRun
        )

        // ── Step 3: Source attribution ─────────────────────────────────────
        let overlayContext = TodayPlanExplanationAssembler.overlayContext(
            activeRun: activeRun,
            activeOverlays: activeOverlays,
            nextSession: recommendation.nextProgramSession
        )
        let attribution = buildAttribution(
            recommendation: recommendation,
            checkIn: checkIn,
            activeRun: activeRun,
            pendingProposalCount: pendingProposalCount,
            recentWorkouts: recentWorkouts,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            overlayContext: overlayContext
        )

        // ── Step 4: Adherence rescue ──────────────────────────────────────
        let adherenceRescue = AdherenceRescueService.evaluate(
            run: activeRun,
            program: activeRun?.program,
            completedWorkoutCount: completedWorkoutCountForRun
        )
        // Only surface rescue when actually behind — on-track rescue is informational only
        let surfacedRescue: AdherenceRescue?
        if let rescue = adherenceRescue, rescue.sessionsBehindCount > 0 {
            surfacedRescue = rescue
        } else {
            surfacedRescue = nil
        }

        // ── Step 5: Explainability text ───────────────────────────────────
        let whyToday = TodayPlanExplanationAssembler.buildWhyToday(
            recommendation: recommendation,
            checkIn: checkIn,
            activeRun: activeRun,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            adherenceRescue: surfacedRescue
        )
        let proposalAwareness = TodayPlanExplanationAssembler.buildProposalAwareness(
            pendingProposals: pendingProposals,
            activeRun: activeRun,
            nextSession: recommendation.nextProgramSession
        )
        let changeSummary = TodayPlanExplanationAssembler.buildChangeSummary(
            recommendation: recommendation,
            checkIn: checkIn,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            adherenceRescue: surfacedRescue,
            overlayContext: overlayContext,
            proposalAwareness: proposalAwareness,
            pendingProposalCount: pendingProposalCount
        )
        let whatChangedToday = changeSummary.compactText
        let nextStepGuidance = TodayPlanExplanationAssembler.buildNextStepGuidance(
            recommendation: recommendation,
            confidence: confidence,
            checkIn: checkIn,
            activeRun: activeRun,
            recentWorkouts: recentWorkouts
        )

        return TodayPlan(
            recommendation: recommendation,
            confidence: confidence,
            confidenceRationale: confidenceRationale,
            attribution: attribution,
            adherenceRescue: surfacedRescue,
            whyToday: whyToday,
            whatChangedToday: whatChangedToday,
            changeSummary: changeSummary,
            proposalAwareness: proposalAwareness,
            nextStepGuidance: nextStepGuidance
        )
    }

    // MARK: - Confidence Scoring

    /// Deterministic confidence classification based on actual signal quality.
    ///
    /// High:
    ///   - Active program + recent program-linked workouts (≥ 1) + today check-in
    ///   - OR: active program + weekly analysis data + today check-in
    ///
    /// Medium:
    ///   - Active program but no recent program-linked workouts (new program run)
    ///   - OR: standalone user with check-in and ≥ 3 recent workouts
    ///   - OR: standalone user with check-in but no weekly analysis (sparse history)
    ///
    /// Low:
    ///   - No check-in AND no active program AND fewer than 3 recent workouts
    ///   - OR: no check-in AND no weekly analysis data
    static func computeConfidence(
        checkIn: DailyCoachCheckIn?,
        activeRun: ProgramRun?,
        latestAnalysis: WeeklyTrainingAnalysis?,
        recentWorkouts: [Workout],
        completedWorkoutCountForRun: Int
    ) -> (TodayPlanConfidence, String) {
        let hasCheckIn = checkIn != nil
        let hasProgram = activeRun?.program != nil
        let hasProgramHistory = hasProgram && completedWorkoutCountForRun > 0
        let hasWeeklyAnalysis = latestAnalysis != nil
        let recentWorkoutCount = recentWorkouts.count

        // High confidence: program + program history + check-in
        if hasProgram && hasProgramHistory && hasCheckIn {
            return (.high, "Active program with \(completedWorkoutCountForRun) logged session\(completedWorkoutCountForRun == 1 ? "" : "s") and today's check-in. All primary coaching signals are present.")
        }

        // High confidence: program + weekly analysis + check-in
        if hasProgram && hasWeeklyAnalysis && hasCheckIn {
            return (.high, "Active program with weekly analysis data and today's check-in. Strong signal quality.")
        }

        // Medium confidence: program exists but limited history
        if hasProgram && hasCheckIn {
            return (.medium, "Active program with today's check-in, but limited program history so far. Confidence will increase as sessions are logged.")
        }

        // Medium confidence: standalone with decent history + check-in
        if !hasProgram && hasCheckIn && recentWorkoutCount >= 3 {
            return (.medium, "Check-in submitted and \(recentWorkoutCount) recent workouts on file. No active program — recommendation is history-informed but broader.")
        }

        // Medium confidence: program + analysis but no check-in
        if hasProgram && hasWeeklyAnalysis {
            return (.medium, "Active program and weekly analysis data are available, but no check-in was submitted today. Readiness is assumed neutral.")
        }

        // Low confidence: no check-in + no analysis or sparse history
        if !hasCheckIn && !hasWeeklyAnalysis {
            return (.low, "No check-in and no weekly analysis data. Recommendation is based on defaults and available training history only.")
        }

        if !hasCheckIn && recentWorkoutCount < 3 {
            return (.low, "No check-in today and fewer than 3 recent workouts on file. Sparse signal — recommendation is conservative by default.")
        }

        // Fallback: medium
        return (.medium, "Partial signals available. Submit a daily check-in to improve recommendation quality.")
    }

    // MARK: - Source Attribution

    static func buildAttribution(
        recommendation: DailyCoachRecommendation,
        checkIn: DailyCoachCheckIn?,
        activeRun: ProgramRun?,
        pendingProposalCount: Int,
        recentWorkouts: [Workout],
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?,
        overlayContext: TodayPlanOverlayInfluenceContext = TodayPlanOverlayInfluenceContext(
            activeOverlayCount: 0,
            overlaysAffectingTodayCount: 0
        )
    ) -> TodayPlanSourceAttribution {
        TodayPlanExplanationAssembler.buildAttribution(
            recommendation: recommendation,
            checkIn: checkIn,
            activeRun: activeRun,
            pendingProposalCount: pendingProposalCount,
            recentWorkouts: recentWorkouts,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            overlayContext: overlayContext
        )
    }

    static func buildAttribution(
        checkIn: DailyCoachCheckIn?,
        activeRun: ProgramRun?,
        pendingProposalCount: Int,
        recentWorkouts: [Workout],
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?
    ) -> TodayPlanSourceAttribution {
        let recommendation = DailyCoachRecommendationService.generate(
            checkIn: checkIn,
            activeRun: activeRun,
            latestAnalysis: nil,
            pendingProposalCount: pendingProposalCount,
            recentWorkouts: recentWorkouts,
            objectiveRecoveryInsight: objectiveRecoveryInsight
        )
        return buildAttribution(
            recommendation: recommendation,
            checkIn: checkIn,
            activeRun: activeRun,
            pendingProposalCount: pendingProposalCount,
            recentWorkouts: recentWorkouts,
            objectiveRecoveryInsight: objectiveRecoveryInsight
        )
    }

    // MARK: - Explainability Text

    static func buildWhyToday(
        recommendation: DailyCoachRecommendation,
        checkIn: DailyCoachCheckIn?,
        activeRun: ProgramRun?,
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?,
        adherenceRescue: AdherenceRescue?
    ) -> String {
        TodayPlanExplanationAssembler.buildWhyToday(
            recommendation: recommendation,
            checkIn: checkIn,
            activeRun: activeRun,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            adherenceRescue: adherenceRescue
        )
    }

    static func buildWhatChangedToday(
        recommendation: DailyCoachRecommendation,
        checkIn: DailyCoachCheckIn?,
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?,
        adherenceRescue: AdherenceRescue?,
        pendingProposalCount: Int,
        overlayContext: TodayPlanOverlayInfluenceContext = TodayPlanOverlayInfluenceContext(
            activeOverlayCount: 0,
            overlaysAffectingTodayCount: 0
        ),
        proposalAwareness: [TodayPlanProposalAwarenessItem] = []
    ) -> String {
        TodayPlanExplanationAssembler.buildChangeSummary(
            recommendation: recommendation,
            checkIn: checkIn,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            adherenceRescue: adherenceRescue,
            overlayContext: overlayContext,
            proposalAwareness: proposalAwareness,
            pendingProposalCount: pendingProposalCount
        ).compactText
    }
}
