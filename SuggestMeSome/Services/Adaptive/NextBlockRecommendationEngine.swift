//
//  NextBlockRecommendationEngine.swift
//  SuggestMeSome
//
//  Feature 13 Prompt 3 — Ranked next-block recommendation engine and
//  editable prefill context mapping for program generation.
//

import Foundation

enum NextBlockRecommendationEngine {
    private static let generationService = ProgramGenerationService()
    private static let explainabilityService = AdaptiveExplainabilityService()

    private struct SignalSummary {
        let currentFocus: ProgramFocus?
        let currentLevel: ProgramLevel
        let progressionModel: ProgramProgressionModel?
        let plannedSessions: Int
        let completedSessions: Int
        let missedSessions: Int
        let adherenceRatio: Double
        let bestLiftImprovement: Int
        let prExerciseCount: Int
        let hasProgress: Bool
        let strongProgress: Bool
        let stalledDespiteAdherence: Bool
        let lowAdherence: Bool
        let moderateFriction: Bool
        let sparseData: Bool
        let conditioningBias: Bool
        let standaloneSupportCount: Int
        let currentDurationWeeks: Int
        let currentSessionsPerWeek: Int
        let anchorExercises: [String]
        let notableExercises: [String]
        let notableLiftDisplayNames: [String]

        init(
            input: MesocycleRecommendationInputPayload,
            currentDurationWeeks: Int,
            currentSessionsPerWeek: Int
        ) {
            let adherenceRatio: Double
            if input.sessionSummary.plannedSessions > 0 {
                adherenceRatio = Double(input.sessionSummary.completedSessions) / Double(input.sessionSummary.plannedSessions)
            } else {
                adherenceRatio = input.sessionSummary.completedSessions > 0 ? 1.0 : 0.0
            }

            let bestLiftImprovement = input.liftHighlights.map(\.improvementPercentage).max() ?? 0
            let hasProgress = input.personalRecordSummary.achievedSetCount > 0 || bestLiftImprovement > 0
            let strongProgress = input.personalRecordSummary.uniqueExerciseCount >= 2 || bestLiftImprovement >= 4
            let sparseData = input.frictionSignalKinds.contains(.sparseProgramData)
            let lowAdherence = sparseData ||
                input.sessionSummary.completedSessions == 0 ||
                adherenceRatio < 0.65
            let moderateFriction = input.sessionSummary.missedSessions > 0 ||
                input.frictionSignalKinds.contains(.longGapBetweenSessions) ||
                input.frictionSignalKinds.contains(.standaloneDrift)
            let stalledDespiteAdherence = adherenceRatio >= 0.75 && !hasProgress
            let conditioningBias = input.standaloneInfluence.includedWorkoutCount > 0 &&
                input.standaloneInfluence.dominantPatterns.contains { $0.pattern == .conditioning }

            self.currentFocus = input.currentFocus
            self.currentLevel = input.inferredCurrentLevel
            self.progressionModel = input.progressionModel
            self.plannedSessions = input.sessionSummary.plannedSessions
            self.completedSessions = input.sessionSummary.completedSessions
            self.missedSessions = input.sessionSummary.missedSessions
            self.adherenceRatio = adherenceRatio
            self.bestLiftImprovement = bestLiftImprovement
            self.prExerciseCount = input.personalRecordSummary.uniqueExerciseCount
            self.hasProgress = hasProgress
            self.strongProgress = strongProgress
            self.stalledDespiteAdherence = stalledDespiteAdherence
            self.lowAdherence = lowAdherence
            self.moderateFriction = moderateFriction
            self.sparseData = sparseData
            self.conditioningBias = conditioningBias
            self.standaloneSupportCount = input.standaloneInfluence.includedWorkoutCount
            self.currentDurationWeeks = currentDurationWeeks
            self.currentSessionsPerWeek = currentSessionsPerWeek
            self.anchorExercises = input.exerciseConsistencySummary.anchorExercises.map(\.exerciseName)
            self.notableExercises = input.personalRecordSummary.notableExercises
            self.notableLiftDisplayNames = input.liftHighlights.map(\.displayName)
        }

        var adherencePercentage: Int {
            Int((adherenceRatio * 100).rounded())
        }

        var conservativeDurationWeeks: Int {
            currentDurationWeeks <= 6 ? 6 : 8
        }

        var reducedSessionsPerWeek: Int {
            if adherenceRatio < 0.5 {
                return max(2, currentSessionsPerWeek - 2)
            }
            return max(2, currentSessionsPerWeek - 1)
        }

        var hyptrophyLikeFocus: Bool {
            switch currentFocus {
            case .bodybuilding, .pushPull, .generalFitness, .fullBody:
                return true
            case .none, .increaseMaxSquat, .increaseMaxBench, .increaseMaxDeadlift, .powerlifting, .fiveByFive, .powerbuilding, .cardioEndurance:
                return false
            }
        }
    }

