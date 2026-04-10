//
//  AdaptiveVariationSwapService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData

/// Automatic, conservative variation swapping for Feature 6.
/// - Runs at weekly cadence from finalized program analyses.
/// - Uses trend + fatigue + recent outcomes to detect plateau/recoverability issues.
/// - Persists non-destructive overlays so base templates remain unchanged.
enum AdaptiveVariationSwapService {
    private static let lookbackWeeks = 4
    private static let recentSwapAvoidanceWindowWeeks = 2

    static func generateAndApply(
        from analysis: WeeklyTrainingAnalysis,
        context: ModelContext
    ) {
        guard
            analysis.isFinalized,
            let run = analysis.programRun,
            let program = analysis.trainingProgram ?? run.program,
            let completedWeek = analysis.programWeekNumber
        else {
            return
        }

        let targetWeek = completedWeek + 1
        guard targetWeek <= program.lengthInWeeks else { return }
        guard let targetWeekTemplate = program.weeks.first(where: { $0.weekNumber == targetWeek }) else { return }
        guard !targetWeekTemplate.isDeloadWeek else { return }

        let allAnalyses = (try? context.fetch(FetchDescriptor<WeeklyTrainingAnalysis>())) ?? []
        let allOutcomes = (try? context.fetch(FetchDescriptor<ExercisePerformanceOutcome>())) ?? []
        let allTrends = (try? context.fetch(FetchDescriptor<LiftPerformanceTrend>())) ?? []
        var allProposals = (try? context.fetch(FetchDescriptor<AdaptationProposal>())) ?? []
        var allOverlays = (try? context.fetch(FetchDescriptor<AppliedProgramOverlay>())) ?? []
        var allEvents = (try? context.fetch(FetchDescriptor<AdaptationEventHistory>())) ?? []

        let profile = inferredProfile(program: program, analysis: analysis)

        let recentAnalyses = allAnalyses
            .filter { $0.programRun?.id == run.id && $0.isFinalized }
            .sorted { lhs, rhs in
                let lw = lhs.programWeekNumber ?? 0
                let rw = rhs.programWeekNumber ?? 0
                if lw == rw { return lhs.weekStartDate < rhs.weekStartDate }
                return lw < rw
            }
        let lookbackWindow = Array(recentAnalyses.suffix(lookbackWeeks))
        guard !lookbackWindow.isEmpty else { return }

        let lookbackStart = lookbackWindow.first?.weekStartDate ?? analysis.weekStartDate
        let relevantOutcomes = allOutcomes
            .filter { outcome in
                guard let lift = outcome.canonicalLiftKey else { return false }
                guard mainLiftKeys.contains(lift) else { return false }
                guard outcome.workoutDate >= lookbackStart && outcome.workoutDate <= analysis.weekEndDate else { return false }
                return outcome.programRun?.id == run.id || outcome.programRun == nil
            }
            .sorted {
                if $0.workoutDate == $1.workoutDate { return $0.id.uuidString < $1.id.uuidString }
                return $0.workoutDate < $1.workoutDate
            }

        let runTrends = allTrends.filter { $0.programRun?.id == run.id }
        let swapTargets = nextWeekSwapTargets(program: program, targetWeek: targetWeek)
        guard !swapTargets.isEmpty else { return }

        let recentSwapNamesByLift = recentSwapsByLift(
            runID: run.id,
            targetWeek: targetWeek,
            overlays: allOverlays
        )
        let existingAppliedLiftKeys = alreadyAppliedLiftKeys(
            runID: run.id,
            targetWeek: targetWeek,
            overlays: allOverlays
        )

        var candidates: [SwapCandidate] = []
        for (liftKey, targets) in swapTargets.sorted(by: { $0.key < $1.key }) {
            guard !existingAppliedLiftKeys.contains(liftKey) else { continue }
            guard let candidate = evaluateSwapCandidate(
                liftKey: liftKey,
                targets: targets,
                analysis: analysis,
                recentAnalyses: lookbackWindow,
                outcomes: relevantOutcomes,
                trends: runTrends,
                profile: profile,
                recentSwapNames: recentSwapNamesByLift[liftKey] ?? []
            ) else {
                continue
            }
            candidates.append(candidate)
        }

        guard !candidates.isEmpty else { return }

        let constrained = constrainCandidates(
            candidates: candidates,
            profile: profile,
            globalFatigue: analysis.fatigueStatus
        )

        for candidate in constrained {
            supersedeOpenVariationProposals(
                runID: run.id,
                targetWeek: targetWeek,
                liftKey: candidate.liftKey,
                excludingProposalID: nil,
                proposals: allProposals
            )

            let proposal = upsertAutoAppliedProposal(
                candidate: candidate,
                analysis: analysis,
                run: run,
                program: program,
                targetWeek: targetWeek,
                proposals: &allProposals,
                context: context
            )

            let overlay = upsertAppliedOverlay(
                candidate: candidate,
                proposal: proposal,
                analysis: analysis,
                run: run,
                program: program,
                targetWeek: targetWeek,
                overlays: &allOverlays,
                context: context
            )

            supersedeOpenVariationProposals(
                runID: run.id,
                targetWeek: targetWeek,
                liftKey: candidate.liftKey,
                excludingProposalID: proposal.id,
                proposals: allProposals
            )
            upsertOverlayEvent(
                candidate: candidate,
                proposal: proposal,
                overlay: overlay,
                analysis: analysis,
                run: run,
                events: &allEvents,
                context: context
            )
        }
    }

