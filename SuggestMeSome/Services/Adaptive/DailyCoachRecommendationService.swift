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
                compactText: "Pain flagged — review your session before training.",
                expandedText: "You reported pain or discomfort today. No automatic changes are made. Review the session manually and consider a lower-stress variation, a significant load reduction, or skipping the session if training does not feel appropriate."
            )
            let secondary = [DailyCoachSuggestionItem(
                type: .trimAccessories,
                compactText: "Consider skipping accessories and prioritising the primary lift only.",
                expandedText: "If you decide to train, keep the session simple, limit it to the primary lift, and skip accessories that feel likely to add unnecessary stress."
            )]
            return (
                primary,
                secondary,
                "Pain flagged. Manual review recommended before training.",
                "You reported pain or discomfort. The recommendation engine will not auto-swap anything. Review your session manually, choose a lower-stress option if needed, and prioritize comfort and control over intensity."
            )
        }

        // ── Priority 2: Severe time constraint (< 30 min) ──────────────────
        if availableMinutes < 30 {
            let primary = DailyCoachSuggestionItem(
                type: .trimAccessories,
                compactText: "Only \(availableMinutes) min — primary lift + top set only.",
                expandedText: "With under 30 minutes you should preserve: (1) primary lift, (2) top set. Drop all backoff sets and accessories today to stay within your window."
            )
            return (
                primary,
                [],
                "Only \(availableMinutes) min available. Primary lift + top set only.",
                "A severe time constraint means almost everything gets cut. Focus entirely on the primary movement and its top set. Quality over quantity — one good set is better than a rushed incomplete session."
            )
        }

        // ── Priority 2 (cont): Moderate time pressure with elevated fatigue ─
        if availableMinutes < 45 && (fatigueStatus == .elevated || fatigueStatus == .high || fatigueStatus == .critical) {
            let primary = DailyCoachSuggestionItem(
                type: .trimAccessories,
                compactText: "Limited time + elevated fatigue — trim accessories.",
                expandedText: "With \(availableMinutes) minutes and elevated fatigue, keep: (1) primary lift, (2) top set, (3) backoff work, (4) your single highest-value accessory. Drop the rest."
            )
            return (
                primary,
                [],
                "\(availableMinutes) min + elevated fatigue. Trim accessories, keep primary.",
                "Moderate time pressure combined with elevated fatigue calls for a focused session. Run the main lift fully and one key accessory. Skipping lower-priority accessories now helps keep fatigue from building further."
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
                    compactText: "Low readiness + high fatigue — reduce working loads 5–10%.",
                    expandedText: "Both readiness and fatigue are elevated today. Reduce all working loads by 5–10% and drop one backoff set. Keep the primary lift and top set. Your body is signalling it needs more recovery."
                )
            } else {
                primary = DailyCoachSuggestionItem(
                    type: .trimOneBackoffSet,
                    compactText: "Low readiness — run \(sessionLabel), drop one backoff set.",
                    expandedText: "Readiness is low today. Run the session as programmed but remove the final backoff set from the primary lift. Primary lift, top set, and remaining backoff sets are kept. Accessories remain as planned."
                )
            }
            let secondary = [DailyCoachSuggestionItem(
                type: .trimAccessories,
                compactText: "If energy stays low, trim lowest-priority accessories mid-session.",
                expandedText: "If you reach the accessories and still feel off, drop the lowest-priority one. Your top 1–2 accessories are still worth completing."
            )]
            let expanded = hasObjectiveCaution
                ? "Your manual readiness is low, and objective recovery also shows caution. Run the session conservatively — full primary lift, top set, and trimmed backoff. Keep effort controlled and avoid forcing progression."
                : "Your composite readiness is low. The plan is to run the session conservatively — full primary lift, top set, and trimmed backoff. This keeps you training without digging a deeper fatigue hole."
            return (
                primary,
                secondary,
                "Low readiness. Conservative session for \(sessionLabel) suggested.",
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
                    compactText: "Strong check-in, but objective recovery is cautious — trim one backoff set.",
                    expandedText: "Your manual check-in looks strong, but objective recovery is slightly below baseline today. Keep the main lift and top set, then trim one backoff set to stay productive without overreaching."
                )
                return (
                    primary,
                    secondary,
                    "Strong manual readiness with objective caution. Slightly conservative session for \(sessionLabel).",
                    "Manual readiness is strong, but objective recovery is mildly poor versus baseline. Rather than a hard change, take a small conservative adjustment today by trimming one backoff set."
                )
            }

            let primary = DailyCoachSuggestionItem(
                type: .runAsPlanned,
                compactText: "Strong readiness. Push hard on \(sessionLabel).",
                expandedText: "All readiness indicators are high. Execute the full session and focus on quality reps — especially on your top set. High-readiness days are when progress is most likely to happen."
            )
            return (
                primary,
                secondary,
                "Strong readiness. Full session for \(sessionLabel) — push hard.",
                "High readiness across sleep, energy, soreness, and stress. This is one of your better training days. Don't sandbag — run the full session and aim for clean, confident reps on your top set."
            )
        }

        // Neutral (or unknown — treated same as neutral)
        let hasObjectiveCaution = objectiveRecoveryInsight?.status == .caution
        let primary = DailyCoachSuggestionItem(
            type: .runAsPlanned,
            compactText: hasObjectiveCaution
                ? "Solid readiness with mild objective caution. Run \(sessionLabel) with controlled effort."
                : "Solid readiness. Run \(sessionLabel) as planned.",
            expandedText: hasObjectiveCaution
                ? "Manual readiness is solid, but objective recovery is slightly below baseline. Keep the session as planned and leave a small effort buffer on hard sets."
                : "Readiness is in a normal range. Proceed with the full session as programmed. Stay attentive to how working sets feel — if a set feels off, it is fine to stop a rep or two short."
        )
        return (
            primary,
            secondary,
            hasObjectiveCaution
                ? "Solid readiness with objective caution. Run \(sessionLabel) with slightly conservative pacing."
                : "Solid readiness. Run \(sessionLabel) as planned.",
            hasObjectiveCaution
                ? "Manual readiness is neutral-to-good while objective recovery is mildly poor. Keep the full session, but avoid forcing top-end effort if sets feel heavier than usual."
                : "Readiness is neutral-to-good. Run the full session. Adjust effort based on how early working sets feel rather than making pre-session changes."
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
                expandedText: "You flagged pain or discomfort. Skip strength work today. A light recovery session — mobility, walking, or easy cardio — is the most conservative option."
            )
            return (
                primary,
                [],
                "Pain flagged. Light recovery session recommended.",
                "You reported discomfort today. A light recovery option or full rest may fit better than strength training."
            )
        }

        // Recovery day
        if sessionType == .recovery {
            let primary = DailyCoachSuggestionItem(
                type: .standaloneRecoverySession,
                compactText: "Recovery session recommended — light movement today.",
                expandedText: "Readiness and fatigue signals suggest your body needs a lighter day. A recovery session — gentle movement, stretching, or light cardio — will set you up for a better training session tomorrow."
            )
            return (
                primary,
                [],
                "Recovery day. Light movement recommended over hard training.",
                "High fatigue or low readiness signals indicate accumulated stress. A recovery session today will allow better quality training in the next session."
            )
        }

        // Short session
        if availableMinutes < 30 {
            let primary = DailyCoachSuggestionItem(
                type: .standaloneShortStrengthSession,
                compactText: "Under 30 min — 2–3 key compound movements.",
                expandedText: "Pick 2–3 high-value compound movements (e.g. squat, press, row). Keep rest periods to 60–90 seconds and prioritise quality over volume."
            )
            return (
                primary,
                [],
                "Under 30 min. Short strength session — 2–3 movements.",
                "Time is tight. Choose one lower-body and one upper-body compound movement. Two to three working sets each. Short rest, clean reps."
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
                ? "Based on your recent training and today's readiness, a \(name.lowercased()) session fits well. Keep it slightly conservative: use 2–4 key movements and stop hard sets a little short today.\(toneNote)"
                : "Based on your recent training and today's readiness, a \(name.lowercased()) session fits well. Aim for 3–5 compound movements with 3–4 working sets each.\(toneNote)"
        )
        return (
            primary,
            [],
            hasObjectiveCaution
                ? "\(name) session recommended with a slightly conservative pace today."
                : "\(name) session recommended today.",
            hasObjectiveCaution
                ? "Manual readiness supports training today, but objective recovery is mildly poor versus baseline. Keep the \(name.lowercased()) session, reduce session ambition slightly, and prioritize clean reps.\(toneNote)"
                : "Your readiness and recent training history suggest a \(name.lowercased()) session. Choose 3–5 exercises and keep intensity aligned with how you feel during warm-up sets.\(toneNote)"
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
