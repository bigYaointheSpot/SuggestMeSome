//
//  DashboardViewModel.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/10/26.
//

import SwiftUI

// MARK: - WeekBucket

struct WeekBucket: Identifiable {
    var id: Date { monday }
    let monday: Date
    let count: Int
}

struct DashboardRefreshInputs {
    let workouts: [Workout]
    let activeProgramRuns: [ProgramRun]
    let allPRs: [PersonalRecord]
    let weeklyAnalyses: [WeeklyTrainingAnalysis]
    let liftTrends: [LiftPerformanceTrend]
    let allProposals: [AdaptationProposal]
    let exercises: [Exercise]

    static let empty = DashboardRefreshInputs(
        workouts: [],
        activeProgramRuns: [],
        allPRs: [],
        weeklyAnalyses: [],
        liftTrends: [],
        allProposals: [],
        exercises: []
    )
}

// MARK: - DashboardViewModel

@Observable final class DashboardViewModel {

    // MARK: - Navigation & preference state

    var timeWindow: DashboardTimeWindow = .fourWeeks {
        didSet { rebuildDerivedState() }
    }
    var navigateToEmptyWorkout: Bool = false
    var showingGeneratorSheet: Bool = false
    var pendingGeneratedWorkout: GeneratedWorkout? = nil
    var showingGeneratedWorkout: Bool = false
    var showingCompleteProgramSheet: Bool = false
    var pendingProgramWorkout: ProgramWorkoutContext? = nil
    var showingProgramWorkout: Bool = false
    var showingProposalReview: Bool = false
    var selectedLifts: Set<String> = [
        CanonicalLift.bench.displayName,
        CanonicalLift.squat.displayName,
        CanonicalLift.deadlift.displayName,
    ] {
        didSet { rebuildDerivedState() }
    }

    // MARK: - Cached input state

    private var refreshInputs = DashboardRefreshInputs.empty
    private var latestTrainingStateSnapshot: TrainingStateSnapshot? = nil
    private var latestHealthKitInsight: ObjectiveRecoveryInsight? = nil

    // MARK: - Derived analytics cache

    var filteredWorkouts: [Workout] = []
    var workoutCount: Int = 0
    var timeTrainedLabel: String = "0h 0m"
    var prCount: Int = 0
    var streakWeeks: Int = 0

    var recentAnalysis: WeeklyTrainingAnalysis? = nil
    var pendingProposals: [AdaptationProposal] = []
    var significantLiftTrends: [LiftPerformanceTrend] = []

    var workoutFrequencyBuckets: [WeekBucket] = []
    var frequencyTarget: Double = 3

    var volumeByMuscleGroup: [(group: String, sets: Int, color: Color)] = []
    var exerciseNameToMuscleGroup: [String: String] = [:]
    var muscleGroupVolumeCounts: [String: Int] = [:]

    var workoutsSparkline: [Double] = []
    var timeTrainedSparkline: [Double] = []
    var prSparkline: [Double] = []
    var streakSparkline: [Double] = []

    var activeLiftData: [(lift: (name: String, color: Color), points: [ChartPoint])] = []

    var perMuscleSaturation: [ProgramVolumeMuscle: Double] = [:]
    var recoveryPressure: TrainingStateRecoveryPressure = .neutral
    var snapshotFatigueStatus: FatigueStatus? = nil
    var hasAdaptiveSignals: Bool = false

    // MARK: - Constants

    let liftOptions: [(name: String, color: Color)] = [
        (CanonicalLift.bench.displayName,         .blue),
        (CanonicalLift.squat.displayName,         .green),
        (CanonicalLift.deadlift.displayName,      .orange),
        (CanonicalLift.overheadPress.displayName, .purple),
    ]

    // MARK: - Exposed source snapshots

    var workouts: [Workout] { refreshInputs.workouts }
    var activeProgramRuns: [ProgramRun] { refreshInputs.activeProgramRuns }
    var allPRs: [PersonalRecord] { refreshInputs.allPRs }
    var weeklyAnalyses: [WeeklyTrainingAnalysis] { refreshInputs.weeklyAnalyses }
    var healthKitInsight: ObjectiveRecoveryInsight? { latestHealthKitInsight }
    var hasCoachingData: Bool { recentAnalysis != nil || !pendingProposals.isEmpty }

    // MARK: - Refresh

