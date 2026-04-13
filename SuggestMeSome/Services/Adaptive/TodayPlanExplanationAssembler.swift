//
//  TodayPlanExplanationAssembler.swift
//  SuggestMeSome
//
//  Feature 11 Prompt 1 — Today Plan explanation and source-attribution assembly.
//  Separates explanation assembly from raw recommendation logic.
//

import Foundation

struct TodayPlanOverlayInfluenceContext {
    let activeOverlayCount: Int
    let overlaysAffectingTodayCount: Int
}

enum TodayPlanExplanationAssembler {
    static func buildAttribution(
        recommendation: DailyCoachRecommendation,
        checkIn: DailyCoachCheckIn?,
        activeRun: ProgramRun?,
        pendingProposalCount: Int,
        recentWorkouts: [Workout],
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?,
        overlayContext: TodayPlanOverlayInfluenceContext
    ) -> TodayPlanSourceAttribution {
        let manualInfluence: String
        if let c = checkIn {
            let tier = DailyCoachRecommendationService.computeReadinessTier(from: c)
            let tierLabel = readinessTierLabel(tier)
            let painNote = c.hasPainOrDiscomfort ? " Pain/discomfort was flagged — highest-priority runtime override." : ""
            manualInfluence = "Manual check-in submitted: \(tierLabel) readiness, \(c.availableTimeMinutes) min available.\(painNote)"
        } else {
            manualInfluence = "No check-in submitted today. Readiness defaults to neutral and available time defaults to 60 min."
        }

        let healthKitInfluence: String
        if let insight = objectiveRecoveryInsight {
            switch insight.status {
            case .good:
                healthKitInfluence = "HealthKit objective recovery: Good. Supported the recommendation without changing session shape."
            case .neutral:
                healthKitInfluence = "HealthKit objective recovery: Neutral. Near baseline and did not materially change today's recommendation."
            case .caution:
                healthKitInfluence = "HealthKit objective recovery: Caution. Applied a medium conservative nudge only; it does not override manual readiness."
            }
        } else {
            healthKitInfluence = "HealthKit signals unavailable or disabled. Daily Coach is running in baseline mode."
        }

        let programInfluence: String
        if let run = activeRun, let program = run.program {
            let weeksElapsed = max(
                0,
                Calendar.current.dateComponents([.weekOfYear], from: run.startDate, to: Date()).weekOfYear ?? 0
            )
            let currentWeek = min(weeksElapsed + 1, program.lengthInWeeks)
            programInfluence = "Active program context: \"\(program.name)\" (Week \(currentWeek)/\(program.lengthInWeeks), \(program.sessionsPerWeek)x/week). Session sequencing and prescriptions shape today's recommendation."
        } else {
            programInfluence = "No active program. Standalone session type was inferred from recent training history."
        }

        let overlayInfluence: String
        if overlayContext.activeOverlayCount == 0 {
            if pendingProposalCount > 0 {
                let plural = pendingProposalCount == 1 ? "" : "s"
                overlayInfluence = "No approved overlays are active today. \(pendingProposalCount) pending proposal\(plural) are awaiting review."
            } else {
                overlayInfluence = "No approved overlays or pending proposals are currently influencing today."
            }
        } else {
            let active = overlayContext.activeOverlayCount
            let affecting = overlayContext.overlaysAffectingTodayCount
            if affecting > 0 {
                overlayInfluence = "\(active) approved overlay\(active == 1 ? "" : "s") are active, and \(affecting) apply to today's target session."
            } else {
                overlayInfluence = "\(active) approved overlay\(active == 1 ? "" : "s") are active, but none directly target today's session."
            }
        }

        let historyInfluence: String
        let count = recentWorkouts.count
        if count == 0 {
            historyInfluence = "No recent workouts on file. Training-history context is limited."
        } else {
            historyInfluence = "\(count) recent workout\(count == 1 ? "" : "s") provided fatigue/frequency context."
        }

        var labels: [String] = []
        if checkIn != nil { labels.append("Manual Check-In") }
        if activeRun?.program != nil { labels.append("Program") }
        if overlayContext.activeOverlayCount > 0 { labels.append("Approved Overlays") }
        if pendingProposalCount > 0 { labels.append("Proposals") }
        if objectiveRecoveryInsight != nil { labels.append("Health Data") }
        if !recentWorkouts.isEmpty { labels.append("Training History") }

        let flags = TodayPlanInfluenceFlags(
            usedActiveProgramContext: activeRun?.program != nil,
            usedApprovedOverlayContext: overlayContext.overlaysAffectingTodayCount > 0,
            usedPendingProposalContext: pendingProposalCount > 0,
            usedRuntimeCoachAdjustment: recommendation.primarySuggestion.type != .runAsPlanned || recommendation.hasPainFlag,
            usedRecentHistoryContext: !recentWorkouts.isEmpty,
            usedHealthKitRecoveryNudge: objectiveRecoveryInsight?.status == .caution
        )

        return TodayPlanSourceAttribution(
            manualReadinessInfluence: manualInfluence,
            healthKitInfluence: healthKitInfluence,
            programPrescriptionInfluence: programInfluence,
            adaptiveOverlayInfluence: overlayInfluence,
            recentHistoryInfluence: historyInfluence,
            activeSourceLabels: labels,
            influenceFlags: flags
        )
    }