    private struct RecommendationCandidate {
        let focus: ProgramFocus
        let kind: MesocycleNextBlockRecommendationKind
        let title: String
        let summary: String
        let rationale: [String]
        let level: ProgramLevel
        let durationWeeks: Int
        let sessionsPerWeek: Int
        let fitScore: Int
        let fitNote: String
        let priority: Int
    }

    static func rankedRecommendations(
        input: MesocycleRecommendationInputPayload,
        currentDurationWeeks: Int,
        currentSessionsPerWeek: Int,
        completionEndDate: Date,
        personalRecords: [PersonalRecord],
        workoutsInWindow: [Workout],
        continuitySnapshot: ProgramBlockContinuitySnapshot? = nil
    ) -> [MesocycleNextBlockRecommendation] {
        let signals = SignalSummary(
            input: input,
            currentDurationWeeks: currentDurationWeeks,
            currentSessionsPerWeek: currentSessionsPerWeek
        )

        var candidates = [
            continuityCandidate(from: input, signals: signals),
            growthCandidate(from: input, signals: signals),
            fallbackCandidate(from: input, signals: signals),
        ]

        if signals.conditioningBias {
            candidates.append(conditioningCandidate(from: input, signals: signals))
        }

        let deduped = deduplicateByFocus(candidates)
        let finalCandidates = ensureCandidateCount(deduped, input: input, signals: signals)
            .sorted { lhs, rhs in
                let lhsScore = lhs.fitScore + continuityFitAdjustment(for: lhs.focus, continuitySnapshot: continuitySnapshot)
                let rhsScore = rhs.fitScore + continuityFitAdjustment(for: rhs.focus, continuitySnapshot: continuitySnapshot)
                if lhsScore == rhsScore {
                    return lhs.priority < rhs.priority
                }
                return lhsScore > rhsScore
            }
            .prefix(3)

        return finalCandidates.enumerated().map { index, candidate in
            makeRecommendation(
                rank: index + 1,
                candidate: candidate,
                isPrimary: index == 0,
                input: input,
                completionEndDate: completionEndDate,
                personalRecords: personalRecords,
                workoutsInWindow: workoutsInWindow,
                continuitySnapshot: continuitySnapshot
            )
        }
    }

    static func fallbackPrefill(
        runStableID: String,
        recommendationStableID: String?,
        focus: ProgramFocus,
        level: ProgramLevel,
        durationWeeks: Int,
        sessionsPerWeek: Int,
        endDate: Date,
        personalRecords: [PersonalRecord],
        workoutsInWindow: [Workout],
        note: String,
        input: MesocycleRecommendationInputPayload? = nil,
        steeringProfile: AdaptiveSteeringProfile? = nil,
        explanationBundle: AdaptiveExplanationBundle? = nil
    ) -> NextBlockPrefillContext {
        let targetStyle = generationService.progressionModel(for: focus, level: level)
        let oneRepMaxSuggestions = buildOneRepMaxSuggestions(
            for: focus,
            endDate: endDate,
            personalRecords: personalRecords,
            workoutsInWindow: workoutsInWindow
        )
        let preservedExerciseNames = buildPreservedExerciseNames(
            targetFocus: focus,
            input: input,
            workoutsInWindow: workoutsInWindow
        )
        let notableLiftNames = orderedUnique(
            (input?.liftHighlights.map(\.displayName) ?? []) +
            oneRepMaxSuggestions.map(\.exerciseName)
        )
        let valueSources = buildValueSources(
            focus: focus,
            style: targetStyle,
            level: level,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            note: note,
            oneRepMaxSuggestions: oneRepMaxSuggestions,
            preservedExerciseNames: preservedExerciseNames,
            recommendationStableID: recommendationStableID
        )

        let intensityContext = NextBlockIntensityContext(
            suggestedProgressionModel: targetStyle,
            carriedOneRepMaxes: oneRepMaxSuggestions,
            notableLiftDisplayNames: Array(notableLiftNames.prefix(4)),
            sourceNotes: orderedUnique(
                oneRepMaxSuggestions.map(\.sourceSummary) +
                [note]
            )
        )

        return NextBlockPrefillContext(
            sourceProgramRunStableID: runStableID,
            recommendationStableID: recommendationStableID,
            focus: focus,
            style: targetStyle,
            level: level,
            durationWeeks: durationWeeks,
            sessionsPerWeek: max(
                FocusTemplateLibrary.template(for: focus).minimumFrequency,
                sessionsPerWeek
            ),
            oneRepMaxSuggestions: oneRepMaxSuggestions,
            preservedExerciseNames: preservedExerciseNames,
            rationaleText: note,
            valueSources: valueSources,
            intensityContext: intensityContext,
            notes: orderedUnique([note] + oneRepMaxSuggestions.map(\.sourceSummary)),
            steeringProfile: steeringProfile,
            explanationBundle: explanationBundle
        )
    }

