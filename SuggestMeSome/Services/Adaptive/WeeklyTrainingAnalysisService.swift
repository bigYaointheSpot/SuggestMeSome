//
//  WeeklyTrainingAnalysisService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData

/// Weekly aggregation engine for Feature 6.
/// - Public façade for completed-week analysis orchestration.
/// - Uses narrow week/run-scoped queries and staged collaborators for maintainability.
enum WeeklyTrainingAnalysisService {
    private static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    static func analyzeCompletedWeeks(triggeredBy workout: Workout, context: ModelContext) {
        let allRuns = WeeklyAnalysisWeekDataLoader.programRuns(context: context)

        if let run = workout.programRun {
            analyzePendingProgramWeeks(for: run, referenceDate: workout.date, context: context)
        }

        analyzePendingStandaloneWeeks(referenceDate: workout.date, allRuns: allRuns, context: context)
    }

    // MARK: - Program Weeks

    private static func analyzePendingProgramWeeks(
        for run: ProgramRun,
        referenceDate: Date,
        context: ModelContext
    ) {
        guard let program = run.program else { return }
        let maxWeek = min(
            program.lengthInWeeks,
            max(1, inferredProgramWeekNumber(for: referenceDate, runStartDate: run.startDate))
        )

        let runWorkouts = WeeklyAnalysisWeekDataLoader.fetchProgramWorkouts(
            for: run,
            beforeOrOn: referenceDate,
            context: context
        )

        for weekNumber in 1...maxWeek {
            let window = programWeekWindow(runStartDate: run.startDate, weekNumber: weekNumber)
            let runWeekWorkouts = runWorkouts.filter {
                resolvedProgramWeekNumber(for: $0, runStartDate: run.startDate) == weekNumber
            }
            let uniqueCompletedSessions = Set(runWeekWorkouts.compactMap(\.programSessionNumber)).count
            let weekEnded = referenceDate > window.weekEndDate
            let weekComplete = uniqueCompletedSessions >= program.sessionsPerWeek || weekEnded

            guard weekComplete else { continue }
            _ = analyzeProgramWeek(run: run, weekNumber: weekNumber, context: context)
        }
    }

    @discardableResult
    static func analyzeProgramWeek(
        run: ProgramRun,
        weekNumber: Int,
        context: ModelContext
    ) -> WeeklyTrainingAnalysis? {
        guard let program = run.program else { return nil }

        let window = programWeekWindow(runStartDate: run.startDate, weekNumber: weekNumber)
        let weekInputs = WeeklyAnalysisWeekDataLoader.loadProgramWeekInputs(
            run: run,
            window: window,
            context: context
        )
        let selection = WeeklyAnalysisDedupeHelper.resolveProgramWeekSelection(inputs: weekInputs)

        let plannedFatigue = plannedFatigueForProgramWeek(program: program, weekNumber: weekNumber)
        let plannedVolumeByMuscle = WeeklyAnalysisVolumeAggregator.plannedVolumeByMuscle(
            program: program,
            weekNumber: weekNumber
        )
        let aggregates = WeeklyAnalysisAggregateScorer.aggregateWeekSignals(
            selectedWorkouts: selection.selectedWorkouts,
            selectedOutcomes: selection.selectedOutcomes,
            plannedFatigueScore: plannedFatigue
        )

        let analysis = WeeklyAnalysisPersistenceCoordinator.upsertAnalysis(
            for: .program(runID: run.id, weekNumber: weekNumber),
            context: context
        )
        WeeklyAnalysisPersistenceCoordinator.configureBaseFields(
            analysis: analysis,
            weekStartDate: window.weekStartDate,
            weekEndDate: window.weekEndDate,
            programRun: run,
            trainingProgram: program,
            programWeekNumber: weekNumber,
            selectedProgramWorkouts: selection.selectedProgramWorkouts,
            standaloneWorkouts: selection.selectedStandaloneWorkouts,
            selectedOutcomes: selection.selectedOutcomes
        )
        WeeklyAnalysisPersistenceCoordinator.applyAggregateFields(
            analysis: analysis,
            aggregates: aggregates,
            plannedFatigueScore: plannedFatigue,
            plannedVolumeByMuscle: plannedVolumeByMuscle
        )
        WeeklyAnalysisPersistenceCoordinator.upsertVolumeMetrics(
            analysis: analysis,
            completedByMuscle: aggregates.completedHardSetsByMuscle,
            weightedByMuscle: aggregates.weightedHardSetsByMuscle,
            plannedByMuscle: plannedVolumeByMuscle,
            context: context
        )
        WeeklyAnalysisPersistenceCoordinator.attachOutcomes(selection.selectedOutcomes, to: analysis)
        WeeklyAnalysisPersistenceCoordinator.finalize(analysis)

        let trendSummary = LiftTrendTrackingService.updateTrends(for: analysis, context: context)

        WeeklyAnalysisEventHistoryWriter.upsertWeeklyFinalizedEvent(
            analysis: analysis,
            programRun: run,
            programWeekNumber: weekNumber,
            topSetSummary: aggregates.mainLiftTopSetE1RM,
            trendSummary: trendSummary,
            skippedProgramDuplicateWorkouts: selection.skippedProgramDuplicateWorkouts,
            context: context
        )

        WeeklyAnalysisProposalPipelineCoordinator.finalizeProgramWeek(from: analysis, context: context)

        return analysis
    }

    // MARK: - Standalone Weeks

    private static func analyzePendingStandaloneWeeks(
        referenceDate: Date,
        allRuns: [ProgramRun],
        context: ModelContext
    ) {
        guard let currentWeekInterval = isoCalendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return }
        let currentWeekStart = currentWeekInterval.start
        let standaloneWorkouts = WeeklyAnalysisWeekDataLoader.fetchStandaloneWorkouts(
            before: currentWeekStart,
            context: context
        )
        guard !standaloneWorkouts.isEmpty else { return }

