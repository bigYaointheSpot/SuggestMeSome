//
//  TrainingContextQueryService.swift
//  SuggestMeSome
//
//  Shared query helpers for commonly reused training-context reads.
//

import Foundation
import SwiftData

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

    static func runScopedWorkouts(for run: ProgramRun, in workouts: [Workout]) -> [Workout] {
        workouts.filter { $0.programRun?.id == run.id }
    }

    static func completedWorkoutCount(for run: ProgramRun, in workouts: [Workout]) -> Int {
        runScopedWorkouts(for: run, in: workouts).count
    }

    static func completedWorkoutCount(for run: ProgramRun, context: ModelContext) throws -> Int {
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        return completedWorkoutCount(for: run, in: workouts)
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

    static func fetchPersonalRecords(context: ModelContext) -> [PersonalRecord] {
        (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? []
    }
}