    private static func continuityCandidate(
        from input: MesocycleRecommendationInputPayload,
        signals: SignalSummary
    ) -> RecommendationCandidate {
        let focus = signals.lowAdherence
            ? consistencyResetFocus(from: input.currentFocus)
            : (input.currentFocus ?? .generalFitness)
        let kind: MesocycleNextBlockRecommendationKind
        if signals.lowAdherence {
            kind = .rebuildConsistency
        } else if signals.stalledDespiteAdherence || signals.moderateFriction {
            kind = .consolidateFocus
        } else {
            kind = .repeatFocus
        }

        let level = kind == .rebuildConsistency
            ? stepDownLevel(from: input.inferredCurrentLevel)
            : input.inferredCurrentLevel
        let durationWeeks = kind == .rebuildConsistency
            ? signals.conservativeDurationWeeks
            : signals.currentDurationWeeks
        let frequencySeed = kind == .repeatFocus ? signals.currentSessionsPerWeek : signals.reducedSessionsPerWeek
        let sessionsPerWeek = normalizedFrequency(for: focus, preferred: frequencySeed)

        var rationale: [String] = []
        if signals.plannedSessions > 0 {
            rationale.append("\(signals.completedSessions)/\(signals.plannedSessions) planned sessions were completed during the block.")
        } else {
            rationale.append("The finished block has limited planned-session metadata, so the engine leaned on continuity signals.")
        }

        if signals.strongProgress {
            rationale.append("PR and lift-momentum signals show the block still had productive upside to carry forward.")
        } else if signals.stalledDespiteAdherence {
            rationale.append("Adherence stayed solid, but progress signals were flat, so the next block should keep continuity while changing stressors.")
        }

        if signals.lowAdherence {
            rationale.append("Missed sessions and friction signals argue for a lower-friction block before increasing stress again.")
        } else if signals.moderateFriction {
            rationale.append("Keeping the same focus preserves specificity while trimming complexity around schedule or recovery friction.")
        }

        let title: String
        let summary: String
        switch kind {
        case .repeatFocus:
            title = "Advance \(FocusTemplateLibrary.template(for: focus).displayName) with fresh defaults"
            summary = "The next block should keep the same focus, but as editable prefilled context instead of replaying the exact same plan."
        case .consolidateFocus:
            title = "Keep the focus and smooth the stress cost"
            summary = "Continuity still fits, but the next version should modify stressors and frequency before pushing harder."
        case .rebuildConsistency:
            title = "Rebuild consistency with \(FocusTemplateLibrary.template(for: focus).displayName)"
            summary = "A simpler continuation is the safest way to keep structured training moving when completion friction was the loudest signal."
        case .pivotFocus, .addConditioningBias:
            title = "Continue with \(FocusTemplateLibrary.template(for: focus).displayName)"
            summary = "The engine kept continuity with a simpler follow-up."
        }

        var fitScoreSeed = 60
        fitScoreSeed += signals.lowAdherence ? 6 : 10
        fitScoreSeed += signals.strongProgress ? (signals.hyptrophyLikeFocus ? 4 : 12) : 0
        fitScoreSeed += signals.stalledDespiteAdherence ? 6 : 0
        fitScoreSeed += signals.moderateFriction ? -4 : 6
        fitScoreSeed += signals.hyptrophyLikeFocus && signals.strongProgress ? -12 : 0
        let fitScore = clampedFitScore(fitScoreSeed)

        return RecommendationCandidate(
            focus: focus,
            kind: kind,
            title: title,
            summary: summary,
            rationale: Array(rationale.prefix(3)),
            level: level,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            fitScore: fitScore,
            fitNote: fitNote(
                prefix: fitScore >= 78 ? "High fit" : "Moderate fit",
                clauses: [
                    "\(signals.adherencePercentage)% adherence",
                    signals.hasProgress ? "\(max(1, signals.prExerciseCount)) PR-linked exercise\(signals.prExerciseCount == 1 ? "" : "s")" : "limited progress signal",
                    kind == .rebuildConsistency
                        ? "frequency reduced to \(sessionsPerWeek)x/week"
                        : "continuity preserved"
                ]
            ),
            priority: 0
        )
    }