    static func buildWhyToday(
        recommendation: DailyCoachRecommendation,
        checkIn: DailyCoachCheckIn?,
        activeRun: ProgramRun?,
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?,
        adherenceRescue: AdherenceRescue?
    ) -> String {
        var parts: [String] = []

        if recommendation.hasPainFlag {
            return "Pain or discomfort was flagged in today's check-in. This is the highest-priority runtime signal and overrides normal session progression."
        }

        switch recommendation.readinessTier {
        case .strong:
            parts.append("Manual readiness is strong today.")
        case .neutral, .unknown:
            parts.append("Manual readiness is in a normal range today.")
        case .low:
            parts.append("Manual readiness is below normal today, so a conservative session shape is recommended.")
        }

        if let session = recommendation.nextProgramSession {
            parts.append("Active program context selected Week \(session.weekNumber), Session \(session.sessionNumber)\(session.sessionName.map { " (\($0))" } ?? "").")
        } else if let sessionType = recommendation.standaloneSessionType {
            parts.append("No active program is running, so a \(sessionType.rawValue.lowercased()) session was inferred from history and readiness.")
        } else if checkIn == nil && activeRun == nil {
            parts.append("No active program and no check-in were available, so baseline defaults were used.")
        }

        if let rescue = adherenceRescue {
            parts.append("Program adherence is \(rescue.sessionsBehindCount) session\(rescue.sessionsBehindCount == 1 ? "" : "s") behind expected pace; \(rescue.guidanceType.rawValue.lowercased()) guidance is active.")
        }

        if objectiveRecoveryInsight?.status == .caution {
            parts.append("HealthKit objective recovery is cautious, so the recommendation includes only a medium conservative nudge.")
        }

        parts.append(recommendation.primarySuggestion.compactText)
        return parts.joined(separator: " ")
    }

    static func buildProposalAwareness(
        pendingProposals: [AdaptationProposal],
        activeRun: ProgramRun?,
        nextSession: NextProgramSessionInfo?
    ) -> [TodayPlanProposalAwarenessItem] {
        pendingProposals.map { proposal in
            let impact = classifyProposalImpact(
                proposal: proposal,
                activeRun: activeRun,
                nextSession: nextSession
            )
            return TodayPlanProposalAwarenessItem(
                proposalID: proposal.id,
                summaryText: proposal.summaryText,
                impact: impact,
                targetDescription: targetDescription(for: proposal)
            )
        }
    }

