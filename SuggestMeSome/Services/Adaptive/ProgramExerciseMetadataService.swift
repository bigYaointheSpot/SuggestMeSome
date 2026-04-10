//
//  ProgramExerciseMetadataService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation

enum ProgramVolumeMuscle: String, CaseIterable, Codable {
    case chest
    case upperBackLats
    case quads
    case hamstrings
    case glutes
    case shoulders
    case biceps
    case triceps
    case calves
    case abs

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .upperBackLats: return "Upper Back/Lats"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .calves: return "Calves"
        case .abs: return "Abs"
        }
    }
}

enum ExerciseFatigueTier: String, Codable {
    case high
    case medium
    case low

    var baseScorePerSet: Double {
        switch self {
        case .high: return 3.1
        case .medium: return 2.0
        case .low: return 1.0
        }
    }

    var highFatigueWeight: Double {
        switch self {
        case .high: return 1.0
        case .medium: return 0.35
        case .low: return 0.1
        }
    }
}

struct ProgramExerciseMetadata {
    let muscleContributions: [ProgramVolumeMuscle: Double]
    let defaultFatigueTier: ExerciseFatigueTier
}

struct ProgramWeeklyTargetRange {
    let minHardSets: Double
    let maxHardSets: Double
}

struct ProgramWeeklyVolumeTargets {
    let ranges: [ProgramVolumeMuscle: ProgramWeeklyTargetRange]

    func range(for muscle: ProgramVolumeMuscle) -> ProgramWeeklyTargetRange {
        ranges[muscle] ?? ProgramWeeklyTargetRange(minHardSets: 0, maxHardSets: 0)
    }
}

struct ProgramFatigueBudgets {
    let weekBudget: Double
    let sessionBudget: Double
    let deadliftSessionBudget: Double
    let adjacentSessionPairBudget: Double
}

enum ProgramExerciseMetadataService {
    private struct FocusFatigueProfile {
        let baseWeekBudget: Double
        let deadliftSessionScale: Double
        let adjacentSessionPairScale: Double
    }

    private struct FocusVolumeFatigueProfile {
        let volumeRanges: [ProgramVolumeMuscle: ProgramWeeklyTargetRange]
        let fatigue: FocusFatigueProfile
        let minimumMuscleHardSets: Double
    }

    static func metadata(for exerciseName: String) -> ProgramExerciseMetadata {
        if let exact = exerciseMetadata[exerciseName] {
            return exact
        }
        return heuristicMetadata(for: exerciseName)
    }

    static func fatigueTier(
        for exerciseName: String,
        role: ExerciseRole,
        maxPercentage1RM: Double?,
        minReps: Int,
        hasTopSet: Bool
    ) -> ExerciseFatigueTier {
        let base = metadata(for: exerciseName).defaultFatigueTier

        if role != .cardio,
           (hasTopSet ||
            (maxPercentage1RM ?? 0) >= 0.82 ||
            minReps <= 5),
           base != .low {
            return .high
        }

        if role == .primary,
           (maxPercentage1RM ?? 0) >= 0.78,
           minReps <= 8,
           base == .medium {
            return .high
        }

        return base
    }

    static func weeklyVolumeTargets(focus: ProgramFocus, level: ProgramLevel) -> ProgramWeeklyVolumeTargets {
        let profile = focusVolumeFatigueProfile(for: focus)
        let levelScale = volumeLevelScale(for: level, focus: focus)

        let ranges = Dictionary(uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map { muscle in
            let r = profile.volumeRanges[muscle] ?? ProgramWeeklyTargetRange(minHardSets: 6, maxHardSets: 10)
            let minSets = max(profile.minimumMuscleHardSets, (r.minHardSets * levelScale).rounded())
            let maxSets = max(minSets, (r.maxHardSets * levelScale).rounded())
            return (muscle, ProgramWeeklyTargetRange(minHardSets: minSets, maxHardSets: maxSets))
        })

        return ProgramWeeklyVolumeTargets(ranges: ranges)
    }

