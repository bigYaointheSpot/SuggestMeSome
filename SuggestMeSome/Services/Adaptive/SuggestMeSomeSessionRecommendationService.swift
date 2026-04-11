import Foundation

/// Builds an intermediate recommendation from per-session inputs before final workout construction.
struct SuggestMeSomeSessionRecommendationService {

    func recommendSession(
        configuration: SuggestMeSomeSessionConfiguration,
        allMuscleGroups: [MuscleGroup]
    ) -> SuggestMeSomeSessionRecommendation {
        let resolvedMode = resolveMode(for: configuration.mode)
        let adjustedIntensity = adjustedIntensity(for: configuration)

        let request = SuggestMeSomeGenerationRequest(
            generationType: generationType(for: resolvedMode),
            durationMinutes: Double(configuration.durationMinutes),
            intensity: adjustedIntensity,
            selectedMuscleGroups: selectedGroups(for: resolvedMode, allMuscleGroups: allMuscleGroups),
            selectedExercises: [],
            goal: configuration.goal,
            equipmentProfile: configuration.equipmentProfile
        )

        let title = "\(resolvedMode.title) \(configuration.goal.title) Session"
        let rationale = rationaleText(
            mode: resolvedMode,
            goal: configuration.goal,
            equipmentProfile: configuration.equipmentProfile,
            intensity: adjustedIntensity,
            durationMinutes: configuration.durationMinutes
        )

        return SuggestMeSomeSessionRecommendation(title: title, rationale: rationale, request: request)
    }

    private func resolveMode(for mode: SuggestMeSomeSessionMode) -> SuggestMeSomeSessionMode {
        guard mode == .surpriseMe else { return mode }
        return [
            SuggestMeSomeSessionMode.fullBody,
            .upper,
            .lower,
            .push,
            .pull,
            .armsShoulders,
            .conditioning,
        ].randomElement() ?? .fullBody
    }

    private func generationType(for mode: SuggestMeSomeSessionMode) -> WorkoutGenerationType {
        mode == .fullBody ? .fullBody : .custom
    }

    private func adjustedIntensity(for configuration: SuggestMeSomeSessionConfiguration) -> Int {
        let base = configuration.intensity
        let adjusted: Int

        switch configuration.goal {
        case .recovery:
            adjusted = min(base, 2)
        case .conditioning, .fatLoss:
            adjusted = min(base + 1, 5)
        case .strength:
            adjusted = max(base, 4)
        case .hypertrophy, .generalFitness:
            adjusted = base
        }

        if configuration.mode == .recovery {
            return min(adjusted, 2)
        }
        return adjusted
    }

    private func selectedGroups(
        for mode: SuggestMeSomeSessionMode,
        allMuscleGroups: [MuscleGroup]
    ) -> [MuscleGroup] {
        let targetNames: Set<String>

        switch mode {
        case .fullBody, .surpriseMe:
            targetNames = []
        case .upper:
            targetNames = ["Chest", "Back", "Shoulders", "Arms"]
        case .lower:
            targetNames = ["Legs", "Core"]
        case .push:
            targetNames = ["Chest", "Shoulders", "Arms"]
        case .pull:
            targetNames = ["Back", "Arms"]
        case .armsShoulders:
            targetNames = ["Arms", "Shoulders"]
        case .recovery:
            targetNames = ["Core", "Cardio"]
        case .conditioning:
            targetNames = ["Cardio", "Legs", "Core"]
        }

        guard !targetNames.isEmpty else { return [] }
        return allMuscleGroups.filter { targetNames.contains($0.name) }
    }

    private func rationaleText(
        mode: SuggestMeSomeSessionMode,
        goal: SuggestMeSomeGenerationGoal,
        equipmentProfile: SuggestMeSomeEquipmentProfile,
        intensity: Int,
        durationMinutes: Int
    ) -> String {
        "Mode: \(mode.title) · Goal: \(goal.title) · Equipment: \(equipmentProfile.title) · \(durationMinutes) min at intensity \(intensity)."
    }
}