    static func buildChangeSummary(
        recommendation: DailyCoachRecommendation,
        checkIn: DailyCoachCheckIn?,
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?,
        adherenceRescue: AdherenceRescue?,
        overlayContext: TodayPlanOverlayInfluenceContext,
        proposalAwareness: [TodayPlanProposalAwarenessItem],
        pendingProposalCount: Int
    ) -> TodayPlanChangeSummary {
        var details: [String] = []
        var hasRuntimeAdjustment = false
        var hasOverlayInfluence = false
        var hasProposalInfluence = false

        if recommendation.primarySuggestion.type != .runAsPlanned || recommendation.hasPainFlag {
            hasRuntimeAdjustment = true
        }

        if checkIn?.hasPainOrDiscomfort == true {
            details.append("Pain/discomfort flag triggered the highest-priority runtime override.")
        } else if let checkIn {
            let tier = DailyCoachRecommendationService.computeReadinessTier(from: checkIn)
            if tier == .low {
                details.append("Readiness is below normal, so runtime conservative adjustments were applied.")
            }
        }

        if objectiveRecoveryInsight?.status == .caution {
            hasRuntimeAdjustment = true
            details.append("HealthKit recovery showed caution and added a medium conservative nudge.")
        }

        if let rescue = adherenceRescue, rescue.sessionsBehindCount > 0 {
            hasRuntimeAdjustment = true
            details.append("Adherence guidance is active because pacing is \(rescue.sessionsBehindCount) session\(rescue.sessionsBehindCount == 1 ? "" : "s") behind.")
        }

        if overlayContext.overlaysAffectingTodayCount > 0 {
            hasOverlayInfluence = true
            details.append("\(overlayContext.overlaysAffectingTodayCount) approved overlay\(overlayContext.overlaysAffectingTodayCount == 1 ? "" : "s") are shaping today's session.")
        }

        if pendingProposalCount > 0 {
            hasProposalInfluence = true
            let todayCount = proposalAwareness.filter { $0.impact == .affectsToday }.count
            let upcomingCount = proposalAwareness.filter { $0.impact == .affectsUpcomingSession }.count
            if todayCount > 0 {
                details.append("\(todayCount) pending proposal\(todayCount == 1 ? "" : "s") appear to affect today's session and need review.")
            } else if upcomingCount > 0 {
                details.append("\(upcomingCount) pending proposal\(upcomingCount == 1 ? "" : "s") target upcoming sessions.")
            } else {
                details.append("\(pendingProposalCount) pending proposal\(pendingProposalCount == 1 ? "" : "s") apply to longer-horizon programming.")
            }
        }

        let type: TodayPlanChangeType
        let headline: String
        if details.isEmpty {
            type = .noChanges
            headline = "No notable changes from baseline."
        } else if hasRuntimeAdjustment && !hasOverlayInfluence && !hasProposalInfluence {
            type = .runtimeOnlyAdjustment
            headline = "Runtime Daily Coach adjustments are active."
        } else if hasOverlayInfluence && !hasProposalInfluence && !hasRuntimeAdjustment {
            type = .approvedOverlayInfluence
            headline = "Approved overlays are influencing today's session."
        } else if hasProposalInfluence && !hasOverlayInfluence && !hasRuntimeAdjustment {
            type = .pendingProposalRelevance
            headline = "Pending proposals are relevant to today's planning."
        } else if hasOverlayInfluence && !hasRuntimeAdjustment {
            type = .approvedOverlayInfluence
            headline = "Approved overlays are influencing session planning."
        } else if hasProposalInfluence && !hasRuntimeAdjustment {
            type = .pendingProposalRelevance
            headline = "Pending proposals are influencing session planning."
        } else {
            type = .combinedInfluence
            headline = "Multiple signals changed today's plan."
        }

        return TodayPlanChangeSummary(changeType: type, headline: headline, details: details)
    }

    static func buildNextStepGuidance(
        recommendation: DailyCoachRecommendation,
        confidence: TodayPlanConfidence,
        checkIn: DailyCoachCheckIn?,
        activeRun: ProgramRun?,
        recentWorkouts: [Workout]
    ) -> TodayPlanNextStepGuidance {
        if activeRun?.program != nil {
            return TodayPlanNextStepGuidance(
                contextMode: .activeProgram,
                headline: "Program session guidance is available for today.",
                actions: [
                    "Run the next programmed session and keep effort feedback accurate.",
                    "If today's recommendation feels off, review the suggested version before starting.",
                    "Complete a daily check-in before the next session to keep confidence high."
                ]
            )
        }

        let hasStrongStandaloneSignal = confidence != .low
            || checkIn != nil
            || recentWorkouts.count >= 3

        if hasStrongStandaloneSignal {
            let sessionLabel = recommendation.standaloneSessionType?.rawValue ?? "Standalone"
            return TodayPlanNextStepGuidance(
                contextMode: .standaloneHistoryInformed,
                headline: "No active program. Today's \(sessionLabel.lowercased()) recommendation is history-informed.",
                actions: [
                    "Use SuggestMeSome with today's mode/intensity to keep session continuity.",
                    "Log effort feedback so the next standalone recommendation can progress or downshift intentionally.",
                    "Check in before your next session to improve readiness-based adjustments."
                ]
            )
        }

        return TodayPlanNextStepGuidance(
            contextMode: .standaloneLowConfidence,
            headline: "No active program and sparse inputs. Today's recommendation is a conservative baseline guess.",
            actions: [
                "Complete a daily check-in before training to improve recommendation quality.",
                "Keep this session moderate and log the result to establish history.",
                "After 2-3 logged sessions, expect more specific standalone guidance."
            ]
        )
    }

