//
//  AdaptiveFatigueDeloadService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData

/// Weekly fatigue detection and deload/downshift proposal engine for Feature 6.
/// - Uses performance-only training signals (no readiness inputs).
/// - Runs on finalized program weeks at weekly cadence.
/// - Persists explainable, user-confirmed proposals without mutating base templates.
enum AdaptiveFatigueDeloadService {
    private static let lookbackWeeks = 4
    private static let highEffortRPEThreshold = 8.5
    private static let lowRIRThreshold = 1.0

    static func generateProposals(
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

        let allAnalyses = (try? context.fetch(FetchDescriptor<WeeklyTrainingAnalysis>())) ?? []
        let allTrends = (try? context.fetch(FetchDescriptor<LiftPerformanceTrend>())) ?? []
        var allProposals = (try? context.fetch(FetchDescriptor<AdaptationProposal>())) ?? []
        var allEvents = (try? context.fetch(FetchDescriptor<AdaptationEventHistory>())) ?? []

        let runAnalyses = allAnalyses
            .filter { $0.programRun?.id == run.id && $0.isFinalized }
            .sorted { lhs, rhs in
                let lw = lhs.programWeekNumber ?? 0
                let rw = rhs.programWeekNumber ?? 0
                if lw == rw { return lhs.weekStartDate < rhs.weekStartDate }
                return lw < rw
            }
        let recentAnalyses = Array(runAnalyses.suffix(lookbackWeeks))
        guard !recentAnalyses.isEmpty else { return }

        let signal = buildFatigueSignal(
            analysis: analysis,
            recentAnalyses: recentAnalyses,
            trends: allTrends,
            runID: run.id
        )
        let decision = decideAction(from: signal, recentAnalyses: recentAnalyses)

        if decision.action == .none {
            upsertFatigueCheckEvent(
                run: run,
                analysis: analysis,
                signal: signal,
                decision: decision,
                events: &allEvents,
                context: context
            )
            return
        }

        supersedeConflictingProposals(
            runID: run.id,
            targetWeek: targetWeek,
            aggressive: decision.action == .deload,
            excludingProposalID: nil,
            proposals: allProposals
        )

        let proposal = upsertFatigueProposal(
            analysis: analysis,
            run: run,
            program: program,
            targetWeek: targetWeek,
            signal: signal,
            decision: decision,
            proposals: &allProposals,
            context: context
        )

        supersedeConflictingProposals(
            runID: run.id,
            targetWeek: targetWeek,
            aggressive: decision.action == .deload,
            excludingProposalID: proposal.id,
            proposals: allProposals
        )

        upsertProposalEvent(
            proposal: proposal,
            run: run,
            analysis: analysis,
            signal: signal,
            decision: decision,
            events: &allEvents,
            context: context
        )
    }

    // MARK: - Signal Detection

