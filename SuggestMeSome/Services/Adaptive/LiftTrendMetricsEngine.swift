import Foundation

enum LiftTrendMetricsEngine {
    static func buildMetrics(
        points: [LiftTrendPoint],
        liftKey: String,
        weekEndDate: Date
    ) -> LiftTrendMetrics {
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
        let currentE1RM = LiftTrendTrackingSupport.robustWeightedAverage(
            latestWindow.map { ($0.e1rm, $0.adjustedWeight) }
        )
        let previousE1RM = LiftTrendTrackingSupport.robustWeightedAverage(
            previousWindow.map { ($0.e1rm, $0.adjustedWeight) }
        )

        let calendar = LiftTrendTrackingSupport.calendar
        let currentWindowStart = calendar.date(byAdding: .day, value: -27, to: weekEndDate) ?? weekEndDate
        let priorWindowEnd = calendar.date(byAdding: .day, value: -28, to: weekEndDate) ?? weekEndDate
        let priorWindowStart = calendar.date(byAdding: .day, value: -55, to: weekEndDate) ?? weekEndDate

        let currentWindowPoints = points.filter {
            $0.date >= currentWindowStart && $0.date <= weekEndDate
        }
        let priorWindowPoints = points.filter {
            $0.date >= priorWindowStart && $0.date <= priorWindowEnd
        }

        let currentWindowE1RM = LiftTrendTrackingSupport.robustWeightedAverage(
            currentWindowPoints.map { ($0.e1rm, $0.adjustedWeight) }
        )
        let priorWindowE1RM = LiftTrendTrackingSupport.robustWeightedAverage(
            priorWindowPoints.map { ($0.e1rm, $0.adjustedWeight) }
        )

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
        let volatilityPercent = LiftTrendTrackingSupport.coefficientOfVariationPercent(recentValues)
        let recentPerformanceScore = LiftTrendTrackingSupport.robustWeightedAverage(
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

        return LiftTrendMetrics(
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
            fatigueStatus: inferFatigueStatus(points: points),
            latestTopSetWeight: latest?.topSetWeight,
            latestTopSetReps: latest?.topSetReps,
            latestPerformanceScoreValue: latest?.performanceScoreValue,
            latestPerformanceScore: latest?.performanceScore,
            note: LiftTrendTrackingSupport.noteText(
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
            return .stable
        }

        if recentPerformanceScore >= 3.0 { return .improving }
        if recentPerformanceScore <= -3.0 { return .declining }
        return .stable
    }

    private static func inferFatigueStatus(points: [LiftTrendPoint]) -> FatigueStatus {
        let recent = Array(points.suffix(min(6, points.count)))
        let scalar = LiftTrendTrackingSupport.robustWeightedAverage(recent.map { point in
            (
                LiftTrendTrackingSupport.fatigueScalar(point.inferredFatigueStatus),
                point.adjustedWeight
            )
        }) ?? 1.0

        if scalar < 0.9 { return .low }
        if scalar < 1.15 { return .manageable }
        if scalar < 1.45 { return .elevated }
        if scalar < 1.9 { return .high }
        return .critical
    }
}
