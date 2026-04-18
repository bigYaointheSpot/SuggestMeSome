//
//  DailyCoachRecommendationService.swift
//  SuggestMeSome
//
//  Feature 7 — Daily Coach recommendation engine.
//  Deterministic, purely additive service. Does not mutate any persisted models.
//

import Foundation
import SwiftData

// MARK: - DailyCoachRecommendationService

struct DailyCoachRecommendationService {

    // MARK: - Public Entry Point

    /// Generate today's coaching recommendation from available context signals.
    ///
    /// All parameters are optional so the engine degrades gracefully when data is absent.
    static func generate(
        checkIn: DailyCoachCheckIn?,
        activeRun: ProgramRun?,
        latestAnalysis: WeeklyTrainingAnalysis?,
        pendingProposalCount: Int,
        recentWorkouts: [Workout],
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?,
        completedProgramSessions: Set<ProgramSessionCompletionKey>? = nil
    ) -> DailyCoachRecommendation {

        let hasPain           = checkIn?.hasPainOrDiscomfort ?? false
        let availableMinutes  = checkIn?.availableTimeMinutes ?? 60
        let readinessTier     = computeReadinessTier(from: checkIn)
        let fatigueStatus     = latestAnalysis?.fatigueStatus ?? .manageable

        if let run = activeRun, let program = run.program {
            return generateProgramRecommendation(
                run: run,
                program: program,
                hasPain: hasPain,
                availableMinutes: availableMinutes,
                readinessTier: readinessTier,
                fatigueStatus: fatigueStatus,
                pendingProposalCount: pendingProposalCount,
                recentWorkouts: recentWorkouts,
                objectiveRecoveryInsight: objectiveRecoveryInsight,
                completedProgramSessions: completedProgramSessions
            )
        }

        return generateStandaloneRecommendation(
            hasPain: hasPain,
            availableMinutes: availableMinutes,
            readinessTier: readinessTier,
            fatigueStatus: fatigueStatus,
            pendingProposalCount: pendingProposalCount,
            recentWorkouts: recentWorkouts,
            objectiveRecoveryInsight: objectiveRecoveryInsight
        )
    }

    // MARK: - Readiness Computation

    /// Derives a readiness tier from a check-in's four 1–5 ratings.
    ///
    /// Composite = (sleep + energy + (6 − soreness) + (6 − stress)) / 4
    /// Range: 1.0 (worst) → 5.0 (best)
    static func computeReadinessTier(from checkIn: DailyCoachCheckIn?) -> ReadinessTier {
        guard let c = checkIn else { return .unknown }
        let rawSum = c.sleepQuality + c.energy + (6 - c.soreness) + (6 - c.stress)
        let composite = Double(rawSum) / 4.0
        switch composite {
        case 4.0...: return .strong
        case 2.5..<4.0: return .neutral
        default: return .low
        }
    }

    // MARK: - Program Path

    private static func generateProgramRecommendation(
        run: ProgramRun,
        program: TrainingProgram,
        hasPain: Bool,
        availableMinutes: Int,
        readinessTier: ReadinessTier,
        fatigueStatus: FatigueStatus,
        pendingProposalCount: Int,
        recentWorkouts: [Workout],
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?,
        completedProgramSessions: Set<ProgramSessionCompletionKey>?
    ) -> DailyCoachRecommendation {

        let nextSession  = detectNextSession(
            run: run,
            program: program,
            workouts: recentWorkouts,
            completedSessions: completedProgramSessions
        )
        let sessionLabel = sessionDisplayLabel(for: nextSession)

        let (primary, secondary, compact, expanded) = programSuggestions(
            sessionLabel: sessionLabel,
            hasPain: hasPain,
            availableMinutes: availableMinutes,
            readinessTier: readinessTier,
            fatigueStatus: fatigueStatus,
            pendingProposalCount: pendingProposalCount,
            objectiveRecoveryInsight: objectiveRecoveryInsight
        )

        let sources = buildSources(
            readinessTier: readinessTier,
            objectiveRecoveryInsight: objectiveRecoveryInsight
        )

        return DailyCoachRecommendation(
            compactSummary: compact,
            expandedDetails: expanded,
            primarySuggestion: primary,
            secondarySuggestions: secondary,
            readinessTier: readinessTier,
            hasPainFlag: hasPain,
            nextProgramSession: nextSession,
            standaloneSessionType: nil,
            pendingProposalCount: pendingProposalCount,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            recommendationSources: sources,
            sourceAttributionDetails: sourceAttributionText(
                hasPain: hasPain,
                readinessTier: readinessTier,
                objectiveRecoveryInsight: objectiveRecoveryInsight
            )
        )
    }