    private static func growthCandidate(
        from input: MesocycleRecommendationInputPayload,
        signals: SignalSummary
    ) -> RecommendationCandidate {
        let focus = productiveFollowUpFocus(from: input.currentFocus)
        let sessionsPerWeek = normalizedFrequency(
            for: focus,
            preferred: signals.lowAdherence ? signals.reducedSessionsPerWeek : signals.currentSessionsPerWeek
        )
        let fitScore = clampedFitScore(
            48 +
            (signals.strongProgress ? 16 : 0) +
            (signals.hyptrophyLikeFocus ? 8 : 0) +
            (signals.lowAdherence ? -10 : 4) +
            (signals.stalledDespiteAdherence ? 4 : 0) +
            (signals.hyptrophyLikeFocus && signals.strongProgress ? 10 : 0)
        )

        var rationale = [
            "A complementary follow-up changes the main stressor while still using the finished block as structured context."
        ]

        if signals.hyptrophyLikeFocus && signals.strongProgress {
            rationale.append("This block behaved like a productive hypertrophy phase, so a more strength-oriented follow-up is worth ranking near the top.")
        } else if signals.strongProgress {
            rationale.append("Strong progress signals support a productive pivot instead of blindly replaying the same phase.")
        } else if signals.stalledDespiteAdherence {
            rationale.append("Changing the emphasis is a clean way to keep momentum when adherence was good but outcome signals flattened.")
        }

        return RecommendationCandidate(
            focus: focus,
            kind: .pivotFocus,
            title: "Pivot into \(FocusTemplateLibrary.template(for: focus).displayName)",
            summary: "Use the completed block as an editable launch point for a complementary next phase with a clearer progression target.",
            rationale: Array(rationale.prefix(3)),
            level: input.inferredCurrentLevel,
            durationWeeks: signals.currentDurationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            fitScore: fitScore,
            fitNote: fitNote(
                prefix: fitScore >= 72 ? "High upside" : "Moderate upside",
                clauses: [
                    signals.strongProgress ? "progress supports a phase change" : "phase change adds variety without a hard reset",
                    signals.hyptrophyLikeFocus ? "hypertrophy block can cash out into strength work" : "focus family stays adjacent",
                    "\(sessionsPerWeek)x/week still fits current tolerance"
                ]
            ),
            priority: 1
        )
    }

    private static func conditioningCandidate(
        from input: MesocycleRecommendationInputPayload,
        signals: SignalSummary
    ) -> RecommendationCandidate {
        let sessionsPerWeek = normalizedFrequency(
            for: .cardioEndurance,
            preferred: min(signals.currentSessionsPerWeek, 4)
        )
        let fitScore = clampedFitScore(
            40 +
            min(12, signals.standaloneSupportCount * 4) +
            (signals.lowAdherence ? -6 : 4)
        )

        return RecommendationCandidate(
            focus: .cardioEndurance,
            kind: .addConditioningBias,
            title: "Keep conditioning on the board",
            summary: "Standalone workouts showed enough conditioning support to justify a dedicated ranked option, but not enough to auto-override the top recommendation.",
            rationale: [
                "\(signals.standaloneSupportCount) standalone workout\(signals.standaloneSupportCount == 1 ? "" : "s") contributed to the block window.",
                "Conditioning was a dominant standalone pattern, so the next block keeps an endurance-biased option available.",
                "This option stays conservative by ranking behind stronger continuity signals when adherence needs rebuilding."
            ],
            level: input.inferredCurrentLevel,
            durationWeeks: signals.currentDurationWeeks <= 6 ? 6 : 8,
            sessionsPerWeek: sessionsPerWeek,
            fitScore: fitScore,
            fitNote: fitNote(
                prefix: "Conservative fit",
                clauses: [
                    "standalone conditioning bias detected",
                    "does not override core consistency rules",
                    "\(sessionsPerWeek)x/week keeps the block manageable"
                ]
            ),
            priority: 2
        )
    }

    private static func fallbackCandidate(
        from input: MesocycleRecommendationInputPayload,
        signals: SignalSummary
    ) -> RecommendationCandidate {
        let focus = balancedFallbackFocus(from: input.currentFocus)
        let sessionsPerWeek = normalizedFrequency(
            for: focus,
            preferred: signals.lowAdherence ? signals.reducedSessionsPerWeek : signals.currentSessionsPerWeek
        )
        let fitScore = clampedFitScore(
            36 +
            (signals.lowAdherence ? 12 : 0) +
            (signals.currentSessionsPerWeek >= 5 ? 4 : 0) +
            (signals.sparseData ? 4 : 0)
        )

        return RecommendationCandidate(
            focus: focus,
            kind: signals.lowAdherence ? .rebuildConsistency : .pivotFocus,
            title: "Keep a lower-friction off-ramp available",
            summary: "A balanced fallback stays in the ranked list so the next block can still be edited around recovery, schedule changes, or motivation shifts.",
            rationale: [
                "A third option keeps the next-block flow flexible instead of forcing a single interpretation of the finished block.",
                "\(FocusTemplateLibrary.template(for: focus).displayName) is the clearest low-friction alternative to the primary recommendation."
            ],
            level: signals.lowAdherence
                ? stepDownLevel(from: input.inferredCurrentLevel)
                : input.inferredCurrentLevel,
            durationWeeks: signals.conservativeDurationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            fitScore: fitScore,
            fitNote: fitNote(
                prefix: "Fallback fit",
                clauses: [
                    "keeps options open",
                    signals.lowAdherence ? "simplifies the next block" : "balances recovery and variety",
                    "\(sessionsPerWeek)x/week baseline"
                ]
            ),
            priority: 3
        )
    }

