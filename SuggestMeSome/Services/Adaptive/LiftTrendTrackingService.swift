//
//  LiftTrendTrackingService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData

/// Maintains lift-family trend state from persisted weekly outcomes.
/// - Uses canonical lift-family mapping from stored outcomes (not exact name matching).
/// - Blends program + standalone data while preserving higher confidence for program signals.
/// - Persists both rolling trend state (`LiftPerformanceTrend`) and per-week snapshots
///   (`LiftTrendSnapshot`) for explainability and downstream decision services.
enum LiftTrendTrackingService {
    private static let defaultTrackedLiftKeys: Set<String> =
        Set(CanonicalLift.allCases.map(\.rawValue) + ["row"])

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .autoupdatingCurrent
        return cal
    }

    static func updateTrends(
        for analysis: WeeklyTrainingAnalysis,
        context: ModelContext
    ) -> [String: LiftTrendStatus] {
        guard analysis.isFinalized else { return [:] }

        let allAnalyses = (try? context.fetch(FetchDescriptor<WeeklyTrainingAnalysis>())) ?? []
        var allTrends = (try? context.fetch(FetchDescriptor<LiftPerformanceTrend>())) ?? []
        var allSnapshots = (try? context.fetch(FetchDescriptor<LiftTrendSnapshot>())) ?? []

        let scopedAnalyses = analysesForScope(
            source: allAnalyses,
            runID: analysis.programRun?.id,
            upTo: analysis.weekEndDate
        )
        let scopedOutcomes = scopedAnalyses
            .flatMap(\.outcomes)
            .filter { $0.canonicalLiftKey != nil && $0.actualTopSetEstimated1RM != nil }

        guard !scopedOutcomes.isEmpty else { return [:] }

        var candidateLiftKeys = Set(scopedOutcomes.compactMap(\.canonicalLiftKey))
        let scopedExistingTrendKeys = allTrends
            .filter { trend in
                if let runID = analysis.programRun?.id {
                    return trend.programRun?.id == runID
                }
                return trend.programRun == nil
            }
            .map(\.canonicalLiftKey)
        candidateLiftKeys.formUnion(scopedExistingTrendKeys)

        for key in defaultTrackedLiftKeys {
            let keyCount = scopedOutcomes.filter { $0.canonicalLiftKey == key }.count
            if keyCount >= 2 {
                candidateLiftKeys.insert(key)
            }
        }

        var summary: [String: LiftTrendStatus] = [:]

        for liftKey in candidateLiftKeys.sorted() {
            let rawPoints = scopedOutcomes
                .filter { $0.canonicalLiftKey == liftKey }
                .compactMap { buildPoint(from: $0, liftKey: liftKey) }
                .sorted { lhs, rhs in
                    if lhs.date == rhs.date { return lhs.outcomeID.uuidString < rhs.outcomeID.uuidString }
                    return lhs.date < rhs.date
                }

            guard !rawPoints.isEmpty else { continue }
            let points = collapsePointsByWorkout(rawPoints)
            guard !points.isEmpty else { continue }

            let metrics = buildMetrics(
                points: points,
                liftKey: liftKey,
                weekEndDate: analysis.weekEndDate
            )

            let trend = upsertTrend(
                for: liftKey,
                analysis: analysis,
                existing: &allTrends,
                context: context
            )
            applyMetrics(metrics, to: trend, analysis: analysis)

            upsertSnapshot(
                liftKey: liftKey,
                metrics: metrics,
                trend: trend,
                analysis: analysis,
                snapshots: &allSnapshots,
                context: context
            )

            summary[liftKey] = metrics.trendStatus
        }

        return summary
    }

    // MARK: - Scope Fetch

    private static func analysesForScope(
        source: [WeeklyTrainingAnalysis],
        runID: UUID?,
        upTo weekEndDate: Date
    ) -> [WeeklyTrainingAnalysis] {
        source
            .filter {
                guard $0.isFinalized else { return false }
                guard $0.weekStartDate <= weekEndDate else { return false }
                if let runID {
                    return $0.programRun?.id == runID
                }
                return $0.programRun == nil
            }
            .sorted { lhs, rhs in
                if lhs.weekStartDate == rhs.weekStartDate {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.weekStartDate < rhs.weekStartDate
            }
    }

    // MARK: - Point Build

    private static func buildPoint(
        from outcome: ExercisePerformanceOutcome,
        liftKey: String
    ) -> TrendPoint? {
        guard let e1rm = outcome.actualTopSetEstimated1RM else { return nil }

        let isMainLift = liftKey == CanonicalLift.squat.rawValue || liftKey == CanonicalLift.bench.rawValue || liftKey == CanonicalLift.deadlift.rawValue

        let sourceMultiplier: Double = {
            switch outcome.signalSource {
            case .programLinked: return 1.0
            case .standalone: return 0.75
            }
        }()

        let confidenceMultiplier: Double = {
            switch outcome.signalConfidence {
            case .high: return 1.0
            case .medium: return 0.82
            case .low: return 0.62
            }
        }()

        let topSetMultiplier: Double = {
            if outcome.isTopSetSignal {
                return isMainLift ? 1.22 : 1.08
            }
            return isMainLift ? 0.55 : 0.80
        }()

        var adjustedWeight = max(0.05, outcome.signalWeight)
        adjustedWeight *= sourceMultiplier
        adjustedWeight *= confidenceMultiplier
        adjustedWeight *= topSetMultiplier
        adjustedWeight = min(1.65, adjustedWeight)

        return TrendPoint(
            outcomeID: outcome.id,
            workoutID: outcome.workout?.id,
            date: outcome.workoutDate,
            e1rm: e1rm,
            topSetWeight: outcome.actualTopSetWeight,
            topSetReps: outcome.actualTopSetReps,
            performanceScoreValue: outcome.performanceScoreValue,
            performanceScore: outcome.performanceScore,
            inferredFatigueStatus: outcome.inferredFatigueStatus,
            signalSource: outcome.signalSource,
            adjustedWeight: adjustedWeight
        )
    }

    /// Collapse same-workout lift-family signals into one point to avoid overweighting a
    /// single anomalous session with multiple variation rows.
    private static func collapsePointsByWorkout(_ points: [TrendPoint]) -> [TrendPoint] {
        let grouped = Dictionary(grouping: points) { $0.workoutID ?? $0.outcomeID }
        return grouped.values.compactMap { group in
            guard !group.isEmpty else { return nil }
            return group.max { lhs, rhs in
                let lhsPriority = lhs.adjustedWeight * lhs.e1rm
                let rhsPriority = rhs.adjustedWeight * rhs.e1rm
                if lhsPriority == rhsPriority {
                    if lhs.e1rm == rhs.e1rm {
                        return lhs.outcomeID.uuidString < rhs.outcomeID.uuidString
                    }
                    return lhs.e1rm < rhs.e1rm
                }
                return lhsPriority < rhsPriority
            }
        }
        .sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.outcomeID.uuidString < rhs.outcomeID.uuidString }
            return lhs.date < rhs.date
        }
    }

    // MARK: - Metrics

    private static func buildMetrics(
        points: [TrendPoint],
        liftKey: String,
        weekEndDate: Date
    ) -> TrendMetrics {
        let latest = points.last
        let weightedSignalCount = points.reduce(0.0) { $0 + $1.adjustedWeight }
        let weightedProgramSignal = points
            .filter { $0.signalSource == .programLinked }
            .reduce(0.0) { $0 + $1.adjustedWeight }
        let weightedStandaloneSignal = points
            .filter { $0.signalSource == .standalone }
            .reduce(0.0) { $0 + $1.adjustedWeight }

        let latestWindow = Array(points.suffix(min(4, points.count)))
        let previousWindow = Array(points.dropLast(latestWindow.count).suffix(4))
        let currentE1RM = robustWeightedAverage(latestWindow.map { ($0.e1rm, $0.adjustedWeight) })
        let previousE1RM = robustWeightedAverage(previousWindow.map { ($0.e1rm, $0.adjustedWeight) })

        let currentWindowStart = calendar.date(byAdding: .day, value: -27, to: weekEndDate) ?? weekEndDate
        let priorWindowEnd = calendar.date(byAdding: .day, value: -28, to: weekEndDate) ?? weekEndDate
        let priorWindowStart = calendar.date(byAdding: .day, value: -55, to: weekEndDate) ?? weekEndDate

        let currentWindowPoints = points.filter {
            $0.date >= currentWindowStart && $0.date <= weekEndDate
        }
        let priorWindowPoints = points.filter {
            $0.date >= priorWindowStart && $0.date <= priorWindowEnd
        }

        let currentWindowE1RM = robustWeightedAverage(currentWindowPoints.map { ($0.e1rm, $0.adjustedWeight) })
        let priorWindowE1RM = robustWeightedAverage(priorWindowPoints.map { ($0.e1rm, $0.adjustedWeight) })

        let changePercent: Double? = {
            if let currentWindowE1RM, let priorWindowE1RM, priorWindowE1RM > 0 {
                return ((currentWindowE1RM - priorWindowE1RM) / priorWindowE1RM) * 100.0
            }
            if let currentE1RM, let previousE1RM, previousE1RM > 0 {
                return ((currentE1RM - previousE1RM) / previousE1RM) * 100.0
            }
            return nil
        }()

        let recentValues = Array(points.suffix(min(6, points.count))).map(\.e1rm)
        let volatilityPercent = coefficientOfVariationPercent(recentValues)
        let recentPerformanceScore = robustWeightedAverage(
            Array(points.suffix(min(6, points.count))).map { ($0.performanceScoreValue, $0.adjustedWeight) }
        ) ?? 0

        let confidenceScore = computeConfidenceScore(
            weightedSignalCount: weightedSignalCount,
            weightedProgramSignal: weightedProgramSignal,
            volatilityPercent: volatilityPercent
        )

        let trendStatus = classifyTrendStatus(
            sampleCount: points.count,
            weightedSignalCount: weightedSignalCount,
            changePercent: changePercent,
            recentPerformanceScore: recentPerformanceScore,
            volatilityPercent: volatilityPercent,
            confidenceScore: confidenceScore
        )
        let fatigueStatus = inferFatigueStatus(points: points)

        return TrendMetrics(
            liftKey: liftKey,
            totalDataPoints: points.count,
            programLinkedDataPoints: points.filter { $0.signalSource == .programLinked }.count,
            standaloneDataPoints: points.filter { $0.signalSource == .standalone }.count,
            weightedSignalCount: weightedSignalCount,
            weightedProgramSignal: weightedProgramSignal,
            weightedStandaloneSignal: weightedStandaloneSignal,
            confidenceScore: confidenceScore,
            firstObservationDate: points.first?.date ?? Date.now,
            lastObservationDate: points.last?.date ?? Date.now,
            currentEstimated1RM: currentE1RM,
            previousEstimated1RM: previousE1RM,
            rollingBestEstimated1RM: points.map(\.e1rm).max(),
            changePercent: changePercent,
            trendStatus: trendStatus,
            fatigueStatus: fatigueStatus,
            latestTopSetWeight: latest?.topSetWeight,
            latestTopSetReps: latest?.topSetReps,
            latestPerformanceScoreValue: latest?.performanceScoreValue,
            latestPerformanceScore: latest?.performanceScore,
            note: noteText(
                liftKey: liftKey,
                weightedSignalCount: weightedSignalCount,
                weightedProgramSignal: weightedProgramSignal,
                weightedStandaloneSignal: weightedStandaloneSignal,
                changePercent: changePercent,
                volatilityPercent: volatilityPercent,
                recentPerformanceScore: recentPerformanceScore,
                trendStatus: trendStatus
            )
        )
    }

    private static func computeConfidenceScore(
        weightedSignalCount: Double,
        weightedProgramSignal: Double,
        volatilityPercent: Double
    ) -> Double {
        let sampleComponent = min(1.0, weightedSignalCount / 7.0)
        let programRatio = weightedSignalCount > 0 ? weightedProgramSignal / weightedSignalCount : 0
        let programBonus = min(0.22, programRatio * 0.22)
        let volatilityPenalty: Double = {
            if volatilityPercent > 10 { return 0.12 }
            if volatilityPercent > 6 { return 0.06 }
            return 0
        }()

        return max(0.1, min(1.0, sampleComponent + programBonus - volatilityPenalty))
    }

    private static func classifyTrendStatus(
        sampleCount: Int,
        weightedSignalCount: Double,
        changePercent: Double?,
        recentPerformanceScore: Double,
        volatilityPercent: Double,
        confidenceScore: Double
    ) -> LiftTrendStatus {
        guard sampleCount >= 3, weightedSignalCount >= 1.5 else { return .insufficientData }
        guard confidenceScore >= 0.20 else { return .insufficientData }

        if volatilityPercent > 10.5, (changePercent.map { abs($0) } ?? 0) < 2.5 {
            return .volatile
        }

        if let changePercent {
            if changePercent >= 1.25 { return .improving }
            if changePercent <= -1.25 { return .declining }
            return .stable // stable ~= stagnant
        }

        if recentPerformanceScore >= 3.0 { return .improving }
        if recentPerformanceScore <= -3.0 { return .declining }
        return .stable
    }

    private static func inferFatigueStatus(points: [TrendPoint]) -> FatigueStatus {
        let recent = Array(points.suffix(min(6, points.count)))
        let scalar = robustWeightedAverage(recent.map { point in
            (fatigueScalar(point.inferredFatigueStatus), point.adjustedWeight)
        }) ?? 1.0

        if scalar < 0.9 { return .low }
        if scalar < 1.15 { return .manageable }
        if scalar < 1.45 { return .elevated }
        if scalar < 1.9 { return .high }
        return .critical
    }

    // MARK: - Persistence

    private static func upsertTrend(
        for liftKey: String,
        analysis: WeeklyTrainingAnalysis,
        existing: inout [LiftPerformanceTrend],
        context: ModelContext
    ) -> LiftPerformanceTrend {
        if let found = existing.first(where: { trend in
            trend.canonicalLiftKey == liftKey &&
            (
                (analysis.programRun?.id == nil && trend.programRun == nil) ||
                (analysis.programRun?.id != nil && trend.programRun?.id == analysis.programRun?.id)
            )
        }) {
            return found
        }

        let trend = LiftPerformanceTrend(
            programRun: analysis.programRun,
            trainingProgram: analysis.trainingProgram ?? analysis.programRun?.program,
            canonicalLiftKey: liftKey,
            liftDisplayName: liftDisplayName(for: liftKey)
        )
        context.insert(trend)
        existing.append(trend)
        return trend
    }

    private static func applyMetrics(
        _ metrics: TrendMetrics,
        to trend: LiftPerformanceTrend,
        analysis: WeeklyTrainingAnalysis
    ) {
        trend.updatedAt = Date.now
        trend.programRun = analysis.programRun
        trend.trainingProgram = analysis.trainingProgram ?? analysis.programRun?.program
        trend.canonicalLiftKey = metrics.liftKey
        trend.liftDisplayName = liftDisplayName(for: metrics.liftKey)

        trend.totalDataPoints = metrics.totalDataPoints
        trend.programLinkedDataPoints = metrics.programLinkedDataPoints
        trend.standaloneDataPoints = metrics.standaloneDataPoints
        trend.weightedSignalCount = metrics.weightedSignalCount
        trend.confidenceScore = metrics.confidenceScore

        trend.firstObservationDate = metrics.firstObservationDate
        trend.lastObservationDate = metrics.lastObservationDate
        trend.currentEstimated1RM = metrics.currentEstimated1RM
        trend.previousEstimated1RM = metrics.previousEstimated1RM
        trend.rollingBestEstimated1RM = metrics.rollingBestEstimated1RM
        trend.fourWeekChangePercent = metrics.changePercent
        trend.trendStatus = metrics.trendStatus
        trend.fatigueStatus = metrics.fatigueStatus

        trend.latestTopSetWeight = metrics.latestTopSetWeight
        trend.latestTopSetReps = metrics.latestTopSetReps
        trend.latestPerformanceScoreValue = metrics.latestPerformanceScoreValue
        trend.lastPerformanceScore = metrics.latestPerformanceScore
    }

    private static func upsertSnapshot(
        liftKey: String,
        metrics: TrendMetrics,
        trend: LiftPerformanceTrend,
        analysis: WeeklyTrainingAnalysis,
        snapshots: inout [LiftTrendSnapshot],
        context: ModelContext
    ) {
        let snapshot = snapshots.first(where: {
            $0.analysis?.id == analysis.id &&
            $0.canonicalLiftKey == liftKey &&
            (
                (analysis.programRun?.id == nil && $0.programRun == nil) ||
                (analysis.programRun?.id != nil && $0.programRun?.id == analysis.programRun?.id)
            )
        }) ?? {
            let newSnapshot = LiftTrendSnapshot(
                trend: trend,
                analysis: analysis,
                programRun: analysis.programRun,
                trainingProgram: analysis.trainingProgram ?? analysis.programRun?.program,
                canonicalLiftKey: liftKey,
                liftDisplayName: liftDisplayName(for: liftKey),
                weekStartDate: analysis.weekStartDate,
                weekEndDate: analysis.weekEndDate,
                programWeekNumber: analysis.programWeekNumber
            )
            context.insert(newSnapshot)
            snapshots.append(newSnapshot)
            return newSnapshot
        }()

        snapshot.createdAt = Date.now
        snapshot.trend = trend
        snapshot.analysis = analysis
        snapshot.programRun = analysis.programRun
        snapshot.trainingProgram = analysis.trainingProgram ?? analysis.programRun?.program
        snapshot.canonicalLiftKey = liftKey
        snapshot.liftDisplayName = liftDisplayName(for: liftKey)
        snapshot.weekStartDate = analysis.weekStartDate
        snapshot.weekEndDate = analysis.weekEndDate
        snapshot.programWeekNumber = analysis.programWeekNumber

        snapshot.totalDataPoints = metrics.totalDataPoints
        snapshot.programLinkedDataPoints = metrics.programLinkedDataPoints
        snapshot.standaloneDataPoints = metrics.standaloneDataPoints
        snapshot.weightedSignalCount = metrics.weightedSignalCount
        snapshot.weightedProgramSignal = metrics.weightedProgramSignal
        snapshot.weightedStandaloneSignal = metrics.weightedStandaloneSignal
        snapshot.confidenceScore = metrics.confidenceScore

        snapshot.currentEstimated1RM = metrics.currentEstimated1RM
        snapshot.baselineEstimated1RM = metrics.previousEstimated1RM
        snapshot.rollingBestEstimated1RM = metrics.rollingBestEstimated1RM
        snapshot.changePercent = metrics.changePercent
        snapshot.trendStatus = metrics.trendStatus
        snapshot.fatigueStatus = metrics.fatigueStatus

        snapshot.latestTopSetWeight = metrics.latestTopSetWeight
        snapshot.latestTopSetReps = metrics.latestTopSetReps
        snapshot.latestPerformanceScoreValue = metrics.latestPerformanceScoreValue
        snapshot.note = metrics.note
    }

    // MARK: - Math / Formatting

    private static func robustWeightedAverage(_ values: [(value: Double, weight: Double)]) -> Double? {
        let valid = values.filter { $0.weight > 0 }
        guard !valid.isEmpty else { return nil }

        let sample: [(value: Double, weight: Double)]
        if valid.count >= 7 {
            let sorted = valid.sorted { $0.value < $1.value }
            let trim = max(1, Int(Double(sorted.count) * 0.15))
            if sorted.count > (trim * 2 + 1) {
                sample = Array(sorted.dropFirst(trim).dropLast(trim))
            } else {
                sample = sorted
            }
        } else {
            sample = valid
        }

        let weightedSum = sample.reduce(0.0) { $0 + ($1.value * $1.weight) }
        let totalWeight = sample.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        return weightedSum / totalWeight
    }

    private static func coefficientOfVariationPercent(_ values: [Double]) -> Double {
        guard values.count >= 3 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.reduce(0.0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        let stdDev = sqrt(variance)
        return (stdDev / mean) * 100.0
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

    private static func liftDisplayName(for key: String) -> String {
        switch key {
        case CanonicalLift.squat.rawValue:         return CanonicalLift.squat.displayName
        case CanonicalLift.bench.rawValue:         return CanonicalLift.bench.displayName
        case CanonicalLift.deadlift.rawValue:      return CanonicalLift.deadlift.displayName
        case CanonicalLift.overheadPress.rawValue: return CanonicalLift.overheadPress.displayName
        case "row": return "Row"
        default: return key
        }
    }

    private static func noteText(
        liftKey: String,
        weightedSignalCount: Double,
        weightedProgramSignal: Double,
        weightedStandaloneSignal: Double,
        changePercent: Double?,
        volatilityPercent: Double,
        recentPerformanceScore: Double,
        trendStatus: LiftTrendStatus
    ) -> String {
        [
            "lift=\(liftKey)",
            "weighted_signals=\(fmt2(weightedSignalCount))",
            "program_weight=\(fmt2(weightedProgramSignal))",
            "standalone_weight=\(fmt2(weightedStandaloneSignal))",
            "change_pct=\(fmt1(changePercent))",
            "volatility_pct=\(fmt1(volatilityPercent))",
            "recent_perf_score=\(fmt1(recentPerformanceScore))",
            "trend=\(trendStatus.rawValue)"
        ].joined(separator: "; ")
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

private struct TrendPoint {
    let outcomeID: UUID
    let workoutID: UUID?
    let date: Date
    let e1rm: Double
    let topSetWeight: Double?
    let topSetReps: Int?
    let performanceScoreValue: Double
    let performanceScore: PerformanceScore
    let inferredFatigueStatus: FatigueStatus
    let signalSource: WorkoutSignalSource
    let adjustedWeight: Double
}

private struct TrendMetrics {
    let liftKey: String
    let totalDataPoints: Int
    let programLinkedDataPoints: Int
    let standaloneDataPoints: Int
    let weightedSignalCount: Double
    let weightedProgramSignal: Double
    let weightedStandaloneSignal: Double
    let confidenceScore: Double
    let firstObservationDate: Date
    let lastObservationDate: Date
    let currentEstimated1RM: Double?
    let previousEstimated1RM: Double?
    let rollingBestEstimated1RM: Double?
    let changePercent: Double?
    let trendStatus: LiftTrendStatus
    let fatigueStatus: FatigueStatus
    let latestTopSetWeight: Double?
    let latestTopSetReps: Int?
    let latestPerformanceScoreValue: Double?
    let latestPerformanceScore: PerformanceScore?
    let note: String
}