    private static func detectNextSession(
        run: ProgramRun,
        program: TrainingProgram,
        workouts: [Workout],
        completedSessions: Set<ProgramSessionCompletionKey>?
    ) -> NextProgramSessionInfo? {
        for wk in 1...program.lengthInWeeks {
            for sess in 1...program.sessionsPerWeek {
                let done: Bool
                if let completedSessions {
                    done = completedSessions.contains(
                        ProgramSessionCompletionKey(weekNumber: wk, sessionNumber: sess)
                    )
                } else {
                    done = workouts.contains {
                        $0.programRun?.id == run.id &&
                        $0.programWeekNumber == wk &&
                        $0.programSessionNumber == sess
                    }
                }
                if !done {
                    let sessionName = program.weeks
                        .first { $0.weekNumber == wk }?
                        .sessions
                        .first { $0.sessionNumber == sess }?
                        .sessionName
                    return NextProgramSessionInfo(
                        weekNumber: wk,
                        sessionNumber: sess,
                        sessionName: sessionName,
                        programName: program.name
                    )
                }
            }
        }
        // All sessions logged — wrap back to the start
        let firstName = program.weeks
            .first { $0.weekNumber == 1 }?
            .sessions
            .first { $0.sessionNumber == 1 }?
            .sessionName
        return NextProgramSessionInfo(weekNumber: 1, sessionNumber: 1, sessionName: firstName, programName: program.name)
    }

    private static func sessionDisplayLabel(for session: NextProgramSessionInfo?) -> String {
        guard let s = session else { return "Next Session" }
        let base = "Week \(s.weekNumber), Session \(s.sessionNumber)"
        if let name = s.sessionName, !name.isEmpty {
            return "\(base) — \(name)"
        }
        return base
    }

    // MARK: - Program Suggestion Rules