    func refresh(
        workouts: [Workout],
        activeProgramRuns: [ProgramRun],
        allPRs: [PersonalRecord],
        exercises: [Exercise],
        weeklyAnalyses: [WeeklyTrainingAnalysis],
        liftTrends: [LiftPerformanceTrend],
        allProposals: [AdaptationProposal],
        trainingStateSnapshot: TrainingStateSnapshot?,
        healthKitInsight: ObjectiveRecoveryInsight?
    ) {
        refreshInputs = DashboardRefreshInputs(
            workouts: workouts,
            activeProgramRuns: activeProgramRuns,
            allPRs: allPRs,
            weeklyAnalyses: weeklyAnalyses,
            liftTrends: liftTrends,
            allProposals: allProposals,
            exercises: exercises
        )
        latestTrainingStateSnapshot = trainingStateSnapshot
        latestHealthKitInsight = healthKitInsight
        rebuildDerivedState()
    }

    // MARK: - Derived-state builder

    private func rebuildDerivedState() {
        let filteredWorkouts = buildFilteredWorkouts(from: refreshInputs.workouts)
        let recentAnalysis = refreshInputs.weeklyAnalyses.first { $0.isFinalized }
        let pendingProposals = refreshInputs.allProposals
            .filter { $0.proposalStatus == .pendingUserConfirmation }
            .sorted { $0.priority > $1.priority }
        let significantLiftTrends = refreshInputs.liftTrends
            .filter { $0.trendStatus != .insufficientData && $0.confidenceScore >= 0.25 }
            .sorted { $0.confidenceScore > $1.confidenceScore }
            .prefix(5)
            .map { $0 }
        let workoutFrequencyBuckets = buildWorkoutFrequencyBuckets(
            filteredWorkouts: filteredWorkouts,
            allWorkouts: refreshInputs.workouts
        )
        let frequencyTarget = buildFrequencyTarget(
            activeProgramRuns: refreshInputs.activeProgramRuns,
            workoutFrequencyBuckets: workoutFrequencyBuckets
        )
        let exerciseNameToMuscleGroup = buildExerciseNameToMuscleGroupLookup(
            exercises: refreshInputs.exercises
        )
        let muscleGroupVolumeCounts = buildMuscleGroupVolumeCounts(
            filteredWorkouts: filteredWorkouts,
            exerciseNameToMuscleGroup: exerciseNameToMuscleGroup
        )
        let volumeByMuscleGroup = muscleGroupVolumeCounts
            .sorted { $0.value > $1.value }
            .map {
                (
                    group: $0.key,
                    sets: $0.value,
                    color: DashboardMusclePalette.color(for: $0.key)
                )
            }
        let strengthChartData = StrengthAnalytics.chartPoints(
            for: Array(selectedLifts),
            from: refreshInputs.workouts,
            since: timeWindow.startDate
        )
        let activeLiftData = liftOptions
            .filter { selectedLifts.contains($0.name) }
            .map { lift in
                (
                    lift: lift,
                    points: strengthChartData.filter { $0.exerciseName == lift.name }
                )
            }

        self.filteredWorkouts = filteredWorkouts
        self.workoutCount = filteredWorkouts.count
        self.timeTrainedLabel = buildTimeTrainedLabel(from: filteredWorkouts)
        self.prCount = buildPRCount(from: filteredWorkouts)
        self.streakWeeks = buildStreakWeeks(from: refreshInputs.workouts)
        self.recentAnalysis = recentAnalysis
        self.pendingProposals = pendingProposals
        self.significantLiftTrends = significantLiftTrends
        self.workoutFrequencyBuckets = workoutFrequencyBuckets
        self.frequencyTarget = frequencyTarget
        self.exerciseNameToMuscleGroup = exerciseNameToMuscleGroup
        self.muscleGroupVolumeCounts = muscleGroupVolumeCounts
        self.volumeByMuscleGroup = volumeByMuscleGroup
        self.workoutsSparkline = workoutFrequencyBuckets.map { Double($0.count) }
        self.timeTrainedSparkline = buildTimeTrainedSparkline(
            filteredWorkouts: filteredWorkouts,
            buckets: workoutFrequencyBuckets
        )
        self.prSparkline = buildPRSparkline(
            filteredWorkouts: filteredWorkouts,
            buckets: workoutFrequencyBuckets
        )
        self.streakSparkline = workoutFrequencyBuckets.map { $0.count > 0 ? 1 : 0 }
        self.activeLiftData = activeLiftData
        self.perMuscleSaturation = latestTrainingStateSnapshot?.perMuscleStressSaturation ?? [:]
        self.recoveryPressure = latestTrainingStateSnapshot?.recoveryPressure ?? .neutral
        self.snapshotFatigueStatus = latestTrainingStateSnapshot?.fatigueStatus ?? recentAnalysis?.fatigueStatus
        self.hasAdaptiveSignals = latestTrainingStateSnapshot != nil || latestHealthKitInsight != nil
    }

    // MARK: - Analytics builders

