import Foundation
import SwiftData

enum LiftTrendTrackingScopeLoader {
    static func loadSnapshot(
        for analysis: WeeklyTrainingAnalysis,
        context: ModelContext
    ) -> LiftTrendTrackingScopeSnapshot {
        let finalizedAnalyses = fetchAnalyses(for: analysis, context: context)
        let scopedOutcomes = finalizedAnalyses
            .flatMap(\.outcomes)
            .filter { $0.canonicalLiftKey != nil && $0.actualTopSetEstimated1RM != nil }

        let existingTrends = fetchExistingTrends(for: analysis, context: context)
        let existingSnapshots = fetchCurrentAnalysisSnapshots(for: analysis, context: context)

        var candidateLiftKeys = Set(scopedOutcomes.compactMap(\.canonicalLiftKey))
        candidateLiftKeys.formUnion(existingTrends.map(\.canonicalLiftKey))

        for key in LiftTrendTrackingSupport.defaultTrackedLiftKeys {
            let keyCount = scopedOutcomes.filter { $0.canonicalLiftKey == key }.count
            if keyCount >= 2 {
                candidateLiftKeys.insert(key)
            }
        }

        return LiftTrendTrackingScopeSnapshot(
            finalizedAnalyses: finalizedAnalyses,
            scopedOutcomes: scopedOutcomes,
            existingTrends: existingTrends,
            existingSnapshots: existingSnapshots,
            candidateLiftKeys: candidateLiftKeys
        )
    }

    private static func fetchAnalyses(
        for analysis: WeeklyTrainingAnalysis,
        context: ModelContext
    ) -> [WeeklyTrainingAnalysis] {
        let weekEndDate = analysis.weekEndDate

        let descriptor: FetchDescriptor<WeeklyTrainingAnalysis>
        if let runID = analysis.programRun?.id {
            descriptor = FetchDescriptor<WeeklyTrainingAnalysis>(
                predicate: #Predicate<WeeklyTrainingAnalysis> {
                    $0.programRun?.id == runID &&
                    $0.isFinalized &&
                    $0.weekEndDate <= weekEndDate
                },
                sortBy: [
                    SortDescriptor(\WeeklyTrainingAnalysis.weekStartDate, order: .forward),
                    SortDescriptor(\WeeklyTrainingAnalysis.createdAt, order: .forward),
                ]
            )
        } else {
            descriptor = FetchDescriptor<WeeklyTrainingAnalysis>(
                predicate: #Predicate<WeeklyTrainingAnalysis> {
                    $0.programRun == nil &&
                    $0.isFinalized &&
                    $0.weekEndDate <= weekEndDate
                },
                sortBy: [
                    SortDescriptor(\WeeklyTrainingAnalysis.weekStartDate, order: .forward),
                    SortDescriptor(\WeeklyTrainingAnalysis.createdAt, order: .forward),
                ]
            )
        }

        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchExistingTrends(
        for analysis: WeeklyTrainingAnalysis,
        context: ModelContext
    ) -> [LiftPerformanceTrend] {
        let descriptor: FetchDescriptor<LiftPerformanceTrend>
        if let runID = analysis.programRun?.id {
            descriptor = FetchDescriptor<LiftPerformanceTrend>(
                predicate: #Predicate<LiftPerformanceTrend> { $0.programRun?.id == runID },
                sortBy: [
                    SortDescriptor(\LiftPerformanceTrend.updatedAt, order: .reverse),
                    SortDescriptor(\LiftPerformanceTrend.canonicalLiftKey, order: .forward),
                ]
            )
        } else {
            descriptor = FetchDescriptor<LiftPerformanceTrend>(
                predicate: #Predicate<LiftPerformanceTrend> { $0.programRun == nil },
                sortBy: [
                    SortDescriptor(\LiftPerformanceTrend.updatedAt, order: .reverse),
                    SortDescriptor(\LiftPerformanceTrend.canonicalLiftKey, order: .forward),
                ]
            )
        }

        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchCurrentAnalysisSnapshots(
        for analysis: WeeklyTrainingAnalysis,
        context: ModelContext
    ) -> [LiftTrendSnapshot] {
        let analysisID = analysis.id
        let descriptor = FetchDescriptor<LiftTrendSnapshot>(
            predicate: #Predicate<LiftTrendSnapshot> { $0.analysis?.id == analysisID },
            sortBy: [SortDescriptor(\LiftTrendSnapshot.canonicalLiftKey, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