    // MARK: - Detection

    private static func evaluateSwapCandidate(
        liftKey: String,
        targets: [ProgramSessionExercise],
        analysis: WeeklyTrainingAnalysis,
        recentAnalyses: [WeeklyTrainingAnalysis],
        outcomes: [ExercisePerformanceOutcome],
        trends: [LiftPerformanceTrend],
        profile: ProgramProfile,
        recentSwapNames: Set<String>
    ) -> SwapCandidate? {
        guard let target = preferredSwapTarget(from: targets, liftKey: liftKey) else { return nil }

        let liftOutcomes = outcomes.filter { $0.canonicalLiftKey == liftKey }
        let focusOutcomes: [ExercisePerformanceOutcome] = {
            let topSets = liftOutcomes.filter(\.isTopSetSignal)
            if !topSets.isEmpty { return Array(topSets.suffix(min(8, topSets.count))) }
            return Array(liftOutcomes.suffix(min(8, liftOutcomes.count)))
        }()
        guard !focusOutcomes.isEmpty else { return nil }

        let behindCount = focusOutcomes.filter {
            $0.performanceScore == .underperformance || $0.performanceScore == .severeUnderperformance
        }.count
        let severeBehind = focusOutcomes.filter { $0.performanceScore == .severeUnderperformance }.count
        let behindRatio = Double(behindCount) / Double(focusOutcomes.count)
        let compositeScore = weightedAverage(values: focusOutcomes.map {
            ($0.performanceScoreValue, max(0.01, $0.signalWeight))
        }) ?? 0

        let trend = trends.first { $0.canonicalLiftKey == liftKey }
        let trendStatus = trend?.trendStatus ?? .insufficientData
        let trendChange = trend?.fourWeekChangePercent ?? 0
        let trendConfidence = trend?.confidenceScore ?? 0
        let trendFatigue = trend?.fatigueStatus ?? .manageable

        let repeatedRecentUnder = repeatedRecentUnderperformance(
            liftKey: liftKey,
            analyses: recentAnalyses
        )

        let plateau =
            trendStatus == .stable &&
            abs(trendChange) < 1.0 &&
            behindRatio >= 0.42 &&
            compositeScore <= -1.5 &&
            repeatedRecentUnder

        let declining =
            trendStatus == .declining &&
            trendConfidence >= 0.30 &&
            (behindRatio >= 0.34 || compositeScore <= -3.0)

        let recoverabilityIssue =
            (analysis.fatigueStatus == .high || analysis.fatigueStatus == .critical ||
             trendFatigue == .high || trendFatigue == .critical) &&
            behindRatio >= 0.30 &&
            repeatedRecentUnder

        guard declining || plateau || recoverabilityIssue else { return nil }

        // Avoid unnecessary novelty: if recent performance recovered, keep current variation.
        if compositeScore >= 1.0 && trendStatus != .declining {
            return nil
        }

        let expectedSourceLift = sourceLiftName(for: liftKey)
        let fatigueDriven = recoverabilityIssue || analysis.fatigueStatus == .high || analysis.fatigueStatus == .critical

        guard let replacement = selectReplacement(
            currentExerciseName: target.exerciseName,
            liftKey: liftKey,
            profile: profile,
            expectedSourceLift: expectedSourceLift,
            fatigueDriven: fatigueDriven,
            recentSwapNames: recentSwapNames
        ) else {
            return nil
        }

        let confidenceBase = min(1.0, (Double(focusOutcomes.count) / 8.0))
        var confidence = (confidenceBase * 0.65) + (trendConfidence * 0.35)
        if severeBehind > 0 { confidence += 0.08 }
        confidence = max(0.25, min(0.95, confidence))

        let reason: AdjustmentReason = {
            if recoverabilityIssue { return .fatigueAccumulation }
            if declining { return .negativeLiftTrend }
            return .plateauDetected
        }()

        let priorityScore: Double = {
            var score = 1.8 + (behindRatio * 2.0)
            if severeBehind > 0 { score += 0.9 }
            if declining { score += 0.7 }
            if recoverabilityIssue { score += 0.7 }
            score += max(0, (-compositeScore / 8.0))
            return score
        }()

        let summary = "Auto-swap \(liftDisplayName(for: liftKey)) variation to \(replacement) for week \(nextWeekNumber(from: analysis))"
        let detail = [
            "lift=\(liftKey)",
            "from=\(target.exerciseName)",
            "to=\(replacement)",
            "profile=\(profile.rawValue)",
            "behind_ratio=\(fmt2(behindRatio))",
            "composite_score=\(fmt1(compositeScore))",
            "trend_status=\(trendStatus.rawValue)",
            "trend_change_pct=\(fmt1(trendChange))",
            "trend_confidence=\(fmt2(trendConfidence))",
            "global_fatigue=\(analysis.fatigueStatus.rawValue)",
            "trend_fatigue=\(trendFatigue.rawValue)",
            "repeated_recent_under=\(repeatedRecentUnder)",
            "fatigue_driven=\(fatigueDriven)"
        ].joined(separator: "; ")

        return SwapCandidate(
            liftKey: liftKey,
            target: target,
            replacementExerciseName: replacement,
            confidence: confidence,
            priorityScore: priorityScore,
            reason: reason,
            summary: summary,
            detail: detail
        )
    }