    static func fatigueBudgets(
        focus: ProgramFocus,
        level: ProgramLevel,
        sessionsPerWeek: Int
    ) -> ProgramFatigueBudgets {
        let profile = focusVolumeFatigueProfile(for: focus)

        let levelScale: Double
        switch level {
        case .beginner: levelScale = 0.90
        case .intermediate: levelScale = 1.00
        case .advanced: levelScale = 1.07
        }

        let frequencyScale: Double
        switch sessionsPerWeek {
        case 2: frequencyScale = 0.92
        case 3: frequencyScale = 0.97
        case 4: frequencyScale = 1.00
        case 5: frequencyScale = 1.04
        case 6: frequencyScale = 1.08
        default: frequencyScale = 1.00
        }

        let weeklyBudget = profile.fatigue.baseWeekBudget * levelScale * frequencyScale
        let sessionBudget = (weeklyBudget / Double(max(1, sessionsPerWeek))) * 1.28

        return ProgramFatigueBudgets(
            weekBudget: weeklyBudget,
            sessionBudget: sessionBudget,
            deadliftSessionBudget: sessionBudget * profile.fatigue.deadliftSessionScale,
            adjacentSessionPairBudget: sessionBudget * profile.fatigue.adjacentSessionPairScale
        )
    }

    private static func volumeLevelScale(for level: ProgramLevel, focus: ProgramFocus) -> Double {
        switch focus {
        case .cardioEndurance:
            return 1.00
        case .bodybuilding:
            switch level {
            case .beginner: return 0.86
            case .intermediate: return 1.00
            case .advanced: return 1.10
            }
        case .fullBody:
            switch level {
            case .beginner: return 0.88
            case .intermediate: return 1.00
            case .advanced: return 1.05
            }
        case .increaseMaxSquat, .increaseMaxBench, .increaseMaxDeadlift, .powerlifting, .fiveByFive:
            switch level {
            case .beginner: return 0.90
            case .intermediate: return 1.00
            case .advanced: return 1.06
            }
        default:
            switch level {
            case .beginner: return 0.90
            case .intermediate: return 1.00
            case .advanced: return 1.10
            }
        }
    }

