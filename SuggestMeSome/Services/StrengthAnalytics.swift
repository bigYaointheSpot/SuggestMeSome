//
//  StrengthAnalytics.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/7/26.
//

import Foundation

// MARK: - ChartPoint

struct ChartPoint: Identifiable {
    let id: UUID = UUID()
    let date: Date
    let exerciseName: String
    let e1RM: Double
}

// MARK: - StrengthAnalytics

enum StrengthAnalytics {

    /// Epley estimated one-rep max. Returns `weight` unchanged when reps == 1.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 1 else { return weight }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    /// Builds chart points for the given exercise names filtered to the time window.
    /// One point per workout per exercise = the best e1RM from any set in that session.
    static func chartPoints(
        for exerciseNames: [String],
        from workouts: [Workout],
        since cutoff: Date?
    ) -> [ChartPoint] {
        let source: [Workout]
        if let c = cutoff {
            source = workouts.filter { $0.date >= c }
        } else {
            source = workouts
        }

        var points: [ChartPoint] = []
        for workout in source {
            for name in exerciseNames {
                let best = workout.exerciseEntries
                    .filter { !$0.isCardio && $0.exerciseName == name }
                    .flatMap { $0.sets }
                    .filter { $0.reps > 0 && $0.weight > 0 }
                    .map { estimatedOneRepMax(weight: $0.weight, reps: $0.reps) }
                    .max()
                if let best {
                    points.append(ChartPoint(date: workout.date, exerciseName: name, e1RM: best))
                }
            }
        }
        return points.sorted { $0.date < $1.date }
    }

    /// Finds the previous best weight (in the same unit) for an exercise+repCount
    /// across all workouts strictly before `date`. Returns nil if no prior data exists.
    static func previousBest(
        exerciseName: String,
        repCount: Int,
        unit: WeightUnit,
        before date: Date,
        workouts: [Workout]
    ) -> Double? {
        var best: Double? = nil
        for workout in workouts where workout.date < date {
            for entry in workout.exerciseEntries
                where entry.exerciseName == exerciseName && entry.unit == unit {
                for set in entry.sets where set.reps == repCount && set.weight > 0 {
                    if best == nil || set.weight > best! {
                        best = set.weight
                    }
                }
            }
        }
        return best
    }
}