    private static func makeRecommendation(
        rank: Int,
        candidate: RecommendationCandidate,
        isPrimary: Bool,
        input: MesocycleRecommendationInputPayload,
        completionEndDate: Date,
        personalRecords: [PersonalRecord],
        workoutsInWindow: [Workout],
        continuitySnapshot: ProgramBlockContinuitySnapshot?
    ) -> MesocycleNextBlockRecommendation {
        let stableID = "\(input.programRunStableID)::recommendation::\(rank)::\(candidate.focus.rawValue)"
        let steeringProfile = continuitySnapshot?.latestConfirmedSteeringProfile
        let prefill = fallbackPrefill(
            runStableID: input.programRunStableID,
            recommendationStableID: stableID,
            focus: candidate.focus,
            level: candidate.level,
            durationWeeks: candidate.durationWeeks,
            sessionsPerWeek: candidate.sessionsPerWeek,
            endDate: completionEndDate,
            personalRecords: personalRecords,
            workoutsInWindow: workoutsInWindow,
            note: candidate.summary,
            input: input,
            steeringProfile: steeringProfile
        )

        let provisional = MesocycleNextBlockRecommendation(
            stableID: stableID,
            rank: rank,
            kind: candidate.kind,
            title: candidate.title,
            summary: candidate.summary,
            rationale: candidate.rationale,
            targetFocus: candidate.focus,
            targetFocusDisplayName: FocusTemplateLibrary.template(for: candidate.focus).displayName,
            suggestedLevel: candidate.level,
            suggestedDurationWeeks: candidate.durationWeeks,
            suggestedSessionsPerWeek: candidate.sessionsPerWeek,
            decision: .pending,
            prefill: prefill,
            isPrimaryRecommendation: isPrimary,
            fitScore: candidate.fitScore,
            fitNote: candidate.fitNote,
            requiresExplicitAcceptance: true
        )
        let explanationBundle = explainabilityService.buildNextBlockExplanation(
            recommendation: provisional,
            input: input,
            continuitySnapshot: continuitySnapshot,
            steeringProfile: prefill.resolvedSteeringProfile
        )
        let explainedPrefill = NextBlockPrefillContext(
            sourceProgramRunStableID: prefill.sourceProgramRunStableID,
            recommendationStableID: prefill.recommendationStableID,
            focus: prefill.focus,
            style: prefill.style,
            level: prefill.level,
            durationWeeks: prefill.durationWeeks,
            sessionsPerWeek: prefill.sessionsPerWeek,
            oneRepMaxSuggestions: prefill.oneRepMaxSuggestions,
            preservedExerciseNames: prefill.preservedExerciseNames,
            rationaleText: prefill.rationaleText,
            valueSources: prefill.valueSources,
            intensityContext: prefill.intensityContext,
            notes: prefill.notes,
            steeringProfile: prefill.steeringProfile,
            explanationBundle: explanationBundle
        )

        return MesocycleNextBlockRecommendation(
            stableID: stableID,
            rank: rank,
            kind: candidate.kind,
            title: candidate.title,
            summary: candidate.summary,
            rationale: candidate.rationale,
            targetFocus: candidate.focus,
            targetFocusDisplayName: FocusTemplateLibrary.template(for: candidate.focus).displayName,
            suggestedLevel: candidate.level,
            suggestedDurationWeeks: candidate.durationWeeks,
            suggestedSessionsPerWeek: candidate.sessionsPerWeek,
            decision: .pending,
            prefill: explainedPrefill,
            isPrimaryRecommendation: isPrimary,
            fitScore: candidate.fitScore,
            fitNote: candidate.fitNote,
            requiresExplicitAcceptance: true,
            explanationBundle: explanationBundle
        )
    }

