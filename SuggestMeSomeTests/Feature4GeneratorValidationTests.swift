//
//  Feature4GeneratorValidationTests.swift
//  SuggestMeSomeTests
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature4GeneratorValidationTests {
    private let service = ProgramGenerationService()

    @Test func eachFocusResolvesValidProgrammingProfile() {
        for focus in ProgramFocus.allCases {
            let profile = service.programmingProfile(for: focus)
            #expect(profile.focus == focus)
            #expect(!profile.weeklyExposurePriorities.isEmpty)

            if focus == .cardioEndurance {
                #expect(profile.cardioProgrammingProfile != nil)
                #expect(!(profile.cardioProgrammingProfile?.weeklyDistribution.isEmpty ?? true))
            } else {
                #expect(profile.cardioProgrammingProfile == nil)
            }
        }
    }

    @Test func sameLevelCanResolveDifferentFocusStrategyFamilies() {
        let level: ProgramLevel = .intermediate

        let strengthFamily = service.progressionStrategyFamily(for: .powerlifting, level: level)
        let mixedFamily = service.progressionStrategyFamily(for: .powerbuilding, level: level)
        let hypertrophyFamily = service.progressionStrategyFamily(for: .bodybuilding, level: level)
        let balancedFamily = service.progressionStrategyFamily(for: .generalFitness, level: level)
        let enduranceFamily = service.progressionStrategyFamily(for: .cardioEndurance, level: level)

        #expect(strengthFamily == .strengthSkill)
        #expect(mixedFamily == .mixedStrengthHypertrophy)
        #expect(hypertrophyFamily == .hypertrophyVolume)
        #expect(balancedFamily == .balancedTraining)
        #expect(enduranceFamily == .enduranceConditioning)

        let families = Set([strengthFamily, mixedFamily, hypertrophyFamily, balancedFamily, enduranceFamily])
        #expect(families.count == 5)
    }

    @Test func sameLevelCanProduceDifferentProgressionModelsByFocusFamily() {
        let level: ProgramLevel = .intermediate
        #expect(service.progressionModel(for: .powerlifting, level: level) == .dup)
        #expect(service.progressionModel(for: .powerbuilding, level: level) == .dup)
        #expect(service.progressionModel(for: .bodybuilding, level: level) == .linear)
        #expect(service.progressionModel(for: .generalFitness, level: level) == .dup)
        #expect(service.progressionModel(for: .cardioEndurance, level: level) == .linear)
    }

    @Test func focusSpecificVolumeTargetsAreDistinctAndDefensible() {
        let level: ProgramLevel = .intermediate

        let maxSquat = ProgramExerciseMetadataService.weeklyVolumeTargets(focus: .increaseMaxSquat, level: level)
        #expect(maxSquat.range(for: .quads).minHardSets > maxSquat.range(for: .chest).minHardSets)

        let maxBench = ProgramExerciseMetadataService.weeklyVolumeTargets(focus: .increaseMaxBench, level: level)
        #expect(maxBench.range(for: .chest).minHardSets > maxBench.range(for: .quads).minHardSets)

        let maxDeadlift = ProgramExerciseMetadataService.weeklyVolumeTargets(focus: .increaseMaxDeadlift, level: level)
        #expect(maxDeadlift.range(for: .hamstrings).minHardSets > maxDeadlift.range(for: .chest).minHardSets)

        let pushPull = ProgramExerciseMetadataService.weeklyVolumeTargets(focus: .pushPull, level: level)
        #expect(pushPull.range(for: .upperBackLats).minHardSets > pushPull.range(for: .quads).minHardSets)
        #expect(pushPull.range(for: .chest).minHardSets > pushPull.range(for: .hamstrings).minHardSets)

        let fiveByFive = ProgramExerciseMetadataService.weeklyVolumeTargets(focus: .fiveByFive, level: level)
        let powerbuilding = ProgramExerciseMetadataService.weeklyVolumeTargets(focus: .powerbuilding, level: level)
        #expect(fiveByFive.range(for: .biceps).maxHardSets < powerbuilding.range(for: .biceps).maxHardSets)
        #expect(fiveByFive.range(for: .triceps).maxHardSets < powerbuilding.range(for: .triceps).maxHardSets)

        let cardio = ProgramExerciseMetadataService.weeklyVolumeTargets(focus: .cardioEndurance, level: level)
        for muscle in ProgramVolumeMuscle.allCases {
            #expect(cardio.range(for: muscle).minHardSets == 0)
            #expect(cardio.range(for: muscle).maxHardSets == 0)
        }
    }

    @Test func focusSpecificFatigueBudgetsAreDistinctAndDefensible() {
        let level: ProgramLevel = .intermediate
        let sessionsPerWeek = 4

        let powerlifting = ProgramExerciseMetadataService.fatigueBudgets(
            focus: .powerlifting,
            level: level,
            sessionsPerWeek: sessionsPerWeek
        )
        let powerbuilding = ProgramExerciseMetadataService.fatigueBudgets(
            focus: .powerbuilding,
            level: level,
            sessionsPerWeek: sessionsPerWeek
        )
        let bodybuilding = ProgramExerciseMetadataService.fatigueBudgets(
            focus: .bodybuilding,
            level: level,
            sessionsPerWeek: sessionsPerWeek
        )
        let general = ProgramExerciseMetadataService.fatigueBudgets(
            focus: .generalFitness,
            level: level,
            sessionsPerWeek: sessionsPerWeek
        )
        let fullBody = ProgramExerciseMetadataService.fatigueBudgets(
            focus: .fullBody,
            level: level,
            sessionsPerWeek: sessionsPerWeek
        )
        let fiveByFive = ProgramExerciseMetadataService.fatigueBudgets(
            focus: .fiveByFive,
            level: level,
            sessionsPerWeek: sessionsPerWeek
        )
        let maxDeadlift = ProgramExerciseMetadataService.fatigueBudgets(
            focus: .increaseMaxDeadlift,
            level: level,
            sessionsPerWeek: sessionsPerWeek
        )
        let maxBench = ProgramExerciseMetadataService.fatigueBudgets(
            focus: .increaseMaxBench,
            level: level,
            sessionsPerWeek: sessionsPerWeek
        )
        let cardio = ProgramExerciseMetadataService.fatigueBudgets(
            focus: .cardioEndurance,
            level: level,
            sessionsPerWeek: sessionsPerWeek
        )

        #expect(powerlifting.weekBudget < powerbuilding.weekBudget)
        #expect(powerbuilding.weekBudget < bodybuilding.weekBudget)
        #expect(fiveByFive.weekBudget < powerlifting.weekBudget)
        #expect(fullBody.adjacentSessionPairBudget < general.adjacentSessionPairBudget)
        #expect(maxDeadlift.deadliftSessionBudget < maxBench.deadliftSessionBudget)
        #expect(cardio.weekBudget < bodybuilding.weekBudget)

        let uniqueBudgets = Set(
            ProgramFocus.allCases.map { focus in
                Int(ProgramExerciseMetadataService.fatigueBudgets(
                    focus: focus,
                    level: level,
                    sessionsPerWeek: sessionsPerWeek
                ).weekBudget.rounded())
            }
        )
        #expect(uniqueBudgets.count >= 9)
    }

    @Test func eachFocusBuildsExpectedWeeksAndResolvedSessions() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        for focus in ProgramFocus.allCases {
            let template = FocusTemplateLibrary.template(for: focus)
            let requestedFrequency = max(2, template.minimumFrequency - 1)
            let expectedFrequency = resolvedFrequency(for: template, requested: requestedFrequency)
            let input = makeInput(
                focus: focus,
                level: .intermediate,
                durationWeeks: 8,
                sessionsPerWeek: requestedFrequency
            )

            let program = service.generateProgram(
                input: input,
                context: context,
                shuffleSeed: deterministicSeed(for: focus, offset: 1)
            )

            #expect(program.weeks.count == 8)
            #expect(program.sessionsPerWeek == expectedFrequency)
            for week in program.weeks {
                #expect(week.sessions.count == expectedFrequency)
            }
        }
    }

    @Test func mappedVariationsProducePrescribedWeightsWhenSourceOneRMsExist() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let input = ProgramGenerationInput(
            focus: .increaseMaxSquat,
            level: .intermediate,
            durationWeeks: 8,
            sessionsPerWeek: 4,
            oneRepMaxes: [
                "Back Squats": (weight: 405, unit: "lbs"),
                "Deadlift": (weight: 495, unit: "lbs"),
            ]
        )

        let program = service.generateProgram(input: input, context: context, shuffleSeed: 207)
        let allExercises = flattenedExercises(from: program)
        let mappedRows = allExercises.filter {
            guard !$0.isWarmup, $0.targetPercentage1RM != nil else { return false }
            return $0.usedMappedSourceLift == true
        }

        #expect(!mappedRows.isEmpty)
        for row in mappedRows {
            guard
                let mapping = FocusTemplateLibrary.loadMapping(for: row.exerciseName),
                let sourceORM = input.oneRepMaxes[mapping.sourceLift],
                let pct = row.targetPercentage1RM
            else {
                Issue.record("Mapped row missing source mapping context for \(row.exerciseName)")
                continue
            }

            let effectiveORM = sourceORM.weight * mapping.multiplier
            let expectedWeight = roundToProgramIncrement(pct * effectiveORM, unit: sourceORM.unit)

            #expect(row.baseLiftUsed == mapping.sourceLift)
            #expect(row.effectiveOneRepMax != nil)
            #expect(row.prescribedWeightUnit == sourceORM.unit)
            #expect(row.prescribedWeight != nil)
            #expect(abs((row.prescribedWeight ?? 0) - expectedWeight) < 0.0001)
        }
    }

    @Test func topSetBackoffOrderingIsValid() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let input = ProgramGenerationInput(
            focus: .increaseMaxBench,
            level: .advanced,
            durationWeeks: 8,
            sessionsPerWeek: 4,
            oneRepMaxes: [
                "Bench Press": (weight: 285, unit: "lbs"),
                "Overhead Press": (weight: 175, unit: "lbs"),
            ]
        )

        let program = service.generateProgram(input: input, context: context, shuffleSeed: 409)

        var sawTopBackoff = false
        for week in program.weeks {
            for session in week.sessions {
                let ordered = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
                let grouped = Dictionary(grouping: ordered) { $0.topBackoffGroupID ?? UUID() }

                for (_, rows) in grouped {
                    let topRows = rows.filter { $0.workingSetStyle == .topSet }
                    let backoffRows = rows.filter { $0.workingSetStyle == .backoff }
                    guard !topRows.isEmpty || !backoffRows.isEmpty else { continue }

                    sawTopBackoff = true
                    #expect(!topRows.isEmpty)
                    #expect(!backoffRows.isEmpty)

                    let topIndex = topRows.map(\.orderIndex).min() ?? Int.max
                    let backoffIndex = backoffRows.map(\.orderIndex).min() ?? Int.max
                    #expect(topIndex < backoffIndex)

                    let warmupRows = rows.filter(\.isWarmup)
                    if let firstWorking = rows.filter({ !$0.isWarmup }).map(\.orderIndex).min() {
                        for warmup in warmupRows {
                            #expect(warmup.orderIndex < firstWorking)
                        }
                    }
                }
            }
        }

        #expect(sawTopBackoff)
    }

    @Test func focusProgrammingProfileIsWiredIntoGenerationTopBackoffPolicy() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let bodybuildingProfile = service.programmingProfile(for: .bodybuilding)
        #expect(bodybuildingProfile.topSetBackoffPolicy == .disabled)

        let bodybuildingProgram = service.generateProgram(
            input: makeInput(focus: .bodybuilding, level: .advanced, durationWeeks: 8, sessionsPerWeek: 4),
            context: context,
            shuffleSeed: deterministicSeed(for: .bodybuilding, offset: 77)
        )
        let bodybuildingStyles = flattenedExercises(from: bodybuildingProgram)
            .filter { !$0.isWarmup }
            .map(\.workingSetStyle)
        #expect(!bodybuildingStyles.contains(.topSet))
        #expect(!bodybuildingStyles.contains(.backoff))

        let powerliftingProfile = service.programmingProfile(for: .powerlifting)
        #expect(powerliftingProfile.topSetBackoffPolicy == .templateDriven)

        let powerliftingProgram = service.generateProgram(
            input: makeInput(focus: .powerlifting, level: .advanced, durationWeeks: 8, sessionsPerWeek: 4),
            context: context,
            shuffleSeed: deterministicSeed(for: .powerlifting, offset: 88)
        )
        let powerliftingStyles = flattenedExercises(from: powerliftingProgram)
            .filter { !$0.isWarmup }
            .map(\.workingSetStyle)
        #expect(powerliftingStyles.contains(.topSet))
        #expect(powerliftingStyles.contains(.backoff))
    }

    @Test func volumeAndFatigueAccountingStayWithinSafeBounds() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let focuses: [ProgramFocus] = [
            .increaseMaxSquat,
            .powerlifting,
            .powerbuilding,
            .fullBody,
            .generalFitness,
            .bodybuilding,
            .cardioEndurance,
        ]

        for focus in focuses {
            let input = makeInput(
                focus: focus,
                level: .intermediate,
                durationWeeks: 8,
                sessionsPerWeek: max(3, FocusTemplateLibrary.template(for: focus).minimumFrequency)
            )
            let program = service.generateProgram(
                input: input,
                context: context,
                shuffleSeed: deterministicSeed(for: focus, offset: 3)
            )
            let summaries = service.weeklySummary(for: program)
            let budgets = ProgramExerciseMetadataService.fatigueBudgets(
                focus: focus,
                level: .intermediate,
                sessionsPerWeek: program.sessionsPerWeek
            )

            for week in summaries {
                #expect(week.totalFatigueScore >= 0)
                #expect(week.totalFatigueScore <= (budgets.weekBudget * 1.10))

                for muscle in ProgramVolumeMuscle.allCases {
                    #expect((week.totalHardSetsByMuscle[muscle] ?? 0) >= 0)
                }

                for sessionSummary in week.sessionSummaries {
                    #expect(sessionSummary.fatigueScore <= (budgets.sessionBudget * 1.10))
                }
            }
        }
    }

    @Test func powerliftingTemplateMaintainsHighSBDExposure() {
        let template = FocusTemplateLibrary.template(for: .powerlifting)

        for frequency in template.sessionDefinitions.keys.sorted() {
            guard let sessions = template.sessionDefinitions[frequency] else {
                Issue.record("Missing powerlifting sessions for frequency \(frequency)")
                continue
            }

            let squatExposure = sessions.filter { session in
                session.primaryExercises.contains { baseLift(for: $0.exerciseName) == "Back Squats" }
            }.count
            let benchExposure = sessions.filter { session in
                session.primaryExercises.contains { baseLift(for: $0.exerciseName) == "Bench Press" }
            }.count
            let deadliftExposure = sessions.filter { session in
                session.primaryExercises.contains { baseLift(for: $0.exerciseName) == "Deadlift" }
            }.count

            #expect(squatExposure >= 2)
            #expect(benchExposure >= min(3, frequency))
            #expect(deadliftExposure >= 1)
        }
    }

    @Test func fullBodyGeneratedSessionsAlwaysIncludeLowerPushAndPullWork() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let input = makeInput(
            focus: .fullBody,
            level: .intermediate,
            durationWeeks: 8,
            sessionsPerWeek: 5
        )

        let program = service.generateProgram(
            input: input,
            context: context,
            shuffleSeed: deterministicSeed(for: .fullBody, offset: 5)
        )

        for week in program.weeks {
            for session in week.sessions {
                let workingNames = session.exercises
                    .filter { !$0.isWarmup }
                    .map(\.exerciseName)

                #expect(workingNames.contains(where: isLowerBodyExercise))
                #expect(workingNames.contains(where: isPushExercise))
                #expect(workingNames.contains(where: isPullExercise))
            }
        }
    }

    @Test func deloadWeeksAppearAtExpectedPositions() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let beginner = service.generateProgram(
            input: makeInput(focus: .increaseMaxSquat, level: .beginner, durationWeeks: 12, sessionsPerWeek: 4),
            context: context,
            shuffleSeed: 601
        )
        let intermediate = service.generateProgram(
            input: makeInput(focus: .increaseMaxBench, level: .intermediate, durationWeeks: 12, sessionsPerWeek: 4),
            context: context,
            shuffleSeed: 701
        )

        #expect(deloadWeeks(in: beginner) == [4, 8, 12])
        #expect(deloadWeeks(in: intermediate) == [4, 8, 12])

        let advancedExpectations: [Int: [Int]] = [
            6: [3],
            8: [4, 8],
            10: [4, 8],
            12: [5, 9, 12],
        ]
        for (duration, expectedDeloadWeeks) in advancedExpectations {
            let advanced = service.generateProgram(
                input: makeInput(
                    focus: .increaseMaxDeadlift,
                    level: .advanced,
                    durationWeeks: duration,
                    sessionsPerWeek: 4
                ),
                context: context,
                shuffleSeed: 801 + duration
            )
            #expect(deloadWeeks(in: advanced) == expectedDeloadWeeks)
        }
    }

    @Test func reviewGroupingKeepsWarmupsAndGroupedLiftsStable() {
        let rows: [ProgramSessionExercise] = [
            ProgramSessionExercise(exerciseName: "Back Squats", orderIndex: 0, targetSets: 1, targetReps: 3, isWarmup: true),
            ProgramSessionExercise(exerciseName: "Back Squats", orderIndex: 1, targetSets: 1, targetReps: 3, isWarmup: true),
            ProgramSessionExercise(exerciseName: "Back Squats", orderIndex: 2, targetSets: 1, targetReps: 3, isWarmup: true),
            ProgramSessionExercise(exerciseName: "Back Squats", orderIndex: 3, targetSets: 1, targetReps: 2, workingSetStyle: .topSet),
            ProgramSessionExercise(exerciseName: "Back Squats", orderIndex: 4, targetSets: 3, targetReps: 4, workingSetStyle: .backoff),
            ProgramSessionExercise(exerciseName: "Bench Press", orderIndex: 5, targetSets: 1, targetReps: 5, isWarmup: true),
            ProgramSessionExercise(exerciseName: "Bench Press", orderIndex: 6, targetSets: 1, targetReps: 5, isWarmup: true),
            ProgramSessionExercise(exerciseName: "Bench Press", orderIndex: 7, targetSets: 4, targetReps: 5, workingSetStyle: .straight),
            ProgramSessionExercise(exerciseName: "Deadlift", orderIndex: 8, targetSets: 1, targetReps: 3, isWarmup: true),
        ]

        let groups = ProgramReviewGrouping.groupedExercises(from: rows)

        #expect(groups.count == 4)
        #expect(groups[0].workingSet.exerciseName == "Back Squats")
        #expect(groups[0].warmupSets.count == 3)
        #expect(groups[1].workingSet.exerciseName == "Back Squats")
        #expect(groups[1].warmupSets.isEmpty)
        #expect(groups[2].workingSet.exerciseName == "Bench Press")
        #expect(groups[2].warmupSets.count == 2)
        #expect(groups[3].workingSet.exerciseName == "Deadlift")
        #expect(groups[3].warmupSets.isEmpty)
    }

    // MARK: Helpers

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

    private func resolvedFrequency(for template: FocusTemplate, requested: Int) -> Int {
        let supported = template.sessionDefinitions.keys.sorted()
        guard let closest = supported.min(by: { abs($0 - requested) < abs($1 - requested) }) else {
            return requested
        }
        return template.sessionDefinitions[closest]?.count ?? closest
    }

    private func flattenedExercises(from program: TrainingProgram) -> [ProgramSessionExercise] {
        program.weeks
            .flatMap(\.sessions)
            .flatMap(\.exercises)
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func roundToProgramIncrement(_ value: Double, unit: String) -> Double {
        if unit == "lbs" {
            return max(5.0, (value / 5.0).rounded() * 5.0)
        }
        return max(2.5, (value / 2.5).rounded() * 2.5)
    }

    private func deloadWeeks(in program: TrainingProgram) -> [Int] {
        program.weeks
            .filter(\.isDeloadWeek)
            .map(\.weekNumber)
            .sorted()
    }

    private func deterministicSeed(for focus: ProgramFocus, offset: Int) -> Int {
        abs(focus.rawValue.hashValue) + (offset * 97) + 1
    }

    private func baseLift(for exerciseName: String) -> String? {
        if ["Back Squats", "Bench Press", "Deadlift"].contains(exerciseName) {
            return exerciseName
        }
        return FocusTemplateLibrary.loadMapping(for: exerciseName)?.sourceLift
    }

    private func isLowerBodyExercise(_ exerciseName: String) -> Bool {
        let metadata = ProgramExerciseMetadataService.metadata(for: exerciseName)
        return (metadata.muscleContributions[.quads] ?? 0) > 0 ||
            (metadata.muscleContributions[.hamstrings] ?? 0) > 0 ||
            (metadata.muscleContributions[.glutes] ?? 0) > 0
    }

    private func isPushExercise(_ exerciseName: String) -> Bool {
        let metadata = ProgramExerciseMetadataService.metadata(for: exerciseName)
        return (metadata.muscleContributions[.chest] ?? 0) > 0 ||
            (metadata.muscleContributions[.shoulders] ?? 0) > 0 ||
            (metadata.muscleContributions[.triceps] ?? 0) > 0
    }

    private func isPullExercise(_ exerciseName: String) -> Bool {
        let metadata = ProgramExerciseMetadataService.metadata(for: exerciseName)
        return (metadata.muscleContributions[.upperBackLats] ?? 0) > 0 ||
            (metadata.muscleContributions[.biceps] ?? 0) > 0
    }
}
