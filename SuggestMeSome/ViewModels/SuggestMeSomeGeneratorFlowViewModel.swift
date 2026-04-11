import Foundation
import SwiftData
import Observation

@Observable
final class SuggestMeSomeGeneratorFlowViewModel {
    enum Step {
        case configure
        case recommendation
        case build
    }

    private enum StorageKey {
        static let mode = "generator.flow.mode"
        static let goal = "generator.flow.goal"
        static let equipment = "generator.flow.equipment"
        static let duration = "generator.flow.duration"
        static let intensity = "generator.flow.intensity"
    }

    private let recommendationService: SuggestMeSomeRecommendationService
    private let generationService: SuggestMeSomeGenerationService

    var step: Step = .configure
    var configuration: SuggestMeSomeSessionConfiguration
    var recommendation: SuggestMeSomeSessionRecommendation?
    var generatedWorkout: GeneratedWorkout?

    init(context: ModelContext) {
        self.recommendationService = SuggestMeSomeRecommendationService(context: context)
        self.generationService = SuggestMeSomeGenerationService(context: context)
        self.configuration = SuggestMeSomeGeneratorFlowViewModel.loadLastConfiguration()
    }

    var currentStepTitle: String {
        switch step {
        case .configure: return "Step 1: Configure"
        case .recommendation: return "Step 2: Recommendation"
        case .build: return "Step 3: Build Workout"
        }
    }

    func updateDuration(_ value: Int) {
        configuration.durationMinutes = value
    }

    func updateIntensity(_ value: Int) {
        configuration.intensity = value
    }

    func makeRecommendation(allMuscleGroups: [MuscleGroup]) {
        persistConfiguration()
        recommendation = recommendationService.recommendSession(
            configuration: configuration,
            allMuscleGroups: allMuscleGroups
        )
        generatedWorkout = nil
        step = .recommendation
    }

    func buildWorkoutFromRecommendation() {
        guard let request = recommendation?.request else { return }
        generatedWorkout = generationService.generateWorkout(request: request)
        step = .build
    }

    func reshuffleWorkout() {
        guard let request = recommendation?.request else { return }
        generatedWorkout = generationService.generateWorkout(request: request)
    }

    func moveBack() {
        switch step {
        case .configure:
            break
        case .recommendation:
            step = .configure
        case .build:
            step = .recommendation
        }
    }

    private func persistConfiguration() {
        let defaults = UserDefaults.standard
        defaults.set(configuration.mode.rawValue, forKey: StorageKey.mode)
        defaults.set(configuration.goal.rawValue, forKey: StorageKey.goal)
        defaults.set(configuration.equipmentProfile.rawValue, forKey: StorageKey.equipment)
        defaults.set(configuration.durationMinutes, forKey: StorageKey.duration)
        defaults.set(configuration.intensity, forKey: StorageKey.intensity)
    }

    private static func loadLastConfiguration() -> SuggestMeSomeSessionConfiguration {
        let defaults = UserDefaults.standard

        let mode = SuggestMeSomeSessionMode(
            rawValue: defaults.string(forKey: StorageKey.mode) ?? ""
        ) ?? .fullBody

        let goal = SuggestMeSomeGenerationGoal(
            rawValue: defaults.string(forKey: StorageKey.goal) ?? ""
        ) ?? .generalFitness

        let equipment = SuggestMeSomeEquipmentProfile(
            rawValue: defaults.string(forKey: StorageKey.equipment) ?? ""
        ) ?? .fullGym

        let duration = defaults.integer(forKey: StorageKey.duration)
        let intensity = defaults.integer(forKey: StorageKey.intensity)

        return SuggestMeSomeSessionConfiguration(
            mode: mode,
            goal: goal,
            equipmentProfile: equipment,
            durationMinutes: duration > 0 ? duration : 60,
            intensity: (1...5).contains(intensity) ? intensity : 3
        )
    }
}
