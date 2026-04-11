import Foundation
import SwiftData

struct SuggestMeSomeGenerationService {
    private let exercisePoolBuilder: SuggestMeSomeExercisePoolBuilder
    private let exerciseSelectionService: SuggestMeSomeExerciseSelectionService
    private let workoutPrescriptionService: SuggestMeSomeWorkoutPrescriptionService
    private let equipmentCompatibilityService: SuggestMeSomeEquipmentCompatibilityService

    init(context: ModelContext) {
        let timeBudgetService = SuggestMeSomeTimeBudgetService()
        let personalRecordLookupService = SuggestMeSomePersonalRecordLookupService(context: context)

        self.exercisePoolBuilder = SuggestMeSomeExercisePoolBuilder(context: context)
        self.exerciseSelectionService = SuggestMeSomeExerciseSelectionService(timeBudgetService: timeBudgetService)
        self.workoutPrescriptionService = SuggestMeSomeWorkoutPrescriptionService(
            personalRecordLookupService: personalRecordLookupService,
            timeBudgetService: timeBudgetService
        )
        self.equipmentCompatibilityService = SuggestMeSomeEquipmentCompatibilityService()
    }

    func generateWorkout(request: SuggestMeSomeGenerationRequest) -> GeneratedWorkout {
        switch request.generationType {
        case .custom:
            generateCustomWorkout(request: request)
        case .fullBody:
            generateFullBodyWorkout(request: request)
        }
    }

    private func generateCustomWorkout(request: SuggestMeSomeGenerationRequest) -> GeneratedWorkout {
        let pools = exercisePoolBuilder.buildCustomPools(
            muscleGroups: request.selectedMuscleGroups,
            selectedExercises: request.selectedExercises
        )

        let strengthPool = equipmentCompatibilityService.filterExercises(
            pools.strength,
            equipmentProfile: request.equipmentProfile
        )
        let cardioPool = equipmentCompatibilityService.filterExercises(
            pools.cardio,
            equipmentProfile: request.equipmentProfile
        )

        // For conditioning and recovery modes, reserve the majority of time for cardio/light work.
        let isCardioFirstMode = request.sessionMode == .conditioning || request.goal == .conditioning
        let isRecoveryMode = request.sessionMode == .recovery || request.goal == .recovery

        // Strength time budget: reduced for cardio-primary and recovery modes
        let strengthTimeBudget: Double
        if isCardioFirstMode {
            // Conditioning: only allocate up to 30% of time to strength circuits
            strengthTimeBudget = request.durationMinutes * 0.30
        } else if isRecoveryMode {
            // Recovery: allow strength (core) work but leave room for cardio
            strengthTimeBudget = request.durationMinutes * 0.55
        } else {
            strengthTimeBudget = request.durationMinutes
        }

        let selectedStrength = exerciseSelectionService.selectStrengthExercises(
            from: strengthPool,
            targetMinutes: strengthTimeBudget,
            intensity: request.intensity
        )

        var generatedExercises = selectedStrength.map {
            workoutPrescriptionService.prescribeStrengthExercise(
                $0,
                intensity: request.intensity,
                goal: request.goal
            )
        }

        let usedMinutes = generatedExercises.reduce(0.0) { $0 + $1.effectiveTimeMinutes }

        if let cardioExercise = cardioPool.shuffled().first {
            let remaining = max(1.0, request.durationMinutes - usedMinutes)
            generatedExercises.append(
                workoutPrescriptionService.prescribeCardioExercise(cardioExercise, durationMinutes: remaining)
            )
        }

        let totalTime = generatedExercises.reduce(0.0) { $0 + $1.effectiveTimeMinutes }
        return GeneratedWorkout(
            exercises: generatedExercises,
            totalEstimatedMinutes: totalTime,
            intensity: request.intensity,
            generationType: .custom
        )
    }

    private func generateFullBodyWorkout(request: SuggestMeSomeGenerationRequest) -> GeneratedWorkout {
        let nonCardioGroups = exercisePoolBuilder.fetchAllNonCardioGroups()
        let filteredGroups = nonCardioGroups.map { group in
            let filteredExercises = equipmentCompatibilityService.filterExercises(
                group.exercises,
                equipmentProfile: request.equipmentProfile
            )
            return SuggestMeSomeExerciseSelectionGroup(name: group.name, exercises: filteredExercises)
        }

        let selected = exerciseSelectionService.selectFullBodyExercises(
            nonCardioGroups: filteredGroups,
            targetMinutes: request.durationMinutes,
            intensity: request.intensity
        )

        let generatedExercises = selected.map {
            workoutPrescriptionService.prescribeStrengthExercise(
                $0,
                intensity: request.intensity,
                goal: request.goal
            )
        }

        let totalTime = generatedExercises.reduce(0.0) { $0 + $1.effectiveTimeMinutes }
        return GeneratedWorkout(
            exercises: generatedExercises,
            totalEstimatedMinutes: totalTime,
            intensity: request.intensity,
            generationType: .fullBody
        )
    }
}
