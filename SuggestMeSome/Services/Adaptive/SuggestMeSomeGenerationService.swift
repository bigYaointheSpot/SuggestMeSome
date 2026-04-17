import Foundation
import SwiftData

struct SuggestMeSomeGenerationService {
    private let exercisePoolBuilder: SuggestMeSomeExercisePoolBuilder
    private let exerciseSelectionService: SuggestMeSomeExerciseSelectionService
    private let workoutPrescriptionService: SuggestMeSomeWorkoutPrescriptionService
    private let equipmentCompatibilityService: SuggestMeSomeEquipmentCompatibilityService
    private let substitutionService: SuggestMeSomeExerciseSubstitutionService
    private let timeBudgetService: SuggestMeSomeTimeBudgetService
    private let adaptiveTrainingStateEngine: AdaptiveTrainingStateEngine
    private let adaptiveExplainabilityService = AdaptiveExplainabilityService()

    init(context: ModelContext) {
        let timeBudgetService = SuggestMeSomeTimeBudgetService()
        let personalRecordLookupService = SuggestMeSomePersonalRecordLookupService(context: context)

        self.timeBudgetService = timeBudgetService
        self.exercisePoolBuilder = SuggestMeSomeExercisePoolBuilder(context: context)
        self.exerciseSelectionService = SuggestMeSomeExerciseSelectionService(timeBudgetService: timeBudgetService)
        self.workoutPrescriptionService = SuggestMeSomeWorkoutPrescriptionService(
            personalRecordLookupService: personalRecordLookupService,
            timeBudgetService: timeBudgetService
        )
        self.equipmentCompatibilityService = SuggestMeSomeEquipmentCompatibilityService()
        self.substitutionService = SuggestMeSomeExerciseSubstitutionService()
        self.adaptiveTrainingStateEngine = AdaptiveTrainingStateEngine(context: context)
    }

    func generateWorkout(request: SuggestMeSomeGenerationRequest) -> GeneratedWorkout {
        let stateSnapshot = request.stateSnapshotOverride ?? adaptiveTrainingStateEngine.buildSnapshot()
        let dailyProgramContext = request.activeProgramContext ??
            adaptiveTrainingStateEngine.buildDailyProgramContext(
                snapshot: stateSnapshot,
                request: request
            )
        let constructionProfile = adaptiveTrainingStateEngine.buildSessionConstructionProfile(
            request: request,
            snapshot: stateSnapshot,
            dailyContext: dailyProgramContext,
            steeringProfile: request.steeringProfile
        )
        let prescribedIntensity = resolvedPrescribedIntensity(
            baseIntensity: request.intensity,
            snapshot: stateSnapshot,
            dailyProgramContext: dailyProgramContext,
            constructionProfile: constructionProfile
        )

        switch request.generationType {
        case .custom:
            return generateCustomWorkout(
                request: request,
                stateSnapshot: stateSnapshot,
                dailyProgramContext: dailyProgramContext,
                constructionProfile: constructionProfile,
                prescribedIntensity: prescribedIntensity
            )
        case .fullBody:
            return generateFullBodyWorkout(
                request: request,
                stateSnapshot: stateSnapshot,
                dailyProgramContext: dailyProgramContext,
                constructionProfile: constructionProfile,
                prescribedIntensity: prescribedIntensity
            )
        }
    }

    // MARK: - Custom workout

