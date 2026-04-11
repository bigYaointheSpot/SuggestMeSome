//
//  DailyCoachSessionSummaryService.swift
//  SuggestMeSome
//
//  Feature 7 — derives a compact, deterministic session summary from the most
//  recent saved workout and its per-exercise effort feedback.
//

import Foundation

// MARK: - SessionSummary

struct SessionSummary {
    /// Human-readable one-sentence description of how the session went.
    let summaryText: String
    /// Date of the summarised workout.
    let workoutDate: Date
    /// True when at least one exercise has effort feedback recorded.
    let hasEffortData: Bool
    /// Raw counts of the three effort bands across rated exercises.
    let tooEasyCount: Int
    let onTargetCount: Int
    let tooHardCount: Int
}

// MARK: - DailyCoachSessionSummaryService

enum DailyCoachSessionSummaryService {

    /// Derives a `SessionSummary` from the most recent workout in `recentWorkouts`.
    /// Returns `nil` when there are no workouts.
    static func latestSummary(
        recentWorkouts: [Workout],
        latestCheckIn: DailyCoachCheckIn?
    ) -> SessionSummary? {
        guard let workout = recentWorkouts.first else { return nil }

        let strengthEntries = workout.exerciseEntries.filter { !$0.isCardio }
        let ratedEntries = strengthEntries.filter { $0.effortFeedback != nil }

        guard !ratedEntries.isEmpty else {
            return SessionSummary(
                summaryText: "Session logged — no effort feedback recorded.",
                workoutDate: workout.date,
                hasEffortData: false,
                tooEasyCount: 0,
                onTargetCount: 0,
                tooHardCount: 0
            )
        }

        let tooEasyCount  = ratedEntries.filter { $0.effortFeedback == .tooEasy }.count
        let onTargetCount = ratedEntries.filter { $0.effortFeedback == .onTarget }.count
        let tooHardCount  = ratedEntries.filter { $0.effortFeedback == .tooHard }.count
        let total = ratedEntries.count

        let summaryText = deriveSummaryText(
            total: total,
            tooEasyCount: tooEasyCount,
            onTargetCount: onTargetCount,
            tooHardCount: tooHardCount,
            workout: workout,
            latestCheckIn: latestCheckIn
        )

        return SessionSummary(
            summaryText: summaryText,
            workoutDate: workout.date,
            hasEffortData: true,
            tooEasyCount: tooEasyCount,
            onTargetCount: onTargetCount,
            tooHardCount: tooHardCount
        )
    }

    // MARK: - Private

    private static func deriveSummaryText(
        total: Int,
        tooEasyCount: Int,
        onTargetCount: Int,
        tooHardCount: Int,
        workout: Workout,
        latestCheckIn: DailyCoachCheckIn?
    ) -> String {
        let majorityHard   = tooHardCount > total / 2
        let majorityEasy   = tooEasyCount > total / 2
        let allOnTarget    = onTargetCount == total
        let mostlyOnTarget = onTargetCount >= (total + 1) / 2

        // When a readiness check-in flagged low energy/fatigue and effort still
        // came out mostly on target, the modified session matched the readiness trim.
        let hadLowReadiness: Bool = {
            guard let checkIn = latestCheckIn else { return false }
            let checkInDay = Calendar.current.startOfDay(for: checkIn.date)
            let workoutDay = Calendar.current.startOfDay(for: workout.date)
            guard checkInDay == workoutDay else { return false }
            let composite = checkIn.sleepQuality + checkIn.energy
                + (6 - checkIn.soreness) + (6 - checkIn.stress)
            return composite <= 10   // roughly "low" readiness tier threshold
        }()

        if allOnTarget && hadLowReadiness {
            return "Session matched the readiness-based trim well."
        }

        if majorityHard {
            return "Primary work skewed too hard."
        }

        if majorityEasy {
            return "Session felt too easy overall."
        }

        if mostlyOnTarget {
            return "Last session was on target overall."
        }

        if tooHardCount > 0 && tooEasyCount == 0 {
            return "A few exercises were harder than expected."
        }

        if tooEasyCount > 0 && tooHardCount == 0 {
            return "Some exercises felt easy — consider progressing."
        }

        return "Session had mixed effort across exercises."
    }
}
