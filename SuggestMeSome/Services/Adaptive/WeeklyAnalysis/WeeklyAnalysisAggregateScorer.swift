import Foundation

enum WeeklyAnalysisAggregateScorer {
    static func aggregateWeekSignals(
        selectedWorkouts: [Workout],
        selectedOutcomes: [ExercisePerformanceOutcome],
        plannedFatigueScore: Double?
    ) -> WeeklyAnalysisAggregates {
        let weightedPerformanceScore = weightedAverage(
            values: selectedOutcomes.map { ($0.performanceScoreValue, max(0.01, $0.signalWeight)) }
        ) ?? 0

        let adherenceScore = WeeklyAnalysisAdherenceScorer.compute(
            selectedWorkouts: selectedWorkouts,
            selectedOutcomes: selectedOutcomes
        )

        let volume = WeeklyAnalysisVolumeAggregator.completedVolume(from: selectedWorkouts)
        let observedFatigueScore = WeeklyAnalysisFatigueEvaluator.observedFatigueScore(outcomes: selectedOutcomes)
        let fatigueStatus = WeeklyAnalysisFatigueEvaluator.inferWeeklyFatigueStatus(
            observedFatigueScore: observedFatigueScore,
            plannedFatigueScore: plannedFatigueScore
        )
        let mainLiftTopSetE1RM = summarizeMainLiftTopSets(outcomes: selectedOutcomes)

        return WeeklyAnalysisAggregates(
            weightedPerformanceScore: weightedPerformanceScore,
            adherenceScore: adherenceScore,
            observedFatigueScore: observedFatigueScore,
            fatigueStatus: fatigueStatus,
            completedHardSetsByMuscle: volume.completedHardSetsByMuscle,
            weightedHardSetsByMuscle: volume.weightedHardSetsByMuscle,
            totalCompletedHardSets: volume.totalCompletedHardSets,
            totalCompletedTonnageLbs: volume.totalCompletedTonnageLbs,
            mainLiftTopSetE1RM: mainLiftTopSetE1RM
        )
    }

    private static func summarizeMainLiftTopSets(
        outcomes: [ExercisePerformanceOutcome]
    ) -> [String: Double] {
        let mainKeys: Set<String> = Set([CanonicalLift.squat, .bench, .deadlift].map(\.rawValue))
        var summary: [String: Double] = [:]

        for outcome in outcomes {
            guard
                let liftKey = outcome.canonicalLiftKey,
                mainKeys.contains(liftKey),
                let e1rm = outcome.actualTopSetEstimated1RM
            else { continue }

            summary[liftKey] = max(summary[liftKey] ?? 0, e1rm)
        }

        return summary
    }

    private static func weightedAverage(values: [(Double, Double)]) -> Double? {
        let valid = values.filter { $0.1 > 0 }
        guard !valid.isEmpty else { return nil }
        let numerator = valid.reduce(0.0) { $0 + ($1.0 * $1.1) }
        let denominator = valid.reduce(0.0) { $0 + $1.1 }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }
}
