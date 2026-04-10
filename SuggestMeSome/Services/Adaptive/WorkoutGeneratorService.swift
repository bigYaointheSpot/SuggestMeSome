import Foundation
import SwiftData

// MARK: - Output Types

enum WorkoutGenerationType {
    case custom
    case fullBody
}

struct GeneratedSet {
    let setNumber: Int
    let isWarmup: Bool
    let suggestedReps: Int
    let suggestedWeight: Double?
    let unit: WeightUnit
}

struct GeneratedExercise {
    let exercise: Exercise
    let sets: [GeneratedSet]
    let effectiveTimeMinutes: Double
}

struct GeneratedWorkout {
    let exercises: [GeneratedExercise]
    let totalEstimatedMinutes: Double
    let intensity: Int
    let generationType: WorkoutGenerationType
}

// MARK: - Service

struct WorkoutGeneratorService {
    let context: ModelContext

    // MARK: - Intensity Helpers

    private func repRange(for intensity: Int) -> ClosedRange<Int> {
        switch intensity {
        case 1: return 10...12
        case 2: return 8...10
        case 3: return 6...8
        case 4: return 4...6
        case 5: return 3...5
        default: return 8...10
        }
    }

    private func targetReps(for intensity: Int) -> Int {
        Int.random(in: repRange(for: intensity))
    }

    /// Per-exercise time multiplier applied to baseTimeMinutes for budget calculations.
    /// Lower intensity → lighter weights → shorter rest → less time per exercise → more exercises fit (high volume).
    /// Higher intensity → heavier weights → longer rest → more time per exercise → fewer exercises fit (low volume).
    /// Maps: intensity 1 → 0.40x, intensity 3 → 0.50x, intensity 5 → 0.60x
    private func intensityFactor(for intensity: Int) -> Double {
        0.35 + Double(intensity) * 0.05
    }

    private func selectionScore(for exercise: Exercise) -> Int {
        switch exercise.exerciseType {
        case .compound:  return 3
        case .accessory: return 2
        case .isolation: return 1
        case .cardio:    return 0
        }
    }

    // MARK: - Personal Record Lookup

    private func personalRecord(for exercise: Exercise, repCount: Int) -> PersonalRecord? {
        let name = exercise.name
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseName == name && $0.repCount == repCount }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - Set Generation

    private func generateSets(for exercise: Exercise, intensity: Int) -> [GeneratedSet] {
        let reps = targetReps(for: intensity)

        guard let pr = personalRecord(for: exercise, repCount: reps) else {
            // No PR: generate warmup + working sets with no weight suggestion
            let warmups = (1...3).map { i in
                GeneratedSet(setNumber: i, isWarmup: true, suggestedReps: reps, suggestedWeight: nil, unit: .lbs)
            }
            let working = (1...4).map { i in
                GeneratedSet(setNumber: i, isWarmup: false, suggestedReps: reps, suggestedWeight: nil, unit: .lbs)
            }
            return warmups + working
        }

        let heavyWorkingWeight = pr.weight * (0.75 + Double(intensity) * 0.04)
        let unit = pr.unit

        let warmupPercentages: [Double] = [0.40, 0.55, 0.70]
        let workingPercentages: [Double] = [0.85, 0.90, 0.95, 1.00]

        let warmups = warmupPercentages.enumerated().map { (i, pct) in
            GeneratedSet(
                setNumber: i + 1,
                isWarmup: true,
                suggestedReps: reps,
                suggestedWeight: heavyWorkingWeight * pct,
                unit: unit
            )
        }
        let working = workingPercentages.enumerated().map { (i, pct) in
            GeneratedSet(
                setNumber: i + 1,
                isWarmup: false,
                suggestedReps: reps,
                suggestedWeight: heavyWorkingWeight * pct,
                unit: unit
            )
        }
        return warmups + working
    }

    private func generateExercise(_ exercise: Exercise, intensity: Int) -> GeneratedExercise {
        let sets = generateSets(for: exercise, intensity: intensity)
        let effectiveTime = Double(exercise.baseTimeMinutes) * intensityFactor(for: intensity)
        return GeneratedExercise(exercise: exercise, sets: sets, effectiveTimeMinutes: effectiveTime)
    }

    // MARK: - Greedy Exercise Selection

    /// Shuffles pool then stable-sorts by score so compounds come first with random ordering
    /// within each tier. Greedily picks exercises until the target duration is reached.
    /// Guarantees at least 1 compound if any compound exists in the pool.
    private func selectExercises(from pool: [Exercise], targetMinutes: Double, intensity: Int) -> [Exercise] {
        let eligible = pool.filter { $0.exerciseType != .cardio }
        guard !eligible.isEmpty else { return [] }

        // Shuffle for variety, then stable-sort by score so compounds surface first
        // while preserving the shuffled order within each score tier.
        let sorted = eligible.shuffled().sorted { selectionScore(for: $0) > selectionScore(for: $1) }

        let factor = intensityFactor(for: intensity)
        var selected: [Exercise] = []
        var accumulatedTime: Double = 0.0
        var selectedIDs: Set<PersistentIdentifier> = []

        for exercise in sorted {
            let effectiveTime = Double(exercise.baseTimeMinutes) * factor
            if accumulatedTime + effectiveTime <= targetMinutes || selected.isEmpty {
                selected.append(exercise)
                selectedIDs.insert(exercise.persistentModelID)
                accumulatedTime += effectiveTime
            }
            if accumulatedTime >= targetMinutes { break }
        }

        // Guarantee at least 1 compound movement
        let hasCompound = selected.contains { $0.exerciseType == .compound }
        if !hasCompound, let compound = sorted.first(where: { $0.exerciseType == .compound }) {
            if let replaceIdx = selected.indices.last(where: { selected[$0].exerciseType != .compound }) {
                selected[replaceIdx] = compound
            } else {
                selected.append(compound)
            }
        }

        return selected
    }