    private static func repeatedRecentUnderperformance(
        liftKey: String,
        analyses: [WeeklyTrainingAnalysis]
    ) -> Bool {
        let recent = Array(analyses.suffix(2))
        let outcomes = recent
            .flatMap(\.outcomes)
            .filter { $0.canonicalLiftKey == liftKey }
        guard !outcomes.isEmpty else { return false }

        let underCount = outcomes.filter {
            $0.performanceScore == .underperformance || $0.performanceScore == .severeUnderperformance
        }.count
        let ratio = Double(underCount) / Double(outcomes.count)
        return underCount >= 2 && ratio >= 0.45
    }

    // MARK: - Target / Replacement Selection

    private static func nextWeekSwapTargets(
        program: TrainingProgram,
        targetWeek: Int
    ) -> [String: [ProgramSessionExercise]] {
        guard let week = program.weeks.first(where: { $0.weekNumber == targetWeek }) else { return [:] }

        var byLift: [String: [ProgramSessionExercise]] = [:]
        for session in week.sessions {
            for exercise in session.exercises where !exercise.isWarmup {
                guard let liftKey = canonicalLiftKey(
                    forExerciseName: exercise.exerciseName,
                    baseLiftUsed: exercise.baseLiftUsed
                ) else {
                    continue
                }
                guard mainLiftKeys.contains(liftKey) else { continue }
                byLift[liftKey, default: []].append(exercise)
            }
        }
        return byLift
    }

