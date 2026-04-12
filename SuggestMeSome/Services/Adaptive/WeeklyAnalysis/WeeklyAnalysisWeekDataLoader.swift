import Foundation
import SwiftData

enum WeeklyAnalysisWeekDataLoader {
    static func programRuns(context: ModelContext) -> [ProgramRun] {
        (try? context.fetch(FetchDescriptor<ProgramRun>())) ?? []
    }

    static func loadProgramWeekInputs(
        run: ProgramRun,
        window: AnalysisWeekWindow,
        context: ModelContext
    ) -> WeeklyAnalysisWeekInputs {
        WeeklyAnalysisWeekInputs(
            programWorkouts: fetchProgramWorkouts(for: run, between: window, context: context),
            standaloneWorkouts: fetchStandaloneWorkouts(between: window, context: context),
            outcomes: fetchOutcomes(between: window, context: context)
        )
    }

    static func loadStandaloneWeekInputs(
        window: AnalysisWeekWindow,
        context: ModelContext
    ) -> WeeklyAnalysisWeekInputs {
        WeeklyAnalysisWeekInputs(
            programWorkouts: [],
            standaloneWorkouts: fetchStandaloneWorkouts(between: window, context: context),
            outcomes: fetchOutcomes(between: window, context: context)
        )
    }

    static func fetchProgramWorkouts(
        for run: ProgramRun,
        beforeOrOn date: Date,
        context: ModelContext
    ) -> [Workout] {
        let runID = run.id
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> {
                $0.programRun?.id == runID && $0.date <= date
            },
            sortBy: [SortDescriptor(\Workout.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchStandaloneWorkouts(
        before date: Date,
        context: ModelContext
    ) -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> {
                $0.programRun == nil &&
                $0.date < date
            },
            sortBy: [SortDescriptor(\Workout.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchProgramWorkouts(
        for run: ProgramRun,
        between window: AnalysisWeekWindow,
        context: ModelContext
    ) -> [Workout] {
        let runID = run.id
        let weekStartDate = window.weekStartDate
        let weekEndDate = window.weekEndDate
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> {
                $0.programRun?.id == runID &&
                $0.date >= weekStartDate &&
                $0.date <= weekEndDate
            },
            sortBy: [SortDescriptor(\Workout.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchStandaloneWorkouts(
        between window: AnalysisWeekWindow,
        context: ModelContext
    ) -> [Workout] {
        let weekStartDate = window.weekStartDate
        let weekEndDate = window.weekEndDate
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> {
                $0.programRun == nil &&
                $0.date >= weekStartDate &&
                $0.date <= weekEndDate
            },
            sortBy: [SortDescriptor(\Workout.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchOutcomes(
        between window: AnalysisWeekWindow,
        context: ModelContext
    ) -> [ExercisePerformanceOutcome] {
        let weekStartDate = window.weekStartDate
        let weekEndDate = window.weekEndDate
        let descriptor = FetchDescriptor<ExercisePerformanceOutcome>(
            predicate: #Predicate<ExercisePerformanceOutcome> {
                $0.workoutDate >= weekStartDate &&
                $0.workoutDate <= weekEndDate
            },
            sortBy: [SortDescriptor(\ExercisePerformanceOutcome.workoutDate, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