    // MARK: - Public API

    func generateCustomWorkout(
        muscleGroups: [MuscleGroup],
        selectedExercises: [Exercise],
        durationMinutes: Double,
        intensity: Int
    ) -> GeneratedWorkout {
        // Separate cardio from strength so they are handled independently.
        var seenIDs: Set<PersistentIdentifier> = []
        var strengthPool: [Exercise] = []
        var cardioPool: [Exercise] = []

        for group in muscleGroups {
            for exercise in group.exercises where !seenIDs.contains(exercise.persistentModelID) {
                if exercise.exerciseType == .cardio { cardioPool.append(exercise) }
                else                                { strengthPool.append(exercise) }
                seenIDs.insert(exercise.persistentModelID)
            }
        }
        for exercise in selectedExercises where !seenIDs.contains(exercise.persistentModelID) {
            if exercise.exerciseType == .cardio { cardioPool.append(exercise) }
            else                                { strengthPool.append(exercise) }
            seenIDs.insert(exercise.persistentModelID)
        }

        // Select strength exercises against the full time budget.
        let selectedStrength = selectExercises(from: strengthPool, targetMinutes: durationMinutes, intensity: intensity)
        var allExercises = selectedStrength.map { generateExercise($0, intensity: intensity) }
        let usedMinutes = allExercises.reduce(0.0) { $0 + $1.effectiveTimeMinutes }

        // If the Cardio group was included, append one randomly chosen cardio exercise
        // whose suggested duration equals the remaining time budget.
        if let cardioExercise = cardioPool.shuffled().first {
            let remaining = max(1.0, durationMinutes - usedMinutes)
            allExercises.append(GeneratedExercise(
                exercise: cardioExercise,
                sets: [],
                effectiveTimeMinutes: remaining
            ))
        }

        let totalTime = allExercises.reduce(0.0) { $0 + $1.effectiveTimeMinutes }
        return GeneratedWorkout(
            exercises: allExercises,
            totalEstimatedMinutes: totalTime,
            intensity: intensity,
            generationType: .custom
        )
    }

    func generateFullBodyWorkout(durationMinutes: Double, intensity: Int) -> GeneratedWorkout {
        let descriptor = FetchDescriptor<MuscleGroup>()
        let allGroups = (try? context.fetch(descriptor)) ?? []
        let nonCardioGroups = allGroups.filter { $0.name.lowercased() != "cardio" }

        let priorityGroupNames: [String] = ["legs", "chest", "back", "shoulders"]
        let factor = intensityFactor(for: intensity)

        var selected: [Exercise] = []
        var selectedIDs: Set<PersistentIdentifier> = []
        var accumulatedTime: Double = 0.0

        // Phase 1: Ensure at least 1 exercise from each priority group before doubling up.
        // Shuffle the priority list so the order changes each generation.
        for groupName in priorityGroupNames.shuffled() {
            guard let group = nonCardioGroups.first(where: { $0.name.lowercased() == groupName }) else { continue }

            // Within each group, prefer compounds then accessory then isolation
            let candidates = group.exercises
                .filter { $0.exerciseType != .cardio }
                .shuffled()
                .sorted { selectionScore(for: $0) > selectionScore(for: $1) }

            guard let pick = candidates.first else { continue }
            let effectiveTime = Double(pick.baseTimeMinutes) * factor
            if accumulatedTime + effectiveTime <= durationMinutes {
                selected.append(pick)
                selectedIDs.insert(pick.persistentModelID)
                accumulatedTime += effectiveTime
            }
        }

        // Phase 2: Fill remaining time from all non-cardio exercises, sorted by score.
        let allEligible = nonCardioGroups
            .flatMap { $0.exercises }
            .filter { $0.exerciseType != .cardio && !selectedIDs.contains($0.persistentModelID) }
            .shuffled()
            .sorted { selectionScore(for: $0) > selectionScore(for: $1) }

        for exercise in allEligible {
            let effectiveTime = Double(exercise.baseTimeMinutes) * factor
            if accumulatedTime + effectiveTime <= durationMinutes {
                selected.append(exercise)
                selectedIDs.insert(exercise.persistentModelID)
                accumulatedTime += effectiveTime
            }
            if accumulatedTime >= durationMinutes { break }
        }

        // Guarantee at least 1 compound if none was selected
        let hasCompound = selected.contains { $0.exerciseType == .compound }
        if !hasCompound {
            let allCompounds = nonCardioGroups
                .flatMap { $0.exercises }
                .filter { $0.exerciseType == .compound }
                .shuffled()
            if let compound = allCompounds.first {
                if let replaceIdx = selected.indices.last(where: { selected[$0].exerciseType != .compound }) {
                    selectedIDs.remove(selected[replaceIdx].persistentModelID)
                    selected[replaceIdx] = compound
                } else {
                    selected.append(compound)
                }
            }
        }

        let generatedExercises = selected.map { generateExercise($0, intensity: intensity) }
        let totalTime = generatedExercises.reduce(0.0) { $0 + $1.effectiveTimeMinutes }

        return GeneratedWorkout(
            exercises: generatedExercises,
            totalEstimatedMinutes: totalTime,
            intensity: intensity,
            generationType: .fullBody
        )
    }
}