    private static func preferredSwapTarget(
        from targets: [ProgramSessionExercise],
        liftKey: String
    ) -> ProgramSessionExercise? {
        let competition = competitionExerciseName(for: liftKey)
        let sorted = targets.sorted { lhs, rhs in
            if lhs.session?.sessionNumber == rhs.session?.sessionNumber {
                return lhs.orderIndex < rhs.orderIndex
            }
            return (lhs.session?.sessionNumber ?? Int.max) < (rhs.session?.sessionNumber ?? Int.max)
        }

        if let topSet = sorted.first(where: { $0.workingSetStyle == .topSet }) {
            return topSet
        }
        if let comp = sorted.first(where: { $0.exerciseName == competition }) {
            return comp
        }
        if let mappedVariation = sorted.first(where: { FocusTemplateLibrary.loadMapping(for: $0.exerciseName) != nil }) {
            return mappedVariation
        }
        return sorted.first
    }

    private static func selectReplacement(
        currentExerciseName: String,
        liftKey: String,
        profile: ProgramProfile,
        expectedSourceLift: String,
        fatigueDriven: Bool,
        recentSwapNames: Set<String>
    ) -> String? {
        let baseCandidates = replacementCandidates(
            liftKey: liftKey,
            profile: profile,
            fatigueDriven: fatigueDriven
        )
        let continuitySafe = baseCandidates.filter { candidate in
            if candidate == competitionExerciseName(for: liftKey) { return true }
            guard let mapping = FocusTemplateLibrary.loadMapping(for: candidate) else { return false }
            return mapping.sourceLift == expectedSourceLift
        }
        guard !continuitySafe.isEmpty else { return nil }

        let filtered = continuitySafe.filter { $0 != currentExerciseName }
        guard !filtered.isEmpty else { return nil }

        let fresh = filtered.filter { !recentSwapNames.contains($0) }
        if let chosen = fresh.first { return chosen }
        return filtered.first
    }

    private static func replacementCandidates(
        liftKey: String,
        profile: ProgramProfile,
        fatigueDriven: Bool
    ) -> [String] {
        switch liftKey {
        case CanonicalLift.squat.rawValue:
            switch profile {
            case .powerlifting:
                return fatigueDriven
                    ? ["Pause Squat", "Box Squat", "Back Squats", "Front Squat"]
                    : ["Pause Squat", "Front Squat", "Box Squat", "Back Squats"]
            case .powerbuilding:
                return fatigueDriven
                    ? ["Pause Squat", "Front Squat", "Back Squats", "Box Squat"]
                    : ["Front Squat", "Pause Squat", "Box Squat", "Back Squats"]
            case .bodybuilding:
                return ["Front Squat", "Pause Squat", "Back Squats", "Box Squat"]
            case .general:
                return ["Pause Squat", "Front Squat", "Back Squats", "Box Squat"]
            }

        case CanonicalLift.bench.rawValue:
            switch profile {
            case .powerlifting:
                return fatigueDriven
                    ? ["Close Grip Bench Press", "Pause Bench Press", "Bench Press", "Floor Press"]
                    : ["Pause Bench Press", "Close Grip Bench Press", "Floor Press", "Bench Press"]
            case .powerbuilding:
                return fatigueDriven
                    ? ["Close Grip Bench Press", "Incline Bench", "Bench Press", "Pause Bench Press"]
                    : ["Incline Bench", "Close Grip Bench Press", "Pause Bench Press", "Bench Press"]
            case .bodybuilding:
                return ["Incline Bench", "Close Grip Bench Press", "Pause Bench Press", "Bench Press"]
            case .general:
                return ["Pause Bench Press", "Close Grip Bench Press", "Bench Press", "Floor Press"]
            }

        case CanonicalLift.deadlift.rawValue:
            switch profile {
            case .powerlifting:
                return fatigueDriven
                    ? ["Block Pull", "Romanian Deadlift", "Deadlift", "Deficit Deadlift"]
                    : ["Deficit Deadlift", "Block Pull", "Romanian Deadlift", "Deadlift"]
            case .powerbuilding:
                return fatigueDriven
                    ? ["Romanian Deadlift", "Block Pull", "Deadlift", "Deficit Deadlift"]
                    : ["Romanian Deadlift", "Deficit Deadlift", "Block Pull", "Deadlift"]
            case .bodybuilding:
                return ["Romanian Deadlift", "Block Pull", "Deadlift", "Deficit Deadlift"]
            case .general:
                return ["Deficit Deadlift", "Romanian Deadlift", "Deadlift", "Block Pull"]
            }

        default:
            return []
        }
    }