    static func overlayContext(
        activeRun: ProgramRun?,
        activeOverlays: [AppliedProgramOverlay],
        nextSession: NextProgramSessionInfo?
    ) -> TodayPlanOverlayInfluenceContext {
        guard let activeRun else {
            return TodayPlanOverlayInfluenceContext(activeOverlayCount: 0, overlaysAffectingTodayCount: 0)
        }

        let active = activeOverlays.filter {
            $0.programRun?.id == activeRun.id && $0.overlayStatus == .active
        }

        guard let nextSession else {
            return TodayPlanOverlayInfluenceContext(activeOverlayCount: active.count, overlaysAffectingTodayCount: 0)
        }

        let affectingToday = active.filter {
            overlayAffectsSession($0, week: nextSession.weekNumber, session: nextSession.sessionNumber)
        }.count

        return TodayPlanOverlayInfluenceContext(
            activeOverlayCount: active.count,
            overlaysAffectingTodayCount: affectingToday
        )
    }

    // MARK: - Helpers

    private static func classifyProposalImpact(
        proposal: AdaptationProposal,
        activeRun: ProgramRun?,
        nextSession: NextProgramSessionInfo?
    ) -> TodayPlanProposalImpact {
        guard activeRun?.id == proposal.programRun?.id else {
            return .affectsLongHorizonProgramming
        }

        if let nextSession, proposalTargetsSession(proposal, week: nextSession.weekNumber, session: nextSession.sessionNumber) {
            return .affectsToday
        }

        let currentWeek = currentProgramWeek(for: activeRun)
        let start = proposal.targetWeekStart
        let end = max(start, proposal.targetWeekEnd ?? start)
        let upcomingWindowEnd = currentWeek + 1
        if end >= currentWeek && start <= upcomingWindowEnd {
            return .affectsUpcomingSession
        }

        return .affectsLongHorizonProgramming
    }

    private static func targetDescription(for proposal: AdaptationProposal) -> String {
        if let session = proposal.targetSessionNumber {
            return "Week \(proposal.targetWeekStart), Session \(session)"
        }
        let end = max(proposal.targetWeekStart, proposal.targetWeekEnd ?? proposal.targetWeekStart)
        if end > proposal.targetWeekStart {
            return "Weeks \(proposal.targetWeekStart)-\(end)"
        }
        return "Week \(proposal.targetWeekStart)"
    }

    private static func currentProgramWeek(for run: ProgramRun?) -> Int {
        guard let run else { return 1 }
        let elapsed = Calendar.current.dateComponents([.weekOfYear], from: run.startDate, to: Date()).weekOfYear ?? 0
        return max(1, elapsed + 1)
    }

    private static func proposalTargetsSession(
        _ proposal: AdaptationProposal,
        week: Int,
        session: Int
    ) -> Bool {
        guard proposal.targetWeekStart <= week else { return false }
        let weekEnd = max(proposal.targetWeekStart, proposal.targetWeekEnd ?? proposal.targetWeekStart)
        guard weekEnd >= week else { return false }
        if let targetSession = proposal.targetSessionNumber {
            return targetSession == session
        }
        return true
    }

    private static func overlayAffectsSession(
        _ overlay: AppliedProgramOverlay,
        week: Int,
        session: Int
    ) -> Bool {
        guard overlay.effectiveWeekStart <= week else { return false }
        let weekEnd = max(overlay.effectiveWeekStart, overlay.effectiveWeekEnd ?? overlay.effectiveWeekStart)
        guard weekEnd >= week else { return false }

        if overlay.adjustments.isEmpty {
            return true
        }

        return overlay.adjustments.contains { adjustment in
            let weekMatch = adjustment.targetWeekNumber == nil || adjustment.targetWeekNumber == week
            let sessionMatch = adjustment.targetSessionNumber == nil || adjustment.targetSessionNumber == session
            return weekMatch && sessionMatch
        }
    }

    private static func readinessTierLabel(_ tier: ReadinessTier) -> String {
        switch tier {
        case .strong:  return "Strong"
        case .neutral: return "Neutral"
        case .low:     return "Low"
        case .unknown: return "Unknown"
        }
    }
}