    private static func buildFatigueSignal(
        analysis: WeeklyTrainingAnalysis,
        recentAnalyses: [WeeklyTrainingAnalysis],
        trends: [LiftPerformanceTrend],
        runID: UUID
    ) -> FatigueSignalSummary {
        let recentOutcomes = recentAnalyses
            .flatMap(\.outcomes)
            .sorted {
                if $0.workoutDate == $1.workoutDate { return $0.id.uuidString < $1.id.uuidString }
                return $0.workoutDate < $1.workoutDate
            }
        let currentWeekOutcomes = analysis.outcomes

        let repeatedBehind = detectRepeatedBehindPerformance(recentAnalyses: recentAnalyses)
        let repeatedTopSetUnder = detectRepeatedTopSetUnderperformance(recentAnalyses: recentAnalyses)
        let sustainedHighEffort = detectSustainedHighEffort(outcomes: recentOutcomes)
        let regression = detectPerformanceRegression(recentAnalyses: recentAnalyses)
        let excessiveVolume = detectExcessiveVolumeExposure(
            analysis: analysis,
            recentAnalyses: recentAnalyses
        )
        let decliningMainLifts = trends.filter {
            $0.programRun?.id == runID &&
            ($0.canonicalLiftKey == "squat" || $0.canonicalLiftKey == "bench" || $0.canonicalLiftKey == "deadlift") &&
            $0.trendStatus == .declining &&
            $0.confidenceScore >= 0.35
        }.count
        let localOnly = detectLocalizedUnderperformance(
            analysis: analysis,
            outcomes: currentWeekOutcomes,
            excessiveVolume: excessiveVolume.triggered,
            regression: regression.triggered,
            decliningMainLifts: decliningMainLifts
        )

        var score = baseRiskScore(for: analysis.fatigueStatus)
        var signalCount = 0

        if repeatedBehind.triggered {
            score += 1.6
            signalCount += 1
        }
        if repeatedTopSetUnder.triggered {
            score += 1.4
            signalCount += 1
        }
        if sustainedHighEffort.triggered {
            score += 0.9
            signalCount += 1
        }
        if regression.triggered {
            score += 1.4
            signalCount += 1
        }
        if excessiveVolume.triggered {
            score += 1.1
            signalCount += 1
        }
        if decliningMainLifts >= 2 {
            score += 0.9
            signalCount += 1
        }
        if localOnly {
            // Localized misses should route to lift-specific logic, not global deload.
            score -= 1.8
        }

        score = max(0, min(10, score))

        return FatigueSignalSummary(
            riskScore: score,
            signalCount: signalCount,
            repeatedBehind: repeatedBehind,
            repeatedTopSetUnder: repeatedTopSetUnder,
            sustainedHighEffort: sustainedHighEffort,
            performanceRegression: regression,
            excessiveVolume: excessiveVolume,
            decliningMainLifts: decliningMainLifts,
            localizedUnderperformance: localOnly,
            fatigueStatus: analysis.fatigueStatus
        )
    }

    private static func detectRepeatedBehindPerformance(
        recentAnalyses: [WeeklyTrainingAnalysis]
    ) -> SignalMetric {
        let recentTwo = Array(recentAnalyses.suffix(2))
        let outcomes = recentTwo.flatMap(\.outcomes)
        guard !outcomes.isEmpty else {
            return SignalMetric(triggered: false, value: 0, threshold: 0, description: "insufficient_outcomes")
        }

        let behindCount = outcomes.filter {
            $0.performanceScore == .underperformance || $0.performanceScore == .severeUnderperformance
        }.count
        let ratio = Double(behindCount) / Double(outcomes.count)
        let triggered = behindCount >= 5 && ratio >= 0.38

        return SignalMetric(
            triggered: triggered,
            value: ratio,
            threshold: 0.38,
            description: "behind_ratio_2w=\(fmt2(ratio)); behind_count=\(behindCount)"
        )
    }

    private static func detectRepeatedTopSetUnderperformance(
        recentAnalyses: [WeeklyTrainingAnalysis]
    ) -> SignalMetric {
        let recentTwo = Array(recentAnalyses.suffix(2))
        let topSets = recentTwo
            .flatMap(\.outcomes)
            .filter(\.isTopSetSignal)
        guard !topSets.isEmpty else {
            return SignalMetric(triggered: false, value: 0, threshold: 0, description: "insufficient_top_sets")
        }

        let underTopSets = topSets.filter {
            $0.performanceScore == .underperformance || $0.performanceScore == .severeUnderperformance
        }.count
        let ratio = Double(underTopSets) / Double(topSets.count)
        let triggered = underTopSets >= 3 && ratio >= 0.45

        return SignalMetric(
            triggered: triggered,
            value: ratio,
            threshold: 0.45,
            description: "top_set_under_ratio_2w=\(fmt2(ratio)); under_top_sets=\(underTopSets)"
        )
    }

    private static func detectSustainedHighEffort(
        outcomes: [ExercisePerformanceOutcome]
    ) -> SignalMetric {
        guard !outcomes.isEmpty else {
            return SignalMetric(triggered: false, value: 0, threshold: 0, description: "insufficient_outcomes")
        }

        let highEffortOutcomes = outcomes.filter {
            ($0.prescribedTargetRPE ?? 0) >= highEffortRPEThreshold ||
            (($0.prescribedTargetRIR ?? 99) <= lowRIRThreshold)
        }
        guard !highEffortOutcomes.isEmpty else {
            return SignalMetric(triggered: false, value: 0, threshold: 0, description: "no_high_effort_targets")
        }

        let highEffortUnder = highEffortOutcomes.filter {
            $0.performanceScore == .underperformance || $0.performanceScore == .severeUnderperformance
        }.count
        let ratio = Double(highEffortUnder) / Double(highEffortOutcomes.count)
        let triggered = highEffortOutcomes.count >= 4 && ratio >= 0.35

        return SignalMetric(
            triggered: triggered,
            value: ratio,
            threshold: 0.35,
            description: "high_effort_under_ratio=\(fmt2(ratio)); high_effort_samples=\(highEffortOutcomes.count)"
        )
    }