    private static func constrainCandidates(
        candidates: [SwapCandidate],
        profile: ProgramProfile,
        globalFatigue: FatigueStatus
    ) -> [SwapCandidate] {
        guard !candidates.isEmpty else { return [] }

        let maxSwaps: Int = {
            switch profile {
            case .powerlifting: return 1
            case .powerbuilding: return globalFatigue == .high || globalFatigue == .critical ? 1 : 2
            case .bodybuilding: return globalFatigue == .high || globalFatigue == .critical ? 1 : 2
            case .general: return 1
            }
        }()

        return candidates
            .sorted { lhs, rhs in
                if lhs.priorityScore == rhs.priorityScore {
                    return lhs.liftKey < rhs.liftKey
                }
                return lhs.priorityScore > rhs.priorityScore
            }
            .prefix(maxSwaps)
            .map { $0 }
    }

    // MARK: - Persistence

    private static func upsertAutoAppliedProposal(
        candidate: SwapCandidate,
        analysis: WeeklyTrainingAnalysis,
        run: ProgramRun,
        program: TrainingProgram,
        targetWeek: Int,
        proposals: inout [AdaptationProposal],
        context: ModelContext
    ) -> AdaptationProposal {
        let existing = proposals.first(where: {
            $0.sourceAnalysis?.id == analysis.id &&
            $0.proposalType == .variationSwap &&
            $0.targetLiftKey == candidate.liftKey &&
            $0.targetWeekStart == targetWeek
        })

        let proposal: AdaptationProposal
        if let existing {
            proposal = existing
        } else {
            proposal = AdaptationProposal(
                programRun: run,
                trainingProgram: program,
                sourceAnalysis: analysis,
                proposalType: .variationSwap,
                proposalStatus: .autoApplied,
                requiresUserConfirmation: false,
                autoApplyEligible: true,
                confidenceScore: candidate.confidence,
                priority: max(1, Int((candidate.priorityScore * 10).rounded())),
                targetWeekStart: targetWeek,
                targetWeekEnd: targetWeek,
                targetSessionNumber: candidate.target.session?.sessionNumber,
                targetProgramSessionExerciseID: candidate.target.id,
                targetLiftKey: candidate.liftKey,
                swapFromExerciseName: candidate.target.exerciseName,
                swapToExerciseName: candidate.replacementExerciseName,
                adjustmentReason: candidate.reason,
                summaryText: candidate.summary,
                detailText: candidate.detail
            )
            context.insert(proposal)
            proposals.append(proposal)
        }

        proposal.createdAt = Date.now
        proposal.decidedAt = Date.now
        proposal.programRun = run
        proposal.trainingProgram = program
        proposal.sourceAnalysis = analysis
        proposal.proposalType = .variationSwap
        proposal.proposalStatus = .autoApplied
        proposal.requiresUserConfirmation = false
        proposal.autoApplyEligible = true
        proposal.confidenceScore = candidate.confidence
        proposal.priority = max(1, Int((candidate.priorityScore * 10).rounded()))
        proposal.targetWeekStart = targetWeek
        proposal.targetWeekEnd = targetWeek
        proposal.targetSessionNumber = candidate.target.session?.sessionNumber
        proposal.targetProgramSessionExerciseID = candidate.target.id
        proposal.targetLiftKey = candidate.liftKey
        proposal.proposedLoadPercentDelta = nil
        proposal.proposedSetDelta = nil
        proposal.proposedRepDelta = nil
        proposal.proposedDeloadFactor = nil
        proposal.swapFromExerciseName = candidate.target.exerciseName
        proposal.swapToExerciseName = candidate.replacementExerciseName
        proposal.adjustmentReason = candidate.reason
        proposal.summaryText = candidate.summary
        proposal.detailText = candidate.detail
        proposal.expiresAt = programWeekEndDate(runStartDate: run.startDate, weekNumber: targetWeek)

        return proposal
    }

