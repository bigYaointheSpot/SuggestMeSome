import Foundation
import SwiftData

struct TrainingHistoryReadSnapshot {
    let workouts: [Workout]
    let personalRecords: [PersonalRecord]
}

struct WorkoutDateRangeReadSnapshot {
    static let empty = WorkoutDateRangeReadSnapshot(
        workouts: [],
        count: 0,
        earliestDate: nil,
        latestDate: nil
    )

    let workouts: [Workout]
    let count: Int
    let earliestDate: Date?
    let latestDate: Date?
}

struct WorkoutDeleteRangeSummary: Equatable {
    static let empty = WorkoutDeleteRangeSummary(
        count: 0,
        earliestDate: nil,
        latestDate: nil
    )

    let count: Int
    let earliestDate: Date?
    let latestDate: Date?
}

struct ExerciseUsageSummary: Equatable {
    static let empty = ExerciseUsageSummary(exerciseName: "", workoutCount: 0)

    let exerciseName: String
    let workoutCount: Int

    var hasUsage: Bool {
        workoutCount > 0
    }
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

struct AdaptiveProposalPipelineReadSnapshot {
    let finalizedAnalyses: [WeeklyTrainingAnalysis]
    let outcomes: [ExercisePerformanceOutcome]
    let performanceTrends: [LiftPerformanceTrend]
    let proposals: [AdaptationProposal]
    let overlays: [AppliedProgramOverlay]
    let events: [AdaptationEventHistory]
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

    static func workoutDateRangeSnapshot(
        from startDate: Date,
        to endDate: Date,
        context: ModelContext
    ) -> WorkoutDateRangeReadSnapshot {
        let workouts = fetchWorkouts(from: startDate, to: endDate, context: context)
        return WorkoutDateRangeReadSnapshot(
            workouts: workouts,
            count: workouts.count,
            earliestDate: workouts.first?.date,
            latestDate: workouts.last?.date
        )
    }

