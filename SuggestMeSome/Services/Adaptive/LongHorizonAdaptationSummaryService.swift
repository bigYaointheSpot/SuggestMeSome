//
//  LongHorizonAdaptationSummaryService.swift
//  SuggestMeSome
//
//  Feature 13 Prompt 5 — Coach-readable summaries across recent completed blocks.
//

import Foundation

struct LongHorizonAdaptationBlock {
    let run: ProgramRun
    let review: MesocycleReviewSnapshot
}

enum LongHorizonAdaptationSummaryService {
    static func selectedCompletedRuns(
        endingWith anchorRun: ProgramRun? = nil,
        completedRuns: [ProgramRun],
        maxBlocks: Int = 3
    ) -> [ProgramRun] {
        let sortedRuns = completedRuns
            .filter(\.isCompleted)
            .sorted { lhs, rhs in
                let lhsDate = lhs.endDate ?? lhs.startDate
                let rhsDate = rhs.endDate ?? rhs.startDate
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.resolvedSyncStableID < rhs.resolvedSyncStableID
            }

        let anchorDate = anchorRun.map { $0.endDate ?? $0.startDate }
        let boundedRuns = sortedRuns.filter { run in
            guard let anchorDate else { return true }
            return (run.endDate ?? run.startDate) <= anchorDate
        }
        return Array(boundedRuns.suffix(max(1, maxBlocks)))
    }

    static func buildSummary(
        endingWith anchorRun: ProgramRun? = nil,
        blocks: [LongHorizonAdaptationBlock]
    ) -> LongHorizonAdaptationSummary {
        let evaluatedBlocks = blocks.map { block in
            EvaluatedBlock(run: block.run, review: block.review)
        }
        return buildSummary(
            endingWith: anchorRun,
            evaluatedBlocks: evaluatedBlocks
        )
    }

    private struct EvaluatedBlock {
        let run: ProgramRun
        let review: MesocycleReviewSnapshot

        init(run: ProgramRun, review: MesocycleReviewSnapshot) {
            self.run = run
            self.review = review
        }
        var endDate: Date {
            run.endDate ?? review.endDate
        }

        var sessionsPerWeek: Int? {
            run.program?.sessionsPerWeek
        }
    }

    static func buildSummary(
        endingWith anchorRun: ProgramRun? = nil,
        completedRuns: [ProgramRun],
        allWorkouts: [Workout],
        personalRecords: [PersonalRecord] = [],
        maxBlocks: Int = 3
    ) -> LongHorizonAdaptationSummary {
        let selectedRuns = selectedCompletedRuns(
            endingWith: anchorRun,
            completedRuns: completedRuns,
            maxBlocks: maxBlocks
        )
        let evaluatedBlocks = selectedRuns.map { run in
            EvaluatedBlock(
                run: run,
                review: MesocycleReviewService.buildReview(
                    for: run,
                    allWorkouts: allWorkouts,
                    personalRecords: personalRecords
                )
            )
        }
        return buildSummary(
            endingWith: anchorRun,
            evaluatedBlocks: evaluatedBlocks
        )
    }

    private static func buildSummary(
        endingWith anchorRun: ProgramRun? = nil,
        evaluatedBlocks blocks: [EvaluatedBlock]
    ) -> LongHorizonAdaptationSummary {

        guard !blocks.isEmpty else {
            let insight = LongHorizonAdaptationInsight(
                kind: .insufficientData,
                title: "Need completed blocks",
                detail: "Finish at least one full block to unlock long-horizon adaptation trends."
            )
            return LongHorizonAdaptationSummary(
                anchorProgramRunStableID: anchorRun?.resolvedSyncStableID,
                includedProgramRunStableIDs: [],
                blockCount: 0,
                includedStandaloneWorkoutCount: 0,
                headline: insight.detail,
                insights: [insight]
            )
        }

        var insights: [LongHorizonAdaptationInsight] = [
            adherenceInsight(for: blocks)
        ]

        if let movementInsight = movementContinuityInsight(for: blocks) {
            insights.append(movementInsight)
        }
        if let frequencyInsight = frequencyInsight(for: blocks) {
            insights.append(frequencyInsight)
        }
        if let missedInsight = missedSessionPatternInsight(for: blocks) {
            insights.append(missedInsight)
        }
        if let standaloneInsight = standaloneInfluenceInsight(for: blocks) {
            insights.append(standaloneInsight)
        }

        if blocks.count == 1 {
            insights.append(
                LongHorizonAdaptationInsight(
                    kind: .insufficientData,
                    title: "Baseline only",
                    detail: "One completed block gives you a baseline. Finish another block to compare longer trends."
                )
            )
        }

        let totalStandaloneWorkouts = blocks.reduce(0) {
            $0 + $1.review.standaloneInfluence.includedWorkoutCount
        }

        return LongHorizonAdaptationSummary(
            anchorProgramRunStableID: anchorRun?.resolvedSyncStableID ?? blocks.last?.run.resolvedSyncStableID,
            includedProgramRunStableIDs: blocks.map(\.run.resolvedSyncStableID),
            blockCount: blocks.count,
            includedStandaloneWorkoutCount: totalStandaloneWorkouts,
            headline: headline(for: blocks, insights: insights),
            insights: insights
        )
    }

