//
//  ProgramGenerationService.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/7/26.
//

import Foundation
import SwiftData

// MARK: - Public Input Types

struct ProgramGenerationInput {
    let focus: ProgramFocus
    let level: ProgramLevel
    /// Valid values: 6, 8, 10, 12
    let durationWeeks: Int
    /// Valid values: 2–6
    let sessionsPerWeek: Int
    /// exerciseName → (weight, unit). Unit is "lbs" or "kg".
    /// Used to validate exercises exist and to record 1RM context for display.
    /// Actual weight rounding (nearest 5 lbs / 2.5 kg) is applied at display time.
    let oneRepMaxes: [String: (weight: Double, unit: String)]
    /// Optional post-block context carried from a ranked recommendation selection.
    /// Current generation stays backward-compatible and may ignore this context,
    /// but later flows can inspect it for explainability or pre-generation editing.
    let carryForwardContext: ProgramGenerationCarryForwardContext?
    /// Optional adaptive-state override used by validation paths and deterministic tests.
    let stateSnapshotOverride: TrainingStateSnapshot?

    init(
        focus: ProgramFocus,
        level: ProgramLevel,
        durationWeeks: Int,
        sessionsPerWeek: Int,
        oneRepMaxes: [String: (weight: Double, unit: String)],
        carryForwardContext: ProgramGenerationCarryForwardContext? = nil,
        stateSnapshotOverride: TrainingStateSnapshot? = nil
    ) {
        self.focus = focus
        self.level = level
        self.durationWeeks = durationWeeks
        self.sessionsPerWeek = sessionsPerWeek
        self.oneRepMaxes = oneRepMaxes
        self.carryForwardContext = carryForwardContext
        self.stateSnapshotOverride = stateSnapshotOverride
    }
}

enum ProgramLevel: String, CaseIterable, Codable {
    case beginner, intermediate, advanced
}

struct ProgramGeneratedSessionSummary {
    let sessionNumber: Int
    let sessionName: String?
    let hardSetsByMuscle: [ProgramVolumeMuscle: Double]
    let fatigueScore: Double
}

struct ProgramGeneratedWeekSummary {
    let weekNumber: Int
    let sessionSummaries: [ProgramGeneratedSessionSummary]
    let totalHardSetsByMuscle: [ProgramVolumeMuscle: Double]
    let totalFatigueScore: Double
}

// MARK: - Service

struct ProgramGenerationService {
    private let progressionResolver = ProgramGenerationProgressionResolver()
    private let weekScheduleBuilder = ProgramGenerationWeekScheduleBuilder()
    private let loadResolver = ProgramGenerationLoadPrescriptionResolver()
    private let accessoryPlanner = ProgramGenerationAccessoryPlanner()
    private let cardioPlanner = ProgramGenerationCardioPlanner()
    private let explainabilityStamper = ProgramGenerationExplainabilityStamper()
    private let weeklySummaryReporter = ProgramGenerationWeeklySummaryReporter()
    private let loadEstimator = ProgramGenerationLoadEstimator()

    // MARK: - Public API

    /// Generates a new program with a random accessory shuffle.
    func generateProgram(input: ProgramGenerationInput, context: ModelContext) -> TrainingProgram {
        buildProgram(input: input, context: context, shuffleSeed: Int.random(in: 1..<Int.max))
    }

    /// Deterministic helper used by validation paths and tests.
    func generateProgram(
        input: ProgramGenerationInput,
        context: ModelContext,
        shuffleSeed: Int
    ) -> TrainingProgram {
        buildProgram(input: input, context: context, shuffleSeed: shuffleSeed)
    }

    /// Generates a program using different random accessory selections than a previous call.
    func regenerateProgram(input: ProgramGenerationInput, context: ModelContext) -> TrainingProgram {
        buildProgram(input: input, context: context, shuffleSeed: Int.random(in: 1..<Int.max))
    }

    /// Debug helper for validating weekly volume and fatigue accounting from a generated program.
    func debugWeeklySummary(for program: TrainingProgram) -> String {
        weeklySummaryReporter.debugWeeklySummary(for: program)
    }

    func weeklySummary(for program: TrainingProgram) -> [ProgramGeneratedWeekSummary] {
        weeklySummaryReporter.weeklySummary(for: program)
    }

    func programmingProfile(for focus: ProgramFocus) -> ProgramFocusProgrammingProfile {
        FocusTemplateLibrary.programmingProfile(for: focus)
    }

    func progressionStrategyFamily(for focus: ProgramFocus, level: ProgramLevel) -> ProgramProgressionStrategyFamily {
        let profile = programmingProfile(for: focus)
        return progressionResolver.resolveStrategy(focusProfile: profile, level: level).family
    }

