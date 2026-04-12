import Foundation
import SwiftData

enum WeeklyAnalysisEventHistoryWriter {
    static func upsertWeeklyFinalizedEvent(
        analysis: WeeklyTrainingAnalysis,
        programRun: ProgramRun?,
        programWeekNumber: Int?,
        topSetSummary: [String: Double],
        trendSummary: [String: LiftTrendStatus],
        skippedProgramDuplicateWorkouts: Int,
        context: ModelContext
    ) {
        let analysisID = analysis.id
        let descriptor = FetchDescriptor<AdaptationEventHistory>(
            predicate: #Predicate<AdaptationEventHistory> {
                $0.analysis?.id == analysisID
            },
            sortBy: [SortDescriptor(\AdaptationEventHistory.timestamp, order: .reverse)]
        )
        let existing = (try? context.fetch(descriptor))?.first(where: { $0.eventType == .weeklyAnalysisFinalized })

        let event = existing ?? {
            let newEvent = AdaptationEventHistory(
                programRun: programRun,
                trainingProgram: programRun?.program,
                analysis: analysis,
                eventType: .weeklyAnalysisFinalized,
                analysisWeekNumber: programWeekNumber,
                message: ""
            )
            context.insert(newEvent)
            return newEvent
        }()

        let title = {
            if let programWeekNumber {
                return "Week \(programWeekNumber) analysis finalized"
            }
            return "Standalone week analysis finalized"
        }()

        var explanationParts: [String] = []
        explanationParts.append("weighted_performance=\(fmt1(analysis.weightedPerformanceScore))")
        explanationParts.append("fatigue=\(analysis.fatigueStatus.rawValue)")
        explanationParts.append("adherence=\(fmt2(analysis.adherenceScore))")
        explanationParts.append("signals=program:\(fmt1(analysis.programSignalWeight)),standalone:\(fmt1(analysis.standaloneSignalWeight))")
        if skippedProgramDuplicateWorkouts > 0 {
            explanationParts.append("dedupe_skipped_program_workouts=\(skippedProgramDuplicateWorkouts)")
        }
        if !topSetSummary.isEmpty {
            let text = topSetSummary
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(fmt1($0.value))lbs_e1rm" }
                .joined(separator: ", ")
            explanationParts.append("main_lift_top_sets=[\(text)]")
        }
        if !trendSummary.isEmpty {
            let text = trendSummary
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.rawValue)" }
                .joined(separator: ", ")
            explanationParts.append("lift_trends=[\(text)]")
        }

        event.timestamp = Date.now
        event.programRun = programRun
        event.trainingProgram = programRun?.program
        event.analysis = analysis
        event.eventType = .weeklyAnalysisFinalized
        event.analysisWeekNumber = programWeekNumber
        event.message = title
        event.explanation = explanationParts.joined(separator: "; ")
        event.adjustmentReason = nil
        event.performanceScoreSnapshot = classifyAggregatePerformance(analysis.weightedPerformanceScore)
        event.fatigueStatusSnapshot = analysis.fatigueStatus
        event.liftTrendStatusSnapshot = dominantTrendStatus(from: trendSummary)
        event.confidenceSnapshot = min(1.0, analysis.totalSignalWeight / 8.0)
        event.requiresUserAction = false
        event.userActionTaken = false
    }

    private static func dominantTrendStatus(from summary: [String: LiftTrendStatus]) -> LiftTrendStatus? {
        guard !summary.isEmpty else { return nil }
        let counts = Dictionary(grouping: summary.values, by: { $0 }).mapValues(\.count)
        return counts.max(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key.rawValue > rhs.key.rawValue }
            return lhs.value < rhs.value
        })?.key
    }

    private static func classifyAggregatePerformance(_ score: Double) -> PerformanceScore {
        if score <= -12 { return .severeUnderperformance }
        if score <= -4 { return .underperformance }
        if score < 4 { return .onTarget }
        if score < 12 { return .overperformance }
        return .exceptionalPerformance
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
