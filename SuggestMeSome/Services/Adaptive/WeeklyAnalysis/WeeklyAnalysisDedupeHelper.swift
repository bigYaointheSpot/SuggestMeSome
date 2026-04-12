import Foundation

enum WeeklyAnalysisDedupeHelper {
    static func resolveProgramWeekSelection(
        inputs: WeeklyAnalysisWeekInputs
    ) -> WeeklyAnalysisSelectionResult {
        let selectedProgramWorkouts = dedupeProgramWorkoutsBySession(inputs.programWorkouts)
        let selectedStandaloneWorkouts = inputs.standaloneWorkouts

        let selectedWorkoutIDs = Set((selectedProgramWorkouts + selectedStandaloneWorkouts).map(\.id))
        let selectedOutcomes = dedupeOutcomes(
            inputs.outcomes.filter { outcome in
                guard let workoutID = outcome.workout?.id else { return false }
                return selectedWorkoutIDs.contains(workoutID)
            }
        )

        return WeeklyAnalysisSelectionResult(
            selectedProgramWorkouts: selectedProgramWorkouts,
            selectedStandaloneWorkouts: selectedStandaloneWorkouts,
            selectedOutcomes: selectedOutcomes,
            skippedProgramDuplicateWorkouts: max(0, inputs.programWorkouts.count - selectedProgramWorkouts.count)
        )
    }

    static func resolveStandaloneWeekSelection(
        inputs: WeeklyAnalysisWeekInputs
    ) -> WeeklyAnalysisSelectionResult {
        let selectedWorkoutIDs = Set(inputs.standaloneWorkouts.map(\.id))
        let selectedOutcomes = dedupeOutcomes(
            inputs.outcomes.filter { outcome in
                guard let workoutID = outcome.workout?.id else { return false }
                return selectedWorkoutIDs.contains(workoutID)
            }
        )

        return WeeklyAnalysisSelectionResult(
            selectedProgramWorkouts: [],
            selectedStandaloneWorkouts: inputs.standaloneWorkouts,
            selectedOutcomes: selectedOutcomes,
            skippedProgramDuplicateWorkouts: 0
        )
    }

    static func dedupeProgramWorkoutsBySession(_ workouts: [Workout]) -> [Workout] {
        var latestBySession: [Int: Workout] = [:]
        var noSessionWorkouts: [Workout] = []

        for workout in workouts {
            guard let session = workout.programSessionNumber else {
                noSessionWorkouts.append(workout)
                continue
            }
            if let existing = latestBySession[session] {
                if workout.date > existing.date {
                    latestBySession[session] = workout
                }
            } else {
                latestBySession[session] = workout
            }
        }

        return (Array(latestBySession.values) + noSessionWorkouts).sorted {
            if $0.date == $1.date { return $0.id.uuidString < $1.id.uuidString }
            return $0.date < $1.date
        }
    }

    static func dedupeOutcomes(_ outcomes: [ExercisePerformanceOutcome]) -> [ExercisePerformanceOutcome] {
        var byEntryID: [UUID: ExercisePerformanceOutcome] = [:]
        var noEntry: [ExercisePerformanceOutcome] = []

        for outcome in outcomes {
            if let entryID = outcome.exerciseEntry?.id {
                if let existing = byEntryID[entryID] {
                    if outcome.createdAt > existing.createdAt {
                        byEntryID[entryID] = outcome
                    }
                } else {
                    byEntryID[entryID] = outcome
                }
            } else {
                noEntry.append(outcome)
            }
        }

        return (Array(byEntryID.values) + noEntry).sorted {
            if $0.workoutDate == $1.workoutDate { return $0.id.uuidString < $1.id.uuidString }
            return $0.workoutDate < $1.workoutDate
        }
    }
}
