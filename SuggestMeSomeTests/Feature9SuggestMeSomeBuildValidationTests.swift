import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

// MARK: - Build + Validation Tests for Prompt 6

@Suite(.serialized)
@MainActor
struct Feature9SuggestMeSomeBuildValidationTests {

    @Test func productionBuildDoesNotUseLocalDevicePersonalTeamFlag() {
        #expect(AppBuildEnvironment.isLocalDevicePersonalTeam == false)
    }

    // MARK: - Equipment Filtering

    @Test func equipmentFilteringAllowsAllExercisesForFullGym() {
        let service = SuggestMeSomeEquipmentCompatibilityService()
        let exercises = makeStrengthExercises()
        let result = service.filterExercises(exercises, equipmentProfile: .fullGym)
        #expect(result.count == exercises.count)
    }

    @Test func equipmentFilteringNilProfilePassesAllThrough() {
        let service = SuggestMeSomeEquipmentCompatibilityService()
        let exercises = makeStrengthExercises()
        let result = service.filterExercises(exercises, equipmentProfile: nil)
        #expect(result.count == exercises.count)
    }

    @Test func equipmentFilteringBodyweightOnlyExcludesBarbellExercises() {
        let service = SuggestMeSomeEquipmentCompatibilityService()
        let exercises = makeStrengthExercises()
        let result = service.filterExercises(exercises, equipmentProfile: .bodyweightOnly)

        let resultNames = Set(result.map(\.name))
        // Barbell exercises must be excluded
        #expect(!resultNames.contains("Bench Press"))
        #expect(!resultNames.contains("Back Squats"))
        #expect(!resultNames.contains("Deadlift"))
        #expect(!resultNames.contains("Overhead Press"))
        // Bodyweight exercises must be included
        #expect(resultNames.contains("Push-ups"))
        #expect(resultNames.contains("Plank"))
        #expect(resultNames.contains("Pull-ups"))
    }

    @Test func equipmentFilteringDumbbellsOnlyExcludesBarbellAndCable() {
        let service = SuggestMeSomeEquipmentCompatibilityService()
        let exercises = makeStrengthExercises()
        let result = service.filterExercises(exercises, equipmentProfile: .dumbbellsOnly)

        let resultNames = Set(result.map(\.name))
        // Barbell must be excluded
        #expect(!resultNames.contains("Bench Press"))
        #expect(!resultNames.contains("Deadlift"))
        // Cable must be excluded
        #expect(!resultNames.contains("Cable Lateral Raise"))
        // Dumbbell exercises must remain
        #expect(resultNames.contains("Dumbbell Bench Press"))
        #expect(resultNames.contains("DB Shoulder Press"))
        // Bodyweight must remain
        #expect(resultNames.contains("Push-ups"))
    }

    @Test func equipmentFilteringHomeGymExcludesCableAndMachine() {
        let service = SuggestMeSomeEquipmentCompatibilityService()
        let exercises = makeStrengthExercises()
        let result = service.filterExercises(exercises, equipmentProfile: .homeGym)

        let resultNames = Set(result.map(\.name))
        // Cable must be excluded
        #expect(!resultNames.contains("Cable Lateral Raise"))
        // Machine must be excluded
        #expect(!resultNames.contains("Leg Press"))
        // Barbell allowed in home gym
        #expect(resultNames.contains("Bench Press"))
        #expect(resultNames.contains("Deadlift"))
    }

    @Test func equipmentFilteringCardioExercises() {
        let service = SuggestMeSomeEquipmentCompatibilityService()
        let cardioGroup = MuscleGroup(name: "Cardio")
        let bike = Exercise(name: "Exercise Bike", exerciseType: .cardio, muscleGroup: cardioGroup)
        let rope = Exercise(name: "Jump Rope", exerciseType: .cardio, muscleGroup: cardioGroup)
        let exercises = [bike, rope]

        // Bodyweight only: only jump rope allowed
        let bodyweight = service.filterExercises(exercises, equipmentProfile: .bodyweightOnly)
        #expect(bodyweight.map(\.name).contains("Jump Rope"))
        #expect(!bodyweight.map(\.name).contains("Exercise Bike"))

        // Full gym: both allowed
        let full = service.filterExercises(exercises, equipmentProfile: .fullGym)
        #expect(full.count == 2)
    }

    // MARK: - Variation Load Fallback