    private static func adherenceInsight(
        for blocks: [EvaluatedBlock]
    ) -> LongHorizonAdaptationInsight {
        let percentages = blocks.map(\.review.headlineMetrics.adherencePercentage)
        guard let first = percentages.first, let last = percentages.last else {
            return LongHorizonAdaptationInsight(
                kind: .adherenceTrend,
                title: "Adherence trend",
                detail: "Adherence data is not available yet."
            )
        }

        if blocks.count == 1 {
            return LongHorizonAdaptationInsight(
                kind: .adherenceTrend,
                title: "Adherence baseline",
                detail: "The latest completed block landed at \(last)% adherence."
            )
        }

        let average = Int((Double(percentages.reduce(0, +)) / Double(percentages.count)).rounded())
        if abs(last - first) <= 5 {
            return LongHorizonAdaptationInsight(
                kind: .adherenceTrend,
                title: "Adherence trend",
                detail: "Adherence stayed fairly steady across the last \(blocks.count) blocks at about \(average)%."
            )
        }

        if last > first {
            return LongHorizonAdaptationInsight(
                kind: .adherenceTrend,
                title: "Adherence trend",
                detail: "Adherence trended up across the last \(blocks.count) blocks, from \(first)% to \(last)%."
            )
        }

        return LongHorizonAdaptationInsight(
            kind: .adherenceTrend,
            title: "Adherence trend",
            detail: "Adherence trended down across the last \(blocks.count) blocks, from \(first)% to \(last)%."
        )
    }

