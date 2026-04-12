import Foundation

struct WeeklyAnalysisWeekInputs {
    let programWorkouts: [Workout]
    let standaloneWorkouts: [Workout]
    let outcomes: [ExercisePerformanceOutcome]
}

struct WeeklyAnalysisSelectionResult {
    let selectedProgramWorkouts: [Workout]
    let selectedStandaloneWorkouts: [Workout]
    let selectedOutcomes: [ExercisePerformanceOutcome]
    let skippedProgramDuplicateWorkouts: Int

    var selectedWorkouts: [Workout] {
        selectedProgramWorkouts + selectedStandaloneWorkouts
    }
}

struct WeeklyAnalysisAggregates {
    let weightedPerformanceScore: Double
    let adherenceScore: Double
    let observedFatigueScore: Double
    let fatigueStatus: FatigueStatus
    let completedHardSetsByMuscle: [ProgramVolumeMuscle: Double]
    let weightedHardSetsByMuscle: [ProgramVolumeMuscle: Double]
    let totalCompletedHardSets: Double
    let totalCompletedTonnageLbs: Double
    let mainLiftTopSetE1RM: [String: Double]
}

enum WeeklyAnalysisKey {
    case program(runID: UUID, weekNumber: Int)
    case standalone(weekStartDate: Date)
}