    private static func continuityFitAdjustment(
        for focus: ProgramFocus,
        continuitySnapshot: ProgramBlockContinuitySnapshot?
    ) -> Int {
        guard let continuitySnapshot else { return 0 }

        var adjustment = 0
        if continuitySnapshot.selectedRecommendationSnapshot?.targetFocus == focus {
            adjustment += 6
        }
        let declinedFocuses = Set(
            continuitySnapshot.recommendationSnapshots
                .filter { continuitySnapshot.declinedRecommendationStableIDs.contains($0.stableID) }
                .map(\.targetFocus)
        )
        if declinedFocuses.contains(focus) {
            adjustment -= 8
        }
        if continuitySnapshot.latestConfirmedSteeringProfile?.continuityBias == .preserveAnchors {
            let requiredLifts = Set(FocusTemplateLibrary.template(for: focus).requiredLifts.map { $0.lowercased() })
            let preserved = Set(
                continuitySnapshot.carriedForwardContext?.preservedExerciseNames.map { $0.lowercased() } ?? []
            )
            if !requiredLifts.isDisjoint(with: preserved) {
                adjustment += 4
            }
        }

        return adjustment
    }

    private static func deduplicateByFocus(
        _ candidates: [RecommendationCandidate]
    ) -> [RecommendationCandidate] {
        var bestByFocus: [ProgramFocus: RecommendationCandidate] = [:]

        for candidate in candidates {
            if let existing = bestByFocus[candidate.focus] {
                if candidate.fitScore > existing.fitScore ||
                    (candidate.fitScore == existing.fitScore && candidate.priority < existing.priority) {
                    bestByFocus[candidate.focus] = candidate
                }
            } else {
                bestByFocus[candidate.focus] = candidate
            }
        }

        return Array(bestByFocus.values)
    }

    private static func ensureCandidateCount(
        _ candidates: [RecommendationCandidate],
        input: MesocycleRecommendationInputPayload,
        signals: SignalSummary
    ) -> [RecommendationCandidate] {
        guard candidates.count < 3 else { return candidates }

        var results = candidates
        let excluded = Set(results.map(\.focus))
        let fallbackOrder: [ProgramFocus] = [
            balancedFallbackFocus(from: input.currentFocus),
            adjacentGrowthFocus(from: input.currentFocus ?? .generalFitness),
            .generalFitness,
            .fullBody,
            .powerbuilding,
            .cardioEndurance,
        ]

        for focus in orderedUnique(fallbackOrder) where !excluded.contains(focus) {
            results.append(
                RecommendationCandidate(
                    focus: focus,
                    kind: focus == .cardioEndurance ? .addConditioningBias : .pivotFocus,
                    title: "Keep \(FocusTemplateLibrary.template(for: focus).displayName) available",
                    summary: "This backup option keeps the ranked list editable if the primary recommendation feels too aggressive or too specific.",
                    rationale: [
                        "The engine always keeps a distinct fallback available rather than collapsing to one answer."
                    ],
                    level: signals.lowAdherence
                        ? stepDownLevel(from: input.inferredCurrentLevel)
                        : input.inferredCurrentLevel,
                    durationWeeks: signals.conservativeDurationWeeks,
                    sessionsPerWeek: normalizedFrequency(
                        for: focus,
                        preferred: signals.reducedSessionsPerWeek
                    ),
                    fitScore: 34,
                    fitNote: "Fallback fit: included to preserve a second viable editing path.",
                    priority: 10 + results.count
                )
            )

            if results.count >= 3 {
                break
            }
        }

        return results
    }

    private static func buildValueSources(
        focus: ProgramFocus,
        style: ProgramProgressionModel,
        level: ProgramLevel,
        durationWeeks: Int,
        sessionsPerWeek: Int,
        note: String,
        oneRepMaxSuggestions: [MesocycleOneRepMaxPrefill],
        preservedExerciseNames: [String],
        recommendationStableID: String?
    ) -> [NextBlockPrefillValueSource] {
        var sources: [NextBlockPrefillValueSource] = [
            NextBlockPrefillValueSource(
                field: .focus,
                source: .recommendation,
                note: recommendationStableID == nil
                    ? "Fallback focus defaults were inferred from the finished block."
                    : "Focus came from the ranked recommendation engine."
            ),
            NextBlockPrefillValueSource(
                field: .style,
                source: .recommendation,
                note: "Suggested \(style.displayName) for \(level.rawValue.capitalized) \(FocusTemplateLibrary.template(for: focus).displayName)."
            ),
            NextBlockPrefillValueSource(
                field: .durationWeeks,
                source: .recommendation,
                note: "Duration was chosen from adherence and friction signals."
            ),
            NextBlockPrefillValueSource(
                field: .sessionsPerWeek,
                source: .recommendation,
                note: "Frequency was chosen from tolerated weekly training behavior."
            ),
            NextBlockPrefillValueSource(
                field: .level,
                source: .recommendation,
                note: "Level keeps the recommendation explainable and editable before generation."
            ),
            NextBlockPrefillValueSource(
                field: .rationale,
                source: .recommendation,
                note: note
            ),
        ]

        if let firstSource = oneRepMaxSuggestions.first?.sourceSummary {
            sources.append(
                NextBlockPrefillValueSource(
                    field: .trainingMaxes,
                    source: .carryForwardHistory,
                    note: firstSource
                )
            )
        }

        if !preservedExerciseNames.isEmpty {
            sources.append(
                NextBlockPrefillValueSource(
                    field: .notableExercises,
                    source: .carryForwardHistory,
                    note: "Preserved \(min(3, preservedExerciseNames.count)) anchor exercise selection(s) from recent training."
                )
            )
        }

        return sources
    }

