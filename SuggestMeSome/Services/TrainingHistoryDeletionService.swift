import Foundation
import SwiftData

@MainActor
enum TrainingHistoryDeletionService {
    static func deleteProgramRunHistory(
        _ run: ProgramRun,
        context: ModelContext
    ) throws {
        let runID = run.id
        let workouts = runWorkouts(runID: runID, context: context)
        let analyses = runAnalyses(runID: runID, context: context)
        let trends = runTrends(runID: runID, context: context)
        let proposals = runProposals(runID: runID, context: context)
        let overlays = runOverlays(runID: runID, context: context)
        let events = runEvents(runID: runID, context: context)
        let checkIns = runCheckIns(runID: runID, context: context)
        let weeklyReviews = runWeeklyReviews(runID: runID, context: context)
        let affectedExerciseNames = PersonalRecordMaintenanceService.exerciseNames(in: workouts)

        CloudSyncManager.shared.captureDeletedProgramGraph(
            programRuns: [run],
            checkIns: checkIns,
            weeklyReviews: weeklyReviews,
            analyses: analyses,
            trends: trends,
            proposals: proposals,
            overlays: overlays,
            events: events
        )

        delete(runOrphanOutcomes(runID: runID, context: context), context: context)
        delete(events, context: context)
        delete(overlays, context: context)
        delete(proposals, context: context)
        delete(weeklyReviews, context: context)
        delete(checkIns, context: context)
        delete(analyses, context: context)
        delete(trends, context: context)
        delete(workouts, context: context)
        context.delete(run)

        try context.save()

        try PersonalRecordMaintenanceService.recomputePRs(
            for: affectedExerciseNames,
            context: context
        )
        try context.save()
    }

    private static func delete<T: PersistentModel>(_ rows: [T], context: ModelContext) {
        for row in rows {
            context.delete(row)
        }
    }

    private static func fetch<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        context: ModelContext
    ) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    private static func runWorkouts(
        runID: UUID,
        context: ModelContext
    ) -> [Workout] {
        fetch(
            FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { $0.programRun?.id == runID }
            ),
            context: context
        )
    }

    private static func runOrphanOutcomes(
        runID: UUID,
        context: ModelContext
    ) -> [ExercisePerformanceOutcome] {
        fetch(
            FetchDescriptor<ExercisePerformanceOutcome>(
                predicate: #Predicate<ExercisePerformanceOutcome> {
                    $0.programRun?.id == runID && $0.analysis == nil
                }
            ),
            context: context
        )
    }

    private static func runAnalyses(
        runID: UUID,
        context: ModelContext
    ) -> [WeeklyTrainingAnalysis] {
        fetch(
            FetchDescriptor<WeeklyTrainingAnalysis>(
                predicate: #Predicate<WeeklyTrainingAnalysis> { $0.programRun?.id == runID }
            ),
            context: context
        )
    }

    private static func runTrends(
        runID: UUID,
        context: ModelContext
    ) -> [LiftPerformanceTrend] {
        fetch(
            FetchDescriptor<LiftPerformanceTrend>(
                predicate: #Predicate<LiftPerformanceTrend> { $0.programRun?.id == runID }
            ),
            context: context
        )
    }

    private static func runProposals(
        runID: UUID,
        context: ModelContext
    ) -> [AdaptationProposal] {
        fetch(
            FetchDescriptor<AdaptationProposal>(
                predicate: #Predicate<AdaptationProposal> { $0.programRun?.id == runID }
            ),
            context: context
        )
    }

    private static func runOverlays(
        runID: UUID,
        context: ModelContext
    ) -> [AppliedProgramOverlay] {
        fetch(
            FetchDescriptor<AppliedProgramOverlay>(
                predicate: #Predicate<AppliedProgramOverlay> { $0.programRun?.id == runID }
            ),
            context: context
        )
    }

    private static func runEvents(
        runID: UUID,
        context: ModelContext
    ) -> [AdaptationEventHistory] {
        fetch(
            FetchDescriptor<AdaptationEventHistory>(
                predicate: #Predicate<AdaptationEventHistory> { $0.programRun?.id == runID }
            ),
            context: context
        )
    }

    private static func runCheckIns(
        runID: UUID,
        context: ModelContext
    ) -> [DailyCoachCheckIn] {
        fetch(
            FetchDescriptor<DailyCoachCheckIn>(
                predicate: #Predicate<DailyCoachCheckIn> { $0.programRun?.id == runID }
            ),
            context: context
        )
    }

    private static func runWeeklyReviews(
        runID: UUID,
        context: ModelContext
    ) -> [DailyCoachWeeklyReview] {
        fetch(
            FetchDescriptor<DailyCoachWeeklyReview>(
                predicate: #Predicate<DailyCoachWeeklyReview> { $0.programRun?.id == runID }
            ),
            context: context
        )
    }
}