    func progressionModel(for focus: ProgramFocus, level: ProgramLevel) -> ProgramProgressionModel {
        let profile = programmingProfile(for: focus)
        let strategy = progressionResolver.resolveStrategy(focusProfile: profile, level: level)
        return progressionResolver.progressionModel(for: strategy)
    }

    // MARK: - Core Builder

    private func buildProgram(
        input: ProgramGenerationInput,
        context: ModelContext,
        shuffleSeed: Int
    ) -> TrainingProgram {
        let adaptiveEngine = AdaptiveTrainingStateEngine(context: context)
        let trainingState = input.stateSnapshotOverride ?? adaptiveEngine.buildSnapshot(
            focus: input.focus,
            level: input.level,
            sessionsPerWeek: input.sessionsPerWeek
        )
        let doseTargetProfile = adaptiveEngine.buildDoseTargetProfile(
            focus: input.focus,
            level: input.level,
            sessionsPerWeek: input.sessionsPerWeek,
            snapshot: trainingState
        )
        let focusProfile = programmingProfile(for: input.focus)
        let strategy = progressionResolver.resolveStrategy(
            focusProfile: focusProfile,
            level: input.level
        )

        let template = FocusTemplateLibrary.template(for: input.focus)
        let sessionDefs = resolvedSessionDefs(from: template, frequency: input.sessionsPerWeek)
        let resolvedFrequency = max(1, sessionDefs.count)
        let progressionModel = progressionResolver.progressionModel(for: strategy)

        var usedLiftMapping = false
        var usedTopSetBackoff = false

        let program = TrainingProgram(
            name: "\(template.displayName) — \(input.level.rawValue.capitalized) \(input.durationWeeks)wk",
            lengthInWeeks: input.durationWeeks,
            sessionsPerWeek: resolvedFrequency,
            source: .aiGenerated,
            descriptionText: progressionResolver.periodizationDescription(for: strategy),
            progressionModel: progressionModel,
            usedLiftMapping: false,
            usedVolumeBalancing: true,
            usedFatigueBalancing: true,
            usedTopSetBackoff: false
        )
        context.insert(program)

        let schedules = weekScheduleBuilder.buildWeekSchedules(
            strategy: strategy,
            durationWeeks: input.durationWeeks,
            focusProfile: focusProfile,
            trainingState: trainingState,
            doseTargetProfile: doseTargetProfile
        )

        let weeklyAccessoryPlan = accessoryPlanner.buildAdaptiveAccessoryPlan(
            sessionDefs: sessionDefs,
            schedules: schedules,
            focus: input.focus,
            focusProfile: focusProfile,
            level: input.level,
            sessionsPerWeek: resolvedFrequency,
            seed: shuffleSeed,
            doseTargetProfile: doseTargetProfile
        )

        for schedule in schedules {
            let weekTemplate = ProgramWeekTemplate(
                weekNumber: schedule.weekNumber,
                isDeloadWeek: schedule.isDeload,
                progressionPhase: progressionResolver.weekProgressionPhase(
                    strategy: strategy,
                    schedule: schedule
                )
            )
            context.insert(weekTemplate)
            weekTemplate.program = program

            for (sessionIdx, sessionDef) in sessionDefs.enumerated() {
                let sessionTemplate = ProgramSessionTemplate(
                    sessionNumber: sessionIdx + 1,
                    sessionName: sessionDef.sessionName,
                    explainabilityReason: explainabilityStamper.resolveSessionReasonCode(
                        focusProfile: focusProfile,
                        strategy: strategy,
                        schedule: schedule,
                        sessionName: sessionDef.sessionName
                    )
                )
                context.insert(sessionTemplate)
                sessionTemplate.week = weekTemplate

                let weekAccessories = weeklyAccessoryPlan[schedule.weekNumber] ?? Array(repeating: [], count: sessionDefs.count)
                let accessories = sessionIdx < weekAccessories.count ? weekAccessories[sessionIdx] : []
                var orderIdx = 0

                for primary in sessionDef.primaryExercises {
                    orderIdx = populateExercise(
                        primary,
                        isPrimary: true,
                        isSessionOpener: orderIdx == 0,
                        strategy: strategy,
                        focusProfile: focusProfile,
                        schedule: schedule,
                        sessionIdx: sessionIdx,
                        sessionsPerWeek: resolvedFrequency,
                        level: input.level,
                        oneRepMaxes: input.oneRepMaxes,
                        session: sessionTemplate,
                        orderIdx: orderIdx,
                        context: context,
                        doseTargetProfile: doseTargetProfile,
                        cardioSessionType: sessionDef.cardioArchetype,
                        usedLiftMapping: &usedLiftMapping,
                        usedTopSetBackoff: &usedTopSetBackoff
                    )
                }

                for accessory in accessories {
                    orderIdx = populateExercise(
                        accessory.exercise,
                        isPrimary: false,
                        isSessionOpener: false,
                        strategy: strategy,
                        focusProfile: focusProfile,
                        schedule: schedule,
                        sessionIdx: sessionIdx,
                        sessionsPerWeek: resolvedFrequency,
                        level: input.level,
                        oneRepMaxes: input.oneRepMaxes,
                        session: sessionTemplate,
                        orderIdx: orderIdx,
                        context: context,
                        doseTargetProfile: doseTargetProfile,
                        cardioSessionType: sessionDef.cardioArchetype,
                        usedLiftMapping: &usedLiftMapping,
                        usedTopSetBackoff: &usedTopSetBackoff,
                        accessorySelectionReason: accessory.reason
                    )
                }
            }
        }

        program.usedLiftMapping = usedLiftMapping
        program.usedTopSetBackoff = usedTopSetBackoff
        weeklySummaryReporter.stampPlannedFatigueSummaries(on: program)

        return program
    }