        let endedWeekStarts: Set<Date> = Set(
            standaloneWorkouts.compactMap { workout in
                guard let weekInterval = isoCalendar.dateInterval(of: .weekOfYear, for: workout.date) else { return nil }
                return weekInterval.start < currentWeekStart ? weekInterval.start : nil
            }
        )

        for weekStart in endedWeekStarts.sorted() {
            let window = weekWindowFromStart(weekStart)
            if overlapsAnyProgramRun(window: window, allRuns: allRuns) {
                continue
            }
            _ = analyzeStandaloneWeek(startingAt: weekStart, context: context)
        }
    }

    @discardableResult
    static func analyzeStandaloneWeek(
        startingAt weekStartDate: Date,
        context: ModelContext
    ) -> WeeklyTrainingAnalysis? {
        let window = weekWindowFromStart(weekStartDate)
        let weekInputs = WeeklyAnalysisWeekDataLoader.loadStandaloneWeekInputs(
            window: window,
            context: context
        )
        guard !weekInputs.standaloneWorkouts.isEmpty else { return nil }

        let selection = WeeklyAnalysisDedupeHelper.resolveStandaloneWeekSelection(inputs: weekInputs)
        let aggregates = WeeklyAnalysisAggregateScorer.aggregateWeekSignals(
            selectedWorkouts: selection.selectedWorkouts,
            selectedOutcomes: selection.selectedOutcomes,
            plannedFatigueScore: nil
        )

        let analysis = WeeklyAnalysisPersistenceCoordinator.upsertAnalysis(
            for: .standalone(weekStartDate: window.weekStartDate),
            context: context
        )
        WeeklyAnalysisPersistenceCoordinator.configureBaseFields(
            analysis: analysis,
            weekStartDate: window.weekStartDate,
            weekEndDate: window.weekEndDate,
            programRun: nil,
            trainingProgram: nil,
            programWeekNumber: nil,
            selectedProgramWorkouts: [],
            standaloneWorkouts: selection.selectedStandaloneWorkouts,
            selectedOutcomes: selection.selectedOutcomes
        )
        WeeklyAnalysisPersistenceCoordinator.applyAggregateFields(
            analysis: analysis,
            aggregates: aggregates,
            plannedFatigueScore: nil,
            plannedVolumeByMuscle: [:]
        )
        WeeklyAnalysisPersistenceCoordinator.upsertVolumeMetrics(
            analysis: analysis,
            completedByMuscle: aggregates.completedHardSetsByMuscle,
            weightedByMuscle: aggregates.weightedHardSetsByMuscle,
            plannedByMuscle: [:],
            context: context
        )
        WeeklyAnalysisPersistenceCoordinator.attachOutcomes(selection.selectedOutcomes, to: analysis)
        WeeklyAnalysisPersistenceCoordinator.finalize(analysis)

        let trendSummary = LiftTrendTrackingService.updateTrends(for: analysis, context: context)
        WeeklyAnalysisEventHistoryWriter.upsertWeeklyFinalizedEvent(
            analysis: analysis,
            programRun: nil,
            programWeekNumber: nil,
            topSetSummary: aggregates.mainLiftTopSetE1RM,
            trendSummary: trendSummary,
            skippedProgramDuplicateWorkouts: 0,
            context: context
        )

        WeeklyAnalysisProposalPipelineCoordinator.finalizeStandaloneWeek(from: analysis, context: context)

        return analysis
    }

    // MARK: - Planned Week Targets

    private static func plannedFatigueForProgramWeek(
        program: TrainingProgram,
        weekNumber: Int
    ) -> Double? {
        program.weeks.first { $0.weekNumber == weekNumber }?.plannedFatigueScore
    }

    // MARK: - Week Anchors

    private static func programWeekWindow(
        runStartDate: Date,
        weekNumber: Int
    ) -> AnalysisWeekWindow {
        let startOfRun = isoCalendar.startOfDay(for: runStartDate)
        let weekStart = isoCalendar.date(byAdding: .day, value: max(0, (weekNumber - 1) * 7), to: startOfRun) ?? startOfRun
        return weekWindowFromStart(weekStart)
    }

    private static func weekWindowFromStart(_ weekStartDate: Date) -> AnalysisWeekWindow {
        let weekStart = isoCalendar.startOfDay(for: weekStartDate)
        let weekEndStart = isoCalendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let weekEnd = weekEndStart.addingTimeInterval(-1)
        return AnalysisWeekWindow(weekStartDate: weekStart, weekEndDate: weekEnd)
    }

    private static func inferredProgramWeekNumber(
        for date: Date,
        runStartDate: Date
    ) -> Int {
        let start = isoCalendar.startOfDay(for: runStartDate)
        let target = isoCalendar.startOfDay(for: date)
        let days = max(0, isoCalendar.dateComponents([.day], from: start, to: target).day ?? 0)
        return (days / 7) + 1
    }

    private static func resolvedProgramWeekNumber(
        for workout: Workout,
        runStartDate: Date
    ) -> Int {
        workout.programWeekNumber ?? inferredProgramWeekNumber(for: workout.date, runStartDate: runStartDate)
    }

    private static func overlapsAnyProgramRun(
        window: AnalysisWeekWindow,
        allRuns: [ProgramRun]
    ) -> Bool {
        allRuns.contains { run in
            let runStart = isoCalendar.startOfDay(for: run.startDate)
            let runEnd = run.endDate ?? .distantFuture
            return runStart <= window.weekEndDate && runEnd >= window.weekStartDate
        }
    }
}
