import Foundation
import SwiftData

struct SuggestMeSomeExerciseSelectionGroup {
    let name: String
    let exercises: [Exercise]
}

struct SuggestMeSomeExerciseSelectionService {
    let timeBudgetService: SuggestMeSomeTimeBudgetService

    private func selectionScore(for exercise: Exercise) -> Int {
        switch exercise.exerciseType {
        case .compound: return 3
        case .accessory: return 2
        case .isolation: return 1
        case .cardio: return 0
        }
    }

    /// Shuffles pool then stable-sorts by score so compounds come first with random ordering
    /// within each tier. Greedily picks exercises until target duration is reached.
    /// Guarantees at least one compound if available in the pool.
    func selectStrengthExercises(
        from pool: [Exercise],
        targetMinutes: Double,
        intensity: Int
    ) -> [Exercise] {
        let eligible = pool.filter { $0.exerciseType != .cardio }
        guard !eligible.isEmpty else { return [] }

        let sorted = eligible.shuffled().sorted { selectionScore(for: $0) > selectionScore(for: $1) }

        var selected: [Exercise] = []
        var accumulatedTime = 0.0

        for exercise in sorted {
            let effectiveTime = timeBudgetService.effectiveTimeMinutes(for: exercise, intensity: intensity)
            if accumulatedTime + effectiveTime <= targetMinutes || selected.isEmpty {
                selected.append(exercise)
                accumulatedTime += effectiveTime
            }
            if accumulatedTime >= targetMinutes { break }
        }

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

    /// Full-body selection preserves the current two-phase behavior:
    /// 1) prioritize coverage of Legs/Chest/Back/Shoulders
    /// 2) fill remaining time from all non-cardio candidates
    func selectFullBodyExercises(
        nonCardioGroups: [SuggestMeSomeExerciseSelectionGroup],
        targetMinutes: Double,
        intensity: Int
    ) -> [Exercise] {
        let priorityGroupNames: [String] = ["legs", "chest", "back", "shoulders"]

        var selected: [Exercise] = []
        var selectedIDs: Set<PersistentIdentifier> = []
        var accumulatedTime = 0.0

        for groupName in priorityGroupNames.shuffled() {
            guard let group = nonCardioGroups.first(where: { $0.name.lowercased() == groupName }) else { continue }

            let candidates = group.exercises
                .filter { $0.exerciseType != .cardio }
                .shuffled()
                .sorted { selectionScore(for: $0) > selectionScore(for: $1) }

            guard let pick = candidates.first else { continue }
            let effectiveTime = timeBudgetService.effectiveTimeMinutes(for: pick, intensity: intensity)
            if accumulatedTime + effectiveTime <= targetMinutes {
                selected.append(pick)
                selectedIDs.insert(pick.persistentModelID)
                accumulatedTime += effectiveTime
            }
        }

        let allEligible = nonCardioGroups
            .flatMap { $0.exercises }
            .filter { $0.exerciseType != .cardio && !selectedIDs.contains($0.persistentModelID) }
            .shuffled()
            .sorted { selectionScore(for: $0) > selectionScore(for: $1) }

        for exercise in allEligible {
            let effectiveTime = timeBudgetService.effectiveTimeMinutes(for: exercise, intensity: intensity)
            if accumulatedTime + effectiveTime <= targetMinutes {
                selected.append(exercise)
                selectedIDs.insert(exercise.persistentModelID)
                accumulatedTime += effectiveTime
            }
            if accumulatedTime >= targetMinutes { break }
        }

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

        return selected
    }
}