    private static func focusVolumeFatigueProfile(for focus: ProgramFocus) -> FocusVolumeFatigueProfile {
        switch focus {
        case .increaseMaxSquat:
            return .init(
                volumeRanges: [
                    .chest: .init(minHardSets: 4, maxHardSets: 8),
                    .upperBackLats: .init(minHardSets: 8, maxHardSets: 14),
                    .quads: .init(minHardSets: 10, maxHardSets: 16),
                    .hamstrings: .init(minHardSets: 8, maxHardSets: 14),
                    .glutes: .init(minHardSets: 8, maxHardSets: 14),
                    .shoulders: .init(minHardSets: 3, maxHardSets: 8),
                    .biceps: .init(minHardSets: 2, maxHardSets: 6),
                    .triceps: .init(minHardSets: 3, maxHardSets: 8),
                    .calves: .init(minHardSets: 2, maxHardSets: 6),
                    .abs: .init(minHardSets: 6, maxHardSets: 12),
                ],
                fatigue: .init(baseWeekBudget: 88, deadliftSessionScale: 0.82, adjacentSessionPairScale: 1.60),
                minimumMuscleHardSets: 2
            )
        case .increaseMaxBench:
            return .init(
                volumeRanges: [
                    .chest: .init(minHardSets: 10, maxHardSets: 16),
                    .upperBackLats: .init(minHardSets: 8, maxHardSets: 14),
                    .quads: .init(minHardSets: 4, maxHardSets: 8),
                    .hamstrings: .init(minHardSets: 4, maxHardSets: 8),
                    .glutes: .init(minHardSets: 4, maxHardSets: 8),
                    .shoulders: .init(minHardSets: 8, maxHardSets: 14),
                    .biceps: .init(minHardSets: 4, maxHardSets: 8),
                    .triceps: .init(minHardSets: 8, maxHardSets: 14),
                    .calves: .init(minHardSets: 2, maxHardSets: 6),
                    .abs: .init(minHardSets: 4, maxHardSets: 10),
                ],
                fatigue: .init(baseWeekBudget: 89, deadliftSessionScale: 0.84, adjacentSessionPairScale: 1.64),
                minimumMuscleHardSets: 2
            )
        case .increaseMaxDeadlift:
            return .init(
                volumeRanges: [
                    .chest: .init(minHardSets: 4, maxHardSets: 8),
                    .upperBackLats: .init(minHardSets: 10, maxHardSets: 16),
                    .quads: .init(minHardSets: 6, maxHardSets: 12),
                    .hamstrings: .init(minHardSets: 10, maxHardSets: 16),
                    .glutes: .init(minHardSets: 10, maxHardSets: 16),
                    .shoulders: .init(minHardSets: 3, maxHardSets: 8),
                    .biceps: .init(minHardSets: 2, maxHardSets: 6),
                    .triceps: .init(minHardSets: 3, maxHardSets: 8),
                    .calves: .init(minHardSets: 2, maxHardSets: 6),
                    .abs: .init(minHardSets: 6, maxHardSets: 12),
                ],
                fatigue: .init(baseWeekBudget: 87, deadliftSessionScale: 0.78, adjacentSessionPairScale: 1.56),
                minimumMuscleHardSets: 2
            )
        case .powerlifting:
            return .init(
                volumeRanges: [
                    .chest: .init(minHardSets: 6, maxHardSets: 12),
                    .upperBackLats: .init(minHardSets: 8, maxHardSets: 14),
                    .quads: .init(minHardSets: 8, maxHardSets: 14),
                    .hamstrings: .init(minHardSets: 6, maxHardSets: 12),
                    .glutes: .init(minHardSets: 6, maxHardSets: 12),
                    .shoulders: .init(minHardSets: 4, maxHardSets: 10),
                    .biceps: .init(minHardSets: 2, maxHardSets: 8),
                    .triceps: .init(minHardSets: 4, maxHardSets: 10),
                    .calves: .init(minHardSets: 2, maxHardSets: 8),
                    .abs: .init(minHardSets: 4, maxHardSets: 10),
                ],
                fatigue: .init(baseWeekBudget: 92, deadliftSessionScale: 0.82, adjacentSessionPairScale: 1.62),
                minimumMuscleHardSets: 2
            )
        case .fiveByFive:
            return .init(
                volumeRanges: [
                    .chest: .init(minHardSets: 6, maxHardSets: 10),
                    .upperBackLats: .init(minHardSets: 8, maxHardSets: 12),
                    .quads: .init(minHardSets: 8, maxHardSets: 12),
                    .hamstrings: .init(minHardSets: 6, maxHardSets: 10),
                    .glutes: .init(minHardSets: 6, maxHardSets: 10),
                    .shoulders: .init(minHardSets: 4, maxHardSets: 8),
                    .biceps: .init(minHardSets: 2, maxHardSets: 5),
                    .triceps: .init(minHardSets: 3, maxHardSets: 7),
                    .calves: .init(minHardSets: 2, maxHardSets: 5),
                    .abs: .init(minHardSets: 4, maxHardSets: 8),
                ],
                fatigue: .init(baseWeekBudget: 84, deadliftSessionScale: 0.80, adjacentSessionPairScale: 1.54),
                minimumMuscleHardSets: 2
            )
        case .powerbuilding:
            return .init(
                volumeRanges: [
                    .chest: .init(minHardSets: 10, maxHardSets: 18),
                    .upperBackLats: .init(minHardSets: 12, maxHardSets: 20),
                    .quads: .init(minHardSets: 10, maxHardSets: 18),
                    .hamstrings: .init(minHardSets: 8, maxHardSets: 16),
                    .glutes: .init(minHardSets: 8, maxHardSets: 16),
                    .shoulders: .init(minHardSets: 8, maxHardSets: 16),
                    .biceps: .init(minHardSets: 6, maxHardSets: 14),
                    .triceps: .init(minHardSets: 6, maxHardSets: 14),
                    .calves: .init(minHardSets: 6, maxHardSets: 14),
                    .abs: .init(minHardSets: 6, maxHardSets: 14),
                ],
                fatigue: .init(baseWeekBudget: 98, deadliftSessionScale: 0.85, adjacentSessionPairScale: 1.72),
                minimumMuscleHardSets: 2
            )
        case .bodybuilding:
            return .init(
                volumeRanges: [
                    .chest: .init(minHardSets: 12, maxHardSets: 22),
                    .upperBackLats: .init(minHardSets: 14, maxHardSets: 24),
                    .quads: .init(minHardSets: 12, maxHardSets: 22),
                    .hamstrings: .init(minHardSets: 10, maxHardSets: 20),
                    .glutes: .init(minHardSets: 10, maxHardSets: 20),
                    .shoulders: .init(minHardSets: 12, maxHardSets: 22),
                    .biceps: .init(minHardSets: 8, maxHardSets: 18),
                    .triceps: .init(minHardSets: 8, maxHardSets: 18),
                    .calves: .init(minHardSets: 8, maxHardSets: 18),
                    .abs: .init(minHardSets: 8, maxHardSets: 16),
                ],
                fatigue: .init(baseWeekBudget: 104, deadliftSessionScale: 0.90, adjacentSessionPairScale: 1.86),
                minimumMuscleHardSets: 2
            )
        case .generalFitness:
            return .init(
                volumeRanges: [
                    .chest: .init(minHardSets: 8, maxHardSets: 14),
                    .upperBackLats: .init(minHardSets: 8, maxHardSets: 16),
                    .quads: .init(minHardSets: 8, maxHardSets: 14),
                    .hamstrings: .init(minHardSets: 6, maxHardSets: 12),
                    .glutes: .init(minHardSets: 6, maxHardSets: 12),
                    .shoulders: .init(minHardSets: 6, maxHardSets: 12),
                    .biceps: .init(minHardSets: 4, maxHardSets: 10),
                    .triceps: .init(minHardSets: 4, maxHardSets: 10),
                    .calves: .init(minHardSets: 4, maxHardSets: 10),
                    .abs: .init(minHardSets: 6, maxHardSets: 12),
                ],
                fatigue: .init(baseWeekBudget: 90, deadliftSessionScale: 0.84, adjacentSessionPairScale: 1.68),
                minimumMuscleHardSets: 2
            )
        case .fullBody:
            return .init(
                volumeRanges: [
                    .chest: .init(minHardSets: 8, maxHardSets: 16),
                    .upperBackLats: .init(minHardSets: 10, maxHardSets: 18),
                    .quads: .init(minHardSets: 8, maxHardSets: 16),
                    .hamstrings: .init(minHardSets: 8, maxHardSets: 14),
                    .glutes: .init(minHardSets: 8, maxHardSets: 14),
                    .shoulders: .init(minHardSets: 6, maxHardSets: 12),
                    .biceps: .init(minHardSets: 4, maxHardSets: 10),
                    .triceps: .init(minHardSets: 4, maxHardSets: 10),
                    .calves: .init(minHardSets: 4, maxHardSets: 10),
                    .abs: .init(minHardSets: 4, maxHardSets: 10),
                ],
                fatigue: .init(baseWeekBudget: 88, deadliftSessionScale: 0.82, adjacentSessionPairScale: 1.56),
                minimumMuscleHardSets: 2
            )
        case .pushPull:
            return .init(
                volumeRanges: [
                    .chest: .init(minHardSets: 10, maxHardSets: 16),
                    .upperBackLats: .init(minHardSets: 12, maxHardSets: 18),
                    .quads: .init(minHardSets: 5, maxHardSets: 10),
                    .hamstrings: .init(minHardSets: 5, maxHardSets: 10),
                    .glutes: .init(minHardSets: 5, maxHardSets: 10),
                    .shoulders: .init(minHardSets: 8, maxHardSets: 14),
                    .biceps: .init(minHardSets: 8, maxHardSets: 14),
                    .triceps: .init(minHardSets: 8, maxHardSets: 14),
                    .calves: .init(minHardSets: 3, maxHardSets: 8),
                    .abs: .init(minHardSets: 5, maxHardSets: 10),
                ],
                fatigue: .init(baseWeekBudget: 94, deadliftSessionScale: 0.86, adjacentSessionPairScale: 1.74),
                minimumMuscleHardSets: 2
            )
        case .cardioEndurance:
            // Cardio plans should not be biased by resistance-training hard-set assumptions.
            return .init(
                volumeRanges: Dictionary(
                    uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map {
                        ($0, ProgramWeeklyTargetRange(minHardSets: 0, maxHardSets: 0))
                    }
                ),
                fatigue: .init(baseWeekBudget: 72, deadliftSessionScale: 0.95, adjacentSessionPairScale: 1.95),
                minimumMuscleHardSets: 0
            )
        }
    }