    static func workoutCount(context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<Workout>())) ?? 0
    }

    static func workoutDeleteRangeSummary(
        from startDate: Date,
        to endDate: Date,
        context: ModelContext
    ) -> WorkoutDeleteRangeSummary {
        let snapshot = workoutDateRangeSnapshot(
            from: startDate,
            to: endDate,
            context: context
        )
        return WorkoutDeleteRangeSummary(
            count: snapshot.count,
            earliestDate: snapshot.earliestDate,
            latestDate: snapshot.latestDate
        )
    }

    static func exerciseUsageSummary(
        for exerciseName: String,
        context: ModelContext
    ) -> ExerciseUsageSummary {
        let normalized = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .empty
        }

        let descriptor = FetchDescriptor<ExerciseEntry>(
            predicate: #Predicate<ExerciseEntry> { $0.exerciseName == normalized }
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        let distinctWorkoutIDs = Set(entries.compactMap { $0.workout?.id })
        let workoutCount = distinctWorkoutIDs.isEmpty ? entries.count : distinctWorkoutIDs.count

        return ExerciseUsageSummary(
            exerciseName: normalized,
            workoutCount: workoutCount
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

    static func adaptiveProposalPipelineSnapshot(
        for run: ProgramRun,
        referenceDate: Date,
        context: ModelContext,
        outcomeLookbackDays: Int? = nil,
        includeStandaloneOutcomes: Bool = false
    ) -> AdaptiveProposalPipelineReadSnapshot {
        let runID = run.id

        let analysesDescriptor = FetchDescriptor<WeeklyTrainingAnalysis>(
            predicate: #Predicate<WeeklyTrainingAnalysis> {
                $0.programRun?.id == runID &&
                $0.isFinalized &&
                $0.weekEndDate <= referenceDate
            },
            sortBy: [
                SortDescriptor(\WeeklyTrainingAnalysis.weekStartDate, order: .forward),
                SortDescriptor(\WeeklyTrainingAnalysis.createdAt, order: .forward),
            ]
        )

        let trendsDescriptor = FetchDescriptor<LiftPerformanceTrend>(
            predicate: #Predicate<LiftPerformanceTrend> { $0.programRun?.id == runID },
            sortBy: [
                SortDescriptor(\LiftPerformanceTrend.updatedAt, order: .reverse),
                SortDescriptor(\LiftPerformanceTrend.canonicalLiftKey, order: .forward),
            ]
        )

        let proposalsDescriptor = FetchDescriptor<AdaptationProposal>(
            predicate: #Predicate<AdaptationProposal> { $0.programRun?.id == runID },
            sortBy: [
                SortDescriptor(\AdaptationProposal.createdAt, order: .reverse),
                SortDescriptor(\AdaptationProposal.priority, order: .reverse),
            ]
        )

        let overlaysDescriptor = FetchDescriptor<AppliedProgramOverlay>(
            predicate: #Predicate<AppliedProgramOverlay> { $0.programRun?.id == runID },
            sortBy: [SortDescriptor(\AppliedProgramOverlay.appliedAt, order: .reverse)]
        )

        let eventsDescriptor = FetchDescriptor<AdaptationEventHistory>(
            predicate: #Predicate<AdaptationEventHistory> { $0.programRun?.id == runID },
            sortBy: [SortDescriptor(\AdaptationEventHistory.timestamp, order: .reverse)]
        )

        return AdaptiveProposalPipelineReadSnapshot(
            finalizedAnalyses: (try? context.fetch(analysesDescriptor)) ?? [],
            outcomes: fetchAdaptiveOutcomes(
                for: run,
                referenceDate: referenceDate,
                context: context,
                lookbackDays: outcomeLookbackDays,
                includeStandaloneOutcomes: includeStandaloneOutcomes
            ),
            performanceTrends: (try? context.fetch(trendsDescriptor)) ?? [],
            proposals: (try? context.fetch(proposalsDescriptor)) ?? [],
            overlays: (try? context.fetch(overlaysDescriptor)) ?? [],
            events: (try? context.fetch(eventsDescriptor)) ?? []
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
        fetchPendingProposals(
            for: run,
            statuses: [.pendingUserConfirmation],
            restrictToStandaloneWhenNoRun: false,
            context: context,
            limit: limit
        )
    }

    static func fetchPendingCoachContextProposals(
        for run: ProgramRun?,
        context: ModelContext,
        limit: Int = 10
    ) -> [AdaptationProposal] {
        fetchPendingProposals(
            for: run,
            statuses: [.pendingUserConfirmation, .pendingAutoApply],
            restrictToStandaloneWhenNoRun: true,
            context: context,
            limit: limit
        )
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

    static func preferredUnit(
        for exerciseName: String,
        context: ModelContext,
        fallback: WeightUnit = AppPreferences.defaultWeightUnit
    ) -> WeightUnit {
        let normalized = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return fallback }

        var descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate<PersonalRecord> { $0.exerciseName == normalized },
            sortBy: [SortDescriptor(\PersonalRecord.dateAchieved, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.unit ?? fallback
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

    static func fetchWorkouts(
        from startDate: Date,
        to endDate: Date,
        context: ModelContext
    ) -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> {
                $0.date >= startDate && $0.date <= endDate
            },
            sortBy: [SortDescriptor(\Workout.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchWorkouts(for run: ProgramRun, context: ModelContext) -> [Workout] {
        let runID = run.id
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.programRun?.id == runID },
            sortBy: [SortDescriptor(\Workout.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func mesocycleReviewSnapshot(
        for run: ProgramRun,
        context: ModelContext
    ) -> MesocycleReviewSnapshot? {
        guard MesocycleReviewService.isEligible(for: run) else {
            return nil
        }

        let programWorkouts = fetchWorkouts(for: run, context: context)
        let reviewEndDate = run.endDate ?? programWorkouts.map(\.date).max() ?? run.startDate
        let standaloneWorkouts = fetchStandaloneWorkouts(
            from: run.startDate,
            to: reviewEndDate,
            context: context
        )

        return MesocycleReviewService.buildReview(
            for: run,
            programWorkouts: programWorkouts,
            standaloneWorkouts: standaloneWorkouts,
            personalRecords: fetchPersonalRecords(context: context)
        )
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

    private static func fetchPendingProposals(
        for run: ProgramRun?,
        statuses: [ProposalStatus],
        restrictToStandaloneWhenNoRun: Bool,
        context: ModelContext,
        limit: Int?
    ) -> [AdaptationProposal] {
        let fetchLimit = limit.map { max(1, $0) }
        let baseProposals = fetchProposals(
            for: run,
            restrictToStandaloneWhenNoRun: restrictToStandaloneWhenNoRun,
            context: context
        )
        let proposals = baseProposals.filter { proposal in
            statuses.contains(proposal.proposalStatus)
        }
        guard let fetchLimit else { return proposals }
        return Array(proposals.prefix(fetchLimit))
    }

    private static func fetchProposals(
        for run: ProgramRun?,
        restrictToStandaloneWhenNoRun: Bool,
        context: ModelContext
    ) -> [AdaptationProposal] {
        let descriptor = proposalDescriptor(
            for: run,
            restrictToStandaloneWhenNoRun: restrictToStandaloneWhenNoRun
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func proposalDescriptor(
        for run: ProgramRun?,
        restrictToStandaloneWhenNoRun: Bool
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

        if restrictToStandaloneWhenNoRun {
            return FetchDescriptor<AdaptationProposal>(
                predicate: #Predicate<AdaptationProposal> { $0.programRun == nil },
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

    private static func fetchAdaptiveOutcomes(
        for run: ProgramRun,
        referenceDate: Date,
        context: ModelContext,
        lookbackDays: Int?,
        includeStandaloneOutcomes: Bool
    ) -> [ExercisePerformanceOutcome] {
        guard let lookbackDays, lookbackDays >= 0 else { return [] }

        let lowerBound = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -lookbackDays,
            to: referenceDate
        ) ?? referenceDate
        let runID = run.id
        let runDescriptor = FetchDescriptor<ExercisePerformanceOutcome>(
            predicate: #Predicate<ExercisePerformanceOutcome> {
                $0.workoutDate >= lowerBound &&
                $0.workoutDate <= referenceDate &&
                $0.programRun?.id == runID
            },
            sortBy: [
                SortDescriptor(\ExercisePerformanceOutcome.workoutDate, order: .forward),
                SortDescriptor(\ExercisePerformanceOutcome.createdAt, order: .forward),
            ]
        )

        var outcomes = (try? context.fetch(runDescriptor)) ?? []
        guard includeStandaloneOutcomes else { return outcomes }

        let standaloneDescriptor = FetchDescriptor<ExercisePerformanceOutcome>(
            predicate: #Predicate<ExercisePerformanceOutcome> {
                $0.workoutDate >= lowerBound &&
                $0.workoutDate <= referenceDate &&
                $0.programRun == nil
            },
            sortBy: [
                SortDescriptor(\ExercisePerformanceOutcome.workoutDate, order: .forward),
                SortDescriptor(\ExercisePerformanceOutcome.createdAt, order: .forward),
            ]
        )

        outcomes.append(contentsOf: (try? context.fetch(standaloneDescriptor)) ?? [])
        return outcomes.sorted {
            if $0.workoutDate != $1.workoutDate {
                return $0.workoutDate < $1.workoutDate
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private static func fetchStandaloneWorkouts(
        from startDate: Date,
        to endDate: Date,
        context: ModelContext
    ) -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> {
                $0.programRun == nil &&
                $0.date >= startDate &&
                $0.date <= endDate
            },
            sortBy: [SortDescriptor(\Workout.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