    private static func frequencyInsight(
        for blocks: [EvaluatedBlock]
    ) -> LongHorizonAdaptationInsight? {
        let rows = blocks.compactMap { block -> (Int, Int)? in
            guard let sessionsPerWeek = block.sessionsPerWeek else { return nil }
            return (sessionsPerWeek, block.review.headlineMetrics.adherencePercentage)
        }
        guard !rows.isEmpty else { return nil }

        let grouped = Dictionary(grouping: rows) { $0.0 }
        if grouped.count == 1, let frequency = grouped.keys.first {
            return LongHorizonAdaptationInsight(
                kind: .toleratedFrequency,
                title: "Weekly frequency",
                detail: "Recent completed blocks have held at \(frequency) sessions per week."
            )
        }

        let averaged = grouped.map { frequency, values in
            (
                frequency: frequency,
                averageAdherence: Int(
                    (
                        Double(values.map { $0.1 }.reduce(0, +)) /
                        Double(values.count)
                    ).rounded()
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.averageAdherence != rhs.averageAdherence {
                return lhs.averageAdherence > rhs.averageAdherence
            }
            return lhs.frequency < rhs.frequency
        }

        guard let best = averaged.first else { return nil }
        if averaged.count > 1 {
            let runnerUp = averaged[1]
            if best.averageAdherence >= runnerUp.averageAdherence + 7 {
                return LongHorizonAdaptationInsight(
                    kind: .toleratedFrequency,
                    title: "Weekly frequency",
                    detail: "\(best.frequency) sessions per week has looked most sustainable so far, averaging about \(best.averageAdherence)% adherence."
                )
            }
        }

        let frequencyText = averaged
            .map { "\($0.frequency)x/wk" }
            .sorted()
            .joined(separator: " and ")
        return LongHorizonAdaptationInsight(
            kind: .toleratedFrequency,
            title: "Weekly frequency",
            detail: "You have tolerated \(frequencyText) similarly across recent blocks, without one cadence clearly outperforming the others."
        )
    }

    private static func missedSessionPatternInsight(
        for blocks: [EvaluatedBlock]
    ) -> LongHorizonAdaptationInsight? {
        let repeatedBlocks = blocks.filter {
            $0.review.headlineMetrics.sessionSummary.missedSessions > 0
        }
        guard repeatedBlocks.count >= 2 else { return nil }

        let missedCounts = repeatedBlocks.map {
            $0.review.headlineMetrics.sessionSummary.missedSessions
        }
        let averageMissed = Int((Double(missedCounts.reduce(0, +)) / Double(missedCounts.count)).rounded())
        return LongHorizonAdaptationInsight(
            kind: .missedSessionPattern,
            title: "Missed-session pattern",
            detail: "Missed sessions repeated in \(repeatedBlocks.count) of the last \(blocks.count) blocks, usually leaving about \(averageMissed) planned session\(averageMissed == 1 ? "" : "s") unfinished."
        )
    }

    private static func movementContinuityInsight(
        for blocks: [EvaluatedBlock]
    ) -> LongHorizonAdaptationInsight? {
        var liftHistory: [String: [(Date, MesocycleLiftHighlight)]] = [:]
        for block in blocks {
            for lift in block.review.recommendationInput.liftHighlights {
                liftHistory[lift.liftKey, default: []].append((block.endDate, lift))
            }
        }

        if let repeatedLift = liftHistory
            .filter({ $0.value.count >= 2 })
            .sorted(by: { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count > rhs.value.count
                }
                return lhs.key < rhs.key
            })
            .first?.value.sorted(by: { lhs, rhs in lhs.0 < rhs.0 }),
           let firstLift = repeatedLift.first?.1,
           let bestLift = repeatedLift.max(by: { lhs, rhs in
                lhs.1.bestEstimatedOneRepMaxLbs < rhs.1.bestEstimatedOneRepMaxLbs
           })?.1 {
            if bestLift.bestEstimatedOneRepMaxLbs > firstLift.firstEstimatedOneRepMaxLbs {
                return LongHorizonAdaptationInsight(
                    kind: .movementContinuity,
                    title: "Key-lift continuity",
                    detail: "\(bestLift.displayName) carried through \(repeatedLift.count) recent blocks and moved from about \(firstLift.firstEstimatedOneRepMaxLbs) to \(bestLift.bestEstimatedOneRepMaxLbs) lbs estimated 1RM."
                )
            }

            return LongHorizonAdaptationInsight(
                kind: .movementContinuity,
                title: "Key-lift continuity",
                detail: "\(bestLift.displayName) kept showing up across \(repeatedLift.count) recent blocks, which points to stable lift continuity."
            )
        }

        var anchorCounts: [String: Int] = [:]
        for block in blocks {
            let names = Set(block.review.headlineMetrics.exerciseConsistencySummary.anchorExercises.map(\.exerciseName))
            for name in names {
                anchorCounts[name, default: 0] += 1
            }
        }

        let repeatedAnchors = anchorCounts
            .filter { $0.value >= 2 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            .map(\.key)

        if !repeatedAnchors.isEmpty {
            let display = repeatedAnchors.prefix(2).joined(separator: " and ")
            return LongHorizonAdaptationInsight(
                kind: .movementContinuity,
                title: "Exercise continuity",
                detail: "\(display) stayed in rotation across multiple recent blocks."
            )
        }

        let dominantPattern = blocks
            .flatMap { $0.review.recommendationInput.movementPatterns }
            .reduce(into: [ProgramMovementPattern: Int]()) { result, entry in
                result[entry.pattern, default: 0] += entry.workoutCount
            }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key.rawValue < rhs.key.rawValue
            }
            .first?.key

        guard let dominantPattern else { return nil }
        return LongHorizonAdaptationInsight(
            kind: .movementContinuity,
            title: "Movement pattern continuity",
            detail: "\(movementPatternLabel(dominantPattern)) kept showing up across recent blocks, which gives the training history a clear through-line."
        )
    }

    private static func standaloneInfluenceInsight(
        for blocks: [EvaluatedBlock]
    ) -> LongHorizonAdaptationInsight? {
        let totalStandalone = blocks.reduce(0) {
            $0 + $1.review.standaloneInfluence.includedWorkoutCount
        }
        guard totalStandalone > 0 else { return nil }

        let blocksWithStandalone = blocks.filter {
            $0.review.standaloneInfluence.includedWorkoutCount > 0
        }.count
        let dominantPattern = blocks
            .flatMap { $0.review.standaloneInfluence.dominantPatterns }
            .reduce(into: [ProgramMovementPattern: Int]()) { result, entry in
                result[entry.pattern, default: 0] += entry.workoutCount
            }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key.rawValue < rhs.key.rawValue
            }
            .first?.key

        let detail: String
        if let dominantPattern {
            detail = "Standalone \(movementPatternDescriptor(dominantPattern)) showed up in \(blocksWithStandalone) of the last \(blocks.count) blocks and kept supplementing the main plan."
        } else {
            detail = "\(totalStandalone) standalone workout\(totalStandalone == 1 ? "" : "s") supplemented the last \(blocks.count) completed blocks."
        }

        return LongHorizonAdaptationInsight(
            kind: .standaloneInfluence,
            title: "Standalone influence",
            detail: detail
        )
    }

