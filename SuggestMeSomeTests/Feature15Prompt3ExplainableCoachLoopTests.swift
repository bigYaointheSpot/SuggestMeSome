import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature15Prompt3ExplainableCoachLoopTests {
    @Test func programAdaptivePreviewIncludesSteeringAndCarryForwardExplainability() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let service = ProgramGenerationService()

        let input = ProgramGenerationInput(
            focus: .powerlifting,
            level: .intermediate,
            durationWeeks: 8,
            sessionsPerWeek: 4,
            oneRepMaxes: [
                "Back Squats": (315, "lbs"),
                "Bench Press": (235, "lbs"),
                "Deadlift": (405, "lbs"),
            ],
            carryForwardContext: ProgramGenerationCarryForwardContext(
                sourceProgramRunStableID: "source-run",
                recommendationStableID: "rec-1",
                suggestedStyle: .dup,
                preservedExerciseNames: ["Bench Press", "Back Squats"],
                rationaleText: "Keep the strongest anchors from the prior block."
            ),
            stateSnapshotOverride: makeModerateSnapshot(),
            steeringProfile: AdaptiveSteeringProfile(
                progressionBias: .balanced,
                recoveryBias: .protectRecovery,
                continuityBias: .preserveAnchors
            )
        )

        let preview = service.previewAdaptiveContext(input: input, context: context)

        #expect(preview.explanationBundle.governance == .reviewRequired)
        #expect(preview.explanationBundle.topReasons.contains(.recoveryBiasProtect))
        #expect(preview.explanationBundle.topReasons.contains(.continuityBiasPreserve))
        #expect(preview.explanationBundle.carryForwardSources.contains {
            $0.title == "Preserved Exercises"
        })
        #expect(preview.explanationBundle.adjustments.contains {
            $0.key == "anchor-continuity" && $0.personalizedValue.contains("Preserve anchors")
        })
    }

    @Test func nextBlockRecommendationsCarryForwardSteeringAndExplainability() throws {
        let continuitySnapshot = ProgramBlockContinuitySnapshot(
            sourceProgramRunStableID: "prior-run",
            sourceTrainingProgramStableID: "prior-program",
            reviewStableID: "review-1",
            sourceProgramName: "Prior Block",
            snapshotRecordedAt: Date(),
            recommendationSnapshots: [
                ProgramRunRecommendationSnapshot(recommendation: MesocycleReviewSnapshot.mock.rankedRecommendations[0])
            ],
            selectedRecommendationStableID: MesocycleReviewSnapshot.mock.rankedRecommendations[0].stableID,
            selectedRecommendationSnapshot: ProgramRunRecommendationSnapshot(
                recommendation: MesocycleReviewSnapshot.mock.rankedRecommendations[0]
            ),
            declinedRecommendationStableIDs: [],
            decisionEvents: [],
            carriedForwardContext: ProgramGenerationCarryForwardContext(
                sourceProgramRunStableID: "prior-run",
                recommendationStableID: MesocycleReviewSnapshot.mock.rankedRecommendations[0].stableID,
                suggestedStyle: .dup,
                preservedExerciseNames: ["Squat", "Deadlift"],
                rationaleText: "Carry forward the powerlifting anchors.",
                steeringProfile: AdaptiveSteeringProfile(
                    progressionBias: .balanced,
                    recoveryBias: .balanced,
                    continuityBias: .preserveAnchors
                )
            ),
            editedPrefillSnapshot: nil,
            userEditedFields: [],
            latestConfirmedSteeringProfile: AdaptiveSteeringProfile(
                progressionBias: .balanced,
                recoveryBias: .balanced,
                continuityBias: .preserveAnchors
            )
        )

        let recommendations = NextBlockRecommendationEngine.rankedRecommendations(
            input: MesocycleReviewSnapshot.mock.recommendationInput,
            currentDurationWeeks: 8,
            currentSessionsPerWeek: 3,
            completionEndDate: Date(),
            personalRecords: [],
            workoutsInWindow: [],
            continuitySnapshot: continuitySnapshot
        )

        #expect(!recommendations.isEmpty)
        #expect(recommendations[0].prefill.steeringProfile == continuitySnapshot.latestConfirmedSteeringProfile)
        #expect(recommendations[0].explanationBundle?.topReasons.contains(.acceptedContinuityHistory) == true)
        #expect(recommendations[0].prefill.explanationBundle != nil)
    }

    @Test func dailyRecommendationCarriesSteeringIntoRequestAndExplanation() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let groups = makeSeededMuscleGroups(context: context)
        seedActiveProgram(context: context)

        let steering = AdaptiveSteeringProfile(
            progressionBias: .balanced,
            recoveryBias: .protectRecovery,
            continuityBias: .preserveAnchors
        )
        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 50,
            intensity: 4
        )

        let recommendation = service.recommendSession(
            configuration: configuration,
            allMuscleGroups: groups,
            steeringProfile: steering
        )

        #expect(recommendation.request?.steeringProfile == steering)
        #expect(recommendation.explanationBundle?.governance == .automatic)
        #expect(recommendation.explanationBundle?.topReasons.contains(.activeProgramProtection) == true)
        #expect(recommendation.explanationBundle?.topReasons.contains(.continuityBiasPreserve) == true)
    }

    @Test func generatedWorkoutAppliesRecoveryGuardrailsOverAggressiveSteering() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let groups = makeSeededMuscleGroups(context: context)
        let service = SuggestMeSomeGenerationService(context: context)

        let request = SuggestMeSomeGenerationRequest(
            generationType: .custom,
            durationMinutes: 45,
            intensity: 5,
            selectedMuscleGroups: groups.filter { ["Chest", "Shoulders", "Arms", "Back"].contains($0.name) },
            selectedExercises: [],
            goal: .strength,
            equipmentProfile: .fullGym,
            sessionMode: .push,
            activeProgramContext: DailyProgramContext(
                shouldSupportActiveProgram: true,
                activeProgramName: "Powerlifting",
                nextSessionName: "Bench Priority",
                nextSessionMode: .push,
                nextSessionAnchorExercises: ["Bench Press"],
                missedMovementFamilies: ["horizontalPull"],
                blockedCanonicalLifts: [.bench],
                interferenceScore: 0.92
            ),
            stateSnapshotOverride: TrainingStateSnapshot(
                historyWindowWorkoutCount: 18,
                hasSparseHistory: false,
                adherenceTier: .moderate,
                recentVolumeCompletionRate: 0.78,
                fatigueStatus: .high,
                recoveryPressure: .elevated,
                liftMomentumByCanonicalLift: [.bench: .stable],
                perMuscleStressSaturation: [.chest: 1.0],
                preferredAnchorExerciseNames: ["Bench Press"],
                underusedExerciseNames: ["Barbell Row"],
                activeProgramInterferenceRisk: 0.90,
                equipmentReliabilityScore: 0.90,
                continuityBias: 0.50,
                blockedCanonicalLifts: [.bench]
            ),
            steeringProfile: AdaptiveSteeringProfile(
                progressionBias: .push,
                recoveryBias: .trainThrough,
                continuityBias: .balanced
            )
        )

        let workout = service.generateWorkout(request: request)

        #expect(workout.intensity <= 3)
        #expect(workout.explanationBundle?.protectedConstraints.contains {
            $0.contains("Blocked next-session lifts")
        } == true)
        #expect(workout.explanationBundle?.topReasons.contains(.interferenceGuardrail) == true)
    }

    @Test func continuityStorePersistsConfirmedSteeringAndAdjustmentSnapshot() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let program = TrainingProgram(
            name: "Powerlifting",
            lengthInWeeks: 8,
            sessionsPerWeek: 4,
            source: .aiGenerated
        )
        let run = ProgramRun(startDate: Date())
        run.program = program
        context.insert(program)
        context.insert(run)

        let steering = AdaptiveSteeringProfile(
            progressionBias: .push,
            recoveryBias: .balanced,
            continuityBias: .preserveAnchors
        )
        let adjustment = AdaptiveAdjustment(
            key: "anchor-continuity",
            title: "Anchor Continuity",
            baseValue: "Balanced rotation",
            personalizedValue: "Preserve anchors when they fit the block",
            reasonCodes: [.continuityBiasPreserve, .preferredAnchorPreserved],
            guardrailsApplied: ["Replacing preserved anchors remains a review-required change."]
        )
        let editedPrefill = NextBlockPrefillContext(
            sourceProgramRunStableID: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.sourceProgramRunStableID,
            recommendationStableID: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.recommendationStableID,
            focus: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.focus,
            style: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.style,
            level: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.level,
            durationWeeks: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.durationWeeks,
            sessionsPerWeek: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.sessionsPerWeek,
            oneRepMaxSuggestions: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.oneRepMaxSuggestions,
            preservedExerciseNames: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.preservedExerciseNames,
            rationaleText: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.rationaleText,
            valueSources: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.valueSources,
            intensityContext: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.intensityContext,
            notes: MesocycleReviewSnapshot.mock.defaultNextBlockPrefill.notes,
            steeringProfile: steering,
            explanationBundle: AdaptiveExplanationBundle(
                category: .nextBlockRecommendation,
                summary: "Preserve the strongest anchors while keeping the next block editable.",
                topReasons: [.continuityBiasPreserve],
                adjustments: [adjustment],
                protectedConstraints: ["Block-level changes stay review-gated."],
                carryForwardSources: [],
                governance: .reviewRequired,
                steeringPreview: []
            )
        )

        ProgramRunContinuityService.recordDecision(
            on: run,
            review: .mock,
            recommendation: MesocycleReviewSnapshot.mock.rankedRecommendations[0],
            decision: .accepted,
            editedPrefill: editedPrefill,
            steeringProfile: steering
        )

        let stored = run.recommendationDecisionHistorySnapshot
        #expect(stored?.latestConfirmedSteeringProfile == steering)
        #expect(stored?.latestEditedAdjustments?.first?.key == "anchor-continuity")
        #expect(stored?.decisionEvents.last?.confirmedSteeringProfile == steering)
    }

    private func makeModerateSnapshot() -> TrainingStateSnapshot {
        TrainingStateSnapshot(
            historyWindowWorkoutCount: 16,
            hasSparseHistory: false,
            adherenceTier: .moderate,
            recentVolumeCompletionRate: 0.84,
            fatigueStatus: .manageable,
            recoveryPressure: .neutral,
            liftMomentumByCanonicalLift: [.bench: .improving],
            perMuscleStressSaturation: [.chest: 0.82],
            preferredAnchorExerciseNames: ["Bench Press", "Back Squats"],
            underusedExerciseNames: ["Pause Squat"],
            activeProgramInterferenceRisk: 0.24,
            equipmentReliabilityScore: 0.90,
            continuityBias: 0.52,
            blockedCanonicalLifts: []
        )
    }

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
            ExercisePerformanceOutcome.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AdaptationEventHistory.self,
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
            Exercise(name: "Barbell Row", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Pull-ups", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Deadlift", exerciseType: .compound, muscleGroup: back),
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
        ]

        let core = MuscleGroup(name: "Core")
        core.exercises = [
            Exercise(name: "Plank", exerciseType: .accessory, muscleGroup: core),
            Exercise(name: "Dead Bug", exerciseType: .accessory, muscleGroup: core),
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

    private func seedActiveProgram(context: ModelContext) {
        let program = TrainingProgram(
            name: "Powerlifting",
            lengthInWeeks: 8,
            sessionsPerWeek: 4,
            source: .aiGenerated
        )
        let run = ProgramRun(startDate: Date())
        run.program = program

        let week = ProgramWeekTemplate(weekNumber: 1)
        week.program = program
        let session = ProgramSessionTemplate(sessionNumber: 1, sessionName: "Bench Priority")
        session.week = week
        let bench = ProgramSessionExercise(exerciseName: "Bench Press", orderIndex: 0)
        bench.session = session
        session.exercises = [bench]
        week.sessions = [session]
        program.weeks = [week]

        context.insert(program)
        context.insert(run)
        context.insert(week)
        context.insert(session)
        context.insert(bench)
    }
}