    private func generateCustomWorkout(
        request: SuggestMeSomeGenerationRequest,
        stateSnapshot: TrainingStateSnapshot,
        dailyProgramContext: DailyProgramContext,
        constructionProfile: SessionConstructionProfile,
        prescribedIntensity: Int
    ) -> GeneratedWorkout {
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

        let strengthTimeBudget = request.durationMinutes * constructionProfile.strengthTimeShare
        let selectedStrength = assembleStrengthExercises(
            from: augmentedPool,
            request: request,
            stateSnapshot: stateSnapshot,
            dailyProgramContext: dailyProgramContext,
            constructionProfile: constructionProfile,
            targetMinutes: strengthTimeBudget
        )

        var generatedExercises: [GeneratedExercise] = selectedStrength.map { exercise in
            let prescribed = workoutPrescriptionService.prescribeStrengthExercise(
                exercise,
                intensity: prescribedIntensity,
                goal: request.goal,
                prescriptionStyle: constructionProfile.prescriptionStyle
            )
            return GeneratedExercise(
                exercise: prescribed.exercise,
                sets: prescribed.sets,
                effectiveTimeMinutes: prescribed.effectiveTimeMinutes,
                substitutionNote: substitutionNotes[exercise.persistentModelID]
            )
        }

        let usedMinutes = generatedExercises.reduce(0.0) { $0 + $1.effectiveTimeMinutes }

        let targetCardioMinutes = request.durationMinutes * constructionProfile.cardioTimeShare
        let remaining = max(0.0, request.durationMinutes - usedMinutes)
        let shouldAppendCardio = !cardioPool.isEmpty &&
            (targetCardioMinutes >= 8 || (constructionProfile.allowAutomaticCardioAppend && remaining >= 8))

        var appendedCardio = false
        if shouldAppendCardio, let cardioExercise = bestCardioExercise(from: cardioPool, request: request) {
            let cardioMinutes = targetCardioMinutes > 0
                ? min(remaining, max(8.0, targetCardioMinutes))
                : min(remaining, 10.0)
            generatedExercises.append(
                workoutPrescriptionService.prescribeCardioExercise(
                    cardioExercise,
                    durationMinutes: cardioMinutes,
                    prescriptionStyle: constructionProfile.prescriptionStyle == .conditioningIntervals
                        ? .conditioningIntervals
                        : .cardioSteadyState
                )
            )
            appendedCardio = true
        }

        let totalTime = generatedExercises.reduce(0.0) { $0 + $1.effectiveTimeMinutes }
        return GeneratedWorkout(
            exercises: generatedExercises,
            totalEstimatedMinutes: totalTime,
            intensity: prescribedIntensity,
            generationType: .custom,
            adaptationNote: adaptationNote,
            explanationBundle: adaptiveExplainabilityService.buildDailyWorkoutExplanation(
                request: request,
                snapshot: stateSnapshot,
                dailyProgramContext: dailyProgramContext,
                constructionProfile: constructionProfile,
                selectedExercises: generatedExercises.map(\.exercise),
                appendedCardio: appendedCardio,
                prescribedIntensity: prescribedIntensity
            )
        )
    }

    // MARK: - Full-body workout

