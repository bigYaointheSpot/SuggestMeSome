//
//  AdaptiveVolumeProgressionService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData

/// Weekly accessory-volume proposal engine for Feature 6.
/// - Uses finalized weekly analysis signals (volume/performance/fatigue).
/// - Produces small, user-confirmed proposals for future weeks.
/// - Persists non-destructive volume overlays via AdaptationProposal.
enum AdaptiveVolumeProgressionService {
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

        let profile = inferredVolumeProfile(for: program)
        let focus = inferredProgramFocus(for: program, profile: profile)
        let level = inferredProgramLevel(for: program)

        let allAnalyses = (try? context.fetch(FetchDescriptor<WeeklyTrainingAnalysis>())) ?? []
        let allProposals = (try? context.fetch(FetchDescriptor<AdaptationProposal>())) ?? []
        let allEvents = (try? context.fetch(FetchDescriptor<AdaptationEventHistory>())) ?? []

        let runAnalyses = allAnalyses
            .filter { $0.programRun?.id == run.id && $0.isFinalized }
            .sorted { lhs, rhs in
                let lw = lhs.programWeekNumber ?? 0
                let rw = rhs.programWeekNumber ?? 0
                if lw == rw { return lhs.weekStartDate < rhs.weekStartDate }
                return lw < rw
            }
        let recentAnalyses = Array(runAnalyses.suffix(3))

        let weeklyTargets = ProgramExerciseMetadataService.weeklyVolumeTargets(
            focus: focus,
            level: level
        )
        let targetRowsByMuscle = targetAccessoryRowsByMuscle(
            program: program,
            targetWeek: targetWeek
        )

        var proposals = allProposals
        var events = allEvents
        var candidates: [VolumeDecision] = []

        for muscle in ProgramVolumeMuscle.allCases {
            guard let targetRows = targetRowsByMuscle[muscle], !targetRows.isEmpty else { continue }
            let decision = decideVolumeChange(
                muscle: muscle,
                profile: profile,
                analysis: analysis,
                recentAnalyses: recentAnalyses,
                weeklyTargets: weeklyTargets,
                targetRows: targetRows
            )
            guard decision.action != .maintain else { continue }
            candidates.append(decision)
        }

        guard !candidates.isEmpty else { return }

        let constrained = constrainWeeklyChanges(
            candidates: candidates,
            profile: profile,
            globalFatigue: analysis.fatigueStatus
        )

