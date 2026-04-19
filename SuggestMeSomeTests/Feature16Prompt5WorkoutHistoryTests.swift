import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature16Prompt5WorkoutHistoryTests {

    @Test func workoutHistoryDerivedStateBuildsCachedFilterSummaryAndLookup() {
        let chest = MuscleGroup(name: "Chest")
        let back = MuscleGroup(name: "Back")
        let bench = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest)
        let row = Exercise(name: "Barbell Row", exerciseType: .compound, muscleGroup: back)
        chest.exercises = [bench]
        back.exercises = [row]

        let workouts = [
            makeWorkout(
                exerciseName: "Bench Press",
                date: day(-1),
                setSpecs: [(5, 225, true)]
            ),
            makeWorkout(
                exerciseName: "Barbell Row",
                date: day(-2),
                setSpecs: [(8, 185, false)]
            ),
        ]

        let filters = WorkoutHistoryFilterInputs(
            isDateFilterEnabled: false,
            startDate: day(-7),
            endDate: Date(),
            selectedGroupNames: ["Chest"],
            selectedExerciseNames: [],
            isPersonalRecordOnly: true
        )

        let derivedState = WorkoutHistoryDerivedState.build(
            workouts: workouts,
            muscleGroups: [chest, back],
            filters: filters
        )

        #expect(derivedState.filteredWorkouts.count == 1)
        #expect(derivedState.filteredWorkouts.first?.exerciseEntries.first?.exerciseName == "Bench Press")
        #expect(derivedState.activeFilterSummary.isFiltered)
        #expect(derivedState.activeFilterSummary.exerciseFilterActive)
        #expect(derivedState.activeFilterSummary.exerciseFilterLabel == "Chest")
        #expect(derivedState.prOnlyState.isEnabled)
        #expect(derivedState.exerciseNamesByGroup["Chest"] == Set(["Bench Press"]))
        #expect(derivedState.dateRangeBounds == nil)
    }

    @Test func workoutHistoryDerivedStateAppliesDateBoundsAndExplicitExerciseSelections() {
        let chest = MuscleGroup(name: "Chest")
        let legs = MuscleGroup(name: "Legs")
        chest.exercises = [Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest)]
        legs.exercises = [Exercise(name: "Back Squat", exerciseType: .compound, muscleGroup: legs)]

        let workouts = [
            makeWorkout(
                exerciseName: "Bench Press",
                date: day(-1),
                setSpecs: [(5, 225, false)]
            ),
            makeWorkout(
                exerciseName: "Back Squat",
                date: day(-10),
                setSpecs: [(5, 315, false)]
            ),
        ]

        let filters = WorkoutHistoryFilterInputs(
            isDateFilterEnabled: true,
            startDate: day(-3),
            endDate: Date(),
            selectedGroupNames: [],
            selectedExerciseNames: ["Bench Press"],
            isPersonalRecordOnly: false
        )

        let derivedState = WorkoutHistoryDerivedState.build(
            workouts: workouts,
            muscleGroups: [chest, legs],
            filters: filters
        )

        #expect(derivedState.filteredWorkouts.count == 1)
        #expect(derivedState.filteredWorkouts.first?.exerciseEntries.first?.exerciseName == "Bench Press")
        #expect(derivedState.dateRangeBounds != nil)
        #expect(derivedState.activeFilterSummary.exerciseFilterLabel == "Bench Press")
    }

    @Test func workoutDateRangeSnapshotMatchesFilteredWindowCountsAndBounds() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let workouts = [
            Workout(date: day(-12), startTime: day(-12), durationSeconds: 1_200),
            Workout(date: day(-5), startTime: day(-5), durationSeconds: 1_500),
            Workout(date: day(-2), startTime: day(-2), durationSeconds: 1_800),
        ]
        workouts.forEach { context.insert($0) }
        try context.save()

        let startDate = Calendar.current.startOfDay(for: day(-6))
        let endDate = Calendar.current.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: day(-1)
        ) ?? day(-1)

        let snapshot = TrainingReadRepository.workoutDateRangeSnapshot(
            from: startDate,
            to: endDate,
            context: context
        )
        let filtered = workouts
            .filter { $0.date >= startDate && $0.date <= endDate }
            .sorted { $0.date < $1.date }

        #expect(snapshot.count == filtered.count)
        #expect(snapshot.workouts.map(\.id) == filtered.map(\.id))
        #expect(snapshot.earliestDate == filtered.first?.date)
        #expect(snapshot.latestDate == filtered.last?.date)
    }

    @Test func workoutHistoryRefreshTokenIgnoresSetDetailChangesWhenFilterInputsStayEquivalent() {
        let chest = MuscleGroup(name: "Chest")
        chest.exercises = [Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest)]
        let baselineWorkout = makeWorkout(
            exerciseName: "Bench Press",
            date: day(-1),
            setSpecs: [(5, 225, false)]
        )
        let updatedWorkout = makeWorkout(
            id: baselineWorkout.id,
            exerciseName: "Bench Press",
            date: baselineWorkout.date,
            setSpecs: [(8, 315, false)]
        )
        let filters = WorkoutHistoryFilterInputs(
            isDateFilterEnabled: false,
            startDate: day(-7),
            endDate: Date(),
            selectedGroupNames: ["Chest"],
            selectedExerciseNames: [],
            isPersonalRecordOnly: false
        )

        let baselineToken = WorkoutHistoryDerivedState.refreshToken(
            workouts: [baselineWorkout],
            muscleGroups: [chest],
            filters: filters
        )
        let updatedToken = WorkoutHistoryDerivedState.refreshToken(
            workouts: [updatedWorkout],
            muscleGroups: [chest],
            filters: filters
        )

        #expect(baselineToken == updatedToken)
    }

    @Test func workoutHistoryRefreshTokenTracksPRFlagsAndExerciseGroupMembership() {
        let chest = MuscleGroup(name: "Chest")
        chest.exercises = [Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest)]
        let expandedChest = MuscleGroup(name: "Chest")
        expandedChest.exercises = [
            Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: expandedChest),
            Exercise(name: "Incline Bench Press", exerciseType: .compound, muscleGroup: expandedChest)
        ]
        let baselineWorkout = makeWorkout(
            exerciseName: "Bench Press",
            date: day(-1),
            setSpecs: [(5, 225, false)]
        )
        let prWorkout = makeWorkout(
            id: baselineWorkout.id,
            exerciseName: "Bench Press",
            date: baselineWorkout.date,
            setSpecs: [(5, 225, true)]
        )
        let filters = WorkoutHistoryFilterInputs(
            isDateFilterEnabled: false,
            startDate: day(-7),
            endDate: Date(),
            selectedGroupNames: ["Chest"],
            selectedExerciseNames: [],
            isPersonalRecordOnly: true
        )

        let baselineToken = WorkoutHistoryDerivedState.refreshToken(
            workouts: [baselineWorkout],
            muscleGroups: [chest],
            filters: filters
        )
        let prToken = WorkoutHistoryDerivedState.refreshToken(
            workouts: [prWorkout],
            muscleGroups: [chest],
            filters: filters
        )
        let expandedMembershipToken = WorkoutHistoryDerivedState.refreshToken(
            workouts: [baselineWorkout],
            muscleGroups: [expandedChest],
            filters: filters
        )

        #expect(baselineToken != prToken)
        #expect(baselineToken != expandedMembershipToken)
    }

    private func makeWorkout(
        id: UUID? = nil,
        exerciseName: String,
        date: Date,
        setSpecs: [(reps: Int, weight: Double, isPR: Bool)]
    ) -> Workout {
        let workout = Workout(
            id: id ?? UUID(),
            date: date,
            startTime: date,
            durationSeconds: 1_800
        )
        let entry = ExerciseEntry(
            exerciseName: exerciseName,
            unit: .lbs,
            orderIndex: 0
        )
        entry.workout = workout
        workout.exerciseEntries = [entry]
        entry.sets = setSpecs.enumerated().map { index, spec in
            let set = SetEntry(
                setNumber: index + 1,
                reps: spec.reps,
                weight: spec.weight,
                isPR: spec.isPR
            )
            set.exerciseEntry = entry
            return set
        }
        return workout
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            PersonalRecord.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            ProgramRun.self,
            ExercisePerformanceOutcome.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AppliedOverlayAdjustment.self,
            AdaptationEventHistory.self,
            DailyCoachCheckIn.self,
            DailyCoachWeeklyReview.self,
            HealthKitDailySummary.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