    private func buildFilteredWorkouts(from workouts: [Workout]) -> [Workout] {
        guard let cutoff = timeWindow.startDate else { return workouts }
        return workouts.filter { $0.date >= cutoff }
    }

    private func buildTimeTrainedLabel(from workouts: [Workout]) -> String {
        let totalSeconds = workouts.reduce(0) { $0 + $1.durationSeconds }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private func buildPRCount(from workouts: [Workout]) -> Int {
        workouts.reduce(0) { count, workout in
            count + workout.exerciseEntries.reduce(0) { total, entry in
                total + entry.sets.filter(\.isPR).count
            }
        }
    }

    private func buildStreakWeeks(from workouts: [Workout]) -> Int {
        let calendar = Calendar.current
        guard var weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return 0
        }

        var streak = 0
        for _ in 0..<200 {
            guard let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else {
                break
            }
            let hasWorkout = workouts.contains { $0.date >= weekStart && $0.date < weekEnd }
            guard hasWorkout else { break }
            streak += 1
            guard let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) else {
                break
            }
            weekStart = previousWeek
        }
        return streak
    }

    private func buildWorkoutFrequencyBuckets(
        filteredWorkouts: [Workout],
        allWorkouts: [Workout]
    ) -> [WeekBucket] {
        let calendar = Calendar.current
        let now = Date()

        let windowStart: Date
        if let cutoff = timeWindow.startDate {
            windowStart = cutoff
        } else if let earliest = allWorkouts.map(\.date).min() {
            windowStart = earliest
        } else {
            return []
        }

        let firstMonday = mondayOf(windowStart)
        let thisMonday = mondayOf(now)

        var buckets: [WeekBucket] = []
        var weekStart = firstMonday
        while weekStart <= thisMonday {
            guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                break
            }
            let count = filteredWorkouts.filter { $0.date >= weekStart && $0.date < weekEnd }.count
            buckets.append(WeekBucket(monday: weekStart, count: count))
            weekStart = weekEnd
        }
        return buckets
    }

    private func buildFrequencyTarget(
        activeProgramRuns: [ProgramRun],
        workoutFrequencyBuckets: [WeekBucket]
    ) -> Double {
        let sortedRuns = activeProgramRuns.sorted { $0.startDate > $1.startDate }
        if let run = sortedRuns.first, let program = run.program {
            return Double(program.sessionsPerWeek)
        }
        guard !workoutFrequencyBuckets.isEmpty else { return 3 }
        let total = workoutFrequencyBuckets.reduce(0) { $0 + $1.count }
        return Double(total) / Double(workoutFrequencyBuckets.count)
    }

    private func buildExerciseNameToMuscleGroupLookup(
        exercises: [Exercise]
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: exercises.compactMap { exercise in
            guard let muscleGroup = exercise.muscleGroup?.name, muscleGroup != "Cardio" else {
                return nil
            }
            return (exercise.name, muscleGroup)
        })
    }

    private func buildMuscleGroupVolumeCounts(
        filteredWorkouts: [Workout],
        exerciseNameToMuscleGroup: [String: String]
    ) -> [String: Int] {
        var counts: [String: Int] = [:]

        for workout in filteredWorkouts {
            for entry in workout.exerciseEntries where !entry.isCardio {
                guard let groupName = exerciseNameToMuscleGroup[entry.exerciseName] else { continue }
                counts[groupName, default: 0] += entry.sets.count
            }
        }

        return counts
    }

    private func buildTimeTrainedSparkline(
        filteredWorkouts: [Workout],
        buckets: [WeekBucket]
    ) -> [Double] {
        let calendar = Calendar.current
        return buckets.map { bucket in
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: bucket.monday) ?? bucket.monday
            let seconds = filteredWorkouts
                .filter { $0.date >= bucket.monday && $0.date < weekEnd }
                .reduce(0) { $0 + $1.durationSeconds }
            return Double(seconds) / 60.0
        }
    }

    private func buildPRSparkline(
        filteredWorkouts: [Workout],
        buckets: [WeekBucket]
    ) -> [Double] {
        let calendar = Calendar.current
        return buckets.map { bucket in
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: bucket.monday) ?? bucket.monday
            let count = filteredWorkouts
                .filter { $0.date >= bucket.monday && $0.date < weekEnd }
                .reduce(0) { total, workout in
                    total + workout.exerciseEntries.reduce(0) { subtotal, entry in
                        subtotal + entry.sets.filter(\.isPR).count
                    }
                }
            return Double(count)
        }
    }

    private func mondayOf(_ date: Date) -> Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let daysToMonday = (weekday + 5) % 7
        let shiftedDate = calendar.date(byAdding: .day, value: -daysToMonday, to: date) ?? date
        return calendar.startOfDay(for: shiftedDate)
    }
}
