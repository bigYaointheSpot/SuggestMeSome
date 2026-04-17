import Foundation
import SwiftData

enum LiftTrendPersistenceStore {
    static func upsertTrend(
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
            liftDisplayName: LiftTrendTrackingSupport.liftDisplayName(for: liftKey)
        )
        context.insert(trend)
        existing.append(trend)
        return trend
    }

    static func applyMetrics(
        _ metrics: LiftTrendMetrics,
        to trend: LiftPerformanceTrend,
        analysis: WeeklyTrainingAnalysis
    ) {
        trend.updatedAt = Date.now
        trend.programRun = analysis.programRun
        trend.trainingProgram = analysis.trainingProgram ?? analysis.programRun?.program
        trend.canonicalLiftKey = metrics.liftKey
        trend.liftDisplayName = LiftTrendTrackingSupport.liftDisplayName(for: metrics.liftKey)

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

    static func upsertSnapshot(
        liftKey: String,
        metrics: LiftTrendMetrics,
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
                liftDisplayName: LiftTrendTrackingSupport.liftDisplayName(for: liftKey),
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
        snapshot.liftDisplayName = LiftTrendTrackingSupport.liftDisplayName(for: liftKey)
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
}
