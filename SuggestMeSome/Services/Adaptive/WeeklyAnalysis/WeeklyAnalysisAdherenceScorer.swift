import Foundation

enum WeeklyAnalysisAdherenceScorer {
    static func compute(
        selectedWorkouts: [Workout],
        selectedOutcomes: [ExercisePerformanceOutcome]
    ) -> Double {
        let anyProgramWorkout = selectedWorkouts.contains { $0.programRun != nil }
        guard anyProgramWorkout else {
            return 1.0
        }

        let programWorkouts = selectedWorkouts.filter { $0.programRun != nil }
        guard let program = programWorkouts.first?.programRun?.program else { return 1.0 }

        let uniqueProgramSessions = Set(programWorkouts.compactMap(\.programSessionNumber)).count
        let sessionCompletion = Double(uniqueProgramSessions) / Double(max(1, program.sessionsPerWeek))
        let avgCompletionRatio = average(selectedOutcomes.compactMap(\.completionRatio)) ?? sessionCompletion

        let mixed = (sessionCompletion * 0.60) + (avgCompletionRatio * 0.40)
        return min(1.25, max(0.0, mixed))
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0.0, +) / Double(values.count)
    }
}