    private static func detectPerformanceRegression(
        recentAnalyses: [WeeklyTrainingAnalysis]
    ) -> SignalMetric {
        guard recentAnalyses.count >= 3 else {
            return SignalMetric(triggered: false, value: 0, threshold: 0, description: "insufficient_week_history")
        }

        guard let current = recentAnalyses.last else {
            return SignalMetric(triggered: false, value: 0, threshold: 0, description: "missing_current")
        }
        let baselineSlice = recentAnalyses.dropLast().suffix(2)
        let baseline = baselineSlice.reduce(0.0) { $0 + $1.weightedPerformanceScore } / Double(max(1, baselineSlice.count))
        let delta = current.weightedPerformanceScore - baseline
        let triggered = delta <= -5.0

        return SignalMetric(
            triggered: triggered,
            value: delta,
            threshold: -5.0,
            description: "performance_delta_vs_2w_baseline=\(fmt1(delta))"
        )
    }

    private static func detectExcessiveVolumeExposure(
        analysis: WeeklyTrainingAnalysis,
        recentAnalyses: [WeeklyTrainingAnalysis]
    ) -> SignalMetric {
        let weekRatio: Double = {
            let planned = analysis.volumeMetrics.compactMap(\.plannedHardSets).reduce(0.0, +)
            let completed = analysis.volumeMetrics.reduce(0.0) { $0 + $1.completedHardSets }
            guard planned > 0 else { return 0 }
            return completed / planned
        }()

        let fatigueRatio: Double = {
            guard let planned = analysis.plannedFatigueScore, planned > 0 else { return 0 }
            return analysis.observedFatigueScore / planned
        }()

        let recentOverTargetWeeks = recentAnalyses.filter { weekly in
            let planned = weekly.volumeMetrics.compactMap(\.plannedHardSets).reduce(0.0, +)
            let completed = weekly.volumeMetrics.reduce(0.0) { $0 + $1.completedHardSets }
            guard planned > 0 else { return false }
            return completed / planned >= 1.18
        }.count

        let triggered =
            weekRatio >= 1.20 ||
            fatigueRatio >= 1.22 ||
            recentOverTargetWeeks >= 2

        let value = max(weekRatio, fatigueRatio)
        return SignalMetric(
            triggered: triggered,
            value: value,
            threshold: 1.20,
            description: "volume_ratio=\(fmt2(weekRatio)); fatigue_ratio=\(fmt2(fatigueRatio)); over_target_weeks=\(recentOverTargetWeeks)"
        )
    }

    private static func detectLocalizedUnderperformance(
        analysis: WeeklyTrainingAnalysis,
        outcomes: [ExercisePerformanceOutcome],
        excessiveVolume: Bool,
        regression: Bool,
        decliningMainLifts: Int
    ) -> Bool {
        let topSetUnder = outcomes.filter { outcome in
            outcome.isTopSetSignal &&
            (outcome.performanceScore == .underperformance || outcome.performanceScore == .severeUnderperformance)
        }
        guard topSetUnder.count >= 3 else { return false }

        let grouped = Dictionary(grouping: topSetUnder, by: { $0.canonicalLiftKey ?? "unknown" })
        let maxBucket = grouped.values.map(\.count).max() ?? 0
        let concentration = Double(maxBucket) / Double(topSetUnder.count)

        let manageableGlobal = analysis.fatigueStatus == .low || analysis.fatigueStatus == .manageable
        return manageableGlobal && concentration >= 0.75 && !excessiveVolume && !regression && decliningMainLifts <= 1
    }

    private static func baseRiskScore(for status: FatigueStatus) -> Double {
        switch status {
        case .low: return 1.0
        case .manageable: return 2.0
        case .elevated: return 3.5
        case .high: return 4.8
        case .critical: return 5.8
        }
    }

    // MARK: - Decisions

