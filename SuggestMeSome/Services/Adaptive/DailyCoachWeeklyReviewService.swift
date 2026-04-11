//
//  DailyCoachWeeklyReviewService.swift
//  SuggestMeSome
//
//  Feature 7 — Generates or upserts a DailyCoachWeeklyReview from a finalized
//  WeeklyTrainingAnalysis. Called at the end of both program-week and
//  standalone-week analysis paths.
//
//  Rules:
//  - One review per analysis (keyed by sourceWeeklyAnalysisIDText).
//  - Upserts in place when analysis is re-run (re-finalized).
//  - Does not touch hasBeenSeen if review already exists (preserves user read state).
//  - Produces deterministic, human-readable text — no probabilistic generation.
//

import Foundation
import SwiftData

// MARK: - DailyCoachWeeklyReviewService

enum DailyCoachWeeklyReviewService {

    // MARK: - Public Entry Point

    /// Generates or updates a `DailyCoachWeeklyReview` for the given finalized analysis.
    @discardableResult
    static func generateOrUpdate(
        from analysis: WeeklyTrainingAnalysis,
        context: ModelContext
    ) -> DailyCoachWeeklyReview {
        let analysisKey = analysis.id.uuidString
        let isProgramWeek = analysis.programRun != nil

        // Upsert: find existing review or create a new one.
        let existing = (try? context.fetch(FetchDescriptor<DailyCoachWeeklyReview>()))?.first {
            $0.sourceWeeklyAnalysisIDText == analysisKey
        }
        let review: DailyCoachWeeklyReview
        if let existing {
            review = existing
        } else {
            let r = DailyCoachWeeklyReview(
                weekStart: analysis.weekStartDate,
                weekEnd: analysis.weekEndDate
            )
            context.insert(r)
            review = r
        }

        // Always refresh text fields; preserve hasBeenSeen on updates.
        review.weekStart = analysis.weekStartDate
        review.weekEnd = analysis.weekEndDate
        review.isProgramWeek = isProgramWeek
        review.programRun = analysis.programRun
        review.sourceWeeklyAnalysisIDText = analysisKey

        let text = isProgramWeek
            ? buildProgramWeekText(analysis: analysis)
            : buildStandaloneWeekText(analysis: analysis)

        review.headline       = text.headline
        review.winText        = text.winText
        review.watchoutText   = text.watchoutText
        review.nextActionText = text.nextActionText

        return review
    }

    // MARK: - Program-Week Text

    private static func buildProgramWeekText(
        analysis: WeeklyTrainingAnalysis
    ) -> ReviewText {
        let weekLabel = analysis.programWeekNumber.map { "Week \($0)" } ?? "Week"
        let fatigue   = analysis.fatigueStatus
        let adherence = analysis.adherenceScore
        let topSetOutcomes = analysis.outcomes.filter { $0.isTopSetSignal }
        let pendingProposals = analysis.proposals.filter { $0.proposalStatus == .pendingUserConfirmation }

        // ── Headline ──────────────────────────────────────────────────────────
        let headline: String
        if fatigue == .critical {
            headline = "\(weekLabel) — Critical fatigue. Deload strongly recommended."
        } else if fatigue == .high {
            headline = "\(weekLabel) — High fatigue. Keep next week conservative."
        } else if adherence < 0.5 {
            headline = "\(weekLabel) — Low adherence. Rebuild consistency next week."
        } else if adherence >= 0.85 && analysis.weightedPerformanceScore >= 2.0 {
            headline = "\(weekLabel) — Strong execution and solid adherence."
        } else {
            headline = "\(weekLabel) — Week complete."
        }

        // ── Win ───────────────────────────────────────────────────────────────
        let winText: String
        if let improvingTrend = analysis.trendSnapshots.first(where: { $0.trendStatus == .improving }) {
            winText = "\(improvingTrend.liftDisplayName) is trending up — keep it going."
        } else if let topOutcome = bestPerformingOutcome(from: topSetOutcomes) {
            let score = topOutcome.performanceScore
            if score == .exceptionalPerformance || score == .overperformance {
                winText = "Strong top set on \(topOutcome.exerciseName) — clear performance signal."
            } else {
                winText = "Consistent execution on \(topOutcome.exerciseName) — staying on target."
            }
        } else if adherence >= 0.85 {
            winText = "All planned sessions completed — consistency is your biggest asset."
        } else {
            winText = "Week logged — data is building. Keep showing up."
        }

        // ── Watchout ──────────────────────────────────────────────────────────
        let watchoutText: String
        if fatigue == .critical {
            watchoutText = "Critical fatigue — continuing at this load risks injury and stalls progress."
        } else if fatigue == .high {
            watchoutText = "Fatigue is high. Reduce next week's volume or loads to prevent a plateau."
        } else if let decliningTrend = analysis.trendSnapshots.first(where: { $0.trendStatus == .declining }) {
            watchoutText = "\(decliningTrend.liftDisplayName) is declining — review load, sleep, and recovery quality."
        } else if adherence < 0.5 {
            watchoutText = "Missed sessions accumulate quickly. Missing two or more weeks compounds the cost."
        } else if fatigue == .elevated {
            watchoutText = "Fatigue is elevated. One lighter session next week may prevent a bigger drop."
        } else {
            watchoutText = "Fatigue is manageable — stay on schedule and prioritise sleep."
        }

        // ── Next Action ───────────────────────────────────────────────────────
        let nextActionText: String
        if !pendingProposals.isEmpty {
            let count = pendingProposals.count
            let plural = count == 1 ? "" : "s"
            nextActionText = "Review \(count) pending proposal\(plural) before your next session."
        } else if fatigue == .critical || fatigue == .high {
            nextActionText = "Run next week at reduced volume and load — recovery takes priority."
        } else if let improving = analysis.trendSnapshots.first(where: { $0.trendStatus == .improving }) {
            nextActionText = "Maintain current plan for \(improving.liftDisplayName) — the trend is working."
        } else {
            nextActionText = "Execute next session as planned. Small, consistent steps compound over time."
        }

        return ReviewText(
            headline: headline,
            winText: winText,
            watchoutText: watchoutText,
            nextActionText: nextActionText
        )
    }