    private static func heuristicMetadata(for exerciseName: String) -> ProgramExerciseMetadata {
        let lower = exerciseName.lowercased()

        if lower.contains("curl") {
            return .init(muscleContributions: contribution(.biceps, 1.0), defaultFatigueTier: .low)
        }

        if lower.contains("tricep") || lower.contains("skull") || lower.contains("kickback") {
            return .init(muscleContributions: contribution(.triceps, 1.0), defaultFatigueTier: .low)
        }

        if lower.contains("press") {
            return .init(
                muscleContributions: contribution(.chest, 0.75, .shoulders, 0.55, .triceps, 0.55),
                defaultFatigueTier: .medium
            )
        }

        if lower.contains("row") || lower.contains("pull") {
            return .init(
                muscleContributions: contribution(.upperBackLats, 1.0, .biceps, 0.55),
                defaultFatigueTier: .medium
            )
        }

        if lower.contains("squat") || lower.contains("lunge") || lower.contains("leg") {
            return .init(
                muscleContributions: contribution(.quads, 0.9, .glutes, 0.6, .hamstrings, 0.3),
                defaultFatigueTier: .medium
            )
        }

        if lower.contains("dead") || lower.contains("hip") || lower.contains("glute") {
            return .init(
                muscleContributions: contribution(.hamstrings, 0.9, .glutes, 0.9, .upperBackLats, 0.4),
                defaultFatigueTier: .medium
            )
        }

        if lower.contains("calf") {
            return .init(muscleContributions: contribution(.calves, 1.0), defaultFatigueTier: .low)
        }

        if lower.contains("ab") || lower.contains("crunch") || lower.contains("pallof") || lower.contains("bug") {
            return .init(muscleContributions: contribution(.abs, 1.0), defaultFatigueTier: .low)
        }

        if lower.contains("bike") || lower.contains("treadmill") || lower.contains("elliptical") || lower.contains("stair") || lower.contains("jump rope") || lower.contains("rowing") {
            return .init(muscleContributions: [:], defaultFatigueTier: .low)
        }

        return .init(muscleContributions: [:], defaultFatigueTier: .low)
    }