    private static func decideAction(
        from signal: FatigueSignalSummary,
        recentAnalyses: [WeeklyTrainingAnalysis]
    ) -> FatigueDecision {
        let enoughHistory = recentAnalyses.count >= 2
        let highFatigue = signal.fatigueStatus == .high || signal.fatigueStatus == .critical

        let severeTrigger =
            signal.riskScore >= 6.2 &&
            signal.signalCount >= 3 &&
            !signal.localizedUnderperformance &&
            enoughHistory

        let fallbackDeloadTrigger =
            highFatigue &&
            (
                signal.repeatedBehind.triggered ||
                signal.performanceRegression.triggered ||
                signal.excessiveVolume.triggered
            ) &&
            !signal.localizedUnderperformance

        if severeTrigger || fallbackDeloadTrigger {
            return FatigueDecision(
                action: .deload,
                confidence: min(1.0, signal.riskScore / 8.0),
                deloadFactor: signal.riskScore >= 7.4 ? 0.88 : 0.92,
                loadPercentDelta: signal.riskScore >= 7.4 ? -0.10 : -0.07,
                setDelta: -1,
                summary: "Recommend deload week to restore recovery before week progression",
                detailSuffix: "action=deload; reduce_intensity=true; reduce_volume=true; reduce_top_set_exposure=true"
            )
        }

        let moderateTrigger =
            signal.riskScore >= 4.8 &&
            signal.signalCount >= 2 &&
            !signal.localizedUnderperformance &&
            enoughHistory

        if moderateTrigger {
            return FatigueDecision(
                action: .downshift,
                confidence: min(1.0, signal.riskScore / 9.0),
                deloadFactor: nil,
                loadPercentDelta: -0.04,
                setDelta: -1,
                summary: "Recommend conservative downshift week to control accumulating fatigue",
                detailSuffix: "action=downshift; reduce_intensity=true; reduce_volume=true; trim_top_set_exposure=true"
            )
        }

        return FatigueDecision(
            action: .none,
            confidence: min(1.0, signal.riskScore / 10.0),
            deloadFactor: nil,
            loadPercentDelta: nil,
            setDelta: nil,
            summary: "No global fatigue deload needed this week",
            detailSuffix: "action=none"
        )
    }

    // MARK: - Proposal Persistence

    private static func upsertFatigueProposal(
        analysis: WeeklyTrainingAnalysis,
        run: ProgramRun,
        program: TrainingProgram,
        targetWeek: Int,
        signal: FatigueSignalSummary,
        decision: FatigueDecision,
        proposals: inout [AdaptationProposal],
        context: ModelContext
    ) -> AdaptationProposal {
        let type: ProposalType = {
            switch decision.action {
            case .deload: return .deload
            case .downshift: return .decreaseLoad
            case .none: return .deload
            }
        }()

        let existing = proposals.first(where: {
            $0.sourceAnalysis?.id == analysis.id &&
            $0.targetWeekStart == targetWeek &&
            $0.proposalType == type &&
            $0.targetLiftKey == "globalFatigue"
        })

        let proposal: AdaptationProposal
        if let existing {
            proposal = existing
        } else {
            proposal = AdaptationProposal(
                programRun: run,
                trainingProgram: program,
                sourceAnalysis: analysis,
                proposalType: type,
                proposalStatus: .pendingUserConfirmation,
                requiresUserConfirmation: true,
                autoApplyEligible: false,
                confidenceScore: decision.confidence,
                priority: decision.action == .deload ? 98 : 88,
                targetWeekStart: targetWeek,
                targetWeekEnd: targetWeek,
                targetLiftKey: "globalFatigue",
                adjustmentReason: .fatigueAccumulation,
                summaryText: "\(decision.summary) (Week \(targetWeek))",
                detailText: proposalDetail(signal: signal, decision: decision)
            )
            context.insert(proposal)
            proposals.append(proposal)
        }

        proposal.createdAt = Date.now
        proposal.decidedAt = nil
        proposal.programRun = run
        proposal.trainingProgram = program
        proposal.sourceAnalysis = analysis
        proposal.proposalType = type
        proposal.proposalStatus = .pendingUserConfirmation
        proposal.requiresUserConfirmation = true
        proposal.autoApplyEligible = false
        proposal.confidenceScore = decision.confidence
        proposal.priority = decision.action == .deload ? 98 : 88
        proposal.targetWeekStart = targetWeek
        proposal.targetWeekEnd = targetWeek
        proposal.targetSessionNumber = nil
        proposal.targetProgramSessionExerciseID = nil
        proposal.targetLiftKey = "globalFatigue"
        proposal.proposedLoadPercentDelta = decision.loadPercentDelta
        proposal.proposedSetDelta = decision.setDelta
        proposal.proposedRepDelta = nil
        proposal.proposedDeloadFactor = decision.deloadFactor
        proposal.swapFromExerciseName = nil
        proposal.swapToExerciseName = nil
        proposal.adjustmentReason = .fatigueAccumulation
        proposal.summaryText = "\(decision.summary) (Week \(targetWeek))"
        proposal.detailText = proposalDetail(signal: signal, decision: decision)
        proposal.expiresAt = programWeekEndDate(
            runStartDate: run.startDate,
            weekNumber: targetWeek
        )

        return proposal
    }

