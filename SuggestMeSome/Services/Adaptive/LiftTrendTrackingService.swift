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
    static func updateTrends(
        for analysis: WeeklyTrainingAnalysis,
        context: ModelContext
    ) -> [String: LiftTrendStatus] {
        guard analysis.isFinalized else { return [:] }

        var snapshot = LiftTrendTrackingScopeLoader.loadSnapshot(
            for: analysis,
            context: context
        )
        guard !snapshot.scopedOutcomes.isEmpty else { return [:] }

        var summary: [String: LiftTrendStatus] = [:]

        for liftKey in snapshot.candidateLiftKeys.sorted() {
            let points = LiftTrendPointBuilder.buildPoints(
                for: liftKey,
                outcomes: snapshot.scopedOutcomes
            )
            guard !points.isEmpty else { continue }

            let metrics = LiftTrendMetricsEngine.buildMetrics(
                points: points,
                liftKey: liftKey,
                weekEndDate: analysis.weekEndDate
            )
            let trend = LiftTrendPersistenceStore.upsertTrend(
                for: liftKey,
                analysis: analysis,
                existing: &snapshot.existingTrends,
                context: context
            )
            LiftTrendPersistenceStore.applyMetrics(
                metrics,
                to: trend,
                analysis: analysis
            )
            LiftTrendPersistenceStore.upsertSnapshot(
                liftKey: liftKey,
                metrics: metrics,
                trend: trend,
                analysis: analysis,
                snapshots: &snapshot.existingSnapshots,
                context: context
            )

            summary[liftKey] = metrics.trendStatus
        }

        return summary
    }
}
