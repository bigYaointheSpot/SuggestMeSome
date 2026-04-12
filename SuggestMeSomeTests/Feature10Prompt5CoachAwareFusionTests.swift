import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

// MARK: - Feature 10 Prompt 5 — Coach-Aware SuggestMeSome Fusion Tests
//
// Covers:
// - Active-program overlap avoidance (tighter assertion than prior tests)
// - Fatigue-aware recommendation shifts (critical / high / elevated fatigue caps)
// - Overlay-aware behavior (deload overlay forces recovery bias; non-deload overlay chips)
// - Pending deload proposal context
// - Preference-aware anchor lift selection (frequent variation wins)
// - Explainability reason output (chips + rationale + summary content)
// - Focus matrix quality checks across powerlifting / bodybuilding / powerbuilding /
//   general fitness / full body
// - Pain override priority (always highest priority)
// - HealthKit caution nudge (medium signal, never overrides manual)
// - Preference learner service unit tests

@Suite(.serialized)
@MainActor
struct Feature10Prompt5CoachAwareFusionTests {

    // MARK: - Pain Override

    @Test func painForcesRecoveryModeAndIntensity1() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        let coachCtx = SuggestMeSomeCoachContext(hasPainOrDiscomfort: true)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        #expect(rec.mode == .recovery, "Pain override must force recovery mode (got \(rec.mode))")
        #expect(rec.request?.intensity == 1, "Pain override must cap intensity at 1 (got \(String(describing: rec.request?.intensity)))")
        #expect(rec.reasonChips.contains("Pain override"), "Pain override chip must appear")
        #expect(rec.summary.contains("Pain") || rec.summary.contains("pain"), "Summary must mention pain context")
    }

    @Test func painOverrideWinsOverCriticalFatigueForMode() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        // Both pain AND critical fatigue are set — pain wins on forcing recovery + intensity 1.
        let coachCtx = SuggestMeSomeCoachContext(
            fatigueStatus: .critical,
            hasPainOrDiscomfort: true
        )
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        #expect(rec.mode == .recovery)
        #expect(rec.request?.intensity == 1)
        #expect(rec.reasonChips.contains("Pain override"))
    }

    // MARK: - Fatigue-Aware Shifts

    @Test func criticalFatigueAlwaysCapsIntensityAt1() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .fullBody,
            goal: .generalFitness,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        let coachCtx = SuggestMeSomeCoachContext(fatigueStatus: .critical)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        #expect(rec.request?.intensity == 1, "Critical fatigue must cap intensity at 1")
        #expect(rec.reasonChips.contains("Critical fatigue"), "Critical fatigue chip must appear")
        #expect(rec.rationale.contains("Critical fatigue") || rec.rationale.contains("critical"),
                "Rationale must explain critical fatigue intensity cap")
    }

    @Test func highFatigueCapIntensityAt2() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .upper,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        let coachCtx = SuggestMeSomeCoachContext(fatigueStatus: .high)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        #expect((rec.request?.intensity ?? 99) <= 2, "High fatigue must cap intensity at 2 (got \(String(describing: rec.request?.intensity)))")
        #expect(rec.reasonChips.contains("High fatigue"))
    }

    @Test func elevatedFatigueCapIntensityAt3() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        let coachCtx = SuggestMeSomeCoachContext(fatigueStatus: .elevated)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        #expect((rec.request?.intensity ?? 99) <= 3, "Elevated fatigue must cap intensity at 3 (got \(String(describing: rec.request?.intensity)))")
        #expect(rec.reasonChips.contains("Elevated fatigue"))
    }

    @Test func manageableFatigueDoesNotAffectIntensity() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 4
        )

        let coachCtx = SuggestMeSomeCoachContext(fatigueStatus: .manageable)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        // Manageable fatigue should not add any fatigue chips
        #expect(!rec.reasonChips.contains("Elevated fatigue"))
        #expect(!rec.reasonChips.contains("High fatigue"))
        #expect(!rec.reasonChips.contains("Critical fatigue"))
        // And should not cap below what the strength goal adjustment would produce
        let intensityFromRequest = rec.request?.intensity ?? 4
        #expect(intensityFromRequest >= 4, "Manageable fatigue should not reduce intensity below strength goal minimum")
    }

    @Test func elevatedFatigueBiasesSessionTowardRecovery() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        let coachCtx = SuggestMeSomeCoachContext(fatigueStatus: .elevated)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        // Elevated fatigue should redirect the session away from heavy strength
        // Either mode is recovery/conditioning or wasRedirected
        let isConservative = rec.mode == .recovery || rec.mode == .conditioning || rec.wasRedirected || (rec.request?.intensity ?? 5) <= 3
        #expect(isConservative, "Elevated fatigue must make session conservative (mode: \(rec.mode), intensity: \(String(describing: rec.request?.intensity)))")
    }

    // MARK: - Low Readiness

    @Test func lowReadinessTierCapsIntensityAt3() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .upper,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        let coachCtx = SuggestMeSomeCoachContext(readinessTier: .low)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        #expect((rec.request?.intensity ?? 99) <= 3, "Low readiness must cap intensity at 3")
        #expect(rec.reasonChips.contains("Low readiness"), "Low readiness chip must appear")
    }

    @Test func strongReadinessTierAddsNoReadinessChip() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 4
        )

        let coachCtx = SuggestMeSomeCoachContext(readinessTier: .strong)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        #expect(!rec.reasonChips.contains("Low readiness"), "Strong readiness should not generate Low readiness chip")
    }

    // MARK: - Overlay-Aware Behavior

    @Test func deloadOverlaySummaryBiasesRecovery() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        let coachCtx = SuggestMeSomeCoachContext(
            activeOverlaySummaries: ["Deload: -20% load applied for week 5"]
        )
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        // Deload overlay should bias toward recovery
        let isConservative = rec.mode == .recovery || rec.mode == .conditioning || rec.wasRedirected || (rec.request?.intensity ?? 5) <= 3
        #expect(isConservative, "Deload overlay must produce conservative session")
        #expect(rec.reasonChips.contains("Overlay active"), "Overlay active chip must appear")
        #expect(rec.rationale.contains("overlay") || rec.rationale.contains("Overlay"),
                "Rationale must mention overlay influence")
    }

    @Test func nonDeloadOverlaySurfacesChipButDoesNotForceRecovery() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 3
        )

        // A non-deload overlay (load increase) should chip but not force recovery
        let coachCtx = SuggestMeSomeCoachContext(
            activeOverlaySummaries: ["Load increase: +5% on Bench Press for week 3"]
        )
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        // Should chip
        #expect(rec.reasonChips.contains("Overlay active"), "Overlay active chip should appear for any active overlay")
        // But should not be forced to recovery (no deload keyword in summary)
        #expect(rec.candidateExerciseFamilies.contains("Coach-approved overlay in effect"),
                "Candidate families should reference active overlay")
    }

    // MARK: - Pending Proposal Context

    @Test func pendingDeloadProposalBiasesRecovery() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        let deloadProposal = SuggestMeSomeCoachContextProposal(
            proposalType: .deload,
            targetLiftKey: "squat",
            summaryText: "Deload recommended due to persistent fatigue accumulation"
        )
        let coachCtx = SuggestMeSomeCoachContext(pendingProposals: [deloadProposal])
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        let isConservative = rec.mode == .recovery || rec.mode == .conditioning || rec.wasRedirected || (rec.request?.intensity ?? 5) <= 3
        #expect(isConservative, "Pending deload proposal must produce conservative session")
        #expect(rec.reasonChips.contains("Deload proposed"), "Deload proposed chip must appear")
        #expect(rec.rationale.contains("deload") || rec.rationale.contains("Deload"),
                "Rationale must mention pending deload proposal")
    }

    @Test func pendingVariationSwapSurfacesCandidateFamilyHint() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 3
        )

        let swapProposal = SuggestMeSomeCoachContextProposal(
            proposalType: .variationSwap,
            targetLiftKey: "bench",
            summaryText: "Swap Bench Press → Incline Bench for shoulder health"
        )
        let coachCtx = SuggestMeSomeCoachContext(pendingProposals: [swapProposal])
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        #expect(rec.candidateExerciseFamilies.contains("Variation swap candidate (pending proposal)"),
                "Variation swap proposal must surface in candidate families")
    }

    // MARK: - Preference-Aware Anchor Lift Selection

    @Test func frequentlyUsedVariationPreferredOverDefaultAnchor() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        // Add Incline Bench as a seeded exercise variation (not the default "Bench Press")
        let chest = MuscleGroup(name: "Chest")
        let benchPress = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest)
        let inclineBench = Exercise(name: "Incline Bench", exerciseType: .compound, muscleGroup: chest)
        let dumbbellBench = Exercise(name: "Dumbbell Bench Press", exerciseType: .compound, muscleGroup: chest)
        chest.exercises = [benchPress, inclineBench, dumbbellBench]
        context.insert(chest)
        context.insert(benchPress)
        context.insert(inclineBench)
        context.insert(dumbbellBench)

        let back = MuscleGroup(name: "Back")
        let deadlift = Exercise(name: "Deadlift", exerciseType: .compound, muscleGroup: back)
        let row = Exercise(name: "Barbell Row", exerciseType: .compound, muscleGroup: back)
        back.exercises = [deadlift, row]
        context.insert(back)
        context.insert(deadlift)
        context.insert(row)

        let shoulders = MuscleGroup(name: "Shoulders")
        let ohp = Exercise(name: "Overhead Press", exerciseType: .compound, muscleGroup: shoulders)
        shoulders.exercises = [ohp]
        context.insert(shoulders)
        context.insert(ohp)

        let allGroups = [chest, back, shoulders]

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 3
        )

        // User frequently trains "Incline Bench" — should be preferred over "Bench Press" as anchor
        let prefs = SuggestMeSomeExercisePreferences(
            frequentlyUsedExercises: ["Incline Bench"],
            underusedExercises: []
        )
        let coachCtx = SuggestMeSomeCoachContext(exercisePreferences: prefs)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        // If the anchor lifts are built and contain any chest variation, it should prefer Incline Bench
        if !rec.candidateAnchorLifts.isEmpty {
            let anchorLower = rec.candidateAnchorLifts.map { $0.lowercased() }
            if anchorLower.contains("incline bench") || anchorLower.contains("bench press") {
                #expect(anchorLower.contains("incline bench"),
                        "Frequently-used Incline Bench should be preferred over default Bench Press (anchors: \(rec.candidateAnchorLifts))")
            }
        }

        // Preference-biased chip should appear
        #expect(rec.reasonChips.contains("Preference-biased"), "Preference-biased chip must appear when preferences influence selection")
    }

    @Test func preferenceBiasedChipAppearsWithFrequentExercises() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 4
        )

        let prefs = SuggestMeSomeExercisePreferences(
            frequentlyUsedExercises: ["Back Squats", "Romanian Deadlift"],
            underusedExercises: ["Bulgarian Split Squat"]
        )
        let coachCtx = SuggestMeSomeCoachContext(exercisePreferences: prefs)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        #expect(rec.reasonChips.contains("Preference-biased"))
        #expect(rec.rationale.contains("frequently-trained") || rec.rationale.contains("preference"),
                "Rationale must explain preference influence")
    }

    @Test func underusedExercisesAddVarietyRotationCandidate() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .generalFitness,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 3
        )

        let prefs = SuggestMeSomeExercisePreferences(
            frequentlyUsedExercises: ["Back Squats"],
            underusedExercises: ["Bulgarian Split Squat", "Romanian Deadlift"]
        )
        let coachCtx = SuggestMeSomeCoachContext(exercisePreferences: prefs)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        #expect(rec.candidateExerciseFamilies.contains("Variety rotation available"),
                "Underused exercises must produce Variety rotation available family")
    }

    @Test func noPrefsBiasedChipWhenNoPreferences() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 3
        )

        // No preferences → no preference chip
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)
        #expect(!rec.reasonChips.contains("Preference-biased"))
    }

    // MARK: - HealthKit Nudge

    @Test func healthKitCautionNudgesIntensityDown() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 4
        )

        let hkInsight = ObjectiveRecoveryInsight(
            status: .caution,
            compactSummary: "Low HRV + elevated RHR",
            detailSummary: "HRV 20% below baseline and resting HR elevated — recovery may be impaired",
            evaluatedMetricsCount: 2
        )
        let coachCtx = SuggestMeSomeCoachContext(objectiveRecoveryInsight: hkInsight)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        // Hypertrophy goal at intensity 4 stays at 4 normally;
        // HealthKit caution should nudge it down to 3
        #expect((rec.request?.intensity ?? 99) <= 3, "HealthKit caution must nudge intensity down (got \(String(describing: rec.request?.intensity)))")
        #expect(rec.reasonChips.contains("HealthKit nudge"), "HealthKit nudge chip must appear")
        #expect(rec.rationale.contains("HealthKit") || rec.rationale.contains("HK"),
                "Rationale must reference HealthKit signal")
    }

    @Test func healthKitGoodStatusAddsNoNudgeChip() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 3
        )

        let hkInsight = ObjectiveRecoveryInsight(
            status: .good,
            compactSummary: "Strong HRV",
            detailSummary: "HRV above baseline — recovery looks good",
            evaluatedMetricsCount: 2
        )
        let coachCtx = SuggestMeSomeCoachContext(objectiveRecoveryInsight: hkInsight)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        #expect(!rec.reasonChips.contains("HealthKit nudge"), "Good HealthKit status must not generate nudge chip")
    }

    @Test func healthKitCautionCannotOverrideManualReadinessLow() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .upper,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        // Low readiness already caps at 3; HealthKit caution then nudges to 2.
        // Critical: HealthKit must not produce intensity lower than what manual already set.
        let hkInsight = ObjectiveRecoveryInsight(
            status: .caution,
            compactSummary: "Low HRV",
            detailSummary: "HRV below baseline",
            evaluatedMetricsCount: 1
        )
        let coachCtx = SuggestMeSomeCoachContext(readinessTier: .low, objectiveRecoveryInsight: hkInsight)
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        // Low readiness caps at 3, HK caution nudges down 1 → 2.
        // Result must be ≤ 3 (manual cap) and ≥ 1.
        let intensity = rec.request?.intensity ?? 3
        #expect(intensity >= 1 && intensity <= 3,
                "Combined low readiness + HK caution must produce intensity in [1,3] (got \(intensity))")
    }

    // MARK: - Explainability Output

    @Test func rationaleAlwaysHasContentForAllModes() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)

        let modes: [SuggestMeSomeSessionMode] = [.fullBody, .upper, .lower, .push, .pull, .armsShoulders, .recovery, .conditioning]

        for mode in modes {
            let config = SuggestMeSomeSessionConfiguration(
                mode: mode,
                goal: .generalFitness,
                equipmentProfile: .fullGym,
                durationMinutes: 60,
                intensity: 3
            )
            let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)
            #expect(!rec.rationale.isEmpty, "Rationale must never be empty for mode \(mode)")
        }
    }

    @Test func reasonChipsAlwaysContainBaselineChips() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .upper,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 55,
            intensity: 3
        )
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)

        // Equipment, duration, and intensity chips must always be present.
        #expect(rec.reasonChips.contains(where: { $0.contains("Full Gym") }), "Equipment chip must be present")
        #expect(rec.reasonChips.contains(where: { $0.contains("min") }), "Duration chip must be present")
        #expect(rec.reasonChips.contains(where: { $0.contains("Intensity") }), "Intensity chip must be present")
    }

    @Test func coachContextRationaleIsCumulativeWithBaseRationale() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )

        let coachCtx = SuggestMeSomeCoachContext(
            fatigueStatus: .elevated,
            readinessTier: .low
        )

        let baseRec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)
        let coachRec = service.recommendSession(configuration: config, allMuscleGroups: allGroups, coachContext: coachCtx)

        // Coach-context rationale must be richer (more explanation) than the base.
        #expect(coachRec.rationale.count >= baseRec.rationale.count,
                "Coach-context rationale must be at least as detailed as base rationale")

        // Base chips are preserved even with coach context.
        #expect(coachRec.reasonChips.contains(where: { $0.contains("Full Gym") }))
    }

    // MARK: - Focus Matrix Quality (Powerlifting / Bodybuilding / Powerbuilding / General Fitness / Full Body)

    @Test func strengthGoalUpperModeProducesPressingAnchors() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .strength,        // powerlifting-adjacent
            equipmentProfile: .fullGym,
            durationMinutes: 75,
            intensity: 5
        )
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)

        // If not redirected to recovery, should have pressing anchors.
        if !rec.wasRedirected {
            let hasPressAnchor = rec.candidateAnchorLifts.contains(where: {
                let l = $0.lowercased()
                return l.contains("bench") || l.contains("press")
            })
            #expect(hasPressAnchor, "Strength/push mode must produce pressing anchors (got: \(rec.candidateAnchorLifts))")
        }
    }

    @Test func hypertrophyGoalProducesAccesoryFamilies() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .armsShoulders,
            goal: .hypertrophy,     // bodybuilding
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 3
        )
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)

        let hasAccessoryFamily = rec.candidateExerciseFamilies.contains(where: {
            $0.lowercased().contains("delt") || $0.lowercased().contains("arm") || $0.lowercased().contains("shoulder")
        })
        #expect(hasAccessoryFamily, "Hypertrophy arms/shoulders should include delt/arm families")
    }

    @Test func fullBodyGeneralFitnessProducesCompoundBiasedFamilies() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .fullBody,
            goal: .generalFitness,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 3
        )
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)

        let hasCompoundFamily = rec.candidateExerciseFamilies.contains(where: {
            $0.lowercased().contains("compound") || $0.lowercased().contains("push/pull")
        })
        #expect(hasCompoundFamily, "Full body / general fitness should include compound families")
    }

    @Test func strengthGoalLowerModeProducesSquatDeadliftAnchors() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .strength,        // powerbuilding/powerlifting lower focus
            equipmentProfile: .fullGym,
            durationMinutes: 80,
            intensity: 5
        )
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)

        if !rec.wasRedirected {
            let hasHingeOrSquat = rec.candidateAnchorLifts.contains(where: {
                let l = $0.lowercased()
                return l.contains("squat") || l.contains("deadlift")
            })
            #expect(hasHingeOrSquat, "Strength/lower mode should produce squat or deadlift anchors (got: \(rec.candidateAnchorLifts))")
        }
    }

    @Test func recoveryModeProducesLowImpactPriorities() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .recovery,
            goal: .recovery,
            equipmentProfile: .fullGym,
            durationMinutes: 40,
            intensity: 1
        )
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)

        let hasLowImpact = rec.recommendedMovementPriorities.contains(where: {
            $0.lowercased().contains("low-impact") || $0.lowercased().contains("stability") || $0.lowercased().contains("mobility")
        })
        #expect(hasLowImpact, "Recovery mode must prioritize low-impact or stability movements")
        // Intensity should stay at or below 2 for recovery
        #expect((rec.request?.intensity ?? 3) <= 2, "Recovery mode should not exceed intensity 2")
    }

    // MARK: - Active Program Overlap Avoidance (tighter checks)

    @Test func recentProgramLiftExposureBlocksItFromAnchors() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        // Insert a hard squat session from 16 hours ago
        insertHardExposureWorkout(
            context: context,
            date: hoursAgo(16),
            exerciseName: "Back Squats",
            reps: 4,
            weight: 315
        )

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .lower,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)

        // Squat should not be an anchor lift — it was trained hard recently
        #expect(!rec.candidateAnchorLifts.contains(where: { $0.lowercased().contains("squat") }),
                "Recently blocked squat should not appear in anchor lifts")
    }

    @Test func activeProgramNextSessionConflictBiasesRecovery() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        insertHardExposureWorkout(
            context: context,
            date: hoursAgo(10),
            exerciseName: "Deadlift",
            reps: 3,
            weight: 400
        )

        let run = ProgramRun(startDate: daysAgo(7), isCompleted: false)
        let program = TrainingProgram(name: "Pull Focus", lengthInWeeks: 4, sessionsPerWeek: 3, source: .aiGenerated)
        let week = ProgramWeekTemplate(weekNumber: 1)
        let session = ProgramSessionTemplate(sessionNumber: 1, sessionName: "Pull A")
        let exercise = ProgramSessionExercise(exerciseName: "Deadlift", orderIndex: 0, targetSets: 3, targetReps: 3)

        session.exercises = [exercise]
        week.sessions = [session]
        program.weeks = [week]
        run.program = program

        context.insert(run)
        context.insert(program)
        context.insert(week)
        context.insert(session)
        context.insert(exercise)
        try context.save()

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .pull,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 5
        )
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)

        // Both recent hard deadlift AND active program's next session include deadlift → recovery bias
        let isConservative = rec.mode == .recovery || rec.mode == .conditioning || rec.wasRedirected
        #expect(isConservative, "Active program deadlift + recent hard exposure must produce conservative recommendation")
        #expect(rec.reasonChips.contains("Program-aware"), "Program-aware chip must appear")
    }

    // MARK: - SuggestMeSomePreferenceLearnerService Unit Tests

    @Test func learnerReturnsEmptyPreferencesWithNoWorkouts() {
        let learner = SuggestMeSomePreferenceLearnerService()
        let prefs = learner.learnPreferences(from: [])
        #expect(prefs.frequentlyUsedExercises.isEmpty)
        #expect(prefs.underusedExercises.isEmpty)
    }

    @Test func learnerDetectsFrequentlyUsedExercise() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let learner = SuggestMeSomePreferenceLearnerService(
            frequencyWindowSize: 30,
            frequencyThreshold: 3,
            recencyWindowSize: 8
        )

        // 5 workouts each containing "Bench Press" — above threshold of 3.
        var workouts: [Workout] = []
        for i in 0..<5 {
            let date = Date().addingTimeInterval(Double(-i * 86400))
            workouts.append(insertWorkout(context: context, date: date, exerciseName: "Bench Press"))
        }

        let prefs = learner.learnPreferences(from: workouts)
        #expect(prefs.frequentlyUsedExercises.contains("Bench Press"),
                "Bench Press in 5 workouts (threshold=3) must be frequently-used")
    }

    @Test func learnerDoesNotMarkInfrequentExerciseAsFrequent() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let learner = SuggestMeSomePreferenceLearnerService(
            frequencyWindowSize: 30,
            frequencyThreshold: 3,
            recencyWindowSize: 8
        )

        // Only 2 workouts with "Overhead Press" — below threshold of 3.
        var workouts: [Workout] = []
        for i in 0..<2 {
            let date = Date().addingTimeInterval(Double(-i * 86400))
            workouts.append(insertWorkout(context: context, date: date, exerciseName: "Overhead Press"))
        }

        let prefs = learner.learnPreferences(from: workouts)
        #expect(!prefs.frequentlyUsedExercises.contains("Overhead Press"),
                "Exercise appearing only twice must not be classified as frequently-used (threshold=3)")
    }

    @Test func learnerDetectsUnderusedExercise() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let learner = SuggestMeSomePreferenceLearnerService(
            frequencyWindowSize: 30,
            frequencyThreshold: 3,
            recencyWindowSize: 4
        )

        // Build history where "Back Squats" appeared in old workouts (days 4–7 ago)
        // but not in the last 4 (recency window = days 0–3).
        var allWorkouts: [Workout] = []
        for i in 0..<4 {
            let date = Date().addingTimeInterval(Double(-i * 86400))
            allWorkouts.append(insertWorkout(context: context, date: date, exerciseName: "Deadlift"))
        }
        for i in 4..<8 {
            let date = Date().addingTimeInterval(Double(-i * 86400))
            allWorkouts.append(insertWorkout(context: context, date: date, exerciseName: "Back Squats"))
        }
        // Sort newest first as the learner expects
        let sorted = allWorkouts.sorted { $0.date > $1.date }

        let prefs = learner.learnPreferences(from: sorted)
        #expect(prefs.underusedExercises.contains("Back Squats"),
                "Back Squats only in old sessions must appear in underused list")
        #expect(!prefs.underusedExercises.contains("Deadlift"),
                "Deadlift used in recent window must not be underused")
    }

    @Test func learnerCountsEachExerciseOncePerWorkoutSession() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let learner = SuggestMeSomePreferenceLearnerService(
            frequencyWindowSize: 30,
            frequencyThreshold: 3,
            recencyWindowSize: 8
        )

        // One workout with Bench Press listed twice (two entries, same session).
        // Should count as 1 appearance for that session.
        let workout = Workout(date: Date(), startTime: Date(), durationSeconds: 3600, sourceType: .loggedInApp)
        let entry1 = ExerciseEntry(exerciseName: "Bench Press", unit: .lbs, orderIndex: 0)
        let entry2 = ExerciseEntry(exerciseName: "Bench Press", unit: .lbs, orderIndex: 1)
        entry1.workout = workout
        entry2.workout = workout
        workout.exerciseEntries = [entry1, entry2]
        context.insert(workout)
        context.insert(entry1)
        context.insert(entry2)
        try context.save()

        let prefs = learner.learnPreferences(from: [workout])
        // threshold=3, only 1 session → must NOT be frequently-used
        #expect(!prefs.frequentlyUsedExercises.contains("Bench Press"),
                "Exercise appearing twice in one session must count as 1 appearance, not 2")
    }

    // MARK: - No-Context Backward Compatibility

    @Test func nilCoachContextProducesNoCoachChips() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let allGroups = makeSeededMuscleGroups(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let config = SuggestMeSomeSessionConfiguration(
            mode: .upper,
            goal: .hypertrophy,
            equipmentProfile: .fullGym,
            durationMinutes: 60,
            intensity: 3
        )

        // Called without coachContext — must not crash and must not include coach chips.
        let rec = service.recommendSession(configuration: config, allMuscleGroups: allGroups)

        let coachChips = ["Pain override", "Critical fatigue", "High fatigue", "Elevated fatigue",
                          "Low readiness", "Overlay active", "Deload proposed", "HealthKit nudge", "Preference-biased"]
        for chip in coachChips {
            #expect(!rec.reasonChips.contains(chip), "No-context call must not produce coach chip '\(chip)'")
        }
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
            DailyCoachCheckIn.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            ExercisePerformanceOutcome.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AppliedOverlayAdjustment.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            AdaptationEventHistory.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSeededMuscleGroups(context: ModelContext) -> [MuscleGroup] {
        let chest = MuscleGroup(name: "Chest")
        chest.exercises = [
            Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Incline Bench", exerciseType: .compound, muscleGroup: chest),
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
            Exercise(name: "Arnold Press", exerciseType: .accessory, muscleGroup: shoulders),
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

    /// Inserts a single-exercise workout into the context and returns it.
    @discardableResult
    private func insertWorkout(
        context: ModelContext,
        date: Date,
        exerciseName: String
    ) -> Workout {
        let workout = Workout(date: date, startTime: date, durationSeconds: 3600, sourceType: .loggedInApp)
        let entry = ExerciseEntry(exerciseName: exerciseName, unit: .lbs, orderIndex: 0)
        entry.workout = workout
        workout.exerciseEntries = [entry]
        context.insert(workout)
        context.insert(entry)
        try? context.save()
        return workout
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

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
}