    private static func supersedeConflictingProposals(
        runID: UUID,
        targetWeek: Int,
        aggressive: Bool,
        excludingProposalID: UUID?,
        proposals: [AdaptationProposal]
    ) {
        let supersedable: Set<ProposalStatus> = [
            .draft,
            .pendingUserConfirmation,
            .pendingAutoApply
        ]

        let conflictTypes: Set<ProposalType> = aggressive
            ? [.increaseLoad, .decreaseLoad, .increaseVolume, .decreaseVolume, .variationSwap, .deload]
            : [.increaseLoad, .increaseVolume, .decreaseLoad, .deload]

        for proposal in proposals {
            guard proposal.programRun?.id == runID else { continue }
            guard proposal.targetWeekStart == targetWeek else { continue }
            guard supersedable.contains(proposal.proposalStatus) else { continue }
            guard conflictTypes.contains(proposal.proposalType) else { continue }
            if proposal.id == excludingProposalID { continue }

            proposal.proposalStatus = .superseded
            proposal.decidedAt = Date.now
        }
    }

    // MARK: - Events

    private static func upsertProposalEvent(
        proposal: AdaptationProposal,
        run: ProgramRun,
        analysis: WeeklyTrainingAnalysis,
        signal: FatigueSignalSummary,
        decision: FatigueDecision,
        events: inout [AdaptationEventHistory],
        context: ModelContext
    ) {
        let event = events.first(where: {
            $0.eventType == .proposalCreated &&
            $0.proposal?.id == proposal.id
        }) ?? {
            let newEvent = AdaptationEventHistory(
                programRun: run,
                trainingProgram: run.program,
                analysis: analysis,
                proposal: proposal,
                eventType: .proposalCreated,
                analysisWeekNumber: analysis.programWeekNumber,
                targetLiftKey: proposal.targetLiftKey,
                message: proposal.summaryText
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
        event.overlay = nil
        event.eventType = .proposalCreated
        event.analysisWeekNumber = analysis.programWeekNumber
        event.targetLiftKey = proposal.targetLiftKey
        event.message = proposal.summaryText
        event.explanation = proposal.detailText
        event.adjustmentReason = proposal.adjustmentReason
        event.performanceScoreSnapshot = classifyPerformance(
            recentPerformanceAverage(from: analysis)
        )
        event.fatigueStatusSnapshot = analysis.fatigueStatus
        event.liftTrendStatusSnapshot = nil
        event.confidenceSnapshot = decision.confidence
        event.requiresUserAction = true
        event.userActionTaken = false
    }

    private static func upsertFatigueCheckEvent(
        run: ProgramRun,
        analysis: WeeklyTrainingAnalysis,
        signal: FatigueSignalSummary,
        decision: FatigueDecision,
        events: inout [AdaptationEventHistory],
        context: ModelContext
    ) {
        let event = events.first(where: {
            $0.eventType == .trendUpdated &&
            $0.analysis?.id == analysis.id &&
            $0.targetLiftKey == "globalFatigue"
        }) ?? {
            let newEvent = AdaptationEventHistory(
                programRun: run,
                trainingProgram: run.program,
                analysis: analysis,
                proposal: nil,
                eventType: .trendUpdated,
                analysisWeekNumber: analysis.programWeekNumber,
                targetLiftKey: "globalFatigue",
                message: "Fatigue check completed"
            )
            context.insert(newEvent)
            events.append(newEvent)
            return newEvent
        }()

        event.timestamp = Date.now
        event.programRun = run
        event.trainingProgram = run.program
        event.analysis = analysis
        event.proposal = nil
        event.overlay = nil
        event.eventType = .trendUpdated
        event.analysisWeekNumber = analysis.programWeekNumber
        event.targetLiftKey = "globalFatigue"
        event.message = decision.summary
        event.explanation = proposalDetail(signal: signal, decision: decision)
        event.adjustmentReason = .programSignalPriority
        event.performanceScoreSnapshot = classifyPerformance(
            recentPerformanceAverage(from: analysis)
        )
        event.fatigueStatusSnapshot = analysis.fatigueStatus
        event.liftTrendStatusSnapshot = nil
        event.confidenceSnapshot = decision.confidence
        event.requiresUserAction = false
        event.userActionTaken = false
    }

    // MARK: - Formatting / Helpers

    private static func proposalDetail(
        signal: FatigueSignalSummary,
        decision: FatigueDecision
    ) -> String {
        [
            "fatigue_risk_score=\(fmt2(signal.riskScore))",
            "signal_count=\(signal.signalCount)",
            "fatigue_status=\(signal.fatigueStatus.rawValue)",
            "repeated_behind=\(signal.repeatedBehind.triggered) [\(signal.repeatedBehind.description)]",
            "repeated_top_set_under=\(signal.repeatedTopSetUnder.triggered) [\(signal.repeatedTopSetUnder.description)]",
            "sustained_high_effort=\(signal.sustainedHighEffort.triggered) [\(signal.sustainedHighEffort.description)]",
            "performance_regression=\(signal.performanceRegression.triggered) [\(signal.performanceRegression.description)]",
            "excessive_volume=\(signal.excessiveVolume.triggered) [\(signal.excessiveVolume.description)]",
            "declining_main_lifts=\(signal.decliningMainLifts)",
            "localized_underperformance=\(signal.localizedUnderperformance)",
            "proposed_load_delta_pct=\(fmtPercent(decision.loadPercentDelta))",
            "proposed_set_delta=\(decision.setDelta.map(String.init) ?? "n/a")",
            "proposed_deload_factor=\(fmt2(decision.deloadFactor))",
            decision.detailSuffix
        ].joined(separator: "; ")
    }

    private static func recentPerformanceAverage(from analysis: WeeklyTrainingAnalysis) -> Double {
        let pairs = analysis.outcomes.map { ($0.performanceScoreValue, max(0.01, $0.signalWeight)) }
        return weightedAverage(values: pairs) ?? analysis.weightedPerformanceScore
    }

    private static func classifyPerformance(_ score: Double) -> PerformanceScore {
        if score <= -12 { return .severeUnderperformance }
        if score <= -4 { return .underperformance }
        if score < 4 { return .onTarget }
        if score < 12 { return .overperformance }
        return .exceptionalPerformance
    }

    private static func weightedAverage(values: [(Double, Double)]) -> Double? {
        let valid = values.filter { $0.1 > 0 }
        guard !valid.isEmpty else { return nil }
        let numerator = valid.reduce(0.0) { $0 + ($1.0 * $1.1) }
        let denominator = valid.reduce(0.0) { $0 + $1.1 }
        guard denominator > 0 else { return nil }
        return numerator / denominator
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

    private static func fmtPercent(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f%%", value * 100.0)
    }
}

private struct SignalMetric {
    let triggered: Bool
    let value: Double
    let threshold: Double
    let description: String
}

private struct FatigueSignalSummary {
    let riskScore: Double
    let signalCount: Int
    let repeatedBehind: SignalMetric
    let repeatedTopSetUnder: SignalMetric
    let sustainedHighEffort: SignalMetric
    let performanceRegression: SignalMetric
    let excessiveVolume: SignalMetric
    let decliningMainLifts: Int
    let localizedUnderperformance: Bool
    let fatigueStatus: FatigueStatus
}

private enum FatigueAction {
    case none
    case downshift
    case deload
}

private struct FatigueDecision {
    let action: FatigueAction
    let confidence: Double
    let deloadFactor: Double?
    let loadPercentDelta: Double?
    let setDelta: Int?
    let summary: String
    let detailSuffix: String
}
