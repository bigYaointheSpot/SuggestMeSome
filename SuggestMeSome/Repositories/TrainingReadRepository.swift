import Foundation
import SwiftData

struct TrainingHistoryReadSnapshot {
    let workouts: [Workout]
    let personalRecords: [PersonalRecord]
}

struct ProgramRunIndexReadSnapshot {
    let activeRuns: [ProgramRun]
    let completedRuns: [ProgramRun]
}

struct ProgramRunProgressReadSnapshot {
    let run: ProgramRun
    let workouts: [Workout]
    let completedWorkoutCount: Int
    let completedSessionKeys: Set<ProgramSessionCompletionKey>
}

struct CoachContextReadSnapshot {
    let activeRun: ProgramRun?
    let latestFatigueStatus: FatigueStatus?
    let activeOverlaySummaries: [String]
    let pendingProposals: [AdaptationProposal]
    let recentWorkouts: [Workout]
}

struct RecommendationContextReadSnapshot {
    let activeRun: ProgramRun?
    let recentWorkouts: [Workout]
}

enum TrainingReadRepository {
    static func historySnapshot(
        context: ModelContext,
        workoutLimit: Int? = nil
    ) -> TrainingHistoryReadSnapshot {
        TrainingHistoryReadSnapshot(
            workouts: fetchWorkouts(limit: workoutLimit, context: context),
            personalRecords: fetchPersonalRecords(context: context)
        )
    }

    static func programRunIndexSnapshot(
        context: ModelContext,
        activeLimit: Int? = nil,
        completedLimit: Int? = nil
    ) -> ProgramRunIndexReadSnapshot {
        ProgramRunIndexReadSnapshot(
            activeRuns: fetchProgramRuns(isCompleted: false, limit: activeLimit, context: context),
            completedRuns: fetchProgramRuns(isCompleted: true, limit: completedLimit, context: context)
        )
    }

    static func programRunProgressSnapshot(
        for run: ProgramRun,
        context: ModelContext
    ) -> ProgramRunProgressReadSnapshot {
        let workouts = fetchWorkouts(for: run, context: context)
        let completedSessionKeys: Set<ProgramSessionCompletionKey> = Set(workouts.compactMap { workout in
            guard let weekNumber = workout.programWeekNumber,
                  let sessionNumber = workout.programSessionNumber else {
                return nil
            }
            return ProgramSessionCompletionKey(
                weekNumber: weekNumber,
                sessionNumber: sessionNumber
            )
        })

        return ProgramRunProgressReadSnapshot(
            run: run,
            workouts: workouts,
            completedWorkoutCount: workouts.count,
            completedSessionKeys: completedSessionKeys
        )
    }

    static func coachContextSnapshot(
        focusRun: ProgramRun? = nil,
        context: ModelContext,
        recentWorkoutLimit: Int = 30,
        proposalLimit: Int = 10
    ) -> CoachContextReadSnapshot {
        let activeRun = focusRun ?? programRunIndexSnapshot(
            context: context,
            activeLimit: 1,
            completedLimit: 0
        ).activeRuns.first
        let activeOverlaySummaries = activeRun.map { run in
            fetchActiveOverlays(for: run, context: context)
                .compactMap(\.summaryText)
                .filter { !$0.isEmpty }
        } ?? []
        let pendingProposals = fetchPendingCoachContextProposals(
            for: activeRun,
            context: context,
            limit: proposalLimit
        )

        return CoachContextReadSnapshot(
            activeRun: activeRun,
            latestFatigueStatus: fetchLatestFatigueStatus(for: activeRun, context: context),
            activeOverlaySummaries: activeOverlaySummaries,
            pendingProposals: pendingProposals,
            recentWorkouts: fetchWorkouts(limit: recentWorkoutLimit, context: context)
        )
    }

    static func recommendationContextSnapshot(
        context: ModelContext,
        recentWorkoutLimit: Int
    ) -> RecommendationContextReadSnapshot {
        let runIndex = programRunIndexSnapshot(
            context: context,
            activeLimit: 1,
            completedLimit: 0
        )
        return RecommendationContextReadSnapshot(
            activeRun: runIndex.activeRuns.first,
            recentWorkouts: fetchWorkouts(limit: recentWorkoutLimit, context: context)
        )
    }

    static func programRun(matchingStableID stableID: String, context: ModelContext) -> ProgramRun? {
        let normalized = stableID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let stableIDDescriptor = FetchDescriptor<ProgramRun>(
            predicate: #Predicate<ProgramRun> { ($0.syncStableID ?? "") == normalized }
        )
        if let directMatch = (try? context.fetch(stableIDDescriptor))?.first {
            return directMatch
        }

        guard let identifier = UUID(uuidString: normalized) else { return nil }
        let idDescriptor = FetchDescriptor<ProgramRun>(
            predicate: #Predicate<ProgramRun> { $0.id == identifier }
        )
        return (try? context.fetch(idDescriptor))?.first
    }