    // MARK: - Exercise Population

    @discardableResult
    private func populateExercise(
        _ templateEx: TemplateExercise,
        isPrimary: Bool,
        isSessionOpener: Bool,
        strategy: ProgramGenerationProgressionStrategy,
        focusProfile: ProgramFocusProgrammingProfile,
        schedule: ProgramGenerationWeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int,
        level: ProgramLevel,
        oneRepMaxes: [String: (weight: Double, unit: String)],
        session: ProgramSessionTemplate,
        orderIdx: Int,
        context: ModelContext,
        doseTargetProfile: DoseTargetProfile,
        cardioSessionType: ProgramCardioSessionType?,
        usedLiftMapping: inout Bool,
        usedTopSetBackoff: inout Bool,
        accessorySelectionReason: ProgramAccessorySelectionReason? = nil
    ) -> Int {
        var idx = orderIdx
        let phase = progressionResolver.progressionPhase(
            strategy: strategy,
            schedule: schedule,
            sessionIdx: sessionIdx,
            sessionsPerWeek: sessionsPerWeek
        )
        let topBackoffGroupID = UUID()
        let explainabilityPurpose = explainabilityStamper.resolveExercisePurposeCode(
            templateExercise: templateEx,
            isPrimary: isPrimary,
            schedule: schedule,
            sessionName: session.sessionName ?? ""
        )

        if templateEx.role == .cardio {
            let cardioPrescription = cardioPlanner.resolveCardioPrescription(
                sessionName: session.sessionName ?? "",
                cardioSessionType: cardioSessionType,
                focusProfile: focusProfile,
                schedule: schedule,
                doseTargetProfile: doseTargetProfile
            )
            let ex = ProgramSessionExercise(
                exerciseName: templateEx.exerciseName,
                orderIndex: idx,
                targetSets: nil,
                targetReps: cardioPrescription.minutes,
                targetRPE: cardioPrescription.targetRPE,
                targetEffortType: .rpe,
                progressionPhase: phase,
                estimatedFatigueScore: cardioPrescription.estimatedFatigueScore,
                explainabilityPurpose: explainabilityPurpose
            )
            context.insert(ex)
            ex.session = session
            return idx + 1
        }

        let resolvedParams = progressionResolver.computeParams(
            exercise: templateEx,
            strategy: strategy,
            focusProfile: focusProfile,
            schedule: schedule,
            sessionIdx: sessionIdx,
            sessionsPerWeek: sessionsPerWeek
        )
        let params = adaptiveAdjustedParams(
            from: resolvedParams,
            isPrimary: isPrimary,
            schedule: schedule,
            doseTargetProfile: doseTargetProfile
        )
        let effectiveWorkingSets = schedule.isDeload ? max(2, params.sets / 2) : params.sets
        let workingBlocks = progressionResolver.buildWorkingSetBlocks(
            exercise: templateEx,
            isSessionOpener: isSessionOpener,
            focusProfile: focusProfile,
            level: level,
            schedule: schedule,
            params: params,
            totalWorkingSets: effectiveWorkingSets
        )

        let warmupReferencePct = workingBlocks
            .compactMap(\.percentage1RM)
            .max()
        if isPrimary, let workingPct = warmupReferencePct, !schedule.isDeload {
            for (i, multiplier) in [0.40, 0.55, 0.70].enumerated() {
                let warmupPct = workingPct * multiplier
                let load = loadResolver.computePrescribedLoadContext(
                    exercise: templateEx,
                    percentage1RM: warmupPct,
                    oneRepMaxes: oneRepMaxes
                )
                usedLiftMapping = usedLiftMapping || load.usedMappedSourceLift
                let warmup = ProgramSessionExercise(
                    exerciseName: templateEx.exerciseName,
                    orderIndex: idx + i,
                    targetSets: 1,
                    targetReps: params.reps,
                    targetPercentage1RM: warmupPct,
                    isWarmup: true,
                    prescribedWeight: load.prescribedWeight,
                    prescribedWeightUnit: load.prescribedWeightUnit,
                    targetEffortType: progressionResolver.resolveTargetEffortType(
                        percentage1RM: warmupPct,
                        targetRPE: nil,
                        targetRIR: nil
                    ),
                    baseLiftUsed: load.baseLiftUsed,
                    effectiveOneRepMax: load.effectiveOneRepMax,
                    effectiveOneRepMaxUnit: load.effectiveOneRepMaxUnit,
                    usedMappedSourceLift: load.usedMappedSourceLift,
                    progressionPhase: phase,
                    topBackoffGroupID: topBackoffGroupID,
                    explainabilityPurpose: .technique
                )
                warmup.estimatedFatigueScore = loadEstimator.estimateLoad(for: warmup).fatigueScore
                context.insert(warmup)
                warmup.session = session
            }
            idx += 3
        }

        for block in workingBlocks {
            let load = loadResolver.computePrescribedLoadContext(
                exercise: templateEx,
                percentage1RM: block.percentage1RM,
                oneRepMaxes: oneRepMaxes
            )
            usedLiftMapping = usedLiftMapping || load.usedMappedSourceLift
            if block.style == .topSet || block.style == .backoff {
                usedTopSetBackoff = true
            }
            let working = ProgramSessionExercise(
                exerciseName: templateEx.exerciseName,
                orderIndex: idx,
                targetSets: block.sets,
                targetReps: block.reps,
                targetPercentage1RM: block.percentage1RM,
                targetRPE: block.rpe,
                targetRIR: block.rir,
                prescribedWeight: load.prescribedWeight,
                prescribedWeightUnit: load.prescribedWeightUnit,
                workingSetStyle: block.style,
                backoffPercentageDrop: block.backoffDrop,
                targetEffortType: progressionResolver.resolveTargetEffortType(
                    percentage1RM: block.percentage1RM,
                    targetRPE: block.rpe,
                    targetRIR: block.rir
                ),
                baseLiftUsed: load.baseLiftUsed,
                effectiveOneRepMax: load.effectiveOneRepMax,
                effectiveOneRepMaxUnit: load.effectiveOneRepMaxUnit,
                usedMappedSourceLift: load.usedMappedSourceLift,
                progressionPhase: phase,
                topBackoffGroupID: topBackoffGroupID,
                explainabilityPurpose: explainabilityPurpose,
                explainabilitySelectionReason: isPrimary ? nil : accessorySelectionReason
            )
            working.estimatedFatigueScore = loadEstimator.estimateLoad(for: working).fatigueScore
            context.insert(working)
            working.session = session
            idx += 1
        }
        return idx
    }

