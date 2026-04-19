import Foundation

private struct WorkoutHistoryExerciseGroupFingerprint: Hashable {
    let groupName: String
    let exerciseNames: [String]
}

private struct WorkoutHistoryWorkoutFingerprint: Hashable {
    let workoutID: UUID
    let date: Date
    let exerciseNames: [String]
    let containsPersonalRecord: Bool
}

private struct WorkoutHistoryDerivedFingerprint: Hashable {
    let filters: WorkoutHistoryFilterInputs
    let exerciseGroups: [WorkoutHistoryExerciseGroupFingerprint]
    let workouts: [WorkoutHistoryWorkoutFingerprint]
}

struct WorkoutHistoryFilterInputs: Hashable {
    var isDateFilterEnabled: Bool
    var startDate: Date
    var endDate: Date
    var selectedGroupNames: Set<String>
    var selectedExerciseNames: Set<String>
    var isPersonalRecordOnly: Bool
}

struct WorkoutHistoryFilterSummary: Equatable {
    let isFiltered: Bool
    let exerciseFilterActive: Bool
    let exerciseFilterLabel: String
    let selectedFilterCount: Int
}

struct WorkoutHistoryDateBounds: Equatable {
    let startOfDay: Date
    let endOfDay: Date
}

struct WorkoutHistoryPRFilterState: Equatable {
    let isEnabled: Bool
}

struct WorkoutHistoryDerivedState {
    static let placeholder = WorkoutHistoryDerivedState(
        filteredWorkouts: [],
        activeFilterSummary: WorkoutHistoryFilterSummary(
            isFiltered: false,
            exerciseFilterActive: false,
            exerciseFilterLabel: "Exercise",
            selectedFilterCount: 0
        ),
        exerciseNamesByGroup: [:],
        dateRangeBounds: nil,
        prOnlyState: WorkoutHistoryPRFilterState(isEnabled: false)
    )

    let filteredWorkouts: [Workout]
    let activeFilterSummary: WorkoutHistoryFilterSummary
    let exerciseNamesByGroup: [String: Set<String>]
    let dateRangeBounds: WorkoutHistoryDateBounds?
    let prOnlyState: WorkoutHistoryPRFilterState

    static func build(
        workouts: [Workout],
        muscleGroups: [MuscleGroup],
        filters: WorkoutHistoryFilterInputs,
        calendar: Calendar = .autoupdatingCurrent
    ) -> WorkoutHistoryDerivedState {
        let exerciseNamesByGroup = muscleGroups.reduce(into: [String: Set<String>]()) { result, group in
            result[group.name] = Set(group.exercises.map(\.name))
        }

        let selectedFilterCount = filters.selectedGroupNames.count + filters.selectedExerciseNames.count
        let exerciseFilterLabel: String
        switch selectedFilterCount {
        case 0:
            exerciseFilterLabel = "Exercise"
        case 1:
            exerciseFilterLabel = filters.selectedGroupNames.first
                ?? filters.selectedExerciseNames.first
                ?? "Exercise"
        default:
            exerciseFilterLabel = "\(selectedFilterCount) selected"
        }

        let filterSummary = WorkoutHistoryFilterSummary(
            isFiltered: filters.isDateFilterEnabled || selectedFilterCount > 0 || filters.isPersonalRecordOnly,
            exerciseFilterActive: selectedFilterCount > 0,
            exerciseFilterLabel: exerciseFilterLabel,
            selectedFilterCount: selectedFilterCount
        )

        let dateRangeBounds: WorkoutHistoryDateBounds?
        if filters.isDateFilterEnabled {
            let startOfDay = calendar.startOfDay(for: filters.startDate)
            let endOfDay = calendar.date(
                bySettingHour: 23,
                minute: 59,
                second: 59,
                of: filters.endDate
            ) ?? filters.endDate
            dateRangeBounds = WorkoutHistoryDateBounds(
                startOfDay: startOfDay,
                endOfDay: endOfDay
            )
        } else {
            dateRangeBounds = nil
        }

        var allowedExerciseNames = filters.selectedExerciseNames
        for groupName in filters.selectedGroupNames {
            allowedExerciseNames.formUnion(exerciseNamesByGroup[groupName] ?? [])
        }

        let filteredWorkouts = workouts.filter { workout in
            if let dateRangeBounds {
                guard workout.date >= dateRangeBounds.startOfDay && workout.date <= dateRangeBounds.endOfDay else {
                    return false
                }
            }

            if filterSummary.exerciseFilterActive {
                guard workout.exerciseEntries.contains(where: { allowedExerciseNames.contains($0.exerciseName) }) else {
                    return false
                }
            }

            if filters.isPersonalRecordOnly {
                guard containsPersonalRecord(in: workout) else {
                    return false
                }
            }

            return true
        }

        return WorkoutHistoryDerivedState(
            filteredWorkouts: filteredWorkouts,
            activeFilterSummary: filterSummary,
            exerciseNamesByGroup: exerciseNamesByGroup,
            dateRangeBounds: dateRangeBounds,
            prOnlyState: WorkoutHistoryPRFilterState(isEnabled: filters.isPersonalRecordOnly)
        )
    }

    static func refreshToken(
        workouts: [Workout],
        muscleGroups: [MuscleGroup],
        filters: WorkoutHistoryFilterInputs
    ) -> Int {
        let fingerprint = WorkoutHistoryDerivedFingerprint(
            filters: filters,
            exerciseGroups: muscleGroups
                .map { group in
                    WorkoutHistoryExerciseGroupFingerprint(
                        groupName: group.name,
                        exerciseNames: group.exercises.map(\.name).sorted()
                    )
                }
                .sorted(by: { $0.groupName < $1.groupName }),
            workouts: workouts
                .map { workout in
                    WorkoutHistoryWorkoutFingerprint(
                        workoutID: workout.id,
                        date: workout.date,
                        exerciseNames: Array(Set(workout.exerciseEntries.map(\.exerciseName))).sorted(),
                        containsPersonalRecord: containsPersonalRecord(in: workout)
                    )
                }
                .sorted(by: { lhs, rhs in
                    if lhs.date != rhs.date {
                        return lhs.date > rhs.date
                    }
                    return lhs.workoutID.uuidString > rhs.workoutID.uuidString
                })
        )
        var hasher = Hasher()
        hasher.combine(fingerprint)
        return hasher.finalize()
    }

    private static func containsPersonalRecord(in workout: Workout) -> Bool {
        workout.exerciseEntries.contains { entry in
            entry.sets.contains(where: \.isPR)
        }
    }
}