    private static func headline(
        for blocks: [EvaluatedBlock],
        insights: [LongHorizonAdaptationInsight]
    ) -> String {
        guard blocks.count > 1 else {
            return "One completed block gives you a baseline. Finish another block to unlock longer trend comparisons."
        }

        var clauses: [String] = [headlineClause(for: insights, kind: .adherenceTrend)]
        if let continuityClause = optionalHeadlineClause(for: insights, kind: .movementContinuity) {
            clauses.append(continuityClause)
        }
        if let frequencyClause = optionalHeadlineClause(for: insights, kind: .toleratedFrequency) {
            clauses.append(frequencyClause)
        }

        let trimmedClauses = clauses.prefix(3)
        return "Across the last \(blocks.count) blocks, " + trimmedClauses.joined(separator: ", and ") + "."
    }

    private static func headlineClause(
        for insights: [LongHorizonAdaptationInsight],
        kind: LongHorizonAdaptationInsightKind
    ) -> String {
        optionalHeadlineClause(for: insights, kind: kind) ?? "recent block data is available"
    }

    private static func optionalHeadlineClause(
        for insights: [LongHorizonAdaptationInsight],
        kind: LongHorizonAdaptationInsightKind
    ) -> String? {
        guard let insight = insights.first(where: { $0.kind == kind }) else { return nil }
        switch kind {
        case .adherenceTrend:
            if insight.detail.contains("trended up") {
                return "adherence has trended up"
            }
            if insight.detail.contains("trended down") {
                return "adherence has trended down"
            }
            return "adherence has stayed fairly steady"
        case .movementContinuity:
            if insight.title == "Key-lift continuity" {
                return "key lifts have stayed continuous"
            }
            if insight.title == "Exercise continuity" {
                return "anchor exercises have stayed in rotation"
            }
            return "movement patterns have stayed consistent"
        case .toleratedFrequency:
            if let number = insight.detail.firstNumber {
                return "\(number) sessions per week has looked sustainable"
            }
            return "weekly frequency has stayed manageable"
        case .missedSessionPattern:
            return "missed sessions have repeated"
        case .standaloneInfluence:
            return "standalone work has kept supporting the plan"
        case .insufficientData:
            return insight.detail
        }
    }

    private static func movementPatternLabel(_ pattern: ProgramMovementPattern) -> String {
        switch pattern {
        case .squatKneeDominant: return "Knee-dominant lower-body work"
        case .hinge: return "Hip-hinge work"
        case .horizontalPush: return "Horizontal pushing"
        case .verticalPush: return "Vertical pushing"
        case .horizontalPull: return "Horizontal pulling"
        case .verticalPull: return "Vertical pulling"
        case .singleLeg: return "Single-leg work"
        case .trunk: return "Trunk work"
        case .conditioning: return "Conditioning"
        }
    }

    private static func movementPatternDescriptor(_ pattern: ProgramMovementPattern) -> String {
        switch pattern {
        case .squatKneeDominant: return "knee-dominant work"
        case .hinge: return "hinge work"
        case .horizontalPush: return "horizontal pushing"
        case .verticalPush: return "vertical pushing"
        case .horizontalPull: return "horizontal pulling"
        case .verticalPull: return "vertical pulling"
        case .singleLeg: return "single-leg work"
        case .trunk: return "trunk work"
        case .conditioning: return "conditioning"
        }
    }
}

private extension String {
    var firstNumber: String? {
        let digits = self.split(whereSeparator: { !$0.isNumber }).first
        return digits.map(String.init)
    }
}