    static func fetchPendingUserProposals(
        for run: ProgramRun? = nil,
        context: ModelContext,
        limit: Int? = nil
    ) -> [AdaptationProposal] {
        let descriptor = proposalDescriptor(for: run)
        var mutableDescriptor = descriptor
        if let limit {
            mutableDescriptor.fetchLimit = max(1, limit)
        }

        return ((try? context.fetch(mutableDescriptor)) ?? []).filter {
            $0.proposalStatus == .pendingUserConfirmation
        }
    }

    static func fetchPendingCoachContextProposals(
        for run: ProgramRun?,
        context: ModelContext,
        limit: Int = 10
    ) -> [AdaptationProposal] {
        var descriptor = proposalDescriptor(for: run)
        descriptor.fetchLimit = max(limit, 50)

        let rows = (try? context.fetch(descriptor)) ?? []
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

    static func fetchActiveOverlays(for run: ProgramRun, context: ModelContext) -> [AppliedProgramOverlay] {
        let runID = run.id
        let descriptor = FetchDescriptor<AppliedProgramOverlay>(
            predicate: #Predicate<AppliedProgramOverlay> { $0.programRun?.id == runID },
            sortBy: [SortDescriptor(\AppliedProgramOverlay.appliedAt, order: .forward)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.overlayStatus == .active }
    }

    static func fetchPersonalRecords(context: ModelContext) -> [PersonalRecord] {
        (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? []
    }

    static func fetchWorkouts(limit: Int? = nil, context: ModelContext) -> [Workout] {
        var descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\Workout.date, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = max(1, limit)
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchWorkouts(for run: ProgramRun, context: ModelContext) -> [Workout] {
        let runID = run.id
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.programRun?.id == runID }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchProgramRuns(
        isCompleted: Bool,
        limit: Int?,
        context: ModelContext
    ) -> [ProgramRun] {
        if let limit, limit <= 0 {
            return []
        }

        let descriptor: FetchDescriptor<ProgramRun>
        if isCompleted {
            descriptor = FetchDescriptor<ProgramRun>(
                predicate: #Predicate<ProgramRun> { $0.isCompleted },
                sortBy: [
                    SortDescriptor(\ProgramRun.endDate, order: .reverse),
                    SortDescriptor(\ProgramRun.startDate, order: .reverse),
                ]
            )
        } else {
            descriptor = FetchDescriptor<ProgramRun>(
                predicate: #Predicate<ProgramRun> { !$0.isCompleted },
                sortBy: [SortDescriptor(\ProgramRun.startDate, order: .reverse)]
            )
        }

        var mutableDescriptor = descriptor
        if let limit {
            mutableDescriptor.fetchLimit = limit
        }

        return (try? context.fetch(mutableDescriptor)) ?? []
    }

    private static func fetchLatestFatigueStatus(
        for run: ProgramRun?,
        context: ModelContext
    ) -> FatigueStatus? {
        if let run {
            let runID = run.id
            var descriptor = FetchDescriptor<WeeklyTrainingAnalysis>(
                predicate: #Predicate<WeeklyTrainingAnalysis> {
                    $0.programRun?.id == runID && $0.isFinalized
                },
                sortBy: [
                    SortDescriptor(\WeeklyTrainingAnalysis.weekStartDate, order: .reverse),
                    SortDescriptor(\WeeklyTrainingAnalysis.createdAt, order: .reverse),
                ]
            )
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first?.fatigueStatus
        }

        var descriptor = FetchDescriptor<WeeklyTrainingAnalysis>(
            predicate: #Predicate<WeeklyTrainingAnalysis> {
                $0.programRun == nil && $0.isFinalized
            },
            sortBy: [
                SortDescriptor(\WeeklyTrainingAnalysis.weekStartDate, order: .reverse),
                SortDescriptor(\WeeklyTrainingAnalysis.createdAt, order: .reverse),
            ]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.fatigueStatus
    }

    private static func proposalDescriptor(
        for run: ProgramRun?
    ) -> FetchDescriptor<AdaptationProposal> {
        if let run {
            let runID = run.id
            return FetchDescriptor<AdaptationProposal>(
                predicate: #Predicate<AdaptationProposal> { $0.programRun?.id == runID },
                sortBy: [
                    SortDescriptor(\AdaptationProposal.priority, order: .reverse),
                    SortDescriptor(\AdaptationProposal.createdAt, order: .reverse),
                ]
            )
        }

        return FetchDescriptor<AdaptationProposal>(
            sortBy: [
                SortDescriptor(\AdaptationProposal.priority, order: .reverse),
                SortDescriptor(\AdaptationProposal.createdAt, order: .reverse),
            ]
        )
    }
}