        for decision in constrained {
            supersedeOpenVolumeProposals(
                runID: run.id,
                targetWeek: targetWeek,
                muscle: decision.muscle,
                excludingProposalID: nil,
                proposals: proposals
            )

            let proposal = upsertVolumeProposal(
                decision: decision,
                analysis: analysis,
                run: run,
                program: program,
                targetWeek: targetWeek,
                proposals: &proposals,
                context: context
            )

            supersedeOpenVolumeProposals(
                runID: run.id,
                targetWeek: targetWeek,
                muscle: decision.muscle,
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

    // MARK: - Decisioning

    private static func decideVolumeChange(
        muscle: ProgramVolumeMuscle,
        profile: VolumeProfile,
        analysis: WeeklyTrainingAnalysis,
        recentAnalyses: [WeeklyTrainingAnalysis],
        weeklyTargets: ProgramWeeklyVolumeTargets,
        targetRows: [ProgramSessionExercise]
    ) -> VolumeDecision {
        let recentPerformance = recentMusclePerformance(
            muscle: muscle,
            analyses: recentAnalyses
        )
        let recentFatigue = recentMuscleFatigue(
            muscle: muscle,
            analyses: recentAnalyses
        )
        let currentMetric = analysis.volumeMetrics.first { $0.muscle == muscle }
        let planned = currentMetric?.plannedHardSets ?? midpoint(weeklyTargets.range(for: muscle))
        let completed = currentMetric?.completedHardSets ?? 0
        let range = weeklyTargets.range(for: muscle)

        let underdoseRatio = planned > 0 ? max(0, (planned - completed) / planned) : 0
        let overdoseRatio = planned > 0 ? max(0, (completed - planned) / planned) : 0
        let underMin = completed < (range.minHardSets * 0.90)
        let overMax = completed > (range.maxHardSets * 1.08)
        let globalFatigue = analysis.fatigueStatus

        var action: VolumeAction = .maintain
        var reason: AdjustmentReason = .programSignalPriority
        var score = 0.0

        let supportMusclesForPowerlifting: Set<ProgramVolumeMuscle> = [
            .upperBackLats, .triceps, .abs, .hamstrings, .glutes
        ]

        if globalFatigue == .high || globalFatigue == .critical {
            if completed > 0 {
                action = .reduce
                reason = .fatigueAccumulation
                score = 3.0 + overdoseRatio + (recentFatigue == .high || recentFatigue == .critical ? 0.8 : 0)
            }
        } else if overMax || (overdoseRatio > 0.18 && (recentPerformance < 0 || recentFatigue == .elevated || recentFatigue == .high || recentFatigue == .critical)) {
            action = .reduce
            reason = recentFatigue == .elevated || recentFatigue == .high || recentFatigue == .critical
                ? .fatigueAccumulation
                : .accessoryUnderperformance
            score = 2.2 + overdoseRatio + max(0, (-recentPerformance / 10.0))
        } else if underMin || (underdoseRatio > 0.12 && recentPerformance > -2.5) {
            let fatigueProtected = globalFatigue == .elevated || recentFatigue == .elevated || recentFatigue == .high || recentFatigue == .critical
            if !fatigueProtected {
                switch profile {
                case .bodybuilding:
                    action = .increase
                case .powerbuilding:
                    action = .increase
                case .powerlifting:
                    if supportMusclesForPowerlifting.contains(muscle) && underdoseRatio > 0.18 {
                        action = .increase
                    }
                case .general:
                    if underdoseRatio > 0.20 {
                        action = .increase
                    }
                }
            }

            if action == .increase {
                reason = recentPerformance >= 0 ? .accessoryOutperformance : .programSignalPriority
                score = 1.8 + (underdoseRatio * 1.6) + max(0, recentPerformance / 10.0)
                if profile == .bodybuilding || profile == .powerbuilding {
                    score += 0.4 // prioritize underdosed musculature for hypertrophy-focused profiles.
                }
            }
        }

        // Protect recoverability first for bodybuilding/powerbuilding when fatigue drifts up.
        if action == .increase,
           (analysis.fatigueStatus == .elevated || recentFatigue == .elevated),
           (profile == .bodybuilding || profile == .powerbuilding),
           underdoseRatio < 0.25 {
            action = .maintain
            reason = .fatigueAccumulation
            score = 0
        }

        guard action != .maintain else {
        return VolumeDecision(
            action: .maintain,
            muscle: muscle,
            targetRow: targetRows[0],
            setDelta: 0,
            confidence: confidenceForDecision(
                analysis: analysis,
                underdoseRatio: underdoseRatio,
                overdoseRatio: overdoseRatio
            ),
            priorityScore: 0,
            reason: .programSignalPriority,
            summary: "",
            detail: "",
            recentPerformance: recentPerformance
        )
        }

        let setDelta = action == .increase ? 1 : -1
        let targetRow = selectTargetRow(
            from: targetRows,
            for: muscle,
            action: action
        ) ?? targetRows[0]
        let confidence = confidenceForDecision(
            analysis: analysis,
            underdoseRatio: underdoseRatio,
            overdoseRatio: overdoseRatio
        )

        let summary: String = {
            let actionVerb = action == .increase ? "Increase" : "Reduce"
            return "\(actionVerb) \(muscle.displayName) accessory volume by 1 set in week \(nextWeekNumber(from: analysis))"
        }()
        let detail = [
            "muscle=\(muscle.rawValue)",
            "profile=\(profile.rawValue)",
            "planned_sets=\(fmt1(planned))",
            "completed_sets=\(fmt1(completed))",
            "target_range=\(fmt1(range.minHardSets))-\(fmt1(range.maxHardSets))",
            "underdose_ratio=\(fmt2(underdoseRatio))",
            "overdose_ratio=\(fmt2(overdoseRatio))",
            "recent_performance=\(fmt1(recentPerformance))",
            "recent_fatigue=\(recentFatigue.rawValue)",
            "global_fatigue=\(analysis.fatigueStatus.rawValue)",
            "target_exercise=\(targetRow.exerciseName)",
            "set_delta=\(setDelta > 0 ? "+1" : "-1")"
        ].joined(separator: "; ")

        return VolumeDecision(
            action: action,
            muscle: muscle,
            targetRow: targetRow,
            setDelta: setDelta,
            confidence: confidence,
            priorityScore: score,
            reason: reason,
            summary: summary,
            detail: detail,
            recentPerformance: recentPerformance
        )
    }

    private static func constrainWeeklyChanges(
        candidates: [VolumeDecision],
        profile: VolumeProfile,
        globalFatigue: FatigueStatus
    ) -> [VolumeDecision] {
        guard !candidates.isEmpty else { return [] }

        let maxChanges: Int = {
            switch profile {
            case .powerlifting: return 1
            case .powerbuilding: return 2
            case .bodybuilding: return 3
            case .general: return 1
            }
        }()

        // If recoverability is stressed, only allow reductions.
        if globalFatigue == .high || globalFatigue == .critical {
            return candidates
                .filter { $0.action == .reduce }
                .sorted(by: { lhs, rhs in
                    if lhs.priorityScore == rhs.priorityScore {
                        return lhs.muscle.rawValue < rhs.muscle.rawValue
                    }
                    return lhs.priorityScore > rhs.priorityScore
                })
                .prefix(maxChanges)
                .map { $0 }
        }

        let reductions = candidates.filter { $0.action == .reduce }.sorted(by: { lhs, rhs in
            if lhs.priorityScore == rhs.priorityScore {
                return lhs.muscle.rawValue < rhs.muscle.rawValue
            }
            return lhs.priorityScore > rhs.priorityScore
        })
        let increases = candidates.filter { $0.action == .increase }.sorted(by: { lhs, rhs in
            if lhs.priorityScore == rhs.priorityScore {
                return lhs.muscle.rawValue < rhs.muscle.rawValue
            }
            return lhs.priorityScore > rhs.priorityScore
        })

        if !reductions.isEmpty {
            // Reduce first when any clear recoverability concern exists.
            let topReductions = Array(reductions.prefix(max(1, min(maxChanges, reductions.count))))
            if globalFatigue == .elevated {
                return topReductions
            }

            var merged = topReductions
            let remaining = max(0, maxChanges - merged.count)
            if remaining > 0 {
                merged.append(contentsOf: increases.prefix(remaining))
            }
            return merged
        }

        return increases.prefix(maxChanges).map { $0 }
    }

    // MARK: - Target Rows

    private static func targetAccessoryRowsByMuscle(
        program: TrainingProgram,
        targetWeek: Int
    ) -> [ProgramVolumeMuscle: [ProgramSessionExercise]] {
        guard let week = program.weeks.first(where: { $0.weekNumber == targetWeek }) else { return [:] }

        var map: [ProgramVolumeMuscle: [ProgramSessionExercise]] = [:]
        for session in week.sessions.sorted(by: { $0.sessionNumber < $1.sessionNumber }) {
            for row in session.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                guard isAccessoryCandidate(row) else { continue }
                let contributions = ProgramExerciseMetadataService.metadata(for: row.exerciseName).muscleContributions
                for (muscle, contribution) in contributions where contribution > 0.20 {
                    map[muscle, default: []].append(row)
                }
            }
        }
        return map
    }

    private static func isAccessoryCandidate(_ row: ProgramSessionExercise) -> Bool {
        guard !row.isWarmup else { return false }
        guard (row.targetSets ?? 0) > 0 else { return false }

        if row.workingSetStyle == .topSet || row.workingSetStyle == .backoff {
            return false
        }
        if canonicalMainLiftKey(for: row.exerciseName, baseLiftUsed: row.baseLiftUsed) != nil,
           (row.targetPercentage1RM ?? 0) >= 0.80 {
            return false
        }
        if FocusTemplateLibrary.loadMapping(for: row.exerciseName) != nil,
           row.targetPercentage1RM != nil {
            return false
        }
        return true
    }

    private static func selectTargetRow(
        from rows: [ProgramSessionExercise],
        for muscle: ProgramVolumeMuscle,
        action: VolumeAction
    ) -> ProgramSessionExercise? {
        let sorted = rows.sorted { lhs, rhs in
            let left = rowRanking(lhs, muscle: muscle, action: action)
            let right = rowRanking(rhs, muscle: muscle, action: action)
            if left == right {
                let lSession = lhs.session?.sessionNumber ?? 0
                let rSession = rhs.session?.sessionNumber ?? 0
                if lSession == rSession {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lSession < rSession
            }
            return left > right
        }
        return sorted.first
    }

    private static func rowRanking(
        _ row: ProgramSessionExercise,
        muscle: ProgramVolumeMuscle,
        action: VolumeAction
    ) -> Double {
        let metadata = ProgramExerciseMetadataService.metadata(for: row.exerciseName)
        let contribution = metadata.muscleContributions[muscle] ?? 0
        let setCount = Double(max(1, row.targetSets ?? 1))
        let fatigueScore = fatigueTierValue(metadata.defaultFatigueTier)

        switch action {
        case .increase:
            // Prefer high-contribution, lower-fatigue rows for recoverability.
            return (contribution * 2.4) + ((1.0 - fatigueScore) * 1.0) - (setCount * 0.06)
        case .reduce:
            // Prefer trimming high-fatigue rows first.
            return (contribution * 2.2) + (fatigueScore * 1.2) + (setCount * 0.05)
        case .maintain:
            return contribution
        }
    }

    private static func fatigueTierValue(_ tier: ExerciseFatigueTier) -> Double {
        switch tier {
        case .low: return 0.2
        case .medium: return 0.6
        case .high: return 1.0
        }
    }

    // MARK: - Proposal Persistence

    private static func upsertVolumeProposal(
        decision: VolumeDecision,
        analysis: WeeklyTrainingAnalysis,
        run: ProgramRun,
        program: TrainingProgram,
        targetWeek: Int,
        proposals: inout [AdaptationProposal],
        context: ModelContext
    ) -> AdaptationProposal {
        let proposalType: ProposalType = decision.action == .increase ? .increaseVolume : .decreaseVolume
        let liftKey = muscleLiftKey(decision.muscle)
        let targetSession = decision.targetRow.session?.sessionNumber

        let existing = proposals.first(where: {
            $0.sourceAnalysis?.id == analysis.id &&
            $0.targetProgramSessionExerciseID == decision.targetRow.id &&
            $0.proposalType == proposalType &&
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
                proposalType: proposalType,
                proposalStatus: .pendingUserConfirmation,
                requiresUserConfirmation: true,
                autoApplyEligible: false,
                confidenceScore: decision.confidence,
                priority: decisionPriority(for: decision),
                targetWeekStart: targetWeek,
                targetWeekEnd: targetWeek,
                targetSessionNumber: targetSession,
                targetProgramSessionExerciseID: decision.targetRow.id,
                targetLiftKey: liftKey,
                proposedSetDelta: decision.setDelta,
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
        proposal.proposalStatus = .pendingUserConfirmation
        proposal.requiresUserConfirmation = true
        proposal.autoApplyEligible = false
        proposal.confidenceScore = decision.confidence
        proposal.priority = decisionPriority(for: decision)
        proposal.targetWeekStart = targetWeek
        proposal.targetWeekEnd = targetWeek
        proposal.targetSessionNumber = targetSession
        proposal.targetProgramSessionExerciseID = decision.targetRow.id
        proposal.targetLiftKey = liftKey
        proposal.proposedLoadPercentDelta = nil
        proposal.proposedSetDelta = decision.setDelta
        proposal.proposedRepDelta = nil
        proposal.proposedDeloadFactor = nil
        proposal.swapFromExerciseName = nil
        proposal.swapToExerciseName = nil
        proposal.adjustmentReason = decision.reason
        proposal.summaryText = decision.summary
        proposal.detailText = decision.detail
        proposal.expiresAt = programWeekEndDate(
            runStartDate: run.startDate,
            weekNumber: targetWeek
        )

        return proposal
    }

    private static func supersedeOpenVolumeProposals(
        runID: UUID,
        targetWeek: Int,
        muscle: ProgramVolumeMuscle,
        excludingProposalID: UUID?,
        proposals: [AdaptationProposal]
    ) {
        let key = muscleLiftKey(muscle)
        let supersedable: Set<ProposalStatus> = [
            .draft,
            .pendingUserConfirmation,
            .pendingAutoApply
        ]

        for proposal in proposals {
            guard proposal.programRun?.id == runID else { continue }
            guard proposal.targetWeekStart == targetWeek else { continue }
            guard proposal.targetLiftKey == key else { continue }
            guard proposal.proposalType == .increaseVolume || proposal.proposalType == .decreaseVolume else { continue }
            guard supersedable.contains(proposal.proposalStatus) else { continue }
            if proposal.id == excludingProposalID { continue }

            proposal.proposalStatus = .superseded
            proposal.decidedAt = Date.now
        }
    }

    private static func upsertProposalEvent(
        proposal: AdaptationProposal,
        analysis: WeeklyTrainingAnalysis,
        run: ProgramRun,
        decision: VolumeDecision,
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
        event.performanceScoreSnapshot = classifyPerformance(decision.recentPerformance)
        event.fatigueStatusSnapshot = analysis.fatigueStatus
        event.liftTrendStatusSnapshot = nil
        event.confidenceSnapshot = proposal.confidenceScore
        event.requiresUserAction = true
        event.userActionTaken = false
    }

    // MARK: - Signal Helpers

    private static func recentMusclePerformance(
        muscle: ProgramVolumeMuscle,
        analyses: [WeeklyTrainingAnalysis]
    ) -> Double {
        let scored: [(Double, Double)] = analyses.compactMap { analysis in
            let outcomes = analysis.outcomes
            guard !outcomes.isEmpty else { return nil }

            let pairs: [(Double, Double)] = outcomes.compactMap { outcome in
                let contribution = ProgramExerciseMetadataService
                    .metadata(for: outcome.exerciseName)
                    .muscleContributions[muscle] ?? 0
                guard contribution > 0 else { return nil }
                return (outcome.performanceScoreValue, max(0.01, outcome.signalWeight * contribution))
            }
            guard let weekly = weightedAverage(values: pairs) else { return nil }
            return (weekly, max(1.0, analysis.totalSignalWeight))
        }

        return weightedAverage(values: scored) ?? 0
    }

    private static func recentMuscleFatigue(
        muscle: ProgramVolumeMuscle,
        analyses: [WeeklyTrainingAnalysis]
    ) -> FatigueStatus {
        let weighted = analyses.compactMap { analysis -> (Double, Double)? in
            let outcomes = analysis.outcomes
            guard !outcomes.isEmpty else { return nil }

            let pairs: [(Double, Double)] = outcomes.compactMap { outcome in
                let contribution = ProgramExerciseMetadataService
                    .metadata(for: outcome.exerciseName)
                    .muscleContributions[muscle] ?? 0
                guard contribution > 0 else { return nil }
                return (fatigueScalar(outcome.inferredFatigueStatus), max(0.01, outcome.signalWeight * contribution))
            }
            guard let weekly = weightedAverage(values: pairs) else { return nil }
            return (weekly, 1.0)
        }

        let score = weightedAverage(values: weighted) ?? 1.0
        if score < 0.9 { return .low }
        if score < 1.2 { return .manageable }
        if score < 1.5 { return .elevated }
        if score < 2.0 { return .high }
        return .critical
    }

    private static func confidenceForDecision(
        analysis: WeeklyTrainingAnalysis,
        underdoseRatio: Double,
        overdoseRatio: Double
    ) -> Double {
        let baseSignal = min(1.0, analysis.totalSignalWeight / 9.0)
        let severity = min(1.0, max(underdoseRatio, overdoseRatio) * 2.4)
        return (baseSignal * 0.70) + (severity * 0.30)
    }

    private static func decisionPriority(for decision: VolumeDecision) -> Int {
        let base = decision.action == .reduce ? 80 : 70
        return min(100, base + Int((decision.priorityScore * 10.0).rounded()))
    }

    // MARK: - Inference

    private static func inferredVolumeProfile(for program: TrainingProgram) -> VolumeProfile {
        let text = "\(program.name) \(program.descriptionText ?? "")".lowercased()
        if text.contains("bodybuilding") { return .bodybuilding }
        if text.contains("powerbuilding") { return .powerbuilding }
        if text.contains("powerlifting")
            || text.contains("5x5")
            || text.contains("five by five")
            || text.contains("max squat")
            || text.contains("max bench")
            || text.contains("max deadlift") {
            return .powerlifting
        }
        return .general
    }

    private static func inferredProgramFocus(
        for program: TrainingProgram,
        profile: VolumeProfile
    ) -> ProgramFocus {
        switch profile {
        case .bodybuilding: return .bodybuilding
        case .powerbuilding: return .powerbuilding
        case .powerlifting: return .powerlifting
        case .general:
            let text = program.name.lowercased()
            if text.contains("full body") { return .fullBody }
            if text.contains("push") && text.contains("pull") { return .pushPull }
            if text.contains("general fitness") { return .generalFitness }
            return .generalFitness
        }
    }

    private static func inferredProgramLevel(for program: TrainingProgram) -> ProgramLevel {
        let text = "\(program.name) \(program.descriptionText ?? "")".lowercased()
        if text.contains("beginner") || text.contains("novice") {
            return .beginner
        }
        if text.contains("advanced") {
            return .advanced
        }
        return .intermediate
    }

    private static func canonicalMainLiftKey(
        for exerciseName: String,
        baseLiftUsed: String?
    ) -> String? {
        let mappedSource = FocusTemplateLibrary.loadMapping(for: exerciseName)?.sourceLift
        let normalized = (baseLiftUsed ?? mappedSource ?? exerciseName).lowercased()

        if normalized.contains("squat") { return "squat" }
        if normalized.contains("bench") { return "bench" }
        if normalized.contains("deadlift") { return "deadlift" }
        return nil
    }

    // MARK: - Utility

    private static func midpoint(_ range: ProgramWeeklyTargetRange) -> Double {
        (range.minHardSets + range.maxHardSets) / 2.0
    }

    private static func nextWeekNumber(from analysis: WeeklyTrainingAnalysis) -> Int {
        (analysis.programWeekNumber ?? 0) + 1
    }

    private static func muscleLiftKey(_ muscle: ProgramVolumeMuscle) -> String {
        "muscle:\(muscle.rawValue)"
    }

    private static func weightedAverage(values: [(Double, Double)]) -> Double? {
        let valid = values.filter { $0.1 > 0 }
        guard !valid.isEmpty else { return nil }
        let numerator = valid.reduce(0.0) { $0 + ($1.0 * $1.1) }
        let denominator = valid.reduce(0.0) { $0 + $1.1 }
        guard denominator > 0 else { return nil }
        return numerator / denominator
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

    private static func classifyPerformance(_ score: Double) -> PerformanceScore {
        if score <= -12 { return .severeUnderperformance }
        if score <= -4 { return .underperformance }
        if score < 4 { return .onTarget }
        if score < 12 { return .overperformance }
        return .exceptionalPerformance
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

private enum VolumeAction {
    case increase
    case maintain
    case reduce
}

private enum VolumeProfile: String {
    case powerlifting
    case powerbuilding
    case bodybuilding
    case general
}

private struct VolumeDecision {
    let action: VolumeAction
    let muscle: ProgramVolumeMuscle
    let targetRow: ProgramSessionExercise
    let setDelta: Int
    let confidence: Double
    let priorityScore: Double
    let reason: AdjustmentReason
    let summary: String
    let detail: String
    let recentPerformance: Double
}
