import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature10Prompt3ProgramGeneratorDecompositionTests {
    private let service = ProgramGenerationService()

    @Test func progressionResolverAndWeekScheduleBuilderPreservePolicyMapping() {
        let progressionResolver = ProgramGenerationProgressionResolver()
        let weekBuilder = ProgramGenerationWeekScheduleBuilder()

        let expectations: [(ProgramFocus, ProgramProgressionStrategyFamily, ProgramProgressionModel)] = [
            (.powerlifting, .strengthSkill, .dup),
            (.powerbuilding, .mixedStrengthHypertrophy, .dup),
            (.bodybuilding, .hypertrophyVolume, .linear),
            (.generalFitness, .balancedTraining, .dup),
            (.fullBody, .balancedTraining, .dup),
        ]

        for (focus, expectedFamily, expectedModel) in expectations {
            let profile = service.programmingProfile(for: focus)
            let strategy = progressionResolver.resolveStrategy(focusProfile: profile, level: .intermediate)
            #expect(strategy.family == expectedFamily)
            #expect(progressionResolver.progressionModel(for: strategy) == expectedModel)

            let schedules = weekBuilder.buildWeekSchedules(
                strategy: strategy,
                durationWeeks: 8,
                focusProfile: profile
            )
            #expect(schedules.count == 8)
            #expect(schedules.contains(where: { $0.isDeload }))
        }
    }

    @Test func loadPrescriptionResolverUsesMappedOneRMAndRoundsSafely() {
        let resolver = ProgramGenerationLoadPrescriptionResolver()
        let exercise = TemplateExercise(
            exerciseName: "Pause Bench Press",
            role: .variation,
            defaultSets: 4,
            defaultReps: 4,
            percentage1RM: 0.8,
            targetRPE: nil
        )
        let context = resolver.computePrescribedLoadContext(
            exercise: exercise,
            percentage1RM: 0.75,
            oneRepMaxes: ["Bench Press": (weight: 287, unit: "lbs")]
        )

        #expect(context.baseLiftUsed == "Bench Press")
        #expect(context.usedMappedSourceLift)
        #expect(context.prescribedWeightUnit == "lbs")
        #expect(context.prescribedWeight == 200)
    }

    @Test func movementCoverageHelperRejectsPushSessionPullOnlyCandidates() {
        let helper = ProgramGenerationMovementCoverageHelper()
        let reject = helper.shouldRejectMovementCandidate(
            focus: .pushPull,
            sessionName: "Push Session",
            candidatePatterns: [.horizontalPull],
            currentSessionPatterns: [],
            movementTargets: [.horizontalPush: 2, .horizontalPull: 2],
            weeklyPatternExposure: [.horizontalPush: 0, .horizontalPull: 0],
            sessionAccessoryPatterns: [.horizontalPush, .horizontalPull]
        )
        #expect(reject)
    }

    @Test func cardioPlannerAppliesProgressionAndDeloadStepBack() {
        let planner = ProgramGenerationCardioPlanner()
        let profile = service.programmingProfile(for: .cardioEndurance)

        let week2 = ProgramGenerationWeekSchedule(
            weekNumber: 2,
            isDeload: false,
            progressionIndex: 1,
            advancedPhase: nil,
            phaseWeekIndex: 0,
            phaseLength: 1
        )
        let week3Deload = ProgramGenerationWeekSchedule(
            weekNumber: 3,
            isDeload: true,
            progressionIndex: 1,
            advancedPhase: nil,
            phaseWeekIndex: 0,
            phaseLength: 1
        )

        let working = planner.resolveCardioPrescription(
            sessionName: "Long Run",
            focusProfile: profile,
            schedule: week2
        )
        let deload = planner.resolveCardioPrescription(
            sessionName: "Long Run",
            focusProfile: profile,
            schedule: week3Deload
        )

        #expect(working.minutes > deload.minutes)
        #expect(working.targetRPE > deload.targetRPE)
    }

    @Test func fiveFocusMatrixMaintainsSafetyTopBackoffAndExplainability() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let focuses: [ProgramFocus] = [.powerlifting, .bodybuilding, .powerbuilding, .generalFitness, .fullBody]

        for focus in focuses {
            let template = FocusTemplateLibrary.template(for: focus)
            let input = makeInput(
                focus: focus,
                level: .intermediate,
                durationWeeks: 8,
                sessionsPerWeek: max(3, template.minimumFrequency)
            )
            let program = service.generateProgram(
                input: input,
                context: context,
                shuffleSeed: abs(focus.rawValue.hashValue) + 301
            )

            let fatigueBudgets = ProgramExerciseMetadataService.fatigueBudgets(
                focus: focus,
                level: .intermediate,
                sessionsPerWeek: program.sessionsPerWeek
            )
            let summaries = service.weeklySummary(for: program)
            #expect(!summaries.isEmpty)

            for week in summaries {
                #expect(week.totalFatigueScore <= fatigueBudgets.weekBudget * 1.10)
                for session in week.sessionSummaries {
                    #expect(session.fatigueScore <= fatigueBudgets.sessionBudget * 1.10)
                }
            }

            let weekOneSessions = program.weeks
                .first(where: { $0.weekNumber == 1 })?
                .sessions ?? []
            for session in weekOneSessions {
                #expect(session.explainabilityReason != nil)
                for row in session.exercises where !row.isWarmup {
                    #expect(row.explainabilityPurpose != nil)
                }
            }

            let rows = program.weeks
                .flatMap(\.sessions)
                .flatMap(\.exercises)
                .filter { !$0.isWarmup }
            let styles = rows.map(\.workingSetStyle)
            if focus == .powerlifting || focus == .powerbuilding {
                #expect(styles.contains(.topSet))
                #expect(styles.contains(.backoff))
            }
        }
    }

    private func makeInput(
        focus: ProgramFocus,
        level: ProgramLevel,
        durationWeeks: Int,
        sessionsPerWeek: Int
    ) -> ProgramGenerationInput {
        let template = FocusTemplateLibrary.template(for: focus)
        var oneRepMaxes: [String: (weight: Double, unit: String)] = [:]
        for (idx, lift) in template.requiredLifts.enumerated() {
            oneRepMaxes[lift] = (weight: 185 + Double(idx * 25), unit: "lbs")
        }
        return ProgramGenerationInput(
            focus: focus,
            level: level,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            oneRepMaxes: oneRepMaxes
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