    // MARK: - Helpers

    private func resolvedSessionDefs(from template: FocusTemplate, frequency: Int) -> [SessionDefinition] {
        if let defs = template.sessionDefinitions[frequency] { return defs }
        let supported = template.sessionDefinitions.keys.sorted()
        let closest = supported.min(by: { abs($0 - frequency) < abs($1 - frequency) }) ?? frequency
        return template.sessionDefinitions[closest] ?? []
    }

    private func adaptiveAdjustedParams(
        from params: ProgramGenerationExerciseParams,
        isPrimary: Bool,
        schedule: ProgramGenerationWeekSchedule,
        doseTargetProfile: DoseTargetProfile
    ) -> ProgramGenerationExerciseParams {
        let setScale = isPrimary ? doseTargetProfile.sessionStressScale : doseTargetProfile.weeklyVolumeScale
        let adjustedSets = max(1, Int((Double(params.sets) * setScale).rounded()))
        let adjustedPercentage = params.percentage1RM.map {
            let base = $0 * doseTargetProfile.intensityScale
            let deloadAdjusted = schedule.isDeload ? base * 0.97 : base
            return min(0.95, max(0.50, deloadAdjusted))
        }
        let adjustedRPE = params.rpe.map {
            let value = $0 - (doseTargetProfile.rirOffset * 0.35) + ((doseTargetProfile.intensityScale - 1.0) * 4.0)
            return min(10.0, max(5.5, value))
        }
        let adjustedRIR = params.rir.map {
            min(5.0, max(0.0, $0 + doseTargetProfile.rirOffset))
        }

        return ProgramGenerationExerciseParams(
            sets: adjustedSets,
            reps: params.reps,
            percentage1RM: adjustedPercentage,
            rpe: adjustedRPE,
            rir: adjustedRIR
        )
    }
}