    private static func buildPreservedExerciseNames(
        targetFocus: ProgramFocus,
        input: MesocycleRecommendationInputPayload?,
        workoutsInWindow: [Workout]
    ) -> [String] {
        var counts: [String: Int] = [:]
        for workout in workoutsInWindow {
            for entry in workout.exerciseEntries where !entry.isCardio {
                counts[entry.exerciseName, default: 0] += 1
            }
        }

        let recentByFrequency = counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .map(\.key)

        return Array(orderedUnique(
            FocusTemplateLibrary.template(for: targetFocus).requiredLifts +
            (input?.exerciseConsistencySummary.anchorExercises.map(\.exerciseName) ?? []) +
            (input?.personalRecordSummary.notableExercises ?? []) +
            recentByFrequency
        ).prefix(6))
    }

    private static func buildOneRepMaxSuggestions(
        for focus: ProgramFocus,
        endDate: Date,
        personalRecords: [PersonalRecord],
        workoutsInWindow: [Workout]
    ) -> [MesocycleOneRepMaxPrefill] {
        FocusTemplateLibrary
            .template(for: focus)
            .requiredLifts
            .compactMap {
                bestOneRepMaxPrefill(
                    for: $0,
                    endDate: endDate,
                    personalRecords: personalRecords,
                    workoutsInWindow: workoutsInWindow
                )
            }
    }

    private static func bestOneRepMaxPrefill(
        for exerciseName: String,
        endDate: Date,
        personalRecords: [PersonalRecord],
        workoutsInWindow: [Workout]
    ) -> MesocycleOneRepMaxPrefill? {
        let exactRecordCandidates = personalRecords
            .filter {
                $0.exerciseName.caseInsensitiveCompare(exerciseName) == .orderedSame &&
                $0.dateAchieved <= endDate
            }
            .map {
                OneRepMaxCandidate(
                    estimatedOneRepMaxLbs: inLbs(
                        $0.weight * (1.0 + Double($0.repCount) / 30.0),
                        unit: $0.unit
                    ),
                    displayWeight: roundOneRepMax(
                        $0.weight * (1.0 + Double($0.repCount) / 30.0),
                        unit: $0.unit
                    ),
                    unit: $0.unit,
                    sourceSummary: "Prefilled from \(exerciseName) PR history."
                )
            }

        let exactWorkoutCandidates = workoutsInWindow.flatMap { workout in
            workout.exerciseEntries.compactMap { entry -> [OneRepMaxCandidate]? in
                guard entry.exerciseName.caseInsensitiveCompare(exerciseName) == .orderedSame else {
                    return nil
                }

                let candidates = entry.sets
                    .filter { $0.reps > 0 && $0.weight > 0 }
                    .map { set in
                        let estimate = estimatedOneRepMax(
                            weightLbs: inLbs(set.weight, unit: entry.unit),
                            reps: set.reps
                        )
                        return OneRepMaxCandidate(
                            estimatedOneRepMaxLbs: estimate,
                            displayWeight: roundOneRepMax(
                                entry.unit == .kg ? estimate / 2.20462 : estimate,
                                unit: entry.unit
                            ),
                            unit: entry.unit,
                            sourceSummary: "Prefilled from logged \(exerciseName) sets in the completed block."
                        )
                    }

                return candidates.isEmpty ? nil : candidates
            }
        }
        .flatMap { $0 }

        let familyCandidates: [OneRepMaxCandidate]
        if let targetLift = CanonicalLift.from(exerciseName: exerciseName) {
            familyCandidates = workoutsInWindow.flatMap { workout in
                workout.exerciseEntries.compactMap { entry -> [OneRepMaxCandidate]? in
                    guard CanonicalLift.from(exerciseName: entry.exerciseName) == targetLift else {
                        return nil
                    }

                    let candidates = entry.sets
                        .filter { $0.reps > 0 && $0.weight > 0 }
                        .map { set in
                            let estimate = estimatedOneRepMax(
                                weightLbs: inLbs(set.weight, unit: entry.unit),
                                reps: set.reps
                            )
                            return OneRepMaxCandidate(
                                estimatedOneRepMaxLbs: estimate,
                                displayWeight: roundOneRepMax(
                                    entry.unit == .kg ? estimate / 2.20462 : estimate,
                                    unit: entry.unit
                                ),
                                unit: entry.unit,
                                sourceSummary: "Prefilled from \(targetLift.displayName) family work in the completed block."
                            )
                        }

                    return candidates.isEmpty ? nil : candidates
                }
            }
            .flatMap { $0 }
        } else {
            familyCandidates = []
        }

        let best = (exactRecordCandidates + exactWorkoutCandidates + familyCandidates)
            .max(by: { $0.estimatedOneRepMaxLbs < $1.estimatedOneRepMaxLbs })

        guard let best else { return nil }

        return MesocycleOneRepMaxPrefill(
            exerciseName: exerciseName,
            weight: best.displayWeight,
            unit: best.unit,
            sourceSummary: best.sourceSummary
        )
    }