    private static func contribution(
        _ a: ProgramVolumeMuscle, _ av: Double,
        _ b: ProgramVolumeMuscle? = nil, _ bv: Double = 0,
        _ c: ProgramVolumeMuscle? = nil, _ cv: Double = 0,
        _ d: ProgramVolumeMuscle? = nil, _ dv: Double = 0,
        _ e: ProgramVolumeMuscle? = nil, _ ev: Double = 0
    ) -> [ProgramVolumeMuscle: Double] {
        var result: [ProgramVolumeMuscle: Double] = [a: av]
        if let b { result[b] = bv }
        if let c { result[c] = cv }
        if let d { result[d] = dv }
        if let e { result[e] = ev }
        return result
    }

    private static let exerciseMetadata: [String: ProgramExerciseMetadata] = [
        // Squat and quad dominant
        "Back Squats": .init(
            muscleContributions: contribution(.quads, 1.0, .glutes, 0.75, .hamstrings, 0.40, .abs, 0.25),
            defaultFatigueTier: .high
        ),
        "Pause Squat": .init(
            muscleContributions: contribution(.quads, 1.0, .glutes, 0.70, .hamstrings, 0.40, .abs, 0.30),
            defaultFatigueTier: .high
        ),
        "Front Squat": .init(
            muscleContributions: contribution(.quads, 1.0, .glutes, 0.55, .hamstrings, 0.25, .abs, 0.35),
            defaultFatigueTier: .high
        ),
        "Box Squat": .init(
            muscleContributions: contribution(.quads, 0.85, .glutes, 0.85, .hamstrings, 0.45, .abs, 0.25),
            defaultFatigueTier: .high
        ),
        "Hack Squat": .init(
            muscleContributions: contribution(.quads, 1.0, .glutes, 0.55),
            defaultFatigueTier: .medium
        ),
        "Leg Press": .init(
            muscleContributions: contribution(.quads, 1.0, .glutes, 0.60),
            defaultFatigueTier: .medium
        ),
        "Leg Extension": .init(
            muscleContributions: contribution(.quads, 1.0),
            defaultFatigueTier: .low
        ),
        "Bulgarian Split Squat": .init(
            muscleContributions: contribution(.quads, 0.85, .glutes, 0.85, .hamstrings, 0.30, .abs, 0.20),
            defaultFatigueTier: .medium
        ),
        "Walking Lunges": .init(
            muscleContributions: contribution(.quads, 0.80, .glutes, 0.85, .hamstrings, 0.35, .abs, 0.20),
            defaultFatigueTier: .medium
        ),
        "Goblet Squat": .init(
            muscleContributions: contribution(.quads, 0.75, .glutes, 0.55, .hamstrings, 0.25, .abs, 0.20),
            defaultFatigueTier: .medium
        ),

        // Deadlift and posterior chain
        "Deadlift": .init(
            muscleContributions: contribution(.hamstrings, 1.0, .glutes, 1.0, .upperBackLats, 0.60, .quads, 0.40, .abs, 0.40),
            defaultFatigueTier: .high
        ),
        "Sumo Deadlift": .init(
            muscleContributions: contribution(.glutes, 1.0, .hamstrings, 0.80, .quads, 0.60, .upperBackLats, 0.50, .abs, 0.35),
            defaultFatigueTier: .high
        ),
        "Deficit Deadlift": .init(
            muscleContributions: contribution(.hamstrings, 1.0, .glutes, 1.0, .quads, 0.50, .upperBackLats, 0.60, .abs, 0.40),
            defaultFatigueTier: .high
        ),
        "Block Pull": .init(
            muscleContributions: contribution(.glutes, 0.85, .hamstrings, 0.85, .upperBackLats, 0.70, .abs, 0.30),
            defaultFatigueTier: .high
        ),
        "Romanian Deadlift": .init(
            muscleContributions: contribution(.hamstrings, 1.0, .glutes, 0.80, .upperBackLats, 0.35),
            defaultFatigueTier: .medium
        ),
        "Good Mornings": .init(
            muscleContributions: contribution(.hamstrings, 0.90, .glutes, 0.65, .abs, 0.30),
            defaultFatigueTier: .medium
        ),
        "Hip Thrust": .init(
            muscleContributions: contribution(.glutes, 1.0, .hamstrings, 0.40),
            defaultFatigueTier: .medium
        ),
        "Glute Bridge": .init(
            muscleContributions: contribution(.glutes, 1.0, .hamstrings, 0.35),
            defaultFatigueTier: .low
        ),
        "Cable Pull Through": .init(
            muscleContributions: contribution(.glutes, 0.90, .hamstrings, 0.50),
            defaultFatigueTier: .low
        ),
        "Leg Curl": .init(
            muscleContributions: contribution(.hamstrings, 1.0),
            defaultFatigueTier: .low
        ),

        // Chest / press
        "Bench Press": .init(
            muscleContributions: contribution(.chest, 1.0, .triceps, 0.60, .shoulders, 0.40),
            defaultFatigueTier: .high
        ),
        "Pause Bench Press": .init(
            muscleContributions: contribution(.chest, 1.0, .triceps, 0.60, .shoulders, 0.40),
            defaultFatigueTier: .high
        ),
        "Close Grip Bench Press": .init(
            muscleContributions: contribution(.chest, 0.60, .triceps, 0.90, .shoulders, 0.30),
            defaultFatigueTier: .high
        ),
        "Floor Press": .init(
            muscleContributions: contribution(.chest, 0.75, .triceps, 0.85, .shoulders, 0.30),
            defaultFatigueTier: .high
        ),
        "Incline Bench": .init(
            muscleContributions: contribution(.chest, 0.85, .shoulders, 0.60, .triceps, 0.50),
            defaultFatigueTier: .medium
        ),
        "Dumbbell Bench Press": .init(
            muscleContributions: contribution(.chest, 1.0, .triceps, 0.55, .shoulders, 0.40),
            defaultFatigueTier: .medium
        ),
        "Incline Dumbbell Press": .init(
            muscleContributions: contribution(.chest, 0.85, .shoulders, 0.60, .triceps, 0.50),
            defaultFatigueTier: .medium
        ),
        "Chest Dip": .init(
            muscleContributions: contribution(.chest, 0.85, .triceps, 0.85, .shoulders, 0.35),
            defaultFatigueTier: .medium
        ),
        "Dips": .init(
            muscleContributions: contribution(.chest, 0.70, .triceps, 0.85, .shoulders, 0.35),
            defaultFatigueTier: .medium
        ),
        "Cable Flyes": .init(
            muscleContributions: contribution(.chest, 1.0, .shoulders, 0.20),
            defaultFatigueTier: .low
        ),
        "Dumbbell Flyes": .init(
            muscleContributions: contribution(.chest, 1.0, .shoulders, 0.25),
            defaultFatigueTier: .low
        ),
        "Pec Deck Machine Fly": .init(
            muscleContributions: contribution(.chest, 1.0),
            defaultFatigueTier: .low
        ),

        // Shoulders
        "Overhead Press": .init(
            muscleContributions: contribution(.shoulders, 1.0, .triceps, 0.65, .upperBackLats, 0.20),
            defaultFatigueTier: .medium
        ),
        "Barbell Strict Press": .init(
            muscleContributions: contribution(.shoulders, 1.0, .triceps, 0.65, .upperBackLats, 0.20),
            defaultFatigueTier: .medium
        ),
        "DB Shoulder Press": .init(
            muscleContributions: contribution(.shoulders, 1.0, .triceps, 0.60),
            defaultFatigueTier: .medium
        ),
        "Arnold Press": .init(
            muscleContributions: contribution(.shoulders, 1.0, .triceps, 0.55),
            defaultFatigueTier: .medium
        ),
        "Machine Shoulder Press": .init(
            muscleContributions: contribution(.shoulders, 1.0, .triceps, 0.55),
            defaultFatigueTier: .low
        ),
        "Lateral Raises": .init(
            muscleContributions: contribution(.shoulders, 1.0),
            defaultFatigueTier: .low
        ),
        "Cable Lateral Raise": .init(
            muscleContributions: contribution(.shoulders, 1.0),
            defaultFatigueTier: .low
        ),
        "Front Raises": .init(
            muscleContributions: contribution(.shoulders, 1.0),
            defaultFatigueTier: .low
        ),
        "Face Pulls": .init(
            muscleContributions: contribution(.shoulders, 0.70, .upperBackLats, 0.70),
            defaultFatigueTier: .low
        ),
        "Reverse Flyes": .init(
            muscleContributions: contribution(.shoulders, 0.70, .upperBackLats, 0.70),
            defaultFatigueTier: .low
        ),

        // Pulling / back
        "Barbell Row": .init(
            muscleContributions: contribution(.upperBackLats, 1.0, .biceps, 0.55, .hamstrings, 0.20),
            defaultFatigueTier: .medium
        ),
        "Pendlay Row": .init(
            muscleContributions: contribution(.upperBackLats, 1.0, .biceps, 0.55, .hamstrings, 0.20),
            defaultFatigueTier: .medium
        ),
        "T-Bar Row": .init(
            muscleContributions: contribution(.upperBackLats, 1.0, .biceps, 0.60),
            defaultFatigueTier: .medium
        ),
        "Dumbbell Row": .init(
            muscleContributions: contribution(.upperBackLats, 1.0, .biceps, 0.55),
            defaultFatigueTier: .medium
        ),
        "Seated Cable Row": .init(
            muscleContributions: contribution(.upperBackLats, 1.0, .biceps, 0.55),
            defaultFatigueTier: .low
        ),
        "Lat Pulldown": .init(
            muscleContributions: contribution(.upperBackLats, 1.0, .biceps, 0.65),
            defaultFatigueTier: .low
        ),
        "Straight Arm Pulldown": .init(
            muscleContributions: contribution(.upperBackLats, 1.0),
            defaultFatigueTier: .low
        ),
        "Pull-ups": .init(
            muscleContributions: contribution(.upperBackLats, 1.0, .biceps, 0.70),
            defaultFatigueTier: .medium
        ),
        "Chin-ups": .init(
            muscleContributions: contribution(.upperBackLats, 0.90, .biceps, 0.85),
            defaultFatigueTier: .medium
        ),

        // Arms
        "Barbell Curl": .init(
            muscleContributions: contribution(.biceps, 1.0),
            defaultFatigueTier: .low
        ),
        "EZ Bar Curl": .init(
            muscleContributions: contribution(.biceps, 1.0),
            defaultFatigueTier: .low
        ),
        "Hammer Curl": .init(
            muscleContributions: contribution(.biceps, 1.0),
            defaultFatigueTier: .low
        ),
        "Preacher Curl": .init(
            muscleContributions: contribution(.biceps, 1.0),
            defaultFatigueTier: .low
        ),
        "Concentration Curl": .init(
            muscleContributions: contribution(.biceps, 1.0),
            defaultFatigueTier: .low
        ),
        "Cable Curl": .init(
            muscleContributions: contribution(.biceps, 1.0),
            defaultFatigueTier: .low
        ),
        "Incline Dumbbell Curl": .init(
            muscleContributions: contribution(.biceps, 1.0),
            defaultFatigueTier: .low
        ),

        "Tricep Pushdown": .init(
            muscleContributions: contribution(.triceps, 1.0),
            defaultFatigueTier: .low
        ),
        "Skull Crushers": .init(
            muscleContributions: contribution(.triceps, 1.0),
            defaultFatigueTier: .low
        ),
        "Overhead Tricep Extension": .init(
            muscleContributions: contribution(.triceps, 1.0),
            defaultFatigueTier: .low
        ),
        "Cable Tricep Kickback": .init(
            muscleContributions: contribution(.triceps, 1.0),
            defaultFatigueTier: .low
        ),
        "Close Grip Push-ups": .init(
            muscleContributions: contribution(.triceps, 0.90, .chest, 0.45, .shoulders, 0.20),
            defaultFatigueTier: .low
        ),

        // Calves / abs
        "Calf Raises": .init(
            muscleContributions: contribution(.calves, 1.0),
            defaultFatigueTier: .low
        ),
        "Seated Calf Raise": .init(
            muscleContributions: contribution(.calves, 1.0),
            defaultFatigueTier: .low
        ),
        "Ab Rollout": .init(
            muscleContributions: contribution(.abs, 1.0),
            defaultFatigueTier: .low
        ),
        "Hanging Leg Raises": .init(
            muscleContributions: contribution(.abs, 1.0),
            defaultFatigueTier: .low
        ),
        "Cable Crunch": .init(
            muscleContributions: contribution(.abs, 1.0),
            defaultFatigueTier: .low
        ),
        "Pallof Press": .init(
            muscleContributions: contribution(.abs, 1.0),
            defaultFatigueTier: .low
        ),
        "Dead Bug": .init(
            muscleContributions: contribution(.abs, 1.0),
            defaultFatigueTier: .low
        ),

        // Cardio
        "Treadmill": .init(muscleContributions: [:], defaultFatigueTier: .low),
        "Incline Treadmill": .init(muscleContributions: [:], defaultFatigueTier: .low),
        "Exercise Bike": .init(muscleContributions: [:], defaultFatigueTier: .low),
        "Rowing Machine": .init(muscleContributions: [:], defaultFatigueTier: .low),
        "Stairmaster": .init(muscleContributions: [:], defaultFatigueTier: .low),
        "Elliptical": .init(muscleContributions: [:], defaultFatigueTier: .low),
        "Jump Rope": .init(muscleContributions: [:], defaultFatigueTier: .low),
    ]
}