    private static func upsertAppliedOverlay(
        candidate: SwapCandidate,
        proposal: AdaptationProposal,
        analysis: WeeklyTrainingAnalysis,
        run: ProgramRun,
        program: TrainingProgram,
        targetWeek: Int,
        overlays: inout [AppliedProgramOverlay],
        context: ModelContext
    ) -> AppliedProgramOverlay {
        let existing = overlays.first(where: {
            $0.programRun?.id == run.id &&
            $0.sourceProposal?.id == proposal.id
        })

        let overlay: AppliedProgramOverlay
        if let existing {
            overlay = existing
        } else {
            overlay = AppliedProgramOverlay(
                programRun: run,
                trainingProgram: program,
                sourceProposal: proposal,
                effectiveWeekStart: targetWeek,
                effectiveWeekEnd: targetWeek,
                overlayStatus: .active,
                appliedByUserConfirmation: false,
                adjustmentReason: candidate.reason,
                summaryText: candidate.summary
            )
            context.insert(overlay)
            overlays.append(overlay)
        }

        overlay.createdAt = Date.now
        overlay.appliedAt = Date.now
        overlay.programRun = run
        overlay.trainingProgram = program
        overlay.sourceProposal = proposal
        overlay.effectiveWeekStart = targetWeek
        overlay.effectiveWeekEnd = targetWeek
        overlay.overlayStatus = .active
        overlay.appliedByUserConfirmation = false
        overlay.adjustmentReason = candidate.reason
        overlay.summaryText = candidate.summary

        for existingAdjustment in overlay.adjustments {
            context.delete(existingAdjustment)
        }
        overlay.adjustments.removeAll()

        let adjustment = AppliedOverlayAdjustment(
            overlay: overlay,
            sequence: 1,
            targetProgramSessionExerciseID: candidate.target.id,
            targetWeekNumber: targetWeek,
            targetSessionNumber: candidate.target.session?.sessionNumber,
            adjustmentType: .variationSwap,
            replacementExerciseName: candidate.replacementExerciseName,
            adjustmentReason: candidate.reason,
            isAutoApplied: true
        )
        context.insert(adjustment)
        overlay.adjustments = [adjustment]

        proposal.proposalStatus = .autoApplied
        proposal.decidedAt = Date.now

        return overlay
    }

    private static func upsertOverlayEvent(
        candidate: SwapCandidate,
        proposal: AdaptationProposal,
        overlay: AppliedProgramOverlay,
        analysis: WeeklyTrainingAnalysis,
        run: ProgramRun,
        events: inout [AdaptationEventHistory],
        context: ModelContext
    ) {
        let event = events.first(where: {
            $0.eventType == .overlayApplied &&
            $0.overlay?.id == overlay.id
        }) ?? {
            let newEvent = AdaptationEventHistory(
                programRun: run,
                trainingProgram: run.program,
                analysis: analysis,
                proposal: proposal,
                overlay: overlay,
                eventType: .overlayApplied,
                analysisWeekNumber: analysis.programWeekNumber,
                targetLiftKey: candidate.liftKey,
                message: candidate.summary
            )
            context.insert(newEvent)
            events.append(newEvent)
            return newEvent
        }()

        event.timestamp = Date.now
        event.programRun = run
        event.trainingProgram = run.program
        event.analysis = analysis
        event.proposal = proposal
        event.overlay = overlay
        event.eventType = .overlayApplied
        event.analysisWeekNumber = analysis.programWeekNumber
        event.targetLiftKey = candidate.liftKey
        event.message = candidate.summary
        event.explanation = candidate.detail
        event.adjustmentReason = candidate.reason
        event.performanceScoreSnapshot = classifyAggregatePerformance(
            from: analysis.outcomes.filter { $0.canonicalLiftKey == candidate.liftKey }
        )
        event.fatigueStatusSnapshot = analysis.fatigueStatus
        event.liftTrendStatusSnapshot = trendStatusForLift(
            candidate.liftKey,
            analysis: analysis,
            run: run
        )
        event.confidenceSnapshot = candidate.confidence
        event.requiresUserAction = false
        event.userActionTaken = true
    }