    /// Applies the five-tier priority rule chain and returns suggestion components.
    private static func programSuggestions(
        sessionLabel: String,
        hasPain: Bool,
        availableMinutes: Int,
        readinessTier: ReadinessTier,
        fatigueStatus: FatigueStatus,
        pendingProposalCount: Int,
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?
    ) -> (DailyCoachSuggestionItem, [DailyCoachSuggestionItem], String, String) {

        // ── Priority 1: Pain / discomfort ───────────────────────────────────
        if hasPain {
            let primary = DailyCoachSuggestionItem(
                type: .suggestManualVariationSwap,
                compactText: "Pain flagged - review before training.",
                expandedText: "You flagged pain or discomfort today. Keep the call manual: lower stress, swap to a pain-free variation, or skip the session if needed."
            )
            let secondary = [DailyCoachSuggestionItem(
                type: .trimAccessories,
                compactText: "If you train, keep only the main work.",
                expandedText: "If you still want to move, keep the session simple and drop accessory work that adds stress."
            )]
            return (
                primary,
                secondary,
                "Pain flagged. Review today's session before you train.",
                "Daily Coach will not auto-adjust around pain. Choose the lowest-stress option that feels controlled, including stopping entirely."
            )
        }

        // ── Priority 2: Severe time constraint (< 30 min) ──────────────────
        if availableMinutes < 30 {
            let primary = DailyCoachSuggestionItem(
                type: .trimAccessories,
                compactText: "Only \(availableMinutes) min - keep the primary lift + top set.",
                expandedText: "Your window is too short for the full session. Keep the main lift and top set, then move on."
            )
            return (
                primary,
                [],
                "Only \(availableMinutes) min available. Keep the primary lift + top set.",
                "Use the shortest version that still preserves the session's main intent. Backoff work and accessories can wait."
            )
        }

        // ── Priority 2 (cont): Moderate time pressure with elevated fatigue ─
        if availableMinutes < 45 && (fatigueStatus == .elevated || fatigueStatus == .high || fatigueStatus == .critical) {
            let primary = DailyCoachSuggestionItem(
                type: .trimAccessories,
                compactText: "Limited time + high fatigue - trim accessories.",
                expandedText: "Keep the main lift, top set, backoff work, and one high-value accessory. Drop the rest."
            )
            return (
                primary,
                [],
                "\(availableMinutes) min and fatigue is elevated. Run the main work and trim accessories.",
                "This keeps the session productive without stacking extra fatigue on a time-crunched day."
            )
        }

        // ── Priority 3: Low readiness ────────────────────────────────────────
        if readinessTier == .low {
            let isHighFatigue = fatigueStatus == .high || fatigueStatus == .critical
            let hasObjectiveCaution = objectiveRecoveryInsight?.status == .caution
            let primary: DailyCoachSuggestionItem
            if isHighFatigue {
                primary = DailyCoachSuggestionItem(
                    type: .reduceWorkingLoadsSlightly,
                    compactText: "Low readiness + high fatigue - reduce working loads 5-10%.",
                    expandedText: "Keep the main lift, reduce working loads 5-10%, and drop one backoff set. Focus on clean reps instead of pushing."
                )
            } else {
                primary = DailyCoachSuggestionItem(
                    type: .trimOneBackoffSet,
                    compactText: "Low readiness - run \(sessionLabel) and drop one backoff set.",
                    expandedText: "Keep the session intact, but remove the last backoff set from the primary lift. If you still feel flat later, trim the lowest-priority accessory."
                )
            }
            let secondary = [DailyCoachSuggestionItem(
                type: .trimAccessories,
                compactText: "If you still feel flat, trim one accessory.",
                expandedText: "If energy does not come around by the accessory work, drop the lowest-priority piece and finish there."
            )]
            let expanded = hasObjectiveCaution
                ? "Manual readiness is low, and objective recovery also shows caution. Keep the session conservative and avoid forcing progression."
                : "Manual readiness is low. Keep the session conservative and avoid forcing progression."
            return (
                primary,
                secondary,
                "Low readiness. Run \(sessionLabel) conservatively today.",
                expanded
            )
        }

        // ── Priority 4 & 5: Neutral / Strong readiness ───────────────────────
        var secondary: [DailyCoachSuggestionItem] = []
        if pendingProposalCount > 0 {
            let plural = pendingProposalCount == 1 ? "" : "s"
            secondary.append(DailyCoachSuggestionItem(
                type: .runAsPlanned,
                compactText: "\(pendingProposalCount) pending proposal\(plural) — check the Proposals tab.",
                expandedText: "You have \(pendingProposalCount) pending adaptation proposal\(plural) awaiting review. Check the Proposals tab before your session to see if any apply today."
            ))
        }

        if readinessTier == .strong {
            if objectiveRecoveryInsight?.status == .caution {
                let primary = DailyCoachSuggestionItem(
                    type: .trimOneBackoffSet,
                    compactText: "Strong check-in, but recovery is cautious - trim one backoff set.",
                    expandedText: "Manual readiness is strong, but objective recovery is a bit below baseline. Keep the session intact and trim one backoff set."
                )
                return (
                    primary,
                    secondary,
                    "Strong check-in with recovery caution. Run \(sessionLabel) with a small trim.",
                    "You still have a good day to train, but the recovery signal argues for a small buffer."
                )
            }

            let primary = DailyCoachSuggestionItem(
                type: .runAsPlanned,
                compactText: "Strong readiness. Run \(sessionLabel) hard.",
                expandedText: "Signals are favorable today. Run the full session and push the top work if warm-ups feel good."
            )
            return (
                primary,
                secondary,
                "Strong readiness. Run \(sessionLabel) as planned and lean in.",
                "This is a higher-readiness day. Keep quality high and use the session to drive progress."
            )
        }

        // Neutral (or unknown — treated same as neutral)
        let hasObjectiveCaution = objectiveRecoveryInsight?.status == .caution
        let primary = DailyCoachSuggestionItem(
            type: .runAsPlanned,
            compactText: hasObjectiveCaution
                ? "Solid readiness with recovery caution. Run \(sessionLabel) with a small buffer."
                : "Solid readiness. Run \(sessionLabel) as planned.",
            expandedText: hasObjectiveCaution
                ? "Keep the session as planned, but leave a little room on hard sets if they feel heavy."
                : "Nothing is pushing you to change the session up front. Let early working sets guide effort."
        )
        return (
            primary,
            secondary,
            hasObjectiveCaution
                ? "Solid readiness with recovery caution. Run \(sessionLabel) with controlled effort."
                : "Solid readiness. Run \(sessionLabel) as planned.",
            hasObjectiveCaution
                ? "The day still supports training. Just skip the all-out feel and keep reps clean."
                : "This looks like a normal training day. Stay attentive to bar speed and leave room to adjust in-session if needed."
        )
    }

