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
        var descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\Workout.date, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, limit)
        return (try? context.fetch(descriptor)) ?? []
    }

    static func activeProgramRuns(limit: Int = 5, context: ModelContext) -> [ProgramRun] {
        var descriptor = FetchDescriptor<ProgramRun>(
            predicate: #Predicate<ProgramRun> { !$0.isCompleted },
            sortBy: [SortDescriptor(\ProgramRun.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, limit)
        return (try? context.fetch(descriptor)) ?? []
    }

    static func pendingUserProposals(
        for run: ProgramRun? = nil,
        context: ModelContext,
        limit: Int? = nil
    ) -> [AdaptationProposal] {
        let descriptor: FetchDescriptor<AdaptationProposal>
        if let run {
            let runID = run.id
            descriptor = FetchDescriptor<AdaptationProposal>(
                predicate: #Predicate<AdaptationProposal> {
                    $0.programRun?.id == runID
                },
                sortBy: [
                    SortDescriptor(\AdaptationProposal.priority, order: .reverse),
                    SortDescriptor(\AdaptationProposal.createdAt, order: .reverse),
                ]
            )
        } else {
            descriptor = FetchDescriptor<AdaptationProposal>(
                sortBy: [
                    SortDescriptor(\AdaptationProposal.priority, order: .reverse),
                    SortDescriptor(\AdaptationProposal.createdAt, order: .reverse),
                ]
            )
        }

        var mutable = descriptor
        if let limit {
            mutable.fetchLimit = max(1, limit)
        }

        return ((try? context.fetch(mutable)) ?? []).filter {
            $0.proposalStatus == .pendingUserConfirmation
        }
    }

    static func pendingCoachContextProposals(
        for run: ProgramRun?,
        context: ModelContext,
        limit: Int = 10
    ) -> [AdaptationProposal] {
        let descriptor: FetchDescriptor<AdaptationProposal>
        if let run {
            let runID = run.id
            descriptor = FetchDescriptor<AdaptationProposal>(
                predicate: #Predicate<AdaptationProposal> { $0.programRun?.id == runID },
                sortBy: [
                    SortDescriptor(\AdaptationProposal.priority, order: .reverse),
                    SortDescriptor(\AdaptationProposal.createdAt, order: .reverse),
                ]
            )
        } else {
            descriptor = FetchDescriptor<AdaptationProposal>(
                sortBy: [
                    SortDescriptor(\AdaptationProposal.priority, order: .reverse),
                    SortDescriptor(\AdaptationProposal.createdAt, order: .reverse),
                ]
            )
        }

        var mutable = descriptor
        mutable.fetchLimit = max(limit, 50)

        let rows = (try? context.fetch(mutable)) ?? []
        let filtered = rows.filter { proposal in
            let isPending = proposal.proposalStatus == .pendingUserConfirmation ||
                proposal.proposalStatus == .pendingAutoApply
            guard isPending else { return false }

            if let run {
                return proposal.programRun?.id == run.id
            }
            return proposal.programRun == nil
        }

        return Array(filtered.prefix(max(1, limit)))
    }

    static func activeOverlays(for run: ProgramRun, context: ModelContext) -> [AppliedProgramOverlay] {
        let runID = run.id
        let descriptor = FetchDescriptor<AppliedProgramOverlay>(
            predicate: #Predicate<AppliedProgramOverlay> { $0.programRun?.id == runID },
            sortBy: [SortDescriptor(\AppliedProgramOverlay.appliedAt, order: .forward)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.overlayStatus == .active }
    }

    static func completedProgramSessionKeys(for run: ProgramRun, context: ModelContext) -> Set<ProgramSessionCompletionKey> {
        let runID = run.id
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> {
                $0.programRun?.id == runID &&
                $0.programWeekNumber != nil &&
                $0.programSessionNumber != nil
            }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return Set(rows.compactMap { workout in
            guard let week = workout.programWeekNumber, let session = workout.programSessionNumber else {
                return nil
            }
            return ProgramSessionCompletionKey(weekNumber: week, sessionNumber: session)
        })
    }

    static func programWorkoutCount(for run: ProgramRun, context: ModelContext) -> Int {
        let runID = run.id
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.programRun?.id == runID }
        )
        return ((try? context.fetch(descriptor)) ?? []).count
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