    private func generateFullBodyWorkout(
        request: SuggestMeSomeGenerationRequest,
        stateSnapshot: TrainingStateSnapshot,
        dailyProgramContext: DailyProgramContext,
        constructionProfile: SessionConstructionProfile,
        prescribedIntensity: Int
    ) -> GeneratedWorkout {
        let nonCardioGroups = exercisePoolBuilder.fetchAllNonCardioGroups()
        let cardioPool = equipmentCompatibilityService.filterExercises(
            exercisePoolBuilder.fetchAllCardioExercises(),
            equipmentProfile: request.equipmentProfile
        )

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

        let selected = assembleStrengthExercises(
            from: filteredGroups.flatMap(\.exercises),
            request: request,
            stateSnapshot: stateSnapshot,
            dailyProgramContext: dailyProgramContext,
            constructionProfile: constructionProfile,
            targetMinutes: request.durationMinutes * constructionProfile.strengthTimeShare
        )

        let generatedExercises = selected.map {
            workoutPrescriptionService.prescribeStrengthExercise(
                $0,
                intensity: prescribedIntensity,
                goal: request.goal,
                prescriptionStyle: constructionProfile.prescriptionStyle
            )
        }
        var finalExercises = generatedExercises
        let strengthTime = generatedExercises.reduce(0.0) { $0 + $1.effectiveTimeMinutes }
        let remaining = max(0.0, request.durationMinutes - strengthTime)
        var appendedCardio = false
        if !cardioPool.isEmpty,
           (constructionProfile.cardioTimeShare > 0.01 || (constructionProfile.allowAutomaticCardioAppend && remaining >= 8)),
           let cardioExercise = bestCardioExercise(from: cardioPool, request: request) {
            let cardioDuration = constructionProfile.cardioTimeShare > 0
                ? min(remaining, max(8.0, request.durationMinutes * constructionProfile.cardioTimeShare))
                : min(remaining, 10.0)
            finalExercises.append(
                workoutPrescriptionService.prescribeCardioExercise(
                    cardioExercise,
                    durationMinutes: cardioDuration,
                    prescriptionStyle: constructionProfile.cardioTimeShare > 0 ? .conditioningIntervals : .cardioSteadyState
                )
            )
            appendedCardio = true
        }

        let totalTime = finalExercises.reduce(0.0) { $0 + $1.effectiveTimeMinutes }
        return GeneratedWorkout(
            exercises: finalExercises,
            totalEstimatedMinutes: totalTime,
            intensity: prescribedIntensity,
            generationType: .fullBody,
            adaptationNote: fullBodyAdaptationNote,
            explanationBundle: adaptiveExplainabilityService.buildDailyWorkoutExplanation(
                request: request,
                snapshot: stateSnapshot,
                dailyProgramContext: dailyProgramContext,
                constructionProfile: constructionProfile,
                selectedExercises: finalExercises.map(\.exercise),
                appendedCardio: appendedCardio,
                prescribedIntensity: prescribedIntensity
            )
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

    private func assembleStrengthExercises(
        from pool: [Exercise],
        request: SuggestMeSomeGenerationRequest,
        stateSnapshot: TrainingStateSnapshot,
        dailyProgramContext: DailyProgramContext,
        constructionProfile: SessionConstructionProfile,
        targetMinutes: Double
    ) -> [Exercise] {
        let deduped = Dictionary(uniqueKeysWithValues: pool.map { ($0.persistentModelID, $0) })
            .values
            .sorted { $0.name < $1.name }
        let targetMuscles = Set(request.selectedMuscleGroups.compactMap { $0.name.lowercased() })
        let preferredAnchors = Set(
            stateSnapshot.preferredAnchorExerciseNames.map { $0.lowercased() } +
            request.selectedExercises.map { $0.name.lowercased() }
        )
        let underused = Set(stateSnapshot.underusedExerciseNames.map { $0.lowercased() })
        let blocked = Set(dailyProgramContext.blockedCanonicalLifts)
        let supportAnchors = Set(dailyProgramContext.nextSessionAnchorExercises.map { $0.lowercased() })
        let missedFamilies = Set(dailyProgramContext.missedMovementFamilies)
        let prioritizedOptionalSlots = prioritizedOptionalSlots(
            supportActiveProgram: dailyProgramContext.shouldSupportActiveProgram,
            missedMovementFamilies: missedFamilies,
            baseSlots: constructionProfile.optionalSlots,
            requiredSlots: constructionProfile.requiredSlots
        )

        var selected: [Exercise] = []
        var selectedIDs: Set<PersistentIdentifier> = []
        var coveredPatterns: Set<ProgramMovementPattern> = []
        var accumulatedMinutes = 0.0

        for slot in constructionProfile.requiredSlots {
            guard let exercise = bestExercise(
                for: slot,
                candidates: deduped,
                selectedIDs: selectedIDs,
                coveredPatterns: coveredPatterns,
                targetMuscles: targetMuscles,
                preferredAnchors: preferredAnchors,
                underused: underused,
                blockedCanonicalLifts: blocked,
                supportAnchors: supportAnchors,
                missedMovementFamilies: missedFamilies,
                prioritizePreferredAnchors: constructionProfile.prioritizePreferredAnchors,
                preferUnderusedMovements: constructionProfile.preferUnderusedMovements,
                interferencePenaltyScale: constructionProfile.interferencePenaltyScale
            ) else {
                continue
            }
            let exerciseMinutes = timeBudgetService.effectiveTimeMinutes(for: exercise, intensity: request.intensity)
            if accumulatedMinutes + exerciseMinutes <= targetMinutes || selected.isEmpty {
                selected.append(exercise)
                selectedIDs.insert(exercise.persistentModelID)
                coveredPatterns.formUnion(ProgramExerciseMetadataService.movementPatterns(for: exercise.name))
                accumulatedMinutes += exerciseMinutes
            }
        }

        for slot in prioritizedOptionalSlots {
            guard accumulatedMinutes + 5 <= targetMinutes else { break }
            guard let exercise = bestExercise(
                for: slot,
                candidates: deduped,
                selectedIDs: selectedIDs,
                coveredPatterns: coveredPatterns,
                targetMuscles: targetMuscles,
                preferredAnchors: preferredAnchors,
                underused: underused,
                blockedCanonicalLifts: blocked,
                supportAnchors: supportAnchors,
                missedMovementFamilies: missedFamilies,
                prioritizePreferredAnchors: constructionProfile.prioritizePreferredAnchors,
                preferUnderusedMovements: constructionProfile.preferUnderusedMovements,
                interferencePenaltyScale: constructionProfile.interferencePenaltyScale
            ) else {
                continue
            }
            let exerciseMinutes = timeBudgetService.effectiveTimeMinutes(for: exercise, intensity: request.intensity)
            if accumulatedMinutes + exerciseMinutes <= targetMinutes {
                selected.append(exercise)
                selectedIDs.insert(exercise.persistentModelID)
                coveredPatterns.formUnion(ProgramExerciseMetadataService.movementPatterns(for: exercise.name))
                accumulatedMinutes += exerciseMinutes
            }
        }

        if dailyProgramContext.shouldSupportActiveProgram {
            let unresolvedFamilies = missedFamilies.subtracting(coveredMovementFamilies(in: selected))
            if let family = unresolvedFamilies.sorted().first,
               let slot = movementFamilyToSlot(family),
               let supportExercise = bestExercise(
                for: slot,
                candidates: deduped,
                selectedIDs: selectedIDs,
                coveredPatterns: coveredPatterns,
                targetMuscles: targetMuscles,
                preferredAnchors: preferredAnchors,
                underused: underused,
                blockedCanonicalLifts: blocked,
                supportAnchors: supportAnchors,
                missedMovementFamilies: missedFamilies,
                prioritizePreferredAnchors: constructionProfile.prioritizePreferredAnchors,
                preferUnderusedMovements: constructionProfile.preferUnderusedMovements,
                interferencePenaltyScale: constructionProfile.interferencePenaltyScale
               ) {
                let exerciseMinutes = timeBudgetService.effectiveTimeMinutes(for: supportExercise, intensity: request.intensity)
                if accumulatedMinutes + exerciseMinutes <= targetMinutes {
                    selected.append(supportExercise)
                } else if let replacementIndex = selected.indices.last(where: {
                    $0 > 0 && !exerciseMatchesMovementFamily(selected[$0], family: family)
                }) {
                    selected[replacementIndex] = supportExercise
                }
                selectedIDs = Set(selected.map(\.persistentModelID))
                coveredPatterns = Set(selected.flatMap { ProgramExerciseMetadataService.movementPatterns(for: $0.name) })
                accumulatedMinutes = selected.reduce(0.0) {
                    $0 + timeBudgetService.effectiveTimeMinutes(for: $1, intensity: request.intensity)
                }
            }
        }

        if selected.isEmpty,
           let fallback = deduped
            .filter({ $0.exerciseType != .cardio && !isBlockedCanonicalLift($0, blockedCanonicalLifts: blocked) })
            .sorted(by: { deterministicScore(for: $0) > deterministicScore(for: $1) })
            .first {
            selected = [fallback]
        }

        if !selected.contains(where: { $0.exerciseType == .compound }),
           let compound = deduped.first(where: {
               $0.exerciseType == .compound &&
               !selectedIDs.contains($0.persistentModelID) &&
               !isBlockedCanonicalLift($0, blockedCanonicalLifts: blocked)
           }) {
            if let replacementIndex = selected.indices.last(where: { selected[$0].exerciseType != .compound }) {
                selected[replacementIndex] = compound
            } else {
                selected.append(compound)
            }
        }

        return selected
    }

    private func prioritizedOptionalSlots(
        supportActiveProgram: Bool,
        missedMovementFamilies: Set<String>,
        baseSlots: [SuggestMeSomeSessionSlotKind],
        requiredSlots: [SuggestMeSomeSessionSlotKind]
    ) -> [SuggestMeSomeSessionSlotKind] {
        guard supportActiveProgram, !missedMovementFamilies.isEmpty else {
            return baseSlots
        }

        let existing = Set(requiredSlots + baseSlots)
        let supportSlots = missedMovementFamilies.compactMap { movementFamilyToSlot($0) }
            .filter { !existing.contains($0) }

        var ordered: [SuggestMeSomeSessionSlotKind] = []
        for slot in supportSlots + baseSlots where !ordered.contains(slot) {
            ordered.append(slot)
        }
        return ordered
    }

    private func movementFamilyToSlot(_ family: String) -> SuggestMeSomeSessionSlotKind? {
        switch ProgramMovementPattern(rawValue: family) {
        case .horizontalPull, .verticalPull:
            return .upperPull
        case .horizontalPush, .verticalPush:
            return .upperPush
        case .squatKneeDominant, .singleLeg:
            return .lowerPattern
        case .hinge:
            return .posteriorChain
        case .trunk:
            return .trunkStability
        case .conditioning:
            return .cardioFinisher
        case nil:
            return nil
        }
    }

    private func coveredMovementFamilies(in exercises: [Exercise]) -> Set<String> {
        Set(exercises.flatMap {
            ProgramExerciseMetadataService.movementPatterns(for: $0.name).map(\.rawValue)
        })
    }

    private func exerciseMatchesMovementFamily(_ exercise: Exercise, family: String) -> Bool {
        ProgramExerciseMetadataService.movementPatterns(for: exercise.name)
            .map(\.rawValue)
            .contains(family)
    }

    private func bestExercise(
        for slot: SuggestMeSomeSessionSlotKind,
        candidates: [Exercise],
        selectedIDs: Set<PersistentIdentifier>,
        coveredPatterns: Set<ProgramMovementPattern>,
        targetMuscles: Set<String>,
        preferredAnchors: Set<String>,
        underused: Set<String>,
        blockedCanonicalLifts: Set<CanonicalLift>,
        supportAnchors: Set<String>,
        missedMovementFamilies: Set<String>,
        prioritizePreferredAnchors: Bool,
        preferUnderusedMovements: Bool,
        interferencePenaltyScale: Double
    ) -> Exercise? {
        candidates
            .filter { !selectedIDs.contains($0.persistentModelID) }
            .filter { exerciseMatchesSlot($0, slot: slot) }
            .sorted { lhs, rhs in
                let lhsScore = scoreExercise(
                    lhs,
                    slot: slot,
                    coveredPatterns: coveredPatterns,
                    targetMuscles: targetMuscles,
                    preferredAnchors: preferredAnchors,
                    underused: underused,
                    blockedCanonicalLifts: blockedCanonicalLifts,
                    supportAnchors: supportAnchors,
                    missedMovementFamilies: missedMovementFamilies,
                    prioritizePreferredAnchors: prioritizePreferredAnchors,
                    preferUnderusedMovements: preferUnderusedMovements,
                    interferencePenaltyScale: interferencePenaltyScale
                )
                let rhsScore = scoreExercise(
                    rhs,
                    slot: slot,
                    coveredPatterns: coveredPatterns,
                    targetMuscles: targetMuscles,
                    preferredAnchors: preferredAnchors,
                    underused: underused,
                    blockedCanonicalLifts: blockedCanonicalLifts,
                    supportAnchors: supportAnchors,
                    missedMovementFamilies: missedMovementFamilies,
                    prioritizePreferredAnchors: prioritizePreferredAnchors,
                    preferUnderusedMovements: preferUnderusedMovements,
                    interferencePenaltyScale: interferencePenaltyScale
                )
                if lhsScore == rhsScore { return lhs.name < rhs.name }
                return lhsScore > rhsScore
            }
            .first
    }

    private func scoreExercise(
        _ exercise: Exercise,
        slot: SuggestMeSomeSessionSlotKind,
        coveredPatterns: Set<ProgramMovementPattern>,
        targetMuscles: Set<String>,
        preferredAnchors: Set<String>,
        underused: Set<String>,
        blockedCanonicalLifts: Set<CanonicalLift>,
        supportAnchors: Set<String>,
        missedMovementFamilies: Set<String>,
        prioritizePreferredAnchors: Bool,
        preferUnderusedMovements: Bool,
        interferencePenaltyScale: Double
    ) -> Double {
        var score = deterministicScore(for: exercise)
        let lowerName = exercise.name.lowercased()
        let patterns = ProgramExerciseMetadataService.movementPatterns(for: exercise.name)

        if let muscleGroup = exercise.muscleGroup?.name.lowercased(), targetMuscles.contains(muscleGroup) {
            score += 2.2
        }
        if preferredAnchors.contains(lowerName) {
            score += prioritizePreferredAnchors ? 4.0 : 2.0
        }
        if underused.contains(lowerName) {
            score += preferUnderusedMovements ? 2.0 : 0.6
        }
        if patterns.subtracting(coveredPatterns).count > 0 {
            score += Double(patterns.subtracting(coveredPatterns).count) * 1.3
        }
        if !patterns.map(\.rawValue).filter({ missedMovementFamilies.contains($0) }).isEmpty {
            score += 1.8
        }
        if slot == .anchorCompound, CanonicalLift.from(exerciseName: exercise.name) != nil {
            score += 2.8
        }

        if let canonical = CanonicalLift.from(exerciseName: exercise.name),
           blockedCanonicalLifts.contains(canonical) {
            score -= 25.0
        }
        if supportAnchors.contains(lowerName) {
            score -= 4.0 * interferencePenaltyScale
        }

        return score
    }

    private func isBlockedCanonicalLift(
        _ exercise: Exercise,
        blockedCanonicalLifts: Set<CanonicalLift>
    ) -> Bool {
        guard let canonical = CanonicalLift.from(exerciseName: exercise.name) else { return false }
        return blockedCanonicalLifts.contains(canonical)
    }

    private func deterministicScore(for exercise: Exercise) -> Double {
        switch exercise.exerciseType {
        case .compound: return 6.0
        case .accessory: return 4.0
        case .isolation: return 3.0
        case .cardio: return 1.0
        }
    }

    private func resolvedPrescribedIntensity(
        baseIntensity: Int,
        snapshot: TrainingStateSnapshot,
        dailyProgramContext: DailyProgramContext,
        constructionProfile: SessionConstructionProfile
    ) -> Int {
        var adjusted = baseIntensity + constructionProfile.prescribedIntensityAdjustment
        if snapshot.shouldBiasRecovery {
            adjusted = min(adjusted, 3)
        }
        if dailyProgramContext.interferenceScore >= 0.80 {
            adjusted = min(adjusted, 3)
        }
        if !dailyProgramContext.blockedCanonicalLifts.isEmpty {
            adjusted = min(adjusted, 4)
        }
        return max(1, min(5, adjusted))
    }

    private func exerciseMatchesSlot(_ exercise: Exercise, slot: SuggestMeSomeSessionSlotKind) -> Bool {
        let patterns = ProgramExerciseMetadataService.movementPatterns(for: exercise.name)
        let lowerMuscle = exercise.muscleGroup?.name.lowercased() ?? ""
        let lowerName = exercise.name.lowercased()

        switch slot {
        case .anchorCompound:
            return exercise.exerciseType == .compound
        case .secondaryCompound:
            return exercise.exerciseType == .compound
        case .upperPush:
            return patterns.contains(.horizontalPush) || patterns.contains(.verticalPush) ||
                ["chest", "shoulders", "arms"].contains(lowerMuscle)
        case .upperPull:
            return patterns.contains(.horizontalPull) || patterns.contains(.verticalPull) ||
                (lowerMuscle == "back" && !patterns.contains(.hinge))
        case .lowerPattern:
            return patterns.contains(.squatKneeDominant) || patterns.contains(.singleLeg) || lowerMuscle == "legs"
        case .posteriorChain:
            return patterns.contains(.hinge) || lowerName.contains("deadlift") || lowerName.contains("glute")
        case .singleLeg:
            return patterns.contains(.singleLeg) || lowerName.contains("split squat") || lowerName.contains("lunge")
        case .trunkStability:
            return patterns.contains(.trunk) || lowerMuscle == "core"
        case .armAccessory:
            return lowerMuscle == "arms" || lowerName.contains("curl") || lowerName.contains("tricep")
        case .shoulderAccessory:
            return lowerMuscle == "shoulders" || lowerName.contains("shoulder") || lowerName.contains("lateral")
        case .mobilityTempo:
            return exercise.exerciseType != .compound && exercise.exerciseType != .cardio
        case .cardioPrimary, .cardioFinisher:
            return exercise.exerciseType == .cardio
        }
    }

    private func bestCardioExercise(
        from pool: [Exercise],
        request: SuggestMeSomeGenerationRequest
    ) -> Exercise? {
        pool.sorted { lhs, rhs in
            let lhsScore = cardioScore(for: lhs, goal: request.goal)
            let rhsScore = cardioScore(for: rhs, goal: request.goal)
            if lhsScore == rhsScore { return lhs.name < rhs.name }
            return lhsScore > rhsScore
        }.first
    }

    private func cardioScore(for exercise: Exercise, goal: SuggestMeSomeGenerationGoal?) -> Double {
        let lower = exercise.name.lowercased()
        switch goal {
        case .recovery:
            if lower.contains("bike") || lower.contains("elliptical") { return 6.0 }
            if lower.contains("treadmill") { return 5.0 }
            return 4.0
        case .conditioning, .fatLoss:
            if lower.contains("row") || lower.contains("rope") { return 6.0 }
            if lower.contains("bike") { return 5.0 }
            return 4.0
        default:
            if lower.contains("bike") || lower.contains("treadmill") { return 5.0 }
            return 4.0
        }
    }
}
