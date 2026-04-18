import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
struct Feature15Prompt5CoachVoiceRenderTests {

    @MainActor
    @Test func dailyCoachViewRendersCollapsedAndExpandedStates() throws {
        let container = try makeInMemoryContainer()
        let defaults = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let activeWorkoutSessionStore = ActiveWorkoutSessionStore(
            userDefaults: defaults,
            persistenceKey: "activeWorkoutSession.render.tests"
        )
        let purchaseManager = PurchaseManager(
            userDefaults: defaults,
            startListeningForTransactions: false
        )

        let collapsed = DailyCoachView(recommendationExpanded: false)
            .modelContainer(container)
            .environment(activeWorkoutSessionStore)
            .environment(purchaseManager)
        let expanded = DailyCoachView(recommendationExpanded: true)
            .modelContainer(container)
            .environment(activeWorkoutSessionStore)
            .environment(purchaseManager)

        assertRenders(collapsed, size: CGSize(width: 393, height: 852))
        assertRenders(expanded, size: CGSize(width: 393, height: 932))
    }

    @MainActor
    @Test func generatorRecommendationAndBuildViewsRenderCoachHierarchy() throws {
        let container = try makeInMemoryContainer()
        let viewModel = SuggestMeSomeGeneratorFlowViewModel(context: container.mainContext)
        viewModel.recommendation = makeSessionRecommendation()
        viewModel.generatedWorkout = makeGeneratedWorkout()

        let recommendationView = SuggestMeSomeRecommendationStepView(
            viewModel: viewModel,
            onBuildWorkout: {}
        )
        let buildView = SuggestMeSomeBuildStepView(
            viewModel: viewModel,
            onStart: { _ in }
        )

        assertRenders(recommendationView, size: CGSize(width: 393, height: 852))
        assertRenders(buildView, size: CGSize(width: 393, height: 932))
    }

    @MainActor
    @Test func nextBlockPrimaryCardRendersCoachCall() {
        let card = NextBlockRecommendationCard(
            recommendation: makeNextBlockRecommendation(),
            style: .primary,
            isSelected: true,
            onTap: {}
        )

        assertRenders(card.padding(), size: CGSize(width: 393, height: 420))
    }