    private static func fitNote(prefix: String, clauses: [String]) -> String {
        "\(prefix): \(clauses.joined(separator: ", "))."
    }

    private static func clampedFitScore(_ score: Int) -> Int {
        min(95, max(35, score))
    }

    private static func normalizedFrequency(
        for focus: ProgramFocus,
        preferred: Int
    ) -> Int {
        let minimum = FocusTemplateLibrary.template(for: focus).minimumFrequency
        return min(6, max(minimum, preferred))
    }

    private static func productiveFollowUpFocus(from focus: ProgramFocus?) -> ProgramFocus {
        switch focus {
        case .bodybuilding, .pushPull:
            return .powerbuilding
        case .generalFitness, .fullBody:
            return .powerbuilding
        case .powerbuilding, .fiveByFive:
            return .powerlifting
        case .increaseMaxSquat, .increaseMaxBench, .increaseMaxDeadlift, .powerlifting:
            return .powerbuilding
        case .cardioEndurance:
            return .generalFitness
        case .none:
            return .fullBody
        }
    }

    private static func stepDownLevel(from level: ProgramLevel) -> ProgramLevel {
        switch level {
        case .advanced:
            return .intermediate
        case .intermediate:
            return .beginner
        case .beginner:
            return .beginner
        }
    }

    private static func consistencyResetFocus(from focus: ProgramFocus?) -> ProgramFocus {
        switch focus {
        case .cardioEndurance:
            return .cardioEndurance
        case .increaseMaxSquat, .increaseMaxBench, .increaseMaxDeadlift, .powerlifting, .fiveByFive:
            return .fullBody
        case .bodybuilding, .powerbuilding, .pushPull, .generalFitness, .fullBody:
            return .generalFitness
        case .none:
            return .generalFitness
        }
    }

    private static func adjacentGrowthFocus(from focus: ProgramFocus) -> ProgramFocus {
        switch focus {
        case .increaseMaxSquat, .increaseMaxBench, .increaseMaxDeadlift, .powerlifting, .fiveByFive:
            return .powerbuilding
        case .powerbuilding:
            return .bodybuilding
        case .bodybuilding:
            return .powerbuilding
        case .generalFitness:
            return .fullBody
        case .fullBody:
            return .powerbuilding
        case .pushPull:
            return .bodybuilding
        case .cardioEndurance:
            return .generalFitness
        }
    }

    private static func balancedFallbackFocus(from focus: ProgramFocus?) -> ProgramFocus {
        switch focus {
        case .cardioEndurance:
            return .fullBody
        case .powerlifting, .increaseMaxSquat, .increaseMaxBench, .increaseMaxDeadlift, .fiveByFive:
            return .generalFitness
        case .powerbuilding, .bodybuilding, .pushPull, .generalFitness, .fullBody:
            return .generalFitness
        case .none:
            return .fullBody
        }
    }

    private static func estimatedOneRepMax(weightLbs: Double, reps: Int) -> Double {
        if reps <= 1 { return weightLbs }
        return weightLbs * (1.0 + Double(reps) / 30.0)
    }

    private static func inLbs(_ weight: Double, unit: WeightUnit) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }

    private static func roundOneRepMax(_ value: Double, unit: WeightUnit) -> Double {
        switch unit {
        case .lbs:
            return (value / 5.0).rounded() * 5.0
        case .kg:
            return (value / 2.5).rounded() * 2.5
        }
    }

    private static func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var ordered: [T] = []

        for value in values where seen.insert(value).inserted {
            ordered.append(value)
        }

        return ordered
    }
}

private struct OneRepMaxCandidate {
    let estimatedOneRepMaxLbs: Double
    let displayWeight: Double
    let unit: WeightUnit
    let sourceSummary: String
}