    // MARK: - Standalone Path

    private static func generateStandaloneRecommendation(
        hasPain: Bool,
        availableMinutes: Int,
        readinessTier: ReadinessTier,
        fatigueStatus: FatigueStatus,
        pendingProposalCount: Int,
        recentWorkouts: [Workout],
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?
    ) -> DailyCoachRecommendation {

        let sessionType = inferStandaloneSessionType(
            hasPain: hasPain,
            availableMinutes: availableMinutes,
            readinessTier: readinessTier,
            fatigueStatus: fatigueStatus,
            recentWorkouts: recentWorkouts
        )

        let (primary, secondary, compact, expanded) = standaloneSuggestions(
            sessionType: sessionType,
            hasPain: hasPain,
            availableMinutes: availableMinutes,
            readinessTier: readinessTier,
            fatigueStatus: fatigueStatus,
            objectiveRecoveryInsight: objectiveRecoveryInsight
        )

        let sources = buildSources(
            readinessTier: readinessTier,
            objectiveRecoveryInsight: objectiveRecoveryInsight
        )

        return DailyCoachRecommendation(
            compactSummary: compact,
            expandedDetails: expanded,
            primarySuggestion: primary,
            secondarySuggestions: secondary,
            readinessTier: readinessTier,
            hasPainFlag: hasPain,
            nextProgramSession: nil,
            standaloneSessionType: sessionType,
            pendingProposalCount: pendingProposalCount,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            recommendationSources: sources,
            sourceAttributionDetails: sourceAttributionText(
                hasPain: hasPain,
                readinessTier: readinessTier,
                objectiveRecoveryInsight: objectiveRecoveryInsight
            )
        )
    }

