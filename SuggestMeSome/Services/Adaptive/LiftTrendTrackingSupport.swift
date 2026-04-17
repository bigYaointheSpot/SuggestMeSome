import Foundation
import SwiftData

struct LiftTrendTrackingScopeSnapshot {
    let finalizedAnalyses: [WeeklyTrainingAnalysis]
    let scopedOutcomes: [ExercisePerformanceOutcome]
    var existingTrends: [LiftPerformanceTrend]
    var existingSnapshots: [LiftTrendSnapshot]
    let candidateLiftKeys: Set<String>
}

struct LiftTrendPoint {
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

struct LiftTrendMetrics {
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

enum LiftTrendTrackingSupport {
    static let defaultTrackedLiftKeys: Set<String> =
        Set(CanonicalLift.allCases.map(\.rawValue) + ["row"])

    static var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .autoupdatingCurrent
        return cal
    }

    static func liftDisplayName(for key: String) -> String {
        switch key {
        case CanonicalLift.squat.rawValue:         return CanonicalLift.squat.displayName
        case CanonicalLift.bench.rawValue:         return CanonicalLift.bench.displayName
        case CanonicalLift.deadlift.rawValue:      return CanonicalLift.deadlift.displayName
        case CanonicalLift.overheadPress.rawValue: return CanonicalLift.overheadPress.displayName
        case "row": return "Row"
        default: return key
        }
    }

    static func robustWeightedAverage(_ values: [(value: Double, weight: Double)]) -> Double? {
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

    static func coefficientOfVariationPercent(_ values: [Double]) -> Double {
        guard values.count >= 3 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.reduce(0.0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        let stdDev = sqrt(variance)
        return (stdDev / mean) * 100.0
    }

    static func fatigueScalar(_ status: FatigueStatus) -> Double {
        switch status {
        case .low: return 0.8
        case .manageable: return 1.0
        case .elevated: return 1.3
        case .high: return 1.8
        case .critical: return 2.3
        }
    }

    static func noteText(
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

    static func fmt1(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", value)
    }

    static func fmt2(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }
}

enum LiftTrendPointBuilder {
    static func buildPoints(
        for liftKey: String,
        outcomes: [ExercisePerformanceOutcome]
    ) -> [LiftTrendPoint] {
        let rawPoints = outcomes
            .filter { $0.canonicalLiftKey == liftKey }
            .compactMap { buildPoint(from: $0, liftKey: liftKey) }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.outcomeID.uuidString < rhs.outcomeID.uuidString }
                return lhs.date < rhs.date
            }

        guard !rawPoints.isEmpty else { return [] }
        return collapsePointsByWorkout(rawPoints)
    }

    private static func buildPoint(
        from outcome: ExercisePerformanceOutcome,
        liftKey: String
    ) -> LiftTrendPoint? {
        guard let e1rm = outcome.actualTopSetEstimated1RM else { return nil }

        let isMainLift =
            liftKey == CanonicalLift.squat.rawValue ||
            liftKey == CanonicalLift.bench.rawValue ||
            liftKey == CanonicalLift.deadlift.rawValue

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

        return LiftTrendPoint(
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
    private static func collapsePointsByWorkout(_ points: [LiftTrendPoint]) -> [LiftTrendPoint] {
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
}
