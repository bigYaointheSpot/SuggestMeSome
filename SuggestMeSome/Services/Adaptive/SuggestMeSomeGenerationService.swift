import Foundation
import SwiftData

struct SuggestMeSomeGenerationService {
    private let exercisePoolBuilder: SuggestMeSomeExercisePoolBuilder
    private let exerciseSelectionService: SuggestMeSomeExerciseSelectionService
    private let workoutPrescriptionService: SuggestMeSomeWorkoutPrescriptionService
    private let equipmentCompatibilityService: SuggestMeSomeEquipmentCompatibilityService
    private let substitutionService: SuggestMeSomeExerciseSubstitutionService

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
        self.substitutionService = SuggestMeSomeExerciseSubstitutionService()
    }

    func generateWorkout(request: SuggestMeSomeGenerationRequest) -> GeneratedWorkout {
        switch request.generationType {
        case .custom:
            generateCustomWorkout(request: request)
        case .fullBody:
            generateFullBodyWorkout(request: request)
        }
    }

    // MARK: - Custom workout

    private func generateCustomWorkout(request: SuggestMeSomeGenerationRequest) -> GeneratedWorkout {
        let pools = exercisePoolBuilder.buildCustomPools(
            muscleGroups: request.selectedMuscleGroups,
            selectedExercises: request.selectedExercises
        )

        // Equipment-compatible pools
        let compatibleStrength = equipmentCompatibilityService.filterExercises(
            pools.strength,
            equipmentProfile: request.equipmentProfile
        )
        let cardioPool = equipmentCompatibilityService.filterExercises(
            pools.cardio,
            equipmentProfile: request.equipmentProfile
        )

        // Augment the compatible pool with substitutes for removed compounds
        let (augmentedPool, substitutionNotes, adaptationNote) = applySubstitutions(
            originalPool: pools.strength,
            compatiblePool: compatibleStrength,
            request: request
        )

        // Mode-specific time budgets
        let isCardioFirstMode = request.sessionMode == .conditioning || request.goal == .conditioning
        let isRecoveryMode = request.sessionMode == .recovery || request.goal == .recovery

        let strengthTimeBudget: Double
        if isCardioFirstMode {
            strengthTimeBudget = request.durationMinutes * 0.30
        } else if isRecoveryMode {
            strengthTimeBudget = request.durationMinutes * 0.55
        } else {
            strengthTimeBudget = request.durationMinutes
        }

        let selectedStrength = exerciseSelectionService.selectStrengthExercises(
            from: augmentedPool,
            targetMinutes: strengthTimeBudget,
            intensity: request.intensity
        )

        var generatedExercises: [GeneratedExercise] = selectedStrength.map { exercise in
            let prescribed = workoutPrescriptionService.prescribeStrengthExercise(
                exercise,
                intensity: request.intensity,
                goal: request.goal
            )
            return GeneratedExercise(
                exercise: prescribed.exercise,
                sets: prescribed.sets,
                effectiveTimeMinutes: prescribed.effectiveTimeMinutes,
                substitutionNote: substitutionNotes[exercise.persistentModelID]
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
            generationType: .custom,
            adaptationNote: adaptationNote
        )
    }

    // MARK: - Full-body workout

    private func generateFullBodyWorkout(request: SuggestMeSomeGenerationRequest) -> GeneratedWorkout {
        let nonCardioGroups = exercisePoolBuilder.fetchAllNonCardioGroups()

        // Build filtered groups for each muscle group
        let filteredGroups: [SuggestMeSomeExerciseSelectionGroup] = nonCardioGroups.map { group in
            let filtered = equipmentCompatibilityService.filterExercises(
                group.exercises,
                equipmentProfile: request.equipmentProfile
            )
            return SuggestMeSomeExerciseSelectionGroup(name: group.name, exercises: filtered)
        }

        // For full-body, detect if equipment is severely constrained (bodyweight-only or similar)
        // and build an adaptation note when the profile limits available compounds
        let allOriginalStrength = nonCardioGroups.flatMap(\.exercises).filter { $0.exerciseType != .cardio }
        let allFiltered = filteredGroups.flatMap(\.exercises)
        let originalCompounds = allOriginalStrength.filter { $0.exerciseType == .compound }.count
        let filteredCompounds = allFiltered.filter { $0.exerciseType == .compound }.count

        let fullBodyAdaptationNote: String?
        if filteredCompounds < originalCompounds, let profile = request.equipmentProfile, profile != .fullGym {
            fullBodyAdaptationNote = substitutionService.adaptationNote(
                removedCompoundCount: originalCompounds - filteredCompounds,
                substitutionCount: 0,
                canBuildSession: filteredCompounds > 0,
                equipmentProfile: profile,
                mode: request.sessionMode,
                goal: request.goal
            )
        } else {
            fullBodyAdaptationNote = nil
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
            generationType: .fullBody,
            adaptationNote: fullBodyAdaptationNote
        )
    }

    // MARK: - Substitution augmentation

    /// After equipment filtering, identifies removed compounds and attempts to find
    /// compatible substitutes from the same original pool (same selected muscle groups).
    /// Returns the augmented pool, per-exercise substitution notes keyed by PersistentIdentifier,
    /// and an optional high-level adaptation note for the workout.
    private func applySubstitutions(
        originalPool: [Exercise],
        compatiblePool: [Exercise],
        request: SuggestMeSomeGenerationRequest
    ) -> (pool: [Exercise], notes: [PersistentIdentifier: String], adaptationNote: String?) {
        guard let profile = request.equipmentProfile, profile != .fullGym else {
            return (compatiblePool, [:], nil)
        }

        let compatibleIDs = Set(compatiblePool.map(\.persistentModelID))

        // Identify compounds from the original pool that were removed by equipment filtering
        let removedCompounds = originalPool.filter { ex in
            ex.exerciseType == .compound && !compatibleIDs.contains(ex.persistentModelID)
        }

        guard !removedCompounds.isEmpty else {
            return (compatiblePool, [:], nil)
        }

        var augmented = compatiblePool
        var augmentedIDs = compatibleIDs
        var substitutionNotes: [PersistentIdentifier: String] = [:]

        for removed in removedCompounds {
            let subs = substitutionService.rankedSubstitutes(
                for: removed,
                equipmentProfile: profile,
                availableExercises: originalPool
            )
            for sub in subs {
                guard !augmentedIDs.contains(sub.exercise.persistentModelID) else { continue }
                augmented.append(sub.exercise)
                augmentedIDs.insert(sub.exercise.persistentModelID)
                substitutionNotes[sub.exercise.persistentModelID] = sub.note
                break   // one substitute per removed exercise
            }
        }

        let finalCompoundCount = augmented.filter { $0.exerciseType == .compound }.count
        let note = substitutionService.adaptationNote(
            removedCompoundCount: removedCompounds.count,
            substitutionCount: substitutionNotes.count,
            canBuildSession: finalCompoundCount > 0,
            equipmentProfile: profile,
            mode: request.sessionMode,
            goal: request.goal
        )

        return (augmented, substitutionNotes, note)
    }
}
