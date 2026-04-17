import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature15Prompt2ProgramGenerationAdaptiveTests {
    private let service = ProgramGenerationService()

    @Test func weekScheduleBuilderAllowsEarlierStepBackWhenRecoverySignalsArePoor() {
        let builder = ProgramGenerationWeekScheduleBuilder()
        let resolver = ProgramGenerationProgressionResolver()
        let profile = service.programmingProfile(for: .powerlifting)
        let strategy = resolver.resolveStrategy(focusProfile: profile, level: .intermediate)
        let snapshot = makeFatiguedSnapshot()
        let dose = DoseTargetProfile(
            weeklyVolumeScale: 0.88,
            fatigueBudgetScale: 0.90,
            intensityScale: 0.96,
            rirOffset: 1.0,
            sessionStressScale: 0.88,
            deloadIntervalOverride: 3,
            accessoryCountAdjustment: -1,
            cardioDurationScale: 0.92,
            preserveAnchorBias: 0.60,
            interferencePenaltyScale: 1.20
        )

        let schedules = builder.buildWeekSchedules(
            strategy: strategy,
            durationWeeks: 8,
            focusProfile: profile,
            trainingState: snapshot,
            doseTargetProfile: dose
        )

        #expect(schedules.contains(where: { $0.weekNumber == 3 && $0.isDeload }))
    }

    @Test func cardioPlannerPrefersExplicitArchetypeOverSessionNameParsing() {
        let planner = ProgramGenerationCardioPlanner()
        let schedule = ProgramGenerationWeekSchedule(
            weekNumber: 2,
            isDeload: false,
            progressionIndex: 1,
            advancedPhase: nil,
            phaseWeekIndex: 0,
            phaseLength: 1
        )
        let profile = service.programmingProfile(for: .cardioEndurance)

        let interval = planner.resolveCardioPrescription(
            sessionName: "Easy Aerobic / Zone 2",
            cardioSessionType: .interval,
            focusProfile: profile,
            schedule: schedule
        )
        let easy = planner.resolveCardioPrescription(
            sessionName: "Easy Aerobic / Zone 2",
            cardioSessionType: .easyAerobic,
            focusProfile: profile,
            schedule: schedule
        )

        #expect(interval.targetRPE > easy.targetRPE)
        #expect(interval.minutes < easy.minutes)
    }

    @Test func adaptiveDoseChangesReduceTotalWorkingSetsWithoutChangingFocusIdentity() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let baseInput = makeInput(
            focus: .powerlifting,
            level: .intermediate,
            durationWeeks: 8,
            sessionsPerWeek: 4
        )
        let adaptiveInput = ProgramGenerationInput(
            focus: baseInput.focus,
            level: baseInput.level,
            durationWeeks: baseInput.durationWeeks,
            sessionsPerWeek: baseInput.sessionsPerWeek,
            oneRepMaxes: baseInput.oneRepMaxes,
            stateSnapshotOverride: makeFatiguedSnapshot()
        )

        let baseline = service.generateProgram(
            input: baseInput,
            context: context,
            shuffleSeed: 301
        )
        let adaptive = service.generateProgram(
            input: adaptiveInput,
            context: context,
            shuffleSeed: 301
        )

        let baselineWeekOneSessions = baseline.weeks
            .first(where: { $0.weekNumber == 1 })?
            .sessions
            .sorted(by: { $0.sessionNumber < $1.sessionNumber }) ?? []
        let adaptiveWeekOneSessions = adaptive.weeks
            .first(where: { $0.weekNumber == 1 })?
            .sessions
            .sorted(by: { $0.sessionNumber < $1.sessionNumber }) ?? []

        #expect(baselineWeekOneSessions.map(\.sessionName) == adaptiveWeekOneSessions.map(\.sessionName))

        let baselineWorkingSets = baseline.weeks
            .flatMap(\.sessions)
            .flatMap(\.exercises)
            .filter { !$0.isWarmup && $0.targetSets != nil }
            .reduce(0) { $0 + ($1.targetSets ?? 0) }
        let adaptiveWorkingSets = adaptive.weeks
            .flatMap(\.sessions)
            .flatMap(\.exercises)
            .filter { !$0.isWarmup && $0.targetSets != nil }
            .reduce(0) { $0 + ($1.targetSets ?? 0) }

        #expect(adaptiveWorkingSets < baselineWorkingSets)
    }

    private func makeInput(
        focus: ProgramFocus,
        level: ProgramLevel,
        durationWeeks: Int,
        sessionsPerWeek: Int
    ) -> ProgramGenerationInput {
        let template = FocusTemplateLibrary.template(for: focus)
        var oneRepMaxes: [String: (weight: Double, unit: String)] = [:]
        for (index, lift) in template.requiredLifts.enumerated() {
            oneRepMaxes[lift] = (weight: 205 + Double(index * 30), unit: "lbs")
        }
        return ProgramGenerationInput(
            focus: focus,
            level: level,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            oneRepMaxes: oneRepMaxes
        )
    }

    private func makeFatiguedSnapshot() -> TrainingStateSnapshot {
        TrainingStateSnapshot(
            historyWindowWorkoutCount: 16,
            hasSparseHistory: false,
            adherenceTier: .low,
            recentVolumeCompletionRate: 0.58,
            fatigueStatus: .high,
            recoveryPressure: .elevated,
            liftMomentumByCanonicalLift: [.bench: .declining],
            perMuscleStressSaturation: [.chest: 1.1, .quads: 1.0],
            preferredAnchorExerciseNames: ["Bench Press"],
            underusedExerciseNames: ["Floor Press"],
            activeProgramInterferenceRisk: 0.78,
            equipmentReliabilityScore: 0.82,
            continuityBias: 0.35,
            blockedCanonicalLifts: [.bench]
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
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
