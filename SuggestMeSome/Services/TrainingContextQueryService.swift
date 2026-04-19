//
//  TrainingContextQueryService.swift
//  SuggestMeSome
//
//  Shared query helpers for commonly reused training-context reads.
//

import Foundation

enum TrainingContextQueryService {
    static func recentWorkouts(from workouts: [Workout], limit: Int) -> [Workout] {
        let sorted = workouts.sorted { $0.date > $1.date }
        return Array(sorted.prefix(max(0, limit)))
    }

    static func activeProgramRuns(from runs: [ProgramRun]) -> [ProgramRun] {
        runs
            .filter { !$0.isCompleted }
            .sorted { $0.startDate > $1.startDate }
    }

    static func completedProgramRuns(from runs: [ProgramRun]) -> [ProgramRun] {
        runs
            .filter(\.isCompleted)
            .sorted { ($0.endDate ?? $0.startDate) > ($1.endDate ?? $1.startDate) }
    }

    static func latestCompletedRun(from runs: [ProgramRun]) -> ProgramRun? {
        completedProgramRuns(from: runs).first
    }

    static func runScopedWorkouts(for run: ProgramRun, in workouts: [Workout]) -> [Workout] {
        workouts.filter { $0.programRun?.id == run.id }
    }

    static func completedWorkoutCount(for run: ProgramRun, in workouts: [Workout]) -> Int {
        runScopedWorkouts(for: run, in: workouts).count
    }

    static func relevantStandaloneWorkouts(
        for run: ProgramRun,
        in workouts: [Workout]
    ) -> [Workout] {
        MesocycleReviewService.relevantStandaloneWorkouts(for: run, in: workouts)
    }

    static func isMesocycleReviewEligible(for run: ProgramRun) -> Bool {
        MesocycleReviewService.isEligible(for: run)
    }

    static func mesocycleReview(
        for run: ProgramRun,
        workouts: [Workout],
        personalRecords: [PersonalRecord]
    ) -> MesocycleReviewSnapshot? {
        guard isMesocycleReviewEligible(for: run) else { return nil }
        return MesocycleReviewService.buildReview(
            for: run,
            allWorkouts: workouts,
            personalRecords: personalRecords
        )
    }

    static func latestCompletedMesocycleReview(
        from runs: [ProgramRun],
        workouts: [Workout],
        personalRecords: [PersonalRecord]
    ) -> MesocycleReviewSnapshot? {
        guard let run = latestCompletedRun(from: runs) else { return nil }
        return mesocycleReview(
            for: run,
            workouts: workouts,
            personalRecords: personalRecords
        )
    }

    static func longHorizonAdaptationSummary(
        endingWith run: ProgramRun? = nil,
        allRuns: [ProgramRun],
        workouts: [Workout],
        personalRecords: [PersonalRecord] = [],
        maxBlocks: Int = 3
    ) -> LongHorizonAdaptationSummary {
        LongHorizonAdaptationSummaryService.buildSummary(
            endingWith: run,
            completedRuns: completedProgramRuns(from: allRuns),
            allWorkouts: workouts,
            personalRecords: personalRecords,
            maxBlocks: maxBlocks
        )
    }

    static func latestWeeklyAnalysis(
        for run: ProgramRun?,
        in analyses: [WeeklyTrainingAnalysis]
    ) -> WeeklyTrainingAnalysis? {
        let sorted = analyses.sorted {
            if $0.weekStartDate != $1.weekStartDate {
                return $0.weekStartDate > $1.weekStartDate
            }
            return $0.createdAt > $1.createdAt
        }

        if let run {
            return sorted.first { $0.programRun?.id == run.id && $0.isFinalized }
                ?? sorted.first { $0.programRun?.id == run.id }
        }

        return sorted.first { $0.programRun == nil && $0.isFinalized }
            ?? sorted.first { $0.programRun == nil }
    }

    static func isProgramSessionCompleted(
        run: ProgramRun,
        weekNumber: Int,
        sessionNumber: Int,
        in workouts: [Workout]
    ) -> Bool {
        workouts.contains {
            $0.programRun?.id == run.id &&
            $0.programWeekNumber == weekNumber &&
            $0.programSessionNumber == sessionNumber
        }
    }

    static func personalRecord(
        exerciseName: String,
        repCount: Int,
        in records: [PersonalRecord]
    ) -> PersonalRecord? {
        records.first { $0.exerciseName == exerciseName && $0.repCount == repCount }
    }

    static func preferredUnit(
        for exerciseName: String,
        in records: [PersonalRecord],
        fallback: WeightUnit = AppPreferences.defaultWeightUnit
    ) -> WeightUnit {
        records.first(where: { $0.exerciseName == exerciseName })?.unit ?? fallback
    }

    static func pendingUserProposals(
        for run: ProgramRun? = nil,
        proposals: [AdaptationProposal]
    ) -> [AdaptationProposal] {
        proposals
            .filter { proposal in
                proposal.proposalStatus == .pendingUserConfirmation &&
                (run == nil || proposal.programRun?.id == run?.id)
            }
            .sorted { $0.priority > $1.priority }
    }

    static func adaptationEventCount(for run: ProgramRun, events: [AdaptationEventHistory]) -> Int {
        events.filter { $0.programRun?.id == run.id }.count
    }
}
