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
    private let coachContextLoader: SuggestMeSomeCoachContextLoader
    private var lastAllMuscleGroups: [MuscleGroup] = []
    private var lastCoachContext: SuggestMeSomeCoachContext?

    var step: Step = .configure
    var configuration: SuggestMeSomeSessionConfiguration
    var steeringProfile: AdaptiveSteeringProfile = .balanced
    var recommendation: SuggestMeSomeSessionRecommendation?
    var generatedWorkout: GeneratedWorkout?

    init(context: ModelContext) {
        self.recommendationService = SuggestMeSomeRecommendationService(context: context)
        self.generationService = SuggestMeSomeGenerationService(context: context)
        self.coachContextLoader = SuggestMeSomeCoachContextLoader(context: context)
        self.configuration = SuggestMeSomeGeneratorFlowViewModel.loadLastConfiguration()
    }

    var currentStepTitle: String {
        switch step {
        case .configure: return "Session Setup"
        case .recommendation: return "Your Session"
        case .build: return "Session Preview"
        }
    }

    func updateDuration(_ value: Int) {
        configuration.durationMinutes = value
    }

    func updateIntensity(_ value: Int) {
        configuration.intensity = value
    }

    func makeRecommendation(
        allMuscleGroups: [MuscleGroup],
        todayCheckIn: DailyCoachCheckIn? = nil,
        objectiveRecoveryInsight: ObjectiveRecoveryInsight? = nil
    ) {
        persistConfiguration()
        let coachContext = coachContextLoader.loadContext(
            todayCheckIn: todayCheckIn,
            objectiveRecoveryInsight: objectiveRecoveryInsight
        )
        lastAllMuscleGroups = allMuscleGroups
        lastCoachContext = coachContext
        recommendation = recommendationService.recommendSession(
            configuration: configuration,
            allMuscleGroups: allMuscleGroups,
            coachContext: coachContext,
            steeringProfile: steeringProfile
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

    func updateSteering(_ steeringProfile: AdaptiveSteeringProfile) {
        self.steeringProfile = steeringProfile
        rebuildForCurrentSteering()
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

    private func rebuildForCurrentSteering() {
        guard !lastAllMuscleGroups.isEmpty else { return }

        recommendation = recommendationService.recommendSession(
            configuration: configuration,
            allMuscleGroups: lastAllMuscleGroups,
            coachContext: lastCoachContext,
            steeringProfile: steeringProfile
        )

        if step == .build, let request = recommendation?.request {
            generatedWorkout = generationService.generateWorkout(request: request)
        }
    }
}
