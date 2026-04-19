import Foundation
import SwiftData

struct ProgramSessionCompletionKey: Hashable {
    let weekNumber: Int
    let sessionNumber: Int
}

struct AdaptationHistoryReadSnapshot {
    let analyses: [WeeklyTrainingAnalysis]
    let trendSnapshots: [LiftTrendSnapshot]
    let proposals: [AdaptationProposal]
    let overlays: [AppliedProgramOverlay]
    let events: [AdaptationEventHistory]
}

enum ReadQueryRepository {
    static func recentWorkouts(limit: Int, context: ModelContext) -> [Workout] {
        TrainingReadRepository.fetchWorkouts(limit: limit, context: context)
    }

    static func activeProgramRuns(limit: Int = 5, context: ModelContext) -> [ProgramRun] {
        TrainingReadRepository.programRunIndexSnapshot(
            context: context,
            activeLimit: limit,
            completedLimit: 0
        ).activeRuns
    }

    static func pendingUserProposals(
        for run: ProgramRun? = nil,
        context: ModelContext,
        limit: Int? = nil
    ) -> [AdaptationProposal] {
        TrainingReadRepository.fetchPendingUserProposals(
            for: run,
            context: context,
            limit: limit
        )
    }

    static func pendingCoachContextProposals(
        for run: ProgramRun?,
        context: ModelContext,
        limit: Int = 10
    ) -> [AdaptationProposal] {
        TrainingReadRepository.fetchPendingCoachContextProposals(
            for: run,
            context: context,
            limit: limit
        )
    }

    static func activeOverlays(for run: ProgramRun, context: ModelContext) -> [AppliedProgramOverlay] {
        TrainingReadRepository.fetchActiveOverlays(for: run, context: context)
    }

    static func adaptationHistorySnapshot(
        for run: ProgramRun,
        context: ModelContext,
        analysisLimit: Int = 8,
        trendLimit: Int = 80,
        proposalLimit: Int = 16,
        overlayLimit: Int = 16,
        eventLimit: Int = 24
    ) -> AdaptationHistoryReadSnapshot {
        let runID = run.id
        var analysesDescriptor = FetchDescriptor<WeeklyTrainingAnalysis>(
            predicate: #Predicate<WeeklyTrainingAnalysis> { $0.programRun?.id == runID },
            sortBy: [
                SortDescriptor(\WeeklyTrainingAnalysis.weekStartDate, order: .reverse),
                SortDescriptor(\WeeklyTrainingAnalysis.createdAt, order: .reverse),
            ]
        )
        analysesDescriptor.fetchLimit = max(1, analysisLimit)

        var trendsDescriptor = FetchDescriptor<LiftTrendSnapshot>(
            predicate: #Predicate<LiftTrendSnapshot> { $0.programRun?.id == runID },
            sortBy: [
                SortDescriptor(\LiftTrendSnapshot.weekEndDate, order: .reverse),
                SortDescriptor(\LiftTrendSnapshot.createdAt, order: .reverse),
            ]
        )
        trendsDescriptor.fetchLimit = max(1, trendLimit)

        var proposalsDescriptor = FetchDescriptor<AdaptationProposal>(
            predicate: #Predicate<AdaptationProposal> { $0.programRun?.id == runID },
            sortBy: [
                SortDescriptor(\AdaptationProposal.createdAt, order: .reverse),
                SortDescriptor(\AdaptationProposal.priority, order: .reverse),
            ]
        )
        proposalsDescriptor.fetchLimit = max(1, proposalLimit)

        var overlaysDescriptor = FetchDescriptor<AppliedProgramOverlay>(
            predicate: #Predicate<AppliedProgramOverlay> { $0.programRun?.id == runID },
            sortBy: [SortDescriptor(\AppliedProgramOverlay.appliedAt, order: .reverse)]
        )
        overlaysDescriptor.fetchLimit = max(1, overlayLimit)

        var eventsDescriptor = FetchDescriptor<AdaptationEventHistory>(
            predicate: #Predicate<AdaptationEventHistory> { $0.programRun?.id == runID },
            sortBy: [SortDescriptor(\AdaptationEventHistory.timestamp, order: .reverse)]
        )
        eventsDescriptor.fetchLimit = max(1, eventLimit)

        return AdaptationHistoryReadSnapshot(
            analyses: (try? context.fetch(analysesDescriptor)) ?? [],
            trendSnapshots: (try? context.fetch(trendsDescriptor)) ?? [],
            proposals: (try? context.fetch(proposalsDescriptor)) ?? [],
            overlays: (try? context.fetch(overlaysDescriptor)) ?? [],
            events: (try? context.fetch(eventsDescriptor)) ?? []
        )
    }
}