    private static func supersedeOpenVariationProposals(
        runID: UUID,
        targetWeek: Int,
        liftKey: String,
        excludingProposalID: UUID?,
        proposals: [AdaptationProposal]
    ) {
        let supersedable: Set<ProposalStatus> = [
            .draft,
            .pendingUserConfirmation,
            .pendingAutoApply
        ]
        for proposal in proposals {
            guard proposal.programRun?.id == runID else { continue }
            guard proposal.proposalType == .variationSwap else { continue }
            guard proposal.targetWeekStart == targetWeek else { continue }
            guard proposal.targetLiftKey == liftKey else { continue }
            guard supersedable.contains(proposal.proposalStatus) else { continue }
            if proposal.id == excludingProposalID { continue }

            proposal.proposalStatus = .superseded
            proposal.decidedAt = Date.now
        }
    }

    // MARK: - Existing Overlay Introspection

    private static func alreadyAppliedLiftKeys(
        runID: UUID,
        targetWeek: Int,
        overlays: [AppliedProgramOverlay]
    ) -> Set<String> {
        var keys: Set<String> = []
        for overlay in overlays where overlay.programRun?.id == runID {
            guard overlay.overlayStatus == .active else { continue }
            guard overlay.effectiveWeekStart <= targetWeek else { continue }
            if let end = overlay.effectiveWeekEnd, end < targetWeek { continue }

            for adjustment in overlay.adjustments where adjustment.adjustmentType == .variationSwap {
                let liftKey = canonicalLiftKey(
                    forExerciseName: adjustment.replacementExerciseName ?? "",
                    baseLiftUsed: nil
                ) ?? canonicalLiftKey(
                    forExerciseName: overlay.summaryText ?? "",
                    baseLiftUsed: nil
                )
                if let liftKey {
                    keys.insert(liftKey)
                }
            }
        }
        return keys
    }

    private static func recentSwapsByLift(
        runID: UUID,
        targetWeek: Int,
        overlays: [AppliedProgramOverlay]
    ) -> [String: Set<String>] {
        let minWeek = max(1, targetWeek - recentSwapAvoidanceWindowWeeks)
        var result: [String: Set<String>] = [:]

        for overlay in overlays where overlay.programRun?.id == runID {
            guard overlay.overlayStatus != .reverted else { continue }
            guard overlay.effectiveWeekStart >= minWeek && overlay.effectiveWeekStart < targetWeek else { continue }

            for adjustment in overlay.adjustments where adjustment.adjustmentType == .variationSwap {
                guard let replacement = adjustment.replacementExerciseName else { continue }
                guard let liftKey = canonicalLiftKey(forExerciseName: replacement, baseLiftUsed: nil) else { continue }
                result[liftKey, default: []].insert(replacement)
            }
        }

        return result
    }

    // MARK: - Helpers

    private static let mainLiftKeys: Set<String> = Set([CanonicalLift.squat, .bench, .deadlift].map(\.rawValue))

    private static func canonicalLiftKey(
        forExerciseName exerciseName: String,
        baseLiftUsed: String?
    ) -> String? {
        let mappedSource = FocusTemplateLibrary.loadMapping(for: exerciseName)?.sourceLift
        let normalized = (baseLiftUsed ?? mappedSource ?? exerciseName).lowercased()

        if normalized.contains(CanonicalLift.squat.rawValue) { return CanonicalLift.squat.rawValue }
        if normalized.contains(CanonicalLift.bench.rawValue) { return CanonicalLift.bench.rawValue }
        if normalized.contains(CanonicalLift.deadlift.rawValue) { return CanonicalLift.deadlift.rawValue }
        return nil
    }

    private static func sourceLiftName(for liftKey: String) -> String {
        switch liftKey {
        case CanonicalLift.squat.rawValue:    return CanonicalLift.squat.variationNames[0]
        case CanonicalLift.bench.rawValue:    return CanonicalLift.bench.variationNames[0]
        case CanonicalLift.deadlift.rawValue: return CanonicalLift.deadlift.variationNames[0]
        default: return liftKey
        }
    }