    // MARK: - Standalone-Week Text

    private static func buildStandaloneWeekText(
        analysis: WeeklyTrainingAnalysis
    ) -> ReviewText {
        let sessionCount = analysis.standaloneWorkoutCount
        let fatigue      = analysis.fatigueStatus
        let plural       = sessionCount == 1 ? "" : "s"

        // ── Headline ──────────────────────────────────────────────────────────
        let headline: String
        if sessionCount == 0 {
            headline = "No sessions logged this week."
        } else if sessionCount >= 4 {
            headline = "\(sessionCount) sessions this week — high frequency."
        } else {
            headline = "\(sessionCount) session\(plural) logged this week."
        }

        // ── Win ───────────────────────────────────────────────────────────────
        let winText: String
        if sessionCount == 0 {
            winText = "Rest weeks have value — come back strong next week."
        } else if sessionCount >= 3 {
            winText = "Training \(sessionCount) times without a program shows strong self-direction."
        } else {
            winText = "Showing up consistently without a structured plan is harder than it looks."
        }

        // ── Watchout ──────────────────────────────────────────────────────────
        let watchoutText: String
        if fatigue == .critical || fatigue == .high {
            watchoutText = "Fatigue signals are high. Consider a lighter session or full rest day before pushing hard again."
        } else if fatigue == .elevated {
            watchoutText = "Fatigue is slightly elevated — one easier session this week would help recovery."
        } else if sessionCount >= 5 {
            watchoutText = "High session frequency without a structured program can accumulate fatigue quickly. Monitor recovery."
        } else {
            watchoutText = "No major flags. Keep monitoring how you recover between sessions."
        }

        // ── Next Action ───────────────────────────────────────────────────────
        let nextActionText: String
        if sessionCount == 0 {
            nextActionText = "Aim to log at least one session next week to keep momentum."
        } else if fatigue == .high || fatigue == .critical {
            nextActionText = "Prioritise recovery this week — reduce intensity or take a rest day before resuming full training."
        } else {
            let targetSessions = min(sessionCount + 1, 4)
            nextActionText = "Aim for \(targetSessions) sessions next week to build consistent frequency."
        }

        return ReviewText(
            headline: headline,
            winText: winText,
            watchoutText: watchoutText,
            nextActionText: nextActionText
        )
    }

    // MARK: - Private Helpers

    private static func bestPerformingOutcome(
        from outcomes: [ExercisePerformanceOutcome]
    ) -> ExercisePerformanceOutcome? {
        let scoreOrder: [PerformanceScore] = [
            .exceptionalPerformance,
            .overperformance,
            .onTarget,
            .underperformance,
            .severeUnderperformance,
            .insufficientData
        ]
        return outcomes.min { lhs, rhs in
            let li = scoreOrder.firstIndex(of: lhs.performanceScore) ?? scoreOrder.count
            let ri = scoreOrder.firstIndex(of: rhs.performanceScore) ?? scoreOrder.count
            return li < ri
        }
    }
}

// MARK: - ReviewText (private value type)

private struct ReviewText {
    let headline: String
    let winText: String
    let watchoutText: String
    let nextActionText: String
}
