//
//  AdaptiveLoadProgressionService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData

/// Weekly top-set-driven load adaptation proposal engine for Feature 6.
/// - Uses finalized weekly analysis as the cadence trigger.
/// - Produces deterministic lift-family proposals for future weeks.
/// - Persists recommendations as non-destructive overlays (AdaptationProposal),
///   leaving base program templates unchanged.
enum AdaptiveLoadProgressionService {
    private static let mainLiftKeys: Set<String> = ["squat", "bench", "deadlift"]
    private static let lookbackDays = 84

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

        let targetsByLift = nextWeekTargetsByLift(
            program: program,
            targetWeek: targetWeek
        )
        guard !targetsByLift.isEmpty else { return }

        let fetchedOutcomes = (try? context.fetch(FetchDescriptor<ExercisePerformanceOutcome>())) ?? []
        let fetchedTrends = (try? context.fetch(FetchDescriptor<LiftPerformanceTrend>())) ?? []
        var proposals = (try? context.fetch(FetchDescriptor<AdaptationProposal>())) ?? []
        var events = (try? context.fetch(FetchDescriptor<AdaptationEventHistory>())) ?? []

        let level = inferredLevel(for: program)

        for (liftKey, targets) in targetsByLift.sorted(by: { $0.key < $1.key }) {
            let decision = decideLiftAction(
                liftKey: liftKey,
                targets: targets,
                analysis: analysis,
                run: run,
                level: level,
                outcomes: fetchedOutcomes,
                trends: fetchedTrends
            )

            supersedeOpenProposals(
                run: run,
                liftKey: liftKey,
                targetWeek: targetWeek,
                excludingProposalID: nil,
                proposals: proposals
            )

            switch decision.action {
            case .maintain:
                upsertMaintainEvent(
                    liftKey: liftKey,
                    decision: decision,
                    analysis: analysis,
                    run: run,
                    targetWeek: targetWeek,
                    events: &events,
                    context: context
                )

            case .increase, .decrease, .simplify:
                let proposal = upsertProposal(
                    liftKey: liftKey,
                    decision: decision,
                    targets: targets,
                    analysis: analysis,
                    run: run,
                    program: program,
                    targetWeek: targetWeek,
                    proposals: &proposals,
                    context: context
                )

                supersedeOpenProposals(
                    run: run,
                    liftKey: liftKey,
                    targetWeek: targetWeek,
                    excludingProposalID: proposal.id,
                    proposals: proposals
                )
                upsertProposalEvent(
                    proposal: proposal,
                    analysis: analysis,
                    run: run,
                    decision: decision,
                    events: &events,
                    context: context
                )
            }
        }
    }

    // MARK: - Proposal Persistence

    private static func upsertProposal(
        liftKey: String,
        decision: LiftDecision,
        targets: [ProgramSessionExercise],
        analysis: WeeklyTrainingAnalysis,
        run: ProgramRun,
        program: TrainingProgram,
        targetWeek: Int,
        proposals: inout [AdaptationProposal],
        context: ModelContext
    ) -> AdaptationProposal {
        let proposalType: ProposalType = {
            switch decision.action {
            case .increase: return .increaseLoad
            case .decrease: return .decreaseLoad
            case .simplify: return .variationSwap
            case .maintain: return .increaseLoad
            }
        }()

        let existing = proposals.first(where: {
            $0.sourceAnalysis?.id == analysis.id &&
            $0.targetLiftKey == liftKey &&
            $0.targetWeekStart == targetWeek &&
            $0.proposalType == proposalType
        })

        let proposal: AdaptationProposal
        if let existing {
            proposal = existing
        } else {
            proposal = AdaptationProposal(
                programRun: run,
                trainingProgram: program,
                sourceAnalysis: analysis,
                proposalType: proposalType,
                proposalStatus: .pendingAutoApply,
                requiresUserConfirmation: false,
                autoApplyEligible: true,
                confidenceScore: decision.confidence,
                priority: decision.priority,
                targetWeekStart: targetWeek,
                targetWeekEnd: targetWeek,
                targetLiftKey: liftKey,
                adjustmentReason: decision.reason,
                summaryText: decision.summary,
                detailText: decision.detail
            )
            context.insert(proposal)
            proposals.append(proposal)
        }

        proposal.createdAt = Date.now
        proposal.decidedAt = nil
        proposal.programRun = run
        proposal.trainingProgram = program
        proposal.sourceAnalysis = analysis
        proposal.proposalType = proposalType
        proposal.proposalStatus = .pendingAutoApply
        proposal.requiresUserConfirmation = false
        proposal.autoApplyEligible = true
        proposal.confidenceScore = decision.confidence
        proposal.priority = decision.priority
        proposal.targetWeekStart = targetWeek
        proposal.targetWeekEnd = targetWeek
        proposal.targetLiftKey = liftKey
        proposal.adjustmentReason = decision.reason
        proposal.summaryText = decision.summary
        proposal.detailText = decision.detail
        proposal.expiresAt = programWeekEndDate(
            runStartDate: run.startDate,
            weekNumber: targetWeek
        )

        switch decision.action {
        case .increase, .decrease:
            proposal.targetSessionNumber = nil
            proposal.targetProgramSessionExerciseID = nil
            proposal.proposedLoadPercentDelta = decision.loadPercentDelta
            proposal.proposedSetDelta = nil
            proposal.proposedRepDelta = nil
            proposal.proposedDeloadFactor = nil
            proposal.swapFromExerciseName = nil
            proposal.swapToExerciseName = nil

        case .simplify:
            let simplificationTarget = preferredSimplificationTarget(
                targets: targets,
                liftKey: liftKey
            )
            proposal.targetProgramSessionExerciseID = simplificationTarget?.id
            proposal.targetSessionNumber = simplificationTarget?.session?.sessionNumber
            proposal.proposedLoadPercentDelta = decision.loadPercentDelta
            proposal.proposedSetDelta = nil
            proposal.proposedRepDelta = nil
            proposal.proposedDeloadFactor = nil
            proposal.swapFromExerciseName = simplificationTarget?.exerciseName
            proposal.swapToExerciseName = competitionExerciseName(for: liftKey)

        case .maintain:
            break
        }

        return proposal
    }

    private static func supersedeOpenProposals(
        run: ProgramRun,
        liftKey: String,
        targetWeek: Int,
        excludingProposalID: UUID?,
        proposals: [AdaptationProposal]
    ) {
        let supersedable: Set<ProposalStatus> = [
            .draft,
            .pendingUserConfirmation,
            .pendingAutoApply
        ]

        for proposal in proposals {
            guard proposal.programRun?.id == run.id else { continue }
            guard proposal.targetLiftKey == liftKey else { continue }
            guard proposal.targetWeekStart == targetWeek else { continue }
            guard supersedable.contains(proposal.proposalStatus) else { continue }
            if proposal.id == excludingProposalID { continue }

            proposal.proposalStatus = .superseded
            proposal.decidedAt = Date.now
        }
    }

    // MARK: - Explainability Events

    private static func upsertProposalEvent(
        proposal: AdaptationProposal,
        analysis: WeeklyTrainingAnalysis,
        run: ProgramRun,
        decision: LiftDecision,
        events: inout [AdaptationEventHistory],
        context: ModelContext
    ) {
        let event = events.first(where: {
            $0.eventType == .proposalCreated && $0.proposal?.id == proposal.id
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
        event.performanceScoreSnapshot = classifyAggregatePerformance(decision.compositeScore)
        event.fatigueStatusSnapshot = decision.fatigueStatus
        event.liftTrendStatusSnapshot = decision.trendStatus
        event.confidenceSnapshot = proposal.confidenceScore
        event.requiresUserAction = proposal.requiresUserConfirmation
        event.userActionTaken = false
    }

    private static func upsertMaintainEvent(
        liftKey: String,
        decision: LiftDecision,
        analysis: WeeklyTrainingAnalysis,
        run: ProgramRun,
        targetWeek: Int,
        events: inout [AdaptationEventHistory],
        context: ModelContext
    ) {
        let event = events.first(where: {
            $0.eventType == .trendUpdated &&
            $0.analysis?.id == analysis.id &&
            $0.targetLiftKey == liftKey &&
            $0.proposal == nil
        }) ?? {
            let newEvent = AdaptationEventHistory(
                programRun: run,
                trainingProgram: run.program,
                analysis: analysis,
                proposal: nil,
                eventType: .trendUpdated,
                analysisWeekNumber: analysis.programWeekNumber,
                targetLiftKey: liftKey,
                message: "Maintain planned \(liftDisplayName(for: liftKey)) progression"
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
        event.targetLiftKey = liftKey
        event.message = "Maintain planned \(liftDisplayName(for: liftKey)) progression for week \(targetWeek)"
        event.explanation = decision.detail
        event.adjustmentReason = .programSignalPriority
        event.performanceScoreSnapshot = classifyAggregatePerformance(decision.compositeScore)
        event.fatigueStatusSnapshot = decision.fatigueStatus
        event.liftTrendStatusSnapshot = decision.trendStatus
        event.confidenceSnapshot = decision.confidence
        event.requiresUserAction = false
        event.userActionTaken = false
    }

    // MARK: - Decision Engine

    private static func decideLiftAction(
        liftKey: String,
        targets: [ProgramSessionExercise],
        analysis: WeeklyTrainingAnalysis,
        run: ProgramRun,
        level: InferredLevel,
        outcomes: [ExercisePerformanceOutcome],
        trends: [LiftPerformanceTrend]
    ) -> LiftDecision {
        let mode = prescriptionMode(for: targets)
        let lookbackStart = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -lookbackDays,
            to: analysis.weekEndDate
        ) ?? analysis.weekEndDate

        let scopedOutcomes = outcomes
            .filter { outcome in
                guard outcome.canonicalLiftKey == liftKey else { return false }
                guard outcome.workoutDate >= lookbackStart && outcome.workoutDate <= analysis.weekEndDate else { return false }
                return outcome.programRun?.id == run.id || outcome.programRun == nil
            }
            .sorted {
                if $0.workoutDate == $1.workoutDate { return $0.id.uuidString < $1.id.uuidString }
                return $0.workoutDate < $1.workoutDate
            }

        let topSetOutcomes = scopedOutcomes.filter(\.isTopSetSignal)
        let weekTopSetOutcomes = analysis.outcomes.filter {
            $0.canonicalLiftKey == liftKey && $0.isTopSetSignal
        }

        let focusOutcomes: [ExercisePerformanceOutcome] = {
            if !weekTopSetOutcomes.isEmpty { return weekTopSetOutcomes }
            if !topSetOutcomes.isEmpty { return Array(topSetOutcomes.suffix(4)) }
            return scopedOutcomes
        }()

        let weeklyTopSetScore = weightedAverage(
            values: focusOutcomes.map { ($0.performanceScoreValue, max(0.01, $0.signalWeight)) }
        ) ?? 0
        let recentTopSetScore = weightedAverage(
            values: Array(topSetOutcomes.suffix(8)).map { ($0.performanceScoreValue, max(0.01, $0.signalWeight)) }
        ) ?? weeklyTopSetScore

        let trend = trends.first(where: {
            $0.canonicalLiftKey == liftKey && $0.programRun?.id == run.id
        })
        let trendChange = trend?.fourWeekChangePercent
        let trendStatus = trend?.trendStatus ?? .insufficientData
        let fatigueStatus = dominantFatigueStatus(from: focusOutcomes) ?? analysis.fatigueStatus

        var compositeScore = (weeklyTopSetScore * 0.70) + (recentTopSetScore * 0.30)
        if let trendChange {
            compositeScore += clamped(trendChange * 0.30, min: -4.0, max: 4.0)
        }
        compositeScore += trendAdjustment(for: trendStatus)
        compositeScore += fatigueAdjustment(for: fatigueStatus)

        if focusOutcomes.count < 2 {
            compositeScore *= 0.85
        }

        let behindCount = focusOutcomes.filter {
            $0.performanceScore == .severeUnderperformance || $0.performanceScore == .underperformance
        }.count
        let severeBehindCount = focusOutcomes.filter {
            $0.performanceScore == .severeUnderperformance
        }.count
        let aheadCount = focusOutcomes.filter {
            $0.performanceScore == .overperformance || $0.performanceScore == .exceptionalPerformance
        }.count

        let direction: LiftDirection = {
            if severeBehindCount > 0 { return .behind }
            if behindCount >= aheadCount + 2 { return .behind }
            if compositeScore <= -4.5 { return .behind }
            if aheadCount >= behindCount + 2 { return .ahead }
            if compositeScore >= 4.5 { return .ahead }
            return .onTarget
        }()

        let sampleWeight = focusOutcomes.reduce(0.0) { $0 + max(0.01, $1.signalWeight) }
        let sampleConfidence = min(1.0, sampleWeight / 4.0)
        let trendConfidence = trend?.confidenceScore ?? 0
        var confidence = (sampleConfidence * 0.70) + (trendConfidence * 0.30)
        if focusOutcomes.isEmpty { confidence = min(confidence, 0.35) }

        let severeDrop = compositeScore <= -8 || fatigueStatus == .high || fatigueStatus == .critical
        let styleScale = modeStyleScale(mode)

        switch direction {
        case .ahead:
            let delta = progressionDelta(
                level: level,
                modeScale: styleScale,
                confidence: confidence
            )
            return LiftDecision(
                action: .increase,
                loadPercentDelta: delta,
                confidence: confidence,
                reason: trendStatus == .improving ? .positiveLiftTrend : .topSetBeatTarget,
                priority: 70,
                summary: "Increase \(liftDisplayName(for: liftKey)) load by \(fmtPercent(delta)) in week \(nextWeekNumber(from: analysis))",
                detail: decisionDetail(
                    liftKey: liftKey,
                    direction: direction,
                    mode: mode,
                    level: level,
                    compositeScore: compositeScore,
                    weeklyTopSetScore: weeklyTopSetScore,
                    recentTopSetScore: recentTopSetScore,
                    trendChange: trendChange,
                    trendStatus: trendStatus,
                    fatigueStatus: fatigueStatus,
                    confidence: confidence,
                    loadDelta: delta
                ),
                compositeScore: compositeScore,
                fatigueStatus: fatigueStatus,
                trendStatus: trendStatus
            )

        case .onTarget:
            return LiftDecision(
                action: .maintain,
                loadPercentDelta: nil,
                confidence: confidence,
                reason: .programSignalPriority,
                priority: 40,
                summary: "Maintain planned \(liftDisplayName(for: liftKey)) progression",
                detail: decisionDetail(
                    liftKey: liftKey,
                    direction: direction,
                    mode: mode,
                    level: level,
                    compositeScore: compositeScore,
                    weeklyTopSetScore: weeklyTopSetScore,
                    recentTopSetScore: recentTopSetScore,
                    trendChange: trendChange,
                    trendStatus: trendStatus,
                    fatigueStatus: fatigueStatus,
                    confidence: confidence,
                    loadDelta: nil
                ),
                compositeScore: compositeScore,
                fatigueStatus: fatigueStatus,
                trendStatus: trendStatus
            )

        case .behind:
            if severeDrop, preferredSimplificationTarget(targets: targets, liftKey: liftKey) != nil {
                let smallDrop = reductionDelta(
                    level: level,
                    severe: false,
                    modeScale: styleScale,
                    confidence: confidence
                )
                return LiftDecision(
                    action: .simplify,
                    loadPercentDelta: smallDrop,
                    confidence: confidence,
                    reason: .plateauDetected,
                    priority: 95,
                    summary: "Simplify \(liftDisplayName(for: liftKey)) variation in week \(nextWeekNumber(from: analysis))",
                    detail: decisionDetail(
                        liftKey: liftKey,
                        direction: direction,
                        mode: mode,
                        level: level,
                        compositeScore: compositeScore,
                        weeklyTopSetScore: weeklyTopSetScore,
                        recentTopSetScore: recentTopSetScore,
                        trendChange: trendChange,
                        trendStatus: trendStatus,
                        fatigueStatus: fatigueStatus,
                        confidence: confidence,
                        loadDelta: smallDrop
                    ) + "; action=simplify_variation",
                    compositeScore: compositeScore,
                    fatigueStatus: fatigueStatus,
                    trendStatus: trendStatus
                )
            }

            let shouldHold = !severeDrop && compositeScore > -6.0 && fatigueStatus != .high && fatigueStatus != .critical
            let delta = shouldHold
                ? 0.0
                : reductionDelta(
                    level: level,
                    severe: severeDrop,
                    modeScale: styleScale,
                    confidence: confidence
                )
            let summary = shouldHold
                ? "Hold \(liftDisplayName(for: liftKey)) load in week \(nextWeekNumber(from: analysis))"
                : "Reduce \(liftDisplayName(for: liftKey)) load by \(fmtPercent(abs(delta))) in week \(nextWeekNumber(from: analysis))"

            return LiftDecision(
                action: .decrease,
                loadPercentDelta: delta,
                confidence: confidence,
                reason: severeDrop ? .fatigueAccumulation : .topSetMissedTarget,
                priority: shouldHold ? 75 : 90,
                summary: summary,
                detail: decisionDetail(
                    liftKey: liftKey,
                    direction: direction,
                    mode: mode,
                    level: level,
                    compositeScore: compositeScore,
                    weeklyTopSetScore: weeklyTopSetScore,
                    recentTopSetScore: recentTopSetScore,
                    trendChange: trendChange,
                    trendStatus: trendStatus,
                    fatigueStatus: fatigueStatus,
                    confidence: confidence,
                    loadDelta: delta
                ) + (shouldHold ? "; action=hold_load" : "; action=reduce_load"),
                compositeScore: compositeScore,
                fatigueStatus: fatigueStatus,
                trendStatus: trendStatus
            )
        }
    }

    // MARK: - Target Discovery

    private static func nextWeekTargetsByLift(
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
                ) else { continue }
                guard mainLiftKeys.contains(liftKey) else { continue }

                byLift[liftKey, default: []].append(exercise)
            }
        }

        return byLift
    }

    private static func preferredSimplificationTarget(
        targets: [ProgramSessionExercise],
        liftKey: String
    ) -> ProgramSessionExercise? {
        let base = competitionExerciseName(for: liftKey)
        return targets.first(where: { target in
            guard target.exerciseName != base else { return false }
            return FocusTemplateLibrary.loadMapping(for: target.exerciseName) != nil
        })
    }

    // MARK: - Rules

    private static func progressionDelta(
        level: InferredLevel,
        modeScale: Double,
        confidence: Double
    ) -> Double {
        let policy = policyForLevel(level)
        let scaled = policy.upDelta * modeScale * (0.75 + (confidence * 0.25))
        return quantized(clamped(scaled, min: 0.0, max: policy.maxAbsDelta))
    }

    private static func reductionDelta(
        level: InferredLevel,
        severe: Bool,
        modeScale: Double,
        confidence: Double
    ) -> Double {
        let policy = policyForLevel(level)
        let base = severe ? policy.strongDownDelta : policy.mildDownDelta
        let scaled = base * modeScale * (0.85 + (confidence * 0.15))
        let clampedDown = clamped(scaled, min: -policy.maxAbsDelta, max: 0.0)
        return quantized(clampedDown)
    }

    private static func modeStyleScale(_ mode: PrescriptionMode) -> Double {
        switch mode {
        case .percentage: return 1.0
        case .mixed: return 0.85
        case .rpeInformed: return 0.65
        case .unknown: return 0.75
        }
    }

    private static func policyForLevel(_ level: InferredLevel) -> LevelPolicy {
        switch level {
        case .beginner:
            return LevelPolicy(
                upDelta: 0.010,
                mildDownDelta: -0.006,
                strongDownDelta: -0.014,
                maxAbsDelta: 0.020
            )
        case .intermediate:
            return LevelPolicy(
                upDelta: 0.015,
                mildDownDelta: -0.010,
                strongDownDelta: -0.022,
                maxAbsDelta: 0.025
            )
        case .advanced:
            return LevelPolicy(
                upDelta: 0.010,
                mildDownDelta: -0.010,
                strongDownDelta: -0.018,
                maxAbsDelta: 0.020
            )
        }
    }

    private static func prescriptionMode(for targets: [ProgramSessionExercise]) -> PrescriptionMode {
        let hasPercentage = targets.contains { $0.targetPercentage1RM != nil }
        let hasRPEorRIR = targets.contains { $0.targetRPE != nil || $0.targetRIR != nil }

        if hasPercentage && hasRPEorRIR { return .mixed }
        if hasPercentage { return .percentage }
        if hasRPEorRIR { return .rpeInformed }
        return .unknown
    }

    private static func inferredLevel(for program: TrainingProgram) -> InferredLevel {
        let text = "\(program.name) \(program.descriptionText ?? "")".lowercased()
        if text.contains("beginner") || text.contains("novice") {
            return .beginner
        }
        if text.contains("advanced") {
            return .advanced
        }
        return .intermediate
    }

    // MARK: - Scoring Helpers

    private static func weightedAverage(values: [(Double, Double)]) -> Double? {
        let valid = values.filter { $0.1 > 0 }
        guard !valid.isEmpty else { return nil }
        let numerator = valid.reduce(0.0) { $0 + ($1.0 * $1.1) }
        let denominator = valid.reduce(0.0) { $0 + $1.1 }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    private static func dominantFatigueStatus(
        from outcomes: [ExercisePerformanceOutcome]
    ) -> FatigueStatus? {
        guard !outcomes.isEmpty else { return nil }

        let weighted = weightedAverage(values: outcomes.map { outcome in
            (fatigueScalar(outcome.inferredFatigueStatus), max(0.01, outcome.signalWeight))
        }) ?? 1.0

        if weighted < 0.9 { return .low }
        if weighted < 1.2 { return .manageable }
        if weighted < 1.5 { return .elevated }
        if weighted < 2.0 { return .high }
        return .critical
    }

    private static func fatigueScalar(_ status: FatigueStatus) -> Double {
        switch status {
        case .low: return 0.8
        case .manageable: return 1.0
        case .elevated: return 1.3
        case .high: return 1.8
        case .critical: return 2.3
        }
    }

    private static func fatigueAdjustment(for status: FatigueStatus) -> Double {
        switch status {
        case .low: return 0.8
        case .manageable: return 0.0
        case .elevated: return -1.0
        case .high: return -2.4
        case .critical: return -3.5
        }
    }

    private static func trendAdjustment(for status: LiftTrendStatus) -> Double {
        switch status {
        case .improving: return 1.0
        case .stable: return 0.0
        case .declining: return -1.3
        case .volatile: return -0.5
        case .insufficientData: return 0.0
        }
    }

    private static func classifyAggregatePerformance(_ score: Double) -> PerformanceScore {
        if score <= -12 { return .severeUnderperformance }
        if score <= -4 { return .underperformance }
        if score < 4 { return .onTarget }
        if score < 12 { return .overperformance }
        return .exceptionalPerformance
    }

    // MARK: - Lift Mapping / Labels

    private static func canonicalLiftKey(
        forExerciseName exerciseName: String,
        baseLiftUsed: String?
    ) -> String? {
        let mappedSource = FocusTemplateLibrary.loadMapping(for: exerciseName)?.sourceLift
        let normalized = (baseLiftUsed ?? mappedSource ?? exerciseName).lowercased()

        if normalized.contains("squat") { return "squat" }
        if normalized.contains("bench") { return "bench" }
        if normalized.contains("deadlift") { return "deadlift" }
        return nil
    }

    private static func competitionExerciseName(for liftKey: String) -> String {
        switch liftKey {
        case "squat": return "Back Squats"
        case "bench": return "Bench Press"
        case "deadlift": return "Deadlift"
        default: return liftKey
        }
    }

    private static func liftDisplayName(for key: String) -> String {
        switch key {
        case "squat": return "Squat"
        case "bench": return "Bench Press"
        case "deadlift": return "Deadlift"
        default: return key.capitalized
        }
    }

    // MARK: - Formatting / Misc

    private static func nextWeekNumber(from analysis: WeeklyTrainingAnalysis) -> Int {
        (analysis.programWeekNumber ?? 0) + 1
    }

    private static func decisionDetail(
        liftKey: String,
        direction: LiftDirection,
        mode: PrescriptionMode,
        level: InferredLevel,
        compositeScore: Double,
        weeklyTopSetScore: Double,
        recentTopSetScore: Double,
        trendChange: Double?,
        trendStatus: LiftTrendStatus,
        fatigueStatus: FatigueStatus,
        confidence: Double,
        loadDelta: Double?
    ) -> String {
        [
            "lift=\(liftKey)",
            "direction=\(direction.rawValue)",
            "mode=\(mode.rawValue)",
            "level=\(level.rawValue)",
            "composite_score=\(fmt1(compositeScore))",
            "weekly_top_set_score=\(fmt1(weeklyTopSetScore))",
            "recent_top_set_score=\(fmt1(recentTopSetScore))",
            "trend_change_pct=\(fmt1(trendChange))",
            "trend_status=\(trendStatus.rawValue)",
            "fatigue=\(fatigueStatus.rawValue)",
            "confidence=\(fmt2(confidence))",
            "proposed_load_delta_pct=\(fmtPercent(loadDelta))"
        ].joined(separator: "; ")
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

    private static func quantized(_ value: Double) -> Double {
        // Quantize to 0.25% steps for stable, readable proposals.
        let step = 0.0025
        return (value / step).rounded() * step
    }

    private static func clamped(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
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

private enum LiftDirection: String {
    case ahead
    case onTarget
    case behind
}

private enum LiftAction {
    case maintain
    case increase
    case decrease
    case simplify
}

private enum PrescriptionMode: String {
    case percentage
    case rpeInformed
    case mixed
    case unknown
}

private enum InferredLevel: String {
    case beginner
    case intermediate
    case advanced
}

private struct LevelPolicy {
    let upDelta: Double
    let mildDownDelta: Double
    let strongDownDelta: Double
    let maxAbsDelta: Double
}

private struct LiftDecision {
    let action: LiftAction
    let loadPercentDelta: Double?
    let confidence: Double
    let reason: AdjustmentReason
    let priority: Int
    let summary: String
    let detail: String
    let compositeScore: Double
    let fatigueStatus: FatigueStatus
    let trendStatus: LiftTrendStatus
}
