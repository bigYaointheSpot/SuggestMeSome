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
        let attribution = buildAttribution(
            checkIn: checkIn,
            activeRun: activeRun,
            pendingProposalCount: pendingProposalCount,
            recentWorkouts: recentWorkouts,
            objectiveRecoveryInsight: objectiveRecoveryInsight
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
        let whyToday = buildWhyToday(
            recommendation: recommendation,
            checkIn: checkIn,
            activeRun: activeRun,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            adherenceRescue: surfacedRescue
        )
        let whatChangedToday = buildWhatChangedToday(
            checkIn: checkIn,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            adherenceRescue: surfacedRescue,
            pendingProposalCount: pendingProposalCount
        )

        return TodayPlan(
            recommendation: recommendation,
            confidence: confidence,
            confidenceRationale: confidenceRationale,
            attribution: attribution,
            adherenceRescue: surfacedRescue,
            whyToday: whyToday,
            whatChangedToday: whatChangedToday
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
        checkIn: DailyCoachCheckIn?,
        activeRun: ProgramRun?,
        pendingProposalCount: Int,
        recentWorkouts: [Workout],
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?
    ) -> TodayPlanSourceAttribution {

        let manualInfluence: String
        if let c = checkIn {
            let tier = DailyCoachRecommendationService.computeReadinessTier(from: c)
            let tierLabel = readinessTierLabel(tier)
            let painNote = c.hasPainOrDiscomfort ? " Pain/discomfort was flagged — this is the highest-priority override." : ""
            manualInfluence = "Manual check-in submitted: \(tierLabel) readiness, \(c.availableTimeMinutes) min available.\(painNote)"
        } else {
            manualInfluence = "No check-in submitted today. Readiness defaults to neutral; available time defaults to 60 min."
        }

        let healthKitInfluence: String
        if let insight = objectiveRecoveryInsight {
            switch insight.status {
            case .good:
                healthKitInfluence = "HealthKit objective recovery: Good. Supported the existing plan without adjustment."
            case .neutral:
                healthKitInfluence = "HealthKit objective recovery: Neutral. Near baseline — no material change to the recommendation."
            case .caution:
                healthKitInfluence = "HealthKit objective recovery: Caution. Nudged today's recommendation slightly conservative (medium influence, cannot override manual readiness)."
            }
        } else {
            healthKitInfluence = "HealthKit signals unavailable or disabled. Daily Coach running in baseline mode."
        }

        let programInfluence: String
        if let run = activeRun, let program = run.program {
            let weeksElapsed = max(
                0,
                Calendar.current.dateComponents([.weekOfYear], from: run.startDate, to: Date()).weekOfYear ?? 0
            )
            let currentWeek = min(weeksElapsed + 1, program.lengthInWeeks)
            programInfluence = "Active program: \"\(program.name)\" (Week \(currentWeek)/\(program.lengthInWeeks), \(program.sessionsPerWeek)×/week). Session sequence and prescription targets inform today's session label."
        } else {
            programInfluence = "No active program. Standalone recommendation path is used — session type inferred from recent history."
        }

        let overlayInfluence: String
        if pendingProposalCount > 0 {
            let plural = pendingProposalCount == 1 ? "" : "s"
            overlayInfluence = "\(pendingProposalCount) pending adaptation proposal\(plural) awaiting review. Check the Proposals tab before training."
        } else {
            overlayInfluence = "No pending adaptation proposals. No overlay modifications are in effect today."
        }

        let historyInfluence: String
        let count = recentWorkouts.count
        if count == 0 {
            historyInfluence = "No recent workouts on file. Training history context unavailable — this is your first session or history has been cleared."
        } else {
            historyInfluence = "\(count) recent workout\(count == 1 ? "" : "s") on file, providing fatigue context and session frequency patterns."
        }

        // Build visible source labels
        var labels: [String] = []
        if checkIn != nil { labels.append("Manual Check-In") }
        if activeRun?.program != nil { labels.append("Program") }
        if objectiveRecoveryInsight != nil { labels.append("Health Data") }
        if !recentWorkouts.isEmpty { labels.append("Training History") }
        if pendingProposalCount > 0 { labels.append("Proposals") }

        return TodayPlanSourceAttribution(
            manualReadinessInfluence: manualInfluence,
            healthKitInfluence: healthKitInfluence,
            programPrescriptionInfluence: programInfluence,
            adaptiveOverlayInfluence: overlayInfluence,
            recentHistoryInfluence: historyInfluence,
            activeSourceLabels: labels
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
        var parts: [String] = []

        // Pain override always dominates the why
        if recommendation.hasPainFlag {
            return "Pain or discomfort was flagged in today's check-in. This is the highest-priority signal — all other recommendations are superseded. Review the session manually and prioritise keeping pain out of training."
        }

        // Readiness context
        switch recommendation.readinessTier {
        case .strong:
            parts.append("Your composite readiness is strong today.")
        case .neutral, .unknown:
            parts.append("Your readiness is in a normal range today.")
        case .low:
            parts.append("Your composite readiness is low today, warranting a conservative approach.")
        }

        // Program context
        if let session = recommendation.nextProgramSession {
            parts.append("The next scheduled session in \(session.programName) is Week \(session.weekNumber), Session \(session.sessionNumber)\(session.sessionName.map { " — \($0)" } ?? "").")
        } else if let sessionType = recommendation.standaloneSessionType {
            parts.append("No active program — a \(sessionType.rawValue.lowercased()) session was inferred from your recent training history.")
        }

        // Adherence rescue context
        if let rescue = adherenceRescue {
            parts.append("You are currently \(rescue.sessionsBehindCount) session\(rescue.sessionsBehindCount == 1 ? "" : "s") behind the expected program pace. \(rescue.guidanceType == .conservativeResume ? "A conservative resume approach is recommended to re-establish your training pattern." : "Trimming today's session slightly will help you re-sync with the program.")")
        }

        // HealthKit context (medium influence, brief mention)
        if let insight = objectiveRecoveryInsight, insight.status == .caution {
            parts.append("Objective recovery data (HealthKit) shows mild caution, providing a slight conservative nudge.")
        }

        // Primary suggestion framing
        parts.append(recommendation.primarySuggestion.compactText)

        return parts.joined(separator: " ")
    }

    static func buildWhatChangedToday(
        checkIn: DailyCoachCheckIn?,
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?,
        adherenceRescue: AdherenceRescue?,
        pendingProposalCount: Int
    ) -> String {
        var changes: [String] = []

        // Pain is the highest-priority change signal
        if checkIn?.hasPainOrDiscomfort == true {
            changes.append("Pain or discomfort flagged — highest priority override active.")
        }

        // Low readiness is a notable departure from neutral
        if let checkIn {
            let tier = DailyCoachRecommendationService.computeReadinessTier(from: checkIn)
            if tier == .low {
                changes.append("Readiness check-in is below normal — conservative session adjustments applied.")
            } else if tier == .strong {
                changes.append("Readiness check-in is above normal — full session recommended with no reductions.")
            }
        }

        // HealthKit caution
        if objectiveRecoveryInsight?.status == .caution {
            changes.append("HealthKit objective recovery shows mild caution — slight conservative nudge applied.")
        }

        // Adherence rescue
        if let rescue = adherenceRescue, rescue.sessionsBehindCount > 0 {
            changes.append("Adherence alert: \(rescue.sessionsBehindCount) session\(rescue.sessionsBehindCount == 1 ? "" : "s") behind expected pace — \(rescue.guidanceType.rawValue) guidance active.")
        }

        // New proposals
        if pendingProposalCount > 0 {
            let plural = pendingProposalCount == 1 ? "" : "s"
            changes.append("\(pendingProposalCount) pending adaptation proposal\(plural) are awaiting your review.")
        }

        if changes.isEmpty {
            return ""
        }
        return changes.joined(separator: " ")
    }

    // MARK: - Helpers

    private static func readinessTierLabel(_ tier: ReadinessTier) -> String {
        switch tier {
        case .strong:  return "Strong"
        case .neutral: return "Neutral"
        case .low:     return "Low"
        case .unknown: return "Unknown"
        }
    }
}
