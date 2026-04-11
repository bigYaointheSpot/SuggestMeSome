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

// MARK: - DashboardViewModel

@Observable final class DashboardViewModel {

    // MARK: - Navigation & preference state

    var timeWindow: DashboardTimeWindow = .fourWeeks
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
    ]

    // MARK: - Input properties (synced from @Query in the View)

    var workouts: [Workout] = []
    var activeProgramRuns: [ProgramRun] = []
    var allPRs: [PersonalRecord] = []
    var weeklyAnalyses: [WeeklyTrainingAnalysis] = []
    var liftTrends: [LiftPerformanceTrend] = []
    var allProposals: [AdaptationProposal] = []
    var exercises: [Exercise] = []

    // MARK: - Constants

    let liftOptions: [(name: String, color: Color)] = [
        (CanonicalLift.bench.displayName,         .blue),
        (CanonicalLift.squat.displayName,         .green),
        (CanonicalLift.deadlift.displayName,      .orange),
        (CanonicalLift.overheadPress.displayName, .purple),
    ]

    private static let muscleGroupColors: [String: Color] = [
        "Chest":      .blue,
        "Back":       .green,
        "Legs":       .orange,
        "Shoulders":  .purple,
        "Arms":       .red,
        "Core":       .teal,
    ]

    // MARK: - Computed stats

    var filteredWorkouts: [Workout] {
        guard let cutoff = timeWindow.startDate else { return workouts }
        return workouts.filter { $0.date >= cutoff }
    }

    var workoutCount: Int { filteredWorkouts.count }

    var timeTrainedLabel: String {
        let total = filteredWorkouts.reduce(0) { $0 + $1.durationSeconds }
        let h = total / 3600
        let m = (total % 3600) / 60
        return "\(h)h \(m)m"
    }

    var prCount: Int {
        filteredWorkouts.reduce(0) { count, workout in
            count + workout.exerciseEntries.reduce(0) { $0 + $1.sets.filter(\.isPR).count }
        }
    }

    var streakWeeks: Int {
        let cal = Calendar.current
        guard var weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        var streak = 0
        for _ in 0..<200 {
            let weekEnd = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart)!
            let hasWorkout = workouts.contains { $0.date >= weekStart && $0.date < weekEnd }
            guard hasWorkout else { break }
            streak += 1
            weekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart)!
        }
        return streak
    }

    // MARK: - Coaching data

    var recentAnalysis: WeeklyTrainingAnalysis? {
        weeklyAnalyses.first { $0.isFinalized }
    }

    var pendingProposals: [AdaptationProposal] {
        allProposals
            .filter { $0.proposalStatus == .pendingUserConfirmation }
            .sorted { $0.priority > $1.priority }
    }

    var significantLiftTrends: [LiftPerformanceTrend] {
        liftTrends
            .filter { $0.trendStatus != .insufficientData && $0.confidenceScore >= 0.25 }
            .sorted { $0.confidenceScore > $1.confidenceScore }
            .prefix(5)
            .map { $0 }
    }

    var hasCoachingData: Bool {
        recentAnalysis != nil || !pendingProposals.isEmpty
    }

    // MARK: - Chart data (strength)

    var strengthChartData: [ChartPoint] {
        StrengthAnalytics.chartPoints(
            for: Array(selectedLifts),
            from: workouts,
            since: timeWindow.startDate
        )
    }

    var activeLiftData: [(lift: (name: String, color: Color), points: [ChartPoint])] {
        let data = strengthChartData
        return liftOptions
            .filter { selectedLifts.contains($0.name) }
            .map { lift in (lift: lift, points: data.filter { $0.exerciseName == lift.name }) }
    }

    // MARK: - Frequency chart data

    var workoutFrequencyBuckets: [WeekBucket] {
        let cal = Calendar.current
        let now = Date()

        let windowStart: Date
        if let c = timeWindow.startDate {
            windowStart = c
        } else if let earliest = workouts.map(\.date).min() {
            windowStart = earliest
        } else {
            return []
        }

        let firstMonday = mondayOf(windowStart)
        let thisMonday  = mondayOf(now)

        var buckets: [WeekBucket] = []
        var weekStart = firstMonday
        while weekStart <= thisMonday {
            let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)!
            let count = filteredWorkouts.filter { $0.date >= weekStart && $0.date < weekEnd }.count
            buckets.append(WeekBucket(monday: weekStart, count: count))
            weekStart = weekEnd
        }
        return buckets
    }

    var frequencyTarget: Double {
        let sortedRuns = activeProgramRuns.sorted { $0.startDate > $1.startDate }
        if let run = sortedRuns.first, let program = run.program {
            return Double(program.sessionsPerWeek)
        }
        let buckets = workoutFrequencyBuckets
        guard !buckets.isEmpty else { return 3 }
        let total = buckets.reduce(0) { $0 + $1.count }
        return Double(total) / Double(buckets.count)
    }

    // MARK: - Volume by muscle group

    var volumeByMuscleGroup: [(group: String, sets: Int, color: Color)] {
        var counts: [String: Int] = [:]
        for workout in filteredWorkouts {
            for entry in workout.exerciseEntries {
                guard !entry.isCardio else { continue }
                let groupName: String
                if let exercise = exercises.first(where: { $0.name == entry.exerciseName }),
                   let mg = exercise.muscleGroup,
                   mg.name != "Cardio" {
                    groupName = mg.name
                } else if exercises.first(where: { $0.name == entry.exerciseName }) == nil {
                    continue
                } else {
                    groupName = "Other"
                }
                counts[groupName, default: 0] += entry.sets.count
            }
        }
        return counts
            .sorted { $0.value > $1.value }
            .map { (group: $0.key, sets: $0.value, color: Self.muscleGroupColors[$0.key] ?? .gray) }
    }

    // MARK: - Helpers

    private func mondayOf(_ date: Date) -> Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let daysToMonday = (weekday + 5) % 7
        return cal.startOfDay(for: cal.date(byAdding: .day, value: -daysToMonday, to: date)!)
    }
}