    private var defaultsSuiteName: String {
        "Feature15Prompt5CoachVoiceRenderTests"
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
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
            AppliedOverlayAdjustment.self,
            AdaptationEventHistory.self,
            DailyCoachCheckIn.self,
            DailyCoachWeeklyReview.self,
            HealthKitDailySummary.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSessionRecommendation() -> SuggestMeSomeSessionRecommendation {
        SuggestMeSomeSessionRecommendation(
            title: "Upper Pull Reset",
            summary: "Keep your main pull pattern moving without stacking more pressing fatigue today.",
            rationale: "Recent pressing volume is already high, and the next planned work benefits more from rows, bracing, and lower overlap.",
            reasonChips: ["Program-aware", "High recent overlap", "Anchor continuity"],
            wasRedirected: true,
            mode: .pull,
            goal: .strength,
            continuitySummary: "You pushed pressing recently, so today stays with pulls and trunk work.",
            nextActionGuidance: "Build this session and keep the first pull as the anchor.",
            recommendedMovementPriorities: ["Horizontal pull", "Bracing"],
            candidateExerciseFamilies: ["Rows", "Rear delts"],
            candidateAnchorLifts: ["Barbell Row"],
            isBuildableIntoWorkout: true,
            request: SuggestMeSomeGenerationRequest(
                generationType: .custom,
                durationMinutes: 45,
                intensity: 3,
                goal: .strength,
                equipmentProfile: .fullGym,
                sessionMode: .pull,
                steeringProfile: .balanced
            ),
            explanationBundle: makeExplanationBundle(
                summary: "The coach protected continuity, kept overlap low, and left the session buildable."
            )
        )
    }

    private func makeGeneratedWorkout() -> GeneratedWorkout {
        let back = MuscleGroup(name: "Back")
        let arms = MuscleGroup(name: "Arms")
        let row = Exercise(name: "Barbell Row", exerciseType: .compound, muscleGroup: back)
        let curl = Exercise(name: "Hammer Curl", exerciseType: .isolation, muscleGroup: arms)

        let rowSets = [
            GeneratedSet(setNumber: 1, isWarmup: true, suggestedReps: 8, suggestedWeight: 95, unit: .lbs),
            GeneratedSet(setNumber: 2, isWarmup: false, suggestedReps: 6, suggestedWeight: 135, unit: .lbs),
            GeneratedSet(setNumber: 3, isWarmup: false, suggestedReps: 6, suggestedWeight: 135, unit: .lbs),
        ]
        let curlSets = [
            GeneratedSet(setNumber: 1, isWarmup: false, suggestedReps: 12, suggestedWeight: 25, unit: .lbs),
            GeneratedSet(setNumber: 2, isWarmup: false, suggestedReps: 12, suggestedWeight: 25, unit: .lbs),
        ]

        return GeneratedWorkout(
            exercises: [
                GeneratedExercise(exercise: row, sets: rowSets, effectiveTimeMinutes: 18),
                GeneratedExercise(exercise: curl, sets: curlSets, effectiveTimeMinutes: 10),
            ],
            totalEstimatedMinutes: 42,
            intensity: 3,
            generationType: .custom,
            adaptationNote: "Kept the first pull as the anchor and trimmed extra overlap.",
            explanationBundle: makeExplanationBundle(
                summary: "The build kept a familiar row anchor, protected recovery, and left only the highest-value accessory work."
            )
        )
    }

    private func makeExplanationBundle(summary: String) -> AdaptiveExplanationBundle {
        AdaptiveExplanationBundle(
            category: .dailySession,
            summary: summary,
            topReasons: [.activeProgramProtection, .preferredAnchorPreserved, .fatigueProtection],
            adjustments: [
                AdaptiveAdjustment(
                    key: "volume",
                    title: "Working sets",
                    baseValue: "4",
                    personalizedValue: "3",
                    reasonCodes: [.fatigueProtection],
                    guardrailsApplied: ["Kept the main pull slot intact."]
                )
            ],
            protectedConstraints: ["Main pull anchor stayed in place."],
            carryForwardSources: [
                AdaptiveCarryForwardSource(
                    key: "continuity",
                    title: "Recent continuity",
                    detail: "Rows have been sticking well, so the session keeps that anchor."
                )
            ],
            governance: .automatic,
            steeringPreview: [
                AdaptiveSteeringPreview(
                    key: "recovery",
                    title: "Recovery stayed balanced",
                    effectText: "The session trims low-value work before it changes the anchor.",
                    governance: .automatic
                )
            ]
        )
    }

    private func makeNextBlockRecommendation() -> MesocycleNextBlockRecommendation {
        let prefill = MesocycleNextBlockPrefill(
            sourceProgramRunStableID: "run-1",
            focus: .powerbuilding,
            level: .intermediate,
            durationWeeks: 6,
            sessionsPerWeek: 4,
            oneRepMaxSuggestions: []
        )

        return MesocycleNextBlockRecommendation(
            stableID: "next-block-1",
            rank: 1,
            kind: .repeatFocus,
            title: "Keep the same focus, but clean up the weekly shape",
            summary: "Powerbuilding still fits best, but the next block should stay tighter and more repeatable.",
            rationale: [
                "You kept the strongest adherence when the week stayed at four sessions.",
                "Your main lifts still progressed inside the current focus.",
                "The last block only needs a small cleanup rather than a full pivot."
            ],
            targetFocus: .powerbuilding,
            targetFocusDisplayName: "Powerbuilding",
            suggestedLevel: .intermediate,
            suggestedDurationWeeks: 6,
            suggestedSessionsPerWeek: 4,
            decision: .pending,
            prefill: prefill,
            isPrimaryRecommendation: true,
            fitScore: 88,
            fitNote: "Strong fit",
            requiresExplicitAcceptance: true,
            explanationBundle: makeExplanationBundle(
                summary: "The recommendation keeps the same focus, preserves the productive block shape, and only trims friction."
            )
        )
    }

    @MainActor
    private func assertRenders<V: View>(_ view: V, size: CGSize) {
        let content = view
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color.white)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1

        let image = renderer.uiImage
        #expect(image != nil)
        #expect((image?.pngData()?.isEmpty ?? true) == false)
    }
}
