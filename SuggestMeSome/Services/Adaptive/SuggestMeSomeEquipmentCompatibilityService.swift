import Foundation

/// Equipment-compatibility filter for the SuggestMeSome generation pipeline.
///
/// Exercises are classified into equipment tags that mirror the `availableTags`
/// defined on `SuggestMeSomeEquipmentProfile`. An exercise is kept when at least
/// one of its required tags is present in the profile's available set.
struct SuggestMeSomeEquipmentCompatibilityService {
    func filterExercises(
        _ exercises: [Exercise],
        equipmentProfile: SuggestMeSomeEquipmentProfile?
    ) -> [Exercise] {
        guard let profile = equipmentProfile, profile != .fullGym else {
            return exercises
        }
        let available = profile.availableTags
        return exercises.filter { exercise in
            let required = requiredTags(for: exercise)
            return !required.isDisjoint(with: available)
        }
    }

    // MARK: - Tag resolution

    /// Returns the set of equipment tags that this exercise requires.
    /// An exercise is compatible when any required tag exists in the profile's available set.
    private func requiredTags(for exercise: Exercise) -> Set<String> {
        if exercise.exerciseType == .cardio {
            return cardioTags(for: exercise.name)
        }
        return strengthTags(for: exercise.name)
    }

    private func cardioTags(for exerciseName: String) -> Set<String> {
        let lower = exerciseName.lowercased()
        if lower.contains("jump rope") { return ["bodyweight", "cardio"] }
        // Exercise Bike, Elliptical, Treadmill, Stairmaster, Rowing Machine are machine-based
        return ["machine", "cardio"]
    }

    private func strengthTags(for exerciseName: String) -> Set<String> {
        let lower = exerciseName.lowercased()

        // --- Explicit equipment keyword in the name ---

        if lower.contains("cable") { return ["cable"] }

        if lower.contains("machine") || knownMachineNames.contains(lower) { return ["machine"] }

        if lower.contains("dumbbell") || lower.hasPrefix("db ") { return ["dumbbell"] }

        if lower.contains("barbell") || lower.contains("ez bar") { return ["barbell", "rack"] }

        // --- Named barbell-only exercises ---
        if knownBarbellExercises.contains(lower) { return ["barbell", "rack"] }

        // --- Named dumbbell-only exercises ---
        if knownDumbbellExercises.contains(lower) { return ["dumbbell"] }

        // --- Named cable-only exercises ---
        if knownCableExercises.contains(lower) { return ["cable"] }

        // --- Named bodyweight exercises ---
        if knownBodyweightExercises.contains(lower) || lower.contains("push-up") ||
            lower.contains("pull-up") || lower.contains("chin-up") || lower.contains("dip") {
            return ["bodyweight"]
        }

        // --- Default: assume barbell/full gym ---
        return ["barbell", "rack"]
    }

    // MARK: - Named exercise catalogs

    private let knownBarbellExercises: Set<String> = [
        // Chest
        "bench press", "incline bench", "floor press", "pause bench press",
        "close grip bench press",
        // Shoulders
        "overhead press", "barbell strict press",
        // Back
        "deadlift", "sumo deadlift", "deficit deadlift", "block pull",
        "pendlay row",
        // Legs
        "back squats", "front squat", "box squat", "pause squat", "sumo squat",
        "romanian deadlift", "good mornings", "hip thrust",
    ]

    private let knownDumbbellExercises: Set<String> = [
        "arnold press", "concentration curl", "incline dumbbell curl",
        "overhead tricep extension", "goblet squat",
    ]

    private let knownCableExercises: Set<String> = [
        "straight arm pulldown", "cable pull through", "pallof press",
        "lat pulldown", "cable crunch", "face pulls",
    ]

    private let knownBodyweightExercises: Set<String> = [
        "push-ups", "close grip push-ups", "plank", "weighted plank",
        "crunches", "bird dog", "dead bug", "glute bridge",
        "walking lunges", "bulgarian split squat",
        "pull-ups", "chin-ups", "dips", "chest dip",
    ]

    private let knownMachineNames: Set<String> = [
        "leg press", "hack squat", "pec deck machine fly", "seated calf raise",
        "machine shoulder press",
    ]
}
