import Foundation

enum WeeklyAnalysisFatigueEvaluator {
    static func observedFatigueScore(outcomes: [ExercisePerformanceOutcome]) -> Double {
        guard !outcomes.isEmpty else { return 0 }

        var total = 0.0
        for outcome in outcomes {
            let fatigueScalar: Double = {
                switch outcome.inferredFatigueStatus {
                case .low: return 0.80
                case .manageable: return 1.00
                case .elevated: return 1.30
                case .high: return 1.70
                case .critical: return 2.20
                }
            }()
            let setFactor = max(0.50, min(2.0, Double(max(1, outcome.actualSetCount)) / 4.0))
            let topSetFactor = outcome.isTopSetSignal ? 1.20 : 1.0
            total += outcome.signalWeight * fatigueScalar * setFactor * topSetFactor * 4.0
        }

        return total
    }

    static func inferWeeklyFatigueStatus(
        observedFatigueScore: Double,
        plannedFatigueScore: Double?
    ) -> FatigueStatus {
        if let plannedFatigueScore, plannedFatigueScore > 0 {
            let ratio = observedFatigueScore / plannedFatigueScore
            if ratio < 0.75 { return .low }
            if ratio < 1.05 { return .manageable }
            if ratio < 1.25 { return .elevated }
            if ratio < 1.50 { return .high }
            return .critical
        }

        if observedFatigueScore < 20 { return .low }
        if observedFatigueScore < 40 { return .manageable }
        if observedFatigueScore < 60 { return .elevated }
        if observedFatigueScore < 80 { return .high }
        return .critical
    }
}