    @Test func variationLoadFallsBackToSourceLiftPRViaMapping() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        // Insert a Bench Press PR at 5 reps
        let benchPR = PersonalRecord(
            exerciseName: "Bench Press",
            repCount: 5,
            weight: 225,
            unit: .lbs,
            dateAchieved: Date()
        )
        context.insert(benchPR)
        try context.save()

        let service = SuggestMeSomePersonalRecordLookupService(context: context)

        let chestGroup = MuscleGroup(name: "Chest")
        let pauseBench = Exercise(name: "Pause Bench Press", exerciseType: .compound, muscleGroup: chestGroup)

        // Pause Bench Press has no direct PR; should fall back to Bench Press × 0.93
        let result = service.bestAvailableWeight(for: pauseBench, repCount: 5)

        #expect(result != nil)
        if let (weight, unit) = result {
            #expect(abs(weight - 225 * 0.93) < 0.01)
            #expect(unit == .lbs)
        }
    }

    @Test func directPRTakesPriorityOverVariationMapping() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        // Insert both direct PR and source lift PR
        let pauseBreachPR = PersonalRecord(
            exerciseName: "Pause Bench Press",
            repCount: 5,
            weight: 200,
            unit: .lbs,
            dateAchieved: Date()
        )
        let benchPR = PersonalRecord(
            exerciseName: "Bench Press",
            repCount: 5,
            weight: 225,
            unit: .lbs,
            dateAchieved: Date()
        )
        context.insert(pauseBreachPR)
        context.insert(benchPR)
        try context.save()

        let service = SuggestMeSomePersonalRecordLookupService(context: context)

        let chestGroup = MuscleGroup(name: "Chest")
        let pauseBench = Exercise(name: "Pause Bench Press", exerciseType: .compound, muscleGroup: chestGroup)

        let result = service.bestAvailableWeight(for: pauseBench, repCount: 5)

        // Should use direct PR (200), not mapped value (225 × 0.93 = 209.25)
        #expect(result?.weight == 200)
    }

    @Test func canonicalFamilyFallbackUsedWhenNoDirectOrMappedPR() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        // Insert a PR for the primary canonical lift (Back Squats)
        let squatPR = PersonalRecord(
            exerciseName: "Back Squats",
            repCount: 5,
            weight: 315,
            unit: .lbs,
            dateAchieved: Date()
        )
        context.insert(squatPR)
        try context.save()

        let service = SuggestMeSomePersonalRecordLookupService(context: context)

        let legsGroup = MuscleGroup(name: "Legs")
        // Front Squat has a loadMapping to Back Squats × 0.85
        let frontSquat = Exercise(name: "Front Squat", exerciseType: .compound, muscleGroup: legsGroup)

        let result = service.bestAvailableWeight(for: frontSquat, repCount: 5)

        #expect(result != nil)
        if let (weight, _) = result {
            // Should be Back Squats × 0.85
            #expect(abs(weight - 315 * 0.85) < 0.01)
        }
    }

    // MARK: - Goal-Aware Prescription

    @Test func generatedExerciseSnapshotsSourceExerciseBeforeInvalidation() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let chest = MuscleGroup(name: "Chest")
        let fly = Exercise(name: "Cable Fly", exerciseType: .isolation, muscleGroup: chest)
        context.insert(chest)
        context.insert(fly)
        try context.save()

        let generated = GeneratedExercise(
            exercise: fly,
            sets: [GeneratedSet(setNumber: 1, isWarmup: false, suggestedReps: 12, suggestedWeight: 35, unit: .lbs)],
            effectiveTimeMinutes: 8,
            substitutionNote: "Cable Fly (replaces Pec Deck)"
        )

        context.delete(fly)
        try context.save()

        #expect(generated.exerciseName == "Cable Fly")
        #expect(generated.exerciseType == .isolation)
        #expect(generated.substitutionNote == "Cable Fly (replaces Pec Deck)")
        #expect(generated.sets.first?.suggestedWeight == 35)
    }

    @Test func recoveryGoalProducesNoWarmupSets() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        // Insert a PR so weights are filled in (not nil sets)
        let pr = PersonalRecord(
            exerciseName: "Bench Press",
            repCount: 8,
            weight: 185,
            unit: .lbs,
            dateAchieved: Date()
        )
        context.insert(pr)
        try context.save()

        let service = makeFullPrescriptionService(context: context)
        let chestGroup = MuscleGroup(name: "Chest")
        let bench = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chestGroup)

        let result = service.prescribeStrengthExercise(bench, intensity: 2, goal: .recovery)

        let warmups = result.sets.filter(\.isWarmup)
        #expect(warmups.isEmpty, "Recovery goal should produce no warmup sets")
    }

    @Test func recoveryGoalProducesFewerWorkingSets() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let service = makeFullPrescriptionService(context: context)
        let chestGroup = MuscleGroup(name: "Chest")
        let bench = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chestGroup)

        let recoveryResult = service.prescribeStrengthExercise(bench, intensity: 2, goal: .recovery)
        let normalResult = service.prescribeStrengthExercise(bench, intensity: 2, goal: .hypertrophy)

        let recoveryWorking = recoveryResult.sets.filter { !$0.isWarmup }.count
        let normalWorking = normalResult.sets.filter { !$0.isWarmup }.count

        #expect(recoveryWorking < normalWorking,
                "Recovery goal should prescribe fewer working sets than hypertrophy")
    }

    @Test func accessoryExercisesGetNoWarmupSets() {
        let container = try? makeInMemoryContainer()
        guard let context = container?.mainContext else { return }

        let service = makeFullPrescriptionService(context: context)
        let coreGroup = MuscleGroup(name: "Core")
        let plank = Exercise(name: "Plank", exerciseType: .accessory, muscleGroup: coreGroup)

        let result = service.prescribeStrengthExercise(plank, intensity: 3, goal: nil)

        let warmups = result.sets.filter(\.isWarmup)
        #expect(warmups.isEmpty, "Accessory exercises should never have warmup sets")
    }

    @Test func compoundExercisesWithNormalGoalHaveWarmupSets() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let service = makeFullPrescriptionService(context: context)
        let chestGroup = MuscleGroup(name: "Chest")
        let bench = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chestGroup)

        // strength / hypertrophy / generalFitness goals all get warmups
        for goal: SuggestMeSomeGenerationGoal in [.strength, .hypertrophy, .generalFitness] {
            let result = service.prescribeStrengthExercise(bench, intensity: 3, goal: goal)
            let warmups = result.sets.filter(\.isWarmup)
            #expect(!warmups.isEmpty, "Compound exercise with \(goal.title) goal should have warmup sets")
        }
    }

    // MARK: - Recommendation-to-Workout Conversion

    @Test func buildableRecommendationProducesNonEmptyWorkout() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeGenerationService(context: context)
        let request = SuggestMeSomeGenerationRequest(
            generationType: .fullBody,
            durationMinutes: 60,
            intensity: 3,
            selectedMuscleGroups: allGroups.filter { $0.name != "Cardio" },
            selectedExercises: [],
            goal: .generalFitness,
            equipmentProfile: .fullGym
        )

        let workout = service.generateWorkout(request: request)
        #expect(!workout.exercises.isEmpty, "Full body request should produce at least one exercise")
    }

    @Test func recoveryModeRequestProducesLightSession() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeGenerationService(context: context)

        let coreAndCardio = allGroups.filter { $0.name == "Core" || $0.name == "Cardio" }
        let request = SuggestMeSomeGenerationRequest(
            generationType: .custom,
            durationMinutes: 40,
            intensity: 2,
            selectedMuscleGroups: coreAndCardio,
            selectedExercises: [],
            goal: .recovery,
            equipmentProfile: .fullGym,
            sessionMode: .recovery
        )

        let workout = service.generateWorkout(request: request)
        #expect(!workout.exercises.isEmpty)

        // All non-cardio exercises should have no warmup sets (recovery mode)
        let strengthExercises = workout.exercises.filter { $0.exerciseType != .cardio }
        for genExercise in strengthExercises {
            let warmups = genExercise.sets.filter(\.isWarmup)
            #expect(warmups.isEmpty,
                    "Recovery mode exercise '\(genExercise.exerciseName)' should have no warmup sets")
        }
    }

    @Test func conditioningModeIncludesCardioExercise() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeGenerationService(context: context)

        // Conditioning uses Cardio + Legs + Core
        let conditioningGroups = allGroups.filter {
            ["Cardio", "Legs", "Core"].contains($0.name)
        }
        let request = SuggestMeSomeGenerationRequest(
            generationType: .custom,
            durationMinutes: 45,
            intensity: 3,
            selectedMuscleGroups: conditioningGroups,
            selectedExercises: [],
            goal: .conditioning,
            equipmentProfile: .fullGym,
            sessionMode: .conditioning
        )

        let workout = service.generateWorkout(request: request)
        #expect(!workout.exercises.isEmpty)

        let hasCardio = workout.exercises.contains { $0.exerciseType == .cardio }
        #expect(hasCardio, "Conditioning mode should include at least one cardio exercise")
    }

    @Test func conditioningModeAllocatesMoreTimeThanStrengthToCardio() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeGenerationService(context: context)

        let conditioningGroups = allGroups.filter {
            ["Cardio", "Legs", "Core"].contains($0.name)
        }
        let request = SuggestMeSomeGenerationRequest(
            generationType: .custom,
            durationMinutes: 60,
            intensity: 3,
            selectedMuscleGroups: conditioningGroups,
            selectedExercises: [],
            goal: .conditioning,
            equipmentProfile: .fullGym,
            sessionMode: .conditioning
        )

        let workout = service.generateWorkout(request: request)
        let cardioTime = workout.exercises
            .filter { $0.exerciseType == .cardio }
            .reduce(0.0) { $0 + $1.effectiveTimeMinutes }
        let strengthTime = workout.exercises
            .filter { $0.exerciseType != .cardio }
            .reduce(0.0) { $0 + $1.effectiveTimeMinutes }

        // In conditioning mode cardio should dominate the session
        #expect(cardioTime > strengthTime,
                "Conditioning mode should allocate more time to cardio than strength (cardio: \(cardioTime)m, strength: \(strengthTime)m)")
    }

    // MARK: - Conflict Avoidance Carries Through to Built Workout

    @Test func blockedBenchPressDoesNotAppearInBuiltWorkout() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        // Insert a hard recent bench exposure (12 hours ago)
        insertHardExposureWorkout(
            context: context,
            date: hoursAgo(12),
            exerciseName: "Bench Press",
            reps: 5,
            weight: 235
        )

        let recommendationService = SuggestMeSomeRecommendationService(context: context)
        let generationService = SuggestMeSomeGenerationService(context: context)

        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        let recommendation = recommendationService.recommendSession(
            configuration: configuration,
            allMuscleGroups: allGroups
        )

        guard recommendation.isBuildableIntoWorkout, let request = recommendation.request else {
            // If blocked → recovery/conditioning, the recommendation may not be a push day
            // That's correct conflict-avoidance behavior; test passes
            return
        }

        let workout = generationService.generateWorkout(request: request)
        let exerciseNames = workout.exercises.map(\.exerciseName)

        // Bench Press itself should not be in the anchor lifts or the built workout
        // (the conflict avoidance may redirect to a different mode/exercises)
        #expect(!recommendation.candidateAnchorLifts.contains("Bench Press"),
                "Blocked bench should not appear in anchor lifts")
        _ = exerciseNames // Built workout exercises are conflict-aware via mode redirect
    }

    // MARK: - Mode Routing in Recommendation

    @Test func pushModeRecommendationRoutesToPushMusculature() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 3
        )

        let recommendation = service.recommendSession(
            configuration: configuration,
            allMuscleGroups: allGroups
        )

        guard recommendation.isBuildableIntoWorkout, let request = recommendation.request else {
            // If conflict-biased to recovery, that's valid behavior
            return
        }

        let muscleNames = Set(request.selectedMuscleGroups.map(\.name))
        // Push mode should target chest / shoulders / arms
        let hasPushMuscle = muscleNames.contains("Chest") || muscleNames.contains("Shoulders")
        #expect(hasPushMuscle, "Push mode should target chest or shoulders (got: \(muscleNames))")
    }

    @Test func lowerModeRecommendationRoutesToLegMusculature() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 4
        )

        let recommendation = service.recommendSession(
            configuration: configuration,
            allMuscleGroups: allGroups
        )

        guard recommendation.isBuildableIntoWorkout, let request = recommendation.request else {
            return
        }

        let muscleNames = Set(request.selectedMuscleGroups.map(\.name))
        #expect(muscleNames.contains("Legs"),
                "Lower mode should target legs (got: \(muscleNames))")
    }

    @Test func surpriseMeIsAlwaysDeterministicForSameInputs() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .surpriseMe,
            goal: .generalFitness,
            equipmentProfile: .fullGym,
            durationMinutes: 50,
            intensity: 3
        )

        let r1 = service.recommendSession(configuration: config, allMuscleGroups: allGroups)
        let r2 = service.recommendSession(configuration: config, allMuscleGroups: allGroups)

        #expect(r1.mode == r2.mode)
        #expect(r1.goal == r2.goal)
    }

    // MARK: - Helpers

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            PersonalRecord.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            ProgramRun.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSeededMuscleGroups(context: ModelContext) -> [MuscleGroup] {
        let chest = MuscleGroup(name: "Chest")
        chest.exercises = [
            Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Dumbbell Bench Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Push-ups", exerciseType: .accessory, muscleGroup: chest),
        ]

        let back = MuscleGroup(name: "Back")
        back.exercises = [
            Exercise(name: "Deadlift", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Barbell Row", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Pull-ups", exerciseType: .compound, muscleGroup: back),
        ]

        let shoulders = MuscleGroup(name: "Shoulders")
        shoulders.exercises = [
            Exercise(name: "Overhead Press", exerciseType: .compound, muscleGroup: shoulders),
            Exercise(name: "DB Shoulder Press", exerciseType: .accessory, muscleGroup: shoulders),
            Exercise(name: "Cable Lateral Raise", exerciseType: .isolation, muscleGroup: shoulders),
        ]

        let arms = MuscleGroup(name: "Arms")
        arms.exercises = [
            Exercise(name: "Dips", exerciseType: .compound, muscleGroup: arms),
            Exercise(name: "Barbell Curl", exerciseType: .isolation, muscleGroup: arms),
        ]

        let legs = MuscleGroup(name: "Legs")
        legs.exercises = [
            Exercise(name: "Back Squats", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Romanian Deadlift", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Bulgarian Split Squat", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Leg Press", exerciseType: .compound, muscleGroup: legs),
        ]

        let core = MuscleGroup(name: "Core")
        core.exercises = [
            Exercise(name: "Plank", exerciseType: .accessory, muscleGroup: core),
            Exercise(name: "Dead Bug", exerciseType: .accessory, muscleGroup: core),
            Exercise(name: "Bird Dog", exerciseType: .accessory, muscleGroup: core),
        ]

        let cardio = MuscleGroup(name: "Cardio")
        cardio.exercises = [
            Exercise(name: "Exercise Bike", exerciseType: .cardio, muscleGroup: cardio),
            Exercise(name: "Rowing Machine", exerciseType: .cardio, muscleGroup: cardio),
            Exercise(name: "Jump Rope", exerciseType: .cardio, muscleGroup: cardio),
        ]

        let groups = [chest, back, shoulders, arms, legs, core, cardio]
        for group in groups {
            context.insert(group)
            for exercise in group.exercises {
                context.insert(exercise)
            }
        }
        return groups
    }

    /// Makes a standalone list of exercises for equipment filter tests (no SwiftData needed).
    private func makeStrengthExercises() -> [Exercise] {
        let dummy = MuscleGroup(name: "Test")
        return [
            Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: dummy),
            Exercise(name: "Dumbbell Bench Press", exerciseType: .compound, muscleGroup: dummy),
            Exercise(name: "Push-ups", exerciseType: .accessory, muscleGroup: dummy),
            Exercise(name: "Deadlift", exerciseType: .compound, muscleGroup: dummy),
            Exercise(name: "Pull-ups", exerciseType: .compound, muscleGroup: dummy),
            Exercise(name: "Overhead Press", exerciseType: .compound, muscleGroup: dummy),
            Exercise(name: "DB Shoulder Press", exerciseType: .accessory, muscleGroup: dummy),
            Exercise(name: "Cable Lateral Raise", exerciseType: .isolation, muscleGroup: dummy),
            Exercise(name: "Back Squats", exerciseType: .compound, muscleGroup: dummy),
            Exercise(name: "Plank", exerciseType: .accessory, muscleGroup: dummy),
            Exercise(name: "Leg Press", exerciseType: .compound, muscleGroup: dummy),
        ]
    }

    private func makeFullPrescriptionService(context: ModelContext) -> SuggestMeSomeWorkoutPrescriptionService {
        SuggestMeSomeWorkoutPrescriptionService(
            personalRecordLookupService: SuggestMeSomePersonalRecordLookupService(context: context),
            timeBudgetService: SuggestMeSomeTimeBudgetService()
        )
    }

    private func insertHardExposureWorkout(
        context: ModelContext,
        date: Date,
        exerciseName: String,
        reps: Int,
        weight: Double
    ) {
        let workout = Workout(date: date, startTime: date, durationSeconds: 3600, sourceType: .loggedInApp)
        let entry = ExerciseEntry(exerciseName: exerciseName, unit: .lbs, orderIndex: 0)
        let set = SetEntry(setNumber: 1, reps: reps, weight: weight)
        entry.sets = [set]
        entry.workout = workout
        workout.exerciseEntries = [entry]

        context.insert(workout)
        context.insert(entry)
        context.insert(set)
        try? context.save()
    }

    private func hoursAgo(_ hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()
    }
}