    private static func competitionExerciseName(for liftKey: String) -> String {
        switch liftKey {
        case CanonicalLift.squat.rawValue:    return CanonicalLift.squat.variationNames[0]
        case CanonicalLift.bench.rawValue:    return CanonicalLift.bench.variationNames[0]
        case CanonicalLift.deadlift.rawValue: return CanonicalLift.deadlift.variationNames[0]
        default: return liftKey
        }
    }

    private static func liftDisplayName(for key: String) -> String {
        switch key {
        case CanonicalLift.squat.rawValue:    return CanonicalLift.squat.displayName
        case CanonicalLift.bench.rawValue:    return CanonicalLift.bench.displayName
        case CanonicalLift.deadlift.rawValue: return CanonicalLift.deadlift.displayName
        default: return key.capitalized
        }
    }

    private static func weightedAverage(values: [(Double, Double)]) -> Double? {
        let valid = values.filter { $0.1 > 0 }
        guard !valid.isEmpty else { return nil }
        let numerator = valid.reduce(0.0) { $0 + ($1.0 * $1.1) }
        let denominator = valid.reduce(0.0) { $0 + $1.1 }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    private static func trendStatusForLift(
        _ liftKey: String,
        analysis: WeeklyTrainingAnalysis,
        run: ProgramRun
    ) -> LiftTrendStatus? {
        let outcomeScores = analysis.outcomes.filter { $0.canonicalLiftKey == liftKey }.map(\.performanceScoreValue)
        guard !outcomeScores.isEmpty else { return nil }
        let avg = outcomeScores.reduce(0.0, +) / Double(outcomeScores.count)
        if avg >= 3 { return .improving }
        if avg <= -3 { return .declining }
        return .stable
    }

    private static func classifyAggregatePerformance(
        from outcomes: [ExercisePerformanceOutcome]
    ) -> PerformanceScore {
        guard !outcomes.isEmpty else { return .insufficientData }
        let score = weightedAverage(values: outcomes.map {
            ($0.performanceScoreValue, max(0.01, $0.signalWeight))
        }) ?? 0
        if score <= -12 { return .severeUnderperformance }
        if score <= -4 { return .underperformance }
        if score < 4 { return .onTarget }
        if score < 12 { return .overperformance }
        return .exceptionalPerformance
    }

    private static func nextWeekNumber(from analysis: WeeklyTrainingAnalysis) -> Int {
        (analysis.programWeekNumber ?? 0) + 1
    }

    private static func inferredProfile(
        program: TrainingProgram,
        analysis: WeeklyTrainingAnalysis
    ) -> ProgramProfile {
        if let focus = analysis.focusSnapshot {
            switch focus {
            case .powerlifting: return .powerlifting
            case .powerbuilding: return .powerbuilding
            case .bodybuilding: return .bodybuilding
            default: break
            }
        }

        let text = "\(program.name) \(program.descriptionText ?? "")".lowercased()
        if text.contains("powerbuilding") { return .powerbuilding }
        if text.contains("bodybuilding") { return .bodybuilding }
        if text.contains("powerlifting") ||
            text.contains(CanonicalLift.squat.rawValue) ||
            text.contains(CanonicalLift.bench.rawValue) ||
            text.contains(CanonicalLift.deadlift.rawValue) {
            return .powerlifting
        }
        return .general
    }

    private static func programWeekEndDate(
        runStartDate: Date,
        weekNumber: Int
    ) -> Date? {
        let calendar = Calendar.autoupdatingCurrent
        let startOfRun = calendar.startOfDay(for: runStartDate)
        guard let weekStart = calendar.date(byAdding: .day, value: max(0, (weekNumber - 1) * 7), to: startOfRun) else {
            return nil
        }
        guard let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return nil
        }
        return nextWeekStart.addingTimeInterval(-1)
    }

    private static func fmt1(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", value)
    }

    private static func fmt2(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }
}

private struct SwapCandidate {
    let liftKey: String
    let target: ProgramSessionExercise
    let replacementExerciseName: String
    let confidence: Double
    let priorityScore: Double
    let reason: AdjustmentReason
    let summary: String
    let detail: String
}

private enum ProgramProfile: String {
    case powerlifting
    case powerbuilding
    case bodybuilding
    case general
}