    /// Infers the most appropriate session type using readiness and recent history.
    private static func inferStandaloneSessionType(
        hasPain: Bool,
        availableMinutes: Int,
        readinessTier: ReadinessTier,
        fatigueStatus: FatigueStatus,
        recentWorkouts: [Workout]
    ) -> StandaloneSessionType {

        if hasPain || fatigueStatus == .critical {
            return .recovery
        }
        if readinessTier == .low && (fatigueStatus == .high || fatigueStatus == .elevated) {
            return .recovery
        }

        // Simple rotation: look at sessions logged in the last 14 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recent = recentWorkouts.filter { $0.date >= cutoff && $0.programRun == nil }

        // We don't store session-type metadata on standalone workouts yet,
        // so default to full body which is the safest general recommendation.
        if recent.isEmpty {
            return .fullBody
        }

        // If they trained yesterday or the day before, favour upper/lower split intuition
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let trainedRecently = recent.contains { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
        if trainedRecently && readinessTier != .low {
            // Alternate loosely between upper and lower
            return recent.count.isMultiple(of: 2) ? .upper : .lower
        }

        return .fullBody
    }

    // MARK: - Standalone Suggestion Rules

    private static func standaloneSuggestions(
        sessionType: StandaloneSessionType,
        hasPain: Bool,
        availableMinutes: Int,
        readinessTier: ReadinessTier,
        fatigueStatus: FatigueStatus,
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?
    ) -> (DailyCoachSuggestionItem, [DailyCoachSuggestionItem], String, String) {

        // Pain override
        if hasPain {
            let primary = DailyCoachSuggestionItem(
                type: .standaloneRecoverySession,
                compactText: "Pain flagged. Light recovery session only today.",
                expandedText: "Skip strength work today. Mobility, walking, or easy cardio is the safer call."
            )
            return (
                primary,
                [],
                "Pain flagged. Light recovery session recommended.",
                "You reported discomfort today. A light recovery option or full rest fits better than strength training."
            )
        }

        // Recovery day
        if sessionType == .recovery {
            let primary = DailyCoachSuggestionItem(
                type: .standaloneRecoverySession,
                compactText: "Recovery session recommended — light movement today.",
                expandedText: "Readiness and fatigue signals point to a lighter day. Gentle movement, stretching, or easy cardio will set up a better next session."
            )
            return (
                primary,
                [],
                "Recovery day. Light movement recommended over hard training.",
                "High fatigue or low readiness signals suggest accumulated stress. A recovery session today should support better quality training next time."
            )
        }

        // Short session
        if availableMinutes < 30 {
            let primary = DailyCoachSuggestionItem(
                type: .standaloneShortStrengthSession,
                compactText: "Under 30 min - 2-3 key compound movements.",
                expandedText: "Pick 2-3 high-value compound movements, keep rest short, and prioritize quality over volume."
            )
            return (
                primary,
                [],
                "Under 30 min. Short strength session — 2–3 movements.",
                "Time is tight. Choose one lower-body and one upper-body compound movement, then finish."
            )
        }

        let name = sessionType.rawValue
        let isLowReadiness = readinessTier == .low
        let toneNote = isLowReadiness ? " Take it a notch easier today — readiness is low." : ""

        let hasObjectiveCaution = objectiveRecoveryInsight?.status == .caution
        let primary = DailyCoachSuggestionItem(
            type: .standaloneShortStrengthSession,
            compactText: "\(name) session recommended today.",
            expandedText: hasObjectiveCaution
                ? "A \(name.lowercased()) session fits today. Keep it slightly conservative with 2-4 key movements and stop hard sets a little short.\(toneNote)"
                : "A \(name.lowercased()) session fits today. Aim for 3-5 compound movements and let warm-ups set the pace.\(toneNote)"
        )
        return (
            primary,
            [],
            hasObjectiveCaution
                ? "\(name) session recommended with a slightly conservative pace today."
                : "\(name) session recommended today.",
            hasObjectiveCaution
                ? "Manual readiness supports training today, but objective recovery is mildly poor versus baseline. Keep the \(name.lowercased()) session and prioritize clean reps.\(toneNote)"
                : "Your readiness and recent training history point toward a \(name.lowercased()) session. Keep intensity aligned with how warm-up sets feel.\(toneNote)"
        )
    }

    // MARK: - Source Attribution

    private static func buildSources(
        readinessTier: ReadinessTier,
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?
    ) -> [DailyCoachRecommendationSource] {
        var sources: [DailyCoachRecommendationSource] = [.trainingHistory]
        if readinessTier != .unknown {
            sources.insert(.manualCheckIn, at: 0)
        }
        if objectiveRecoveryInsight != nil {
            sources.append(.healthData)
        }
        return sources
    }

    private static func sourceAttributionText(
        hasPain: Bool,
        readinessTier: ReadinessTier,
        objectiveRecoveryInsight: ObjectiveRecoveryInsight?
    ) -> String {
        let manualText: String
        if hasPain {
            manualText = "Manual check-in flagged pain, which overrides all automatic changes."
        } else if readinessTier == .unknown {
            manualText = "No manual check-in was submitted today."
        } else {
            manualText = "Manual check-in was used for readiness and time-available context."
        }

        let trainingText = "Training history provided recent session and fatigue context."

        let healthText: String
        if let objectiveRecoveryInsight {
            switch objectiveRecoveryInsight.status {
            case .caution:
                healthText = "Health data signaled mild caution and nudged the recommendation slightly more conservative."
            case .good:
                healthText = "Health data was favorable and supported the existing recommendation."
            case .neutral:
                healthText = "Health data was near baseline and did not materially change the recommendation."
            }
        } else {
            healthText = "Health data was unavailable or not enabled, so Daily Coach behavior stayed in baseline mode."
        }

        return "\(manualText) \(trainingText) \(healthText)"
    }
}
