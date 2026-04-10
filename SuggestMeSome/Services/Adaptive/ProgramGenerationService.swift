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
        let weeks = weeklySummary(for: program)
        guard !weeks.isEmpty else { return "No weeks found." }

        return weeks.map { week in
            var lines: [String] = []
            lines.append("Week \(week.weekNumber) — total fatigue \(formatOneDecimal(week.totalFatigueScore))")
            for session in week.sessionSummaries {
                let nameSuffix = session.sessionName.map { " (\($0))" } ?? ""
                lines.append("  Session \(session.sessionNumber)\(nameSuffix): fatigue \(formatOneDecimal(session.fatigueScore))")
                for muscle in ProgramVolumeMuscle.allCases {
                    let sets = session.hardSetsByMuscle[muscle] ?? 0
                    guard sets > 0 else { continue }
                    lines.append("    \(muscle.displayName): \(formatOneDecimal(sets)) hard sets")
                }
            }
            lines.append("  Weekly totals:")
            for muscle in ProgramVolumeMuscle.allCases {
                let total = week.totalHardSetsByMuscle[muscle] ?? 0
                guard total > 0 else { continue }
                lines.append("    \(muscle.displayName): \(formatOneDecimal(total))")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    func weeklySummary(for program: TrainingProgram) -> [ProgramGeneratedWeekSummary] {
        program.weeks
            .sorted(by: { $0.weekNumber < $1.weekNumber })
            .map { week in
                var totalMuscleSets = emptyMuscleTotals()
                var totalFatigue = 0.0

                let sessionSummaries = week.sessions
                    .sorted(by: { $0.sessionNumber < $1.sessionNumber })
                    .map { session -> ProgramGeneratedSessionSummary in
                        var sessionMuscleSets = emptyMuscleTotals()
                        var sessionFatigue = 0.0

                        for exercise in session.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }) where !exercise.isWarmup {
                            let estimate = estimateLoad(for: exercise)
                            addMuscleSets(estimate.hardSetsByMuscle, into: &sessionMuscleSets)
                            sessionFatigue += estimate.fatigueScore
                        }

                        addMuscleSets(sessionMuscleSets, into: &totalMuscleSets)
                        totalFatigue += sessionFatigue

                        return ProgramGeneratedSessionSummary(
                            sessionNumber: session.sessionNumber,
                            sessionName: session.sessionName,
                            hardSetsByMuscle: sessionMuscleSets,
                            fatigueScore: sessionFatigue
                        )
                    }

                return ProgramGeneratedWeekSummary(
                    weekNumber: week.weekNumber,
                    sessionSummaries: sessionSummaries,
                    totalHardSetsByMuscle: totalMuscleSets,
                    totalFatigueScore: totalFatigue
                )
            }
    }

    func programmingProfile(for focus: ProgramFocus) -> ProgramFocusProgrammingProfile {
        FocusTemplateLibrary.programmingProfile(for: focus)
    }

    private func stampPlannedFatigueSummaries(on program: TrainingProgram) {
        let byWeek = Dictionary(uniqueKeysWithValues: weeklySummary(for: program).map { ($0.weekNumber, $0) })
        for week in program.weeks {
            guard let summary = byWeek[week.weekNumber] else { continue }
            week.plannedFatigueScore = summary.totalFatigueScore
            let bySession = Dictionary(uniqueKeysWithValues: summary.sessionSummaries.map { ($0.sessionNumber, $0) })
            for session in week.sessions {
                session.plannedFatigueScore = bySession[session.sessionNumber]?.fatigueScore
            }
        }
    }

    // MARK: - Core Builder

    private func buildProgram(
        input: ProgramGenerationInput,
        context: ModelContext,
        shuffleSeed: Int
    ) -> TrainingProgram {
        let focusProfile = programmingProfile(for: input.focus)
        let strategy = resolveProgressionStrategy(focusProfile: focusProfile, level: input.level)

        // Step 1: Retrieve template
        let template = FocusTemplateLibrary.template(for: input.focus)

        // Step 2: Select session definitions for chosen frequency
        let sessionDefs = resolvedSessionDefs(from: template, frequency: input.sessionsPerWeek)
        let resolvedFrequency = max(1, sessionDefs.count)
        let progressionModel = progressionModel(for: strategy)
        var usedLiftMapping = false
        var usedTopSetBackoff = false

        // Step 5: Create TrainingProgram
        let program = TrainingProgram(
            name: "\(template.displayName) — \(input.level.rawValue.capitalized) \(input.durationWeeks)wk",
            lengthInWeeks: input.durationWeeks,
            sessionsPerWeek: resolvedFrequency,
            source: .aiGenerated,
            descriptionText: periodizationDescription(for: strategy),
            progressionModel: progressionModel,
            usedLiftMapping: false,
            usedVolumeBalancing: true,
            usedFatigueBalancing: true,
            usedTopSetBackoff: false
        )
        context.insert(program)

        // Steps 3–4: Build periodized week schedules
        let schedules = buildWeekSchedules(strategy: strategy, durationWeeks: input.durationWeeks, focusProfile: focusProfile)

        // Step 6: Build weekly accessory selections using volume and fatigue accounting.
        let weeklyAccessoryPlan = buildAdaptiveAccessoryPlan(
            sessionDefs: sessionDefs,
            schedules: schedules,
            focus: input.focus,
            focusProfile: focusProfile,
            level: input.level,
            sessionsPerWeek: resolvedFrequency,
            seed: shuffleSeed
        )

        // Step 4: Build week-by-week structure
        for schedule in schedules {
            let weekTemplate = ProgramWeekTemplate(
                weekNumber: schedule.weekNumber,
                isDeloadWeek: schedule.isDeload,
                progressionPhase: weekProgressionPhase(strategy: strategy, schedule: schedule)
            )
            context.insert(weekTemplate)
            weekTemplate.program = program

            for (sessionIdx, sessionDef) in sessionDefs.enumerated() {
                let sessionTemplate = ProgramSessionTemplate(
                    sessionNumber: sessionIdx + 1,
                    sessionName: sessionDef.sessionName
                )
                context.insert(sessionTemplate)
                sessionTemplate.week = weekTemplate

                let weekAccessories = weeklyAccessoryPlan[schedule.weekNumber] ?? Array(repeating: [], count: sessionDefs.count)
                let accessories = sessionIdx < weekAccessories.count ? weekAccessories[sessionIdx] : []
                var orderIdx = 0

                for primary in sessionDef.primaryExercises {
                    orderIdx = populateExercise(
                        primary, isPrimary: true,
                        isSessionOpener: orderIdx == 0,
                        strategy: strategy,
                        focusProfile: focusProfile,
                        schedule: schedule, sessionIdx: sessionIdx,
                        sessionsPerWeek: resolvedFrequency, level: input.level,
                        oneRepMaxes: input.oneRepMaxes,
                        session: sessionTemplate, orderIdx: orderIdx, context: context,
                        usedLiftMapping: &usedLiftMapping,
                        usedTopSetBackoff: &usedTopSetBackoff
                    )
                }

                for accessory in accessories {
                    orderIdx = populateExercise(
                        accessory, isPrimary: false,
                        isSessionOpener: false,
                        strategy: strategy,
                        focusProfile: focusProfile,
                        schedule: schedule, sessionIdx: sessionIdx,
                        sessionsPerWeek: resolvedFrequency, level: input.level,
                        oneRepMaxes: input.oneRepMaxes,
                        session: sessionTemplate, orderIdx: orderIdx, context: context,
                        usedLiftMapping: &usedLiftMapping,
                        usedTopSetBackoff: &usedTopSetBackoff
                    )
                }
            }
        }

        program.usedLiftMapping = usedLiftMapping
        program.usedTopSetBackoff = usedTopSetBackoff
        stampPlannedFatigueSummaries(on: program)

        return program
    }

    // MARK: - Exercise Population

    @discardableResult
    private func populateExercise(
        _ templateEx: TemplateExercise,
        isPrimary: Bool,
        isSessionOpener: Bool,
        strategy: ProgressionStrategy,
        focusProfile: ProgramFocusProgrammingProfile,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int,
        level: ProgramLevel,
        oneRepMaxes: [String: (weight: Double, unit: String)],
        session: ProgramSessionTemplate,
        orderIdx: Int,
        context: ModelContext,
        usedLiftMapping: inout Bool,
        usedTopSetBackoff: inout Bool
    ) -> Int {
        var idx = orderIdx
        let phase = progressionPhase(
            strategy: strategy,
            schedule: schedule,
            sessionIdx: sessionIdx,
            sessionsPerWeek: sessionsPerWeek
        )
        let topBackoffGroupID = UUID()

        // Cardio exercises: encode target duration as targetReps (minutes); no sets.
        if templateEx.role == .cardio {
            let mins = cardioDurationMinutes(progressionIndex: schedule.progressionIndex, isDeload: schedule.isDeload)
            let ex = ProgramSessionExercise(
                exerciseName: templateEx.exerciseName,
                orderIndex: idx,
                targetSets: nil,
                targetReps: mins,
                targetEffortType: ProgramTargetEffortType.none,
                progressionPhase: phase,
                estimatedFatigueScore: Double(mins) * 0.08
            )
            context.insert(ex)
            ex.session = session
            return idx + 1
        }

        let params = computeParams(
            exercise: templateEx,
            strategy: strategy,
            focusProfile: focusProfile,
            schedule: schedule,
            sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek
        )
        let effectiveWorkingSets = schedule.isDeload ? max(2, params.sets / 2) : params.sets
        let workingBlocks = buildWorkingSetBlocks(
            exercise: templateEx,
            isSessionOpener: isSessionOpener,
            focusProfile: focusProfile,
            level: level,
            schedule: schedule,
            params: params,
            totalWorkingSets: effectiveWorkingSets
        )

        // Warmup sets: 3 sets at 40 / 55 / 70% of the working weight.
        // Applied to primary/variation exercises with a %1RM target; skipped during deloads.
        // For top/backoff prescriptions, warmups key off the heaviest working %.
        let warmupReferencePct = workingBlocks
            .compactMap(\.percentage1RM)
            .max()
        if isPrimary, let workingPct = warmupReferencePct, !schedule.isDeload {
            for (i, multiplier) in [0.40, 0.55, 0.70].enumerated() {
                let warmupPct = workingPct * multiplier
                let load = computePrescribedLoadContext(
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
                    targetEffortType: resolveTargetEffortType(
                        percentage1RM: warmupPct,
                        targetRPE: nil,
                        targetRIR: nil
                    ),
                    baseLiftUsed: load.baseLiftUsed,
                    effectiveOneRepMax: load.effectiveOneRepMax,
                    effectiveOneRepMaxUnit: load.effectiveOneRepMaxUnit,
                    usedMappedSourceLift: load.usedMappedSourceLift,
                    progressionPhase: phase,
                    topBackoffGroupID: topBackoffGroupID
                )
                warmup.estimatedFatigueScore = estimateLoad(for: warmup).fatigueScore
                context.insert(warmup)
                warmup.session = session
            }
            idx += 3
        }

        for block in workingBlocks {
            let load = computePrescribedLoadContext(
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
                targetEffortType: resolveTargetEffortType(
                    percentage1RM: block.percentage1RM,
                    targetRPE: block.rpe,
                    targetRIR: block.rir
                ),
                baseLiftUsed: load.baseLiftUsed,
                effectiveOneRepMax: load.effectiveOneRepMax,
                effectiveOneRepMaxUnit: load.effectiveOneRepMaxUnit,
                usedMappedSourceLift: load.usedMappedSourceLift,
                progressionPhase: phase,
                topBackoffGroupID: topBackoffGroupID
            )
            working.estimatedFatigueScore = estimateLoad(for: working).fatigueScore
            context.insert(working)
            working.session = session
            idx += 1
        }
        return idx
    }

    private struct PrescribedLoadContext {
        let prescribedWeight: Double?
        let prescribedWeightUnit: String?
        let baseLiftUsed: String?
        let effectiveOneRepMax: Double?
        let effectiveOneRepMaxUnit: String?
        let usedMappedSourceLift: Bool
    }

    private func computePrescribedLoadContext(
        exercise: TemplateExercise,
        percentage1RM: Double?,
        oneRepMaxes: [String: (weight: Double, unit: String)]
    ) -> PrescribedLoadContext {
        let baseLift: String?
        let effectiveORM: (weight: Double, unit: String)?
        let usedMapped: Bool

        if let direct = oneRepMaxes[exercise.exerciseName] {
            baseLift = exercise.exerciseName
            effectiveORM = direct
            usedMapped = false
        } else if let sourceLift = exercise.loadSourceLift, let sourceORM = oneRepMaxes[sourceLift] {
            let multiplier = exercise.loadMultiplier ?? 1.0
            baseLift = sourceLift
            effectiveORM = (weight: sourceORM.weight * multiplier, unit: sourceORM.unit)
            usedMapped = true
        } else {
            baseLift = nil
            effectiveORM = nil
            usedMapped = false
        }

        guard let pct = percentage1RM, let orm = effectiveORM else {
            return PrescribedLoadContext(
                prescribedWeight: nil,
                prescribedWeightUnit: nil,
                baseLiftUsed: baseLift,
                effectiveOneRepMax: effectiveORM?.weight,
                effectiveOneRepMaxUnit: effectiveORM?.unit,
                usedMappedSourceLift: usedMapped
            )
        }

        let raw = pct * orm.weight
        let rounded: Double
        if orm.unit == "lbs" {
            rounded = max(5.0, (raw / 5.0).rounded() * 5.0)
        } else {
            rounded = max(2.5, (raw / 2.5).rounded() * 2.5)
        }
        return PrescribedLoadContext(
            prescribedWeight: rounded,
            prescribedWeightUnit: orm.unit,
            baseLiftUsed: baseLift,
            effectiveOneRepMax: orm.weight,
            effectiveOneRepMaxUnit: orm.unit,
            usedMappedSourceLift: usedMapped
        )
    }

    private struct WorkingSetBlock {
        let style: ProgramWorkingSetStyle
        let sets: Int
        let reps: Int
        let percentage1RM: Double?
        let rpe: Double?
        let rir: Double?
        let backoffDrop: Double?
    }

    private func buildWorkingSetBlocks(
        exercise: TemplateExercise,
        isSessionOpener: Bool,
        focusProfile: ProgramFocusProgrammingProfile,
        level: ProgramLevel,
        schedule: WeekSchedule,
        params: ExerciseParams,
        totalWorkingSets: Int
    ) -> [WorkingSetBlock] {
        // Straight sets remain the default and all deload weeks use straight work.
        guard !schedule.isDeload else {
            return [straightSetBlock(from: params, sets: totalWorkingSets)]
        }

        guard shouldUseTopBackoff(
            for: exercise,
            isSessionOpener: isSessionOpener,
            focusProfile: focusProfile,
            level: level,
            params: params
        ),
              let top = exercise.topSetPrescription,
              let backoff = exercise.backoffPrescription,
              let topPct = params.percentage1RM else {
            return [straightSetBlock(from: params, sets: totalWorkingSets)]
        }

        let topSets = max(1, top.setCount)
        let topReps = resolvedTopSetReps(baseReps: params.reps)
        let topRPE = top.targetRPE

        let drop = (backoff.loadDropRange.lowerBound + backoff.loadDropRange.upperBound) / 2.0
        let backoffPct = max(0.50, topPct * (1.0 - drop))
        let backoffSets = max(1, backoff.setCount)
        let backoffReps = resolvedBackoffReps(baseReps: params.reps, repDelta: backoff.repDelta)

        return [
            WorkingSetBlock(
                style: .topSet,
                sets: topSets,
                reps: topReps,
                percentage1RM: topPct,
                rpe: topRPE,
                rir: nil,
                backoffDrop: nil
            ),
            WorkingSetBlock(
                style: .backoff,
                sets: backoffSets,
                reps: backoffReps,
                percentage1RM: backoffPct,
                rpe: params.rpe,
                rir: nil,
                backoffDrop: drop
            )
        ]
    }

    private func shouldUseTopBackoff(
        for exercise: TemplateExercise,
        isSessionOpener: Bool,
        focusProfile: ProgramFocusProgrammingProfile,
        level: ProgramLevel,
        params: ExerciseParams
    ) -> Bool {
        if focusProfile.topSetBackoffPolicy == .disabled { return false }
        // Beginner templates stay predominantly straight-set.
        if level == .beginner { return false }
        if focusProfile.topSetBackoffPolicy == .compoundOpener {
            if !isSessionOpener { return false }
            if exercise.role != .primary && exercise.role != .variation { return false }
            // Bodybuilding opener logic should stay mostly strength-endurance, not peaking.
            if params.reps < 5 || params.reps > 7 { return false }
        } else {
            // High-rep hypertrophy work should stay straight-set.
            if params.reps >= 8 { return false }
        }
        // Only %1RM-based work can support load-dropped backoffs.
        if exercise.percentage1RM == nil { return false }
        return exercise.topSetPrescription != nil && exercise.backoffPrescription != nil
    }

    private func straightSetBlock(from params: ExerciseParams, sets: Int) -> WorkingSetBlock {
        WorkingSetBlock(
            style: .straight,
            sets: sets,
            reps: params.reps,
            percentage1RM: params.percentage1RM,
            rpe: params.rpe,
            rir: params.rir,
            backoffDrop: nil
        )
    }

    private func resolvedTopSetReps(baseReps: Int) -> Int {
        // For heavy exposures, allow top single/double feel.
        if baseReps <= 2 { return baseReps }
        if baseReps == 3 { return 2 }
        return baseReps
    }

    private func resolvedBackoffReps(baseReps: Int, repDelta: Int) -> Int {
        // Low-rep tops become more volumized on backoff work.
        if baseReps <= 3 {
            return min(8, max(4, baseReps + max(2, repDelta + 1)))
        }
        return min(15, max(1, baseReps + repDelta))
    }

    private struct ProgressionStrategy {
        let family: ProgramProgressionStrategyFamily
        let level: ProgramLevel
    }

    func progressionStrategyFamily(for focus: ProgramFocus, level: ProgramLevel) -> ProgramProgressionStrategyFamily {
        let profile = programmingProfile(for: focus)
        return resolveProgressionStrategy(focusProfile: profile, level: level).family
    }

    func progressionModel(for focus: ProgramFocus, level: ProgramLevel) -> ProgramProgressionModel {
        let profile = programmingProfile(for: focus)
        let strategy = resolveProgressionStrategy(focusProfile: profile, level: level)
        return progressionModel(for: strategy)
    }

    private func resolveProgressionStrategy(
        focusProfile: ProgramFocusProgrammingProfile,
        level: ProgramLevel
    ) -> ProgressionStrategy {
        ProgressionStrategy(
            family: focusProfile.progressionStrategyFamily,
            level: level
        )
    }

    private func progressionModel(for strategy: ProgressionStrategy) -> ProgramProgressionModel {
        switch strategy.family {
        case .strengthSkill:
            switch strategy.level {
            case .beginner: return .linear
            case .intermediate: return .dup
            case .advanced: return .block
            }
        case .mixedStrengthHypertrophy:
            switch strategy.level {
            case .beginner: return .linear
            case .intermediate, .advanced: return .dup
            }
        case .hypertrophyVolume:
            return .linear
        case .balancedTraining:
            return strategy.level == .beginner ? .linear : .dup
        case .enduranceConditioning:
            return .linear
        }
    }

    private func weekProgressionPhase(strategy: ProgressionStrategy, schedule: WeekSchedule) -> ProgramProgressionPhase {
        if schedule.isDeload { return .deload }

        switch strategy.family {
        case .strengthSkill:
            return strengthSkillWeekPhase(level: strategy.level, schedule: schedule)
        case .mixedStrengthHypertrophy:
            return mixedWeekPhase(level: strategy.level, schedule: schedule)
        case .hypertrophyVolume:
            return .hypertrophy
        case .balancedTraining:
            return strategy.level == .beginner ? .linearWorking : .dupModerate
        case .enduranceConditioning:
            return .linearWorking
        }
    }

    private func progressionPhase(
        strategy: ProgressionStrategy,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ProgramProgressionPhase {
        if schedule.isDeload { return .deload }

        switch strategy.family {
        case .strengthSkill:
            return strengthSkillSessionPhase(
                level: strategy.level,
                schedule: schedule,
                sessionIdx: sessionIdx,
                sessionsPerWeek: sessionsPerWeek
            )
        case .mixedStrengthHypertrophy:
            return mixedSessionPhase(
                level: strategy.level,
                schedule: schedule,
                sessionIdx: sessionIdx,
                sessionsPerWeek: sessionsPerWeek
            )
        case .hypertrophyVolume:
            return .hypertrophy
        case .balancedTraining:
            return balancedSessionPhase(
                level: strategy.level,
                sessionIdx: sessionIdx,
                sessionsPerWeek: sessionsPerWeek
            )
        case .enduranceConditioning:
            return .linearWorking
        }
    }

    private func strengthSkillWeekPhase(level: ProgramLevel, schedule: WeekSchedule) -> ProgramProgressionPhase {
        switch level {
        case .beginner: return .linearWorking
        case .intermediate: return .dupModerate
        case .advanced:
            switch schedule.advancedPhase {
            case .hypertrophy: return .hypertrophy
            case .strength: return .strength
            case .peaking: return .peaking
            case .none: return .hypertrophy
            }
        }
    }

    private func strengthSkillSessionPhase(
        level: ProgramLevel,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ProgramProgressionPhase {
        switch level {
        case .beginner:
            return .linearWorking
        case .intermediate:
            switch dupTier(sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek) {
            case .heavy: return .dupHeavy
            case .moderate: return .dupModerate
            case .light: return .dupLight
            }
        case .advanced:
            switch schedule.advancedPhase {
            case .hypertrophy: return .hypertrophy
            case .strength: return .strength
            case .peaking: return .peaking
            case .none: return .hypertrophy
            }
        }
    }

    private func mixedWeekPhase(level: ProgramLevel, schedule: WeekSchedule) -> ProgramProgressionPhase {
        switch level {
        case .beginner: return .linearWorking
        case .intermediate: return .dupModerate
        case .advanced:
            switch schedule.advancedPhase {
            case .strength: return .strength
            default: return .hypertrophy
            }
        }
    }

    private func mixedSessionPhase(
        level: ProgramLevel,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ProgramProgressionPhase {
        switch level {
        case .beginner:
            return .linearWorking
        case .intermediate:
            switch mixedTier(sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek) {
            case .heavy: return .dupHeavy
            case .moderate: return .dupModerate
            case .light: return .dupLight
            }
        case .advanced:
            switch schedule.advancedPhase {
            case .strength: return .strength
            default: return .hypertrophy
            }
        }
    }

    private func balancedSessionPhase(
        level: ProgramLevel,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ProgramProgressionPhase {
        if level == .beginner { return .linearWorking }
        switch balancedTier(sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek) {
        case .heavy: return .dupModerate
        case .moderate: return .dupModerate
        case .light: return .dupLight
        }
    }

    private func resolveTargetEffortType(
        percentage1RM: Double?,
        targetRPE: Double?,
        targetRIR: Double?
    ) -> ProgramTargetEffortType {
        if percentage1RM != nil { return .percentage1RM }
        if targetRIR != nil { return .rir }
        if targetRPE != nil { return .rpe }
        return .none
    }

    // MARK: - Periodization Parameter Computation

    private struct ExerciseParams {
        let sets: Int
        let reps: Int
        let percentage1RM: Double?
        let rpe: Double?
        let rir: Double?
    }

    private func computeParams(
        exercise: TemplateExercise,
        strategy: ProgressionStrategy,
        focusProfile: ProgramFocusProgrammingProfile,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ExerciseParams {
        switch strategy.family {
        case .strengthSkill:
            return strengthSkillParams(
                exercise: exercise,
                level: strategy.level,
                schedule: schedule,
                sessionIdx: sessionIdx,
                sessionsPerWeek: sessionsPerWeek
            )
        case .mixedStrengthHypertrophy:
            return mixedStrengthHypertrophyParams(
                exercise: exercise,
                level: strategy.level,
                schedule: schedule,
                sessionIdx: sessionIdx,
                sessionsPerWeek: sessionsPerWeek
            )
        case .hypertrophyVolume:
            return hypertrophyParams(
                exercise: exercise,
                focus: focusProfile.focus,
                level: strategy.level,
                schedule: schedule
            )
        case .balancedTraining:
            return balancedTrainingParams(
                exercise: exercise,
                level: strategy.level,
                schedule: schedule,
                sessionIdx: sessionIdx,
                sessionsPerWeek: sessionsPerWeek
            )
        case .enduranceConditioning:
            return enduranceConditioningParams(
                exercise: exercise,
                level: strategy.level,
                schedule: schedule
            )
        }
    }

    // MARK: Beginner — Linear Progression

    private enum BeginnerTuning {
        static let startingOffset = -0.02
        static let weeklyOffsetStep = 0.01
        static let maxPositiveOffset = 0.08
        static let maxNegativeOffset = -0.08
        static let deloadPercentageDrop = 0.08
        static let deloadRPE = 6.0
    }

    private func beginnerParams(
        exercise: TemplateExercise,
        schedule: WeekSchedule
    ) -> ExerciseParams {
        // Deload: explicit volume reduction (applied by caller) + lower intensity.
        if schedule.isDeload {
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(
                    anchor: anchor,
                    candidate: anchor - BeginnerTuning.deloadPercentageDrop,
                    minOffset: BeginnerTuning.maxNegativeOffset,
                    maxOffset: BeginnerTuning.maxPositiveOffset
                )
                return ExerciseParams(
                    sets: exercise.defaultSets,
                    reps: exercise.defaultReps,
                    percentage1RM: pct,
                    rpe: nil,
                    rir: nil
                )
            }
            return ExerciseParams(
                sets: exercise.defaultSets,
                reps: exercise.defaultReps,
                percentage1RM: nil,
                rpe: BeginnerTuning.deloadRPE,
                rir: nil
            )
        }

        // Working weeks: move around the template's anchor intensity.
        if let anchor = exercise.percentage1RM {
            let pct = clampedPercentage(
                anchor: anchor,
                candidate: anchor
                    + BeginnerTuning.startingOffset
                    + Double(schedule.progressionIndex) * BeginnerTuning.weeklyOffsetStep,
                minOffset: BeginnerTuning.maxNegativeOffset,
                maxOffset: BeginnerTuning.maxPositiveOffset
            )
            return ExerciseParams(
                sets: exercise.defaultSets,
                reps: exercise.defaultReps,
                percentage1RM: pct,
                rpe: nil,
                rir: nil
            )
        }

        // RPE-based work keeps template intent during working weeks.
        return ExerciseParams(
            sets: exercise.defaultSets,
            reps: exercise.defaultReps,
            percentage1RM: nil,
            rpe: exercise.targetRPE ?? 7.0,
            rir: nil
        )
    }

    private func strengthSkillParams(
        exercise: TemplateExercise,
        level: ProgramLevel,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ExerciseParams {
        switch level {
        case .beginner:
            return beginnerParams(exercise: exercise, schedule: schedule)
        case .intermediate:
            return intermediateParams(
                exercise: exercise,
                schedule: schedule,
                tier: dupTier(sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek)
            )
        case .advanced:
            return advancedParams(exercise: exercise, schedule: schedule)
        }
    }

    private func mixedStrengthHypertrophyParams(
        exercise: TemplateExercise,
        level: ProgramLevel,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ExerciseParams {
        switch level {
        case .beginner:
            return beginnerParams(exercise: exercise, schedule: schedule)
        case .intermediate:
            return intermediateParams(
                exercise: exercise,
                schedule: schedule,
                tier: mixedTier(sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek)
            )
        case .advanced:
            return advancedParams(exercise: exercise, schedule: schedule)
        }
    }

    private enum HypertrophyTuning {
        static let deloadPercentageDrop = 0.08
        static let deloadRPE = 6.5
        static let maxPositiveOffset = 0.08
        static let maxNegativeOffset = -0.12
    }

    private func hypertrophyParams(
        exercise: TemplateExercise,
        focus: ProgramFocus,
        level: ProgramLevel,
        schedule: WeekSchedule
    ) -> ExerciseParams {
        if focus == .bodybuilding {
            return bodybuildingHypertrophyParams(exercise: exercise, level: level, schedule: schedule)
        }

        let targetRepsByLevel: [ProgramLevel: Int] = [
            .beginner: 12,
            .intermediate: 10,
            .advanced: 8,
        ]
        let targetReps = max(exercise.defaultReps, targetRepsByLevel[level] ?? exercise.defaultReps)

        if schedule.isDeload {
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(
                    anchor: anchor,
                    candidate: anchor - HypertrophyTuning.deloadPercentageDrop,
                    minOffset: HypertrophyTuning.maxNegativeOffset,
                    maxOffset: HypertrophyTuning.maxPositiveOffset
                )
                return ExerciseParams(
                    sets: max(3, exercise.defaultSets),
                    reps: targetReps,
                    percentage1RM: pct,
                    rpe: nil,
                    rir: nil
                )
            }
            return ExerciseParams(
                sets: max(3, exercise.defaultSets),
                reps: targetReps,
                percentage1RM: nil,
                rpe: HypertrophyTuning.deloadRPE,
                rir: nil
            )
        }

        if let anchor = exercise.percentage1RM {
            let pct = clampedPercentage(
                anchor: anchor,
                candidate: anchor - 0.04 + (Double(schedule.progressionIndex) * 0.004),
                minOffset: HypertrophyTuning.maxNegativeOffset,
                maxOffset: HypertrophyTuning.maxPositiveOffset
            )
            return ExerciseParams(
                sets: max(3, exercise.defaultSets),
                reps: targetReps,
                percentage1RM: pct,
                rpe: nil,
                rir: nil
            )
        }

        let rpeAnchor = exercise.targetRPE ?? 7.5
        let rpeTuningByLevel: [ProgramLevel: Double] = [
            .beginner: -0.2,
            .intermediate: 0.0,
            .advanced: 0.2,
        ]
        return ExerciseParams(
            sets: max(3, exercise.defaultSets),
            reps: targetReps,
            percentage1RM: nil,
            rpe: clampedRPE(rpeAnchor + (rpeTuningByLevel[level] ?? 0.0)),
            rir: nil
        )
    }

    private enum BodybuildingExerciseClass {
        case compound
        case stableVariation
        case pumpIsolation
    }

    private func bodybuildingExerciseClass(for exercise: TemplateExercise) -> BodybuildingExerciseClass {
        if exercise.role == .primary, exercise.percentage1RM != nil { return .compound }
        if exercise.role == .variation || exercise.percentage1RM != nil { return .stableVariation }
        return .pumpIsolation
    }

    private func bodybuildingHypertrophyParams(
        exercise: TemplateExercise,
        level: ProgramLevel,
        schedule: WeekSchedule
    ) -> ExerciseParams {
        let cls = bodybuildingExerciseClass(for: exercise)
        let progressionStep = Double(schedule.progressionIndex)

        if schedule.isDeload {
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(
                    anchor: anchor,
                    candidate: anchor - 0.10,
                    minOffset: -0.14,
                    maxOffset: 0.08
                )
                let deloadSets: Int
                let deloadReps: Int
                switch cls {
                case .compound:
                    deloadSets = max(2, min(3, exercise.defaultSets))
                    deloadReps = max(6, exercise.defaultReps)
                case .stableVariation:
                    deloadSets = max(2, min(3, exercise.defaultSets))
                    deloadReps = max(8, exercise.defaultReps)
                case .pumpIsolation:
                    deloadSets = max(2, min(3, exercise.defaultSets))
                    deloadReps = max(12, exercise.defaultReps)
                }
                return ExerciseParams(
                    sets: deloadSets,
                    reps: deloadReps,
                    percentage1RM: pct,
                    rpe: nil,
                    rir: 3.0
                )
            }

            let deloadReps: Int
            switch cls {
            case .compound: deloadReps = max(8, exercise.defaultReps)
            case .stableVariation: deloadReps = max(10, exercise.defaultReps)
            case .pumpIsolation: deloadReps = max(12, exercise.defaultReps)
            }
            return ExerciseParams(
                sets: max(2, min(3, exercise.defaultSets)),
                reps: deloadReps,
                percentage1RM: nil,
                rpe: 6.5,
                rir: 3.0
            )
        }

        switch cls {
        case .compound:
            let repsByLevel: [ProgramLevel: Int] = [.beginner: 8, .intermediate: 7, .advanced: 6]
            let reps = max(6, repsByLevel[level] ?? 7)
            let sets = max(3, min(5, exercise.defaultSets))
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(
                    anchor: anchor,
                    candidate: anchor - 0.02 + progressionStep * 0.004,
                    minOffset: -0.10,
                    maxOffset: 0.08
                )
                return ExerciseParams(sets: sets, reps: reps, percentage1RM: pct, rpe: nil, rir: nil)
            }
            return ExerciseParams(sets: sets, reps: reps, percentage1RM: nil, rpe: clampedRPE((exercise.targetRPE ?? 8.0) - 0.2), rir: 2.0)

        case .stableVariation:
            let repsByLevel: [ProgramLevel: Int] = [.beginner: 11, .intermediate: 10, .advanced: 9]
            let reps = max(8, repsByLevel[level] ?? 10)
            let sets = max(3, min(4, exercise.defaultSets))
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(
                    anchor: anchor,
                    candidate: anchor - 0.04 + progressionStep * 0.003,
                    minOffset: -0.12,
                    maxOffset: 0.07
                )
                return ExerciseParams(sets: sets, reps: reps, percentage1RM: pct, rpe: nil, rir: nil)
            }
            let rirByLevel: [ProgramLevel: Double] = [.beginner: 2.5, .intermediate: 2.0, .advanced: 1.5]
            return ExerciseParams(sets: sets, reps: reps, percentage1RM: nil, rpe: clampedRPE(exercise.targetRPE ?? 7.5), rir: rirByLevel[level] ?? 2.0)

        case .pumpIsolation:
            let repsByLevel: [ProgramLevel: Int] = [.beginner: 14, .intermediate: 13, .advanced: 12]
            let reps = max(10, repsByLevel[level] ?? 13)
            let sets = max(3, min(4, exercise.defaultSets))
            let rirByLevel: [ProgramLevel: Double] = [.beginner: 3.0, .intermediate: 2.0, .advanced: 1.0]
            return ExerciseParams(
                sets: sets,
                reps: reps,
                percentage1RM: nil,
                rpe: clampedRPE((exercise.targetRPE ?? 7.0) - 0.3 + (level == .advanced ? 0.2 : 0.0)),
                rir: rirByLevel[level] ?? 2.0
            )
        }
    }

    private func balancedTrainingParams(
        exercise: TemplateExercise,
        level: ProgramLevel,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ExerciseParams {
        if level == .beginner {
            return beginnerParams(exercise: exercise, schedule: schedule)
        }
        return intermediateParams(
            exercise: exercise,
            schedule: schedule,
            tier: balancedTier(sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek)
        )
    }

    private enum EnduranceTuning {
        static let deloadPercentageDrop = 0.10
        static let deloadRPE = 6.0
        static let maxPositiveOffset = 0.05
        static let maxNegativeOffset = -0.14
    }

    private func enduranceConditioningParams(
        exercise: TemplateExercise,
        level: ProgramLevel,
        schedule: WeekSchedule
    ) -> ExerciseParams {
        let repBonusByLevel: [ProgramLevel: Int] = [
            .beginner: 2,
            .intermediate: 3,
            .advanced: 4,
        ]
        let reps = max(8, exercise.defaultReps + (repBonusByLevel[level] ?? 2))
        let sets = max(2, min(4, exercise.defaultSets))

        if schedule.isDeload {
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(
                    anchor: anchor,
                    candidate: anchor - EnduranceTuning.deloadPercentageDrop,
                    minOffset: EnduranceTuning.maxNegativeOffset,
                    maxOffset: EnduranceTuning.maxPositiveOffset
                )
                return ExerciseParams(
                    sets: sets,
                    reps: reps,
                    percentage1RM: pct,
                    rpe: nil,
                    rir: nil
                )
            }
            return ExerciseParams(
                sets: sets,
                reps: reps,
                percentage1RM: nil,
                rpe: EnduranceTuning.deloadRPE,
                rir: nil
            )
        }

        if let anchor = exercise.percentage1RM {
            let pct = clampedPercentage(
                anchor: anchor,
                candidate: anchor - 0.05 + (Double(schedule.progressionIndex) * 0.003),
                minOffset: EnduranceTuning.maxNegativeOffset,
                maxOffset: EnduranceTuning.maxPositiveOffset
            )
            return ExerciseParams(
                sets: sets,
                reps: reps,
                percentage1RM: pct,
                rpe: nil,
                rir: nil
            )
        }

        let rpeAnchor = exercise.targetRPE ?? 7.0
        return ExerciseParams(
            sets: sets,
            reps: reps,
            percentage1RM: nil,
            rpe: clampedRPE(rpeAnchor - 0.3),
            rir: nil
        )
    }

    // MARK: Intermediate — Daily Undulating Periodization

    private enum DUPTier {
        case heavy, moderate, light

        var percentageAnchorOffset: Double {
            switch self {
            case .heavy: return 0.03
            case .moderate: return 0.00
            case .light: return -0.06
            }
        }
        var defaultSets: Int {
            switch self { case .heavy, .moderate: return 4; case .light: return 3 }
        }
        var repCount: Int {
            // Middle of each rep range (3–5, 6–8, 8–12)
            switch self { case .heavy: return 4; case .moderate: return 7; case .light: return 10 }
        }
        var rpeAnchorOffset: Double {
            switch self {
            case .heavy: return 0.5
            case .moderate: return 0.0
            case .light: return -0.5
            }
        }
    }

    private enum IntermediateTuning {
        static let weeklyPercentageOffsetStep = 0.005
        static let maxPositiveOffset = 0.10
        static let maxNegativeOffset = -0.10
        static let deloadPercentageDrop = 0.10
        static let deloadRPE = 6.0
    }

    private func dupTier(sessionIdx: Int, sessionsPerWeek: Int) -> DUPTier {
        let patterns: [Int: [DUPTier]] = [
            2: [.heavy, .light],
            3: [.heavy, .light, .moderate],
            4: [.heavy, .moderate, .light, .moderate],
            5: [.heavy, .moderate, .light, .moderate, .light],
            6: [.heavy, .moderate, .light, .heavy, .moderate, .light],
        ]
        let pattern = patterns[sessionsPerWeek, default: [.heavy, .moderate, .light]]
        return pattern[sessionIdx % pattern.count]
    }

    private func mixedTier(sessionIdx: Int, sessionsPerWeek: Int) -> DUPTier {
        let patterns: [Int: [DUPTier]] = [
            2: [.heavy, .moderate],
            3: [.heavy, .moderate, .light],
            4: [.heavy, .moderate, .light, .moderate],
            5: [.heavy, .moderate, .light, .moderate, .moderate],
            6: [.heavy, .moderate, .light, .heavy, .moderate, .moderate],
        ]
        let pattern = patterns[sessionsPerWeek, default: [.heavy, .moderate, .light]]
        return pattern[sessionIdx % pattern.count]
    }

    private func balancedTier(sessionIdx: Int, sessionsPerWeek: Int) -> DUPTier {
        let patterns: [Int: [DUPTier]] = [
            2: [.moderate, .light],
            3: [.moderate, .light, .moderate],
            4: [.moderate, .light, .moderate, .light],
            5: [.moderate, .light, .moderate, .light, .moderate],
            6: [.moderate, .light, .moderate, .light, .moderate, .light],
        ]
        let pattern = patterns[sessionsPerWeek, default: [.moderate, .light]]
        return pattern[sessionIdx % pattern.count]
    }

    private func intermediateParams(
        exercise: TemplateExercise,
        schedule: WeekSchedule,
        tier: DUPTier
    ) -> ExerciseParams {
        // Deload: explicit, readable reductions from each exercise anchor.
        if schedule.isDeload {
            let baseSets = DUPTier.light.defaultSets  // populateExercise will halve to 2
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(
                    anchor: anchor,
                    candidate: anchor - IntermediateTuning.deloadPercentageDrop,
                    minOffset: IntermediateTuning.maxNegativeOffset,
                    maxOffset: IntermediateTuning.maxPositiveOffset
                )
                return ExerciseParams(
                    sets: baseSets,
                    reps: DUPTier.light.repCount,
                    percentage1RM: pct,
                    rpe: nil,
                    rir: nil
                )
            }
            return ExerciseParams(
                sets: baseSets,
                reps: DUPTier.light.repCount,
                percentage1RM: nil,
                rpe: IntermediateTuning.deloadRPE,
                rir: nil
            )
        }

        // Working weeks: tier shift + small weekly progression, both relative to template anchor.
        if let anchor = exercise.percentage1RM {
            let pct = clampedPercentage(
                anchor: anchor,
                candidate: anchor
                    + tier.percentageAnchorOffset
                    + Double(schedule.progressionIndex) * IntermediateTuning.weeklyPercentageOffsetStep,
                minOffset: IntermediateTuning.maxNegativeOffset,
                maxOffset: IntermediateTuning.maxPositiveOffset
            )
            return ExerciseParams(
                sets: tier.defaultSets,
                reps: tier.repCount,
                percentage1RM: pct,
                rpe: nil,
                rir: nil
            )
        }

        let rpeAnchor = exercise.targetRPE ?? 7.0
        return ExerciseParams(
            sets: tier.defaultSets,
            reps: tier.repCount,
            percentage1RM: nil,
            rpe: clampedRPE(rpeAnchor + tier.rpeAnchorOffset),
            rir: nil
        )
    }

    // MARK: Advanced — Block Periodization

    private enum AdvancedPhaseType {
        case hypertrophy, strength, peaking

        var percentageAnchorAdjustmentRange: (start: Double, end: Double) {
            switch self {
            case .hypertrophy: return (-0.08, -0.03)
            case .strength:    return (-0.02, 0.03)
            case .peaking:     return (0.04, 0.08)
            }
        }
        var repRange: (min: Int, max: Int) {
            switch self {
            case .hypertrophy: return (8, 12)
            case .strength:    return (4, 6)
            case .peaking:     return (1, 3)
            }
        }
        var defaultSets: Int {
            switch self { case .hypertrophy: return 4; case .strength, .peaking: return 5 }
        }
        var rpeAnchorOffset: Double {
            switch self {
            case .hypertrophy: return 0.0
            case .strength: return 0.5
            case .peaking: return 1.0
            }
        }
        var midReps: Int {
            let r = repRange; return (r.min + r.max + 1) / 2
        }
    }

    private enum AdvancedTuning {
        static let maxPositiveOffset = 0.12
        static let maxNegativeOffset = -0.12
        static let deloadPercentageDrop = 0.10
        static let deloadRPE = 6.0
    }

    private func advancedParams(
        exercise: TemplateExercise,
        schedule: WeekSchedule
    ) -> ExerciseParams {
        let phase = schedule.advancedPhase ?? .hypertrophy

        // Deload: explicit intensity reductions while caller handles volume reduction.
        if schedule.isDeload {
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(
                    anchor: anchor,
                    candidate: anchor - AdvancedTuning.deloadPercentageDrop,
                    minOffset: AdvancedTuning.maxNegativeOffset,
                    maxOffset: AdvancedTuning.maxPositiveOffset
                )
                return ExerciseParams(
                    sets: phase.defaultSets,
                    reps: phase.midReps,
                    percentage1RM: pct,
                    rpe: nil,
                    rir: nil
                )
            }
            return ExerciseParams(
                sets: phase.defaultSets,
                reps: phase.midReps,
                percentage1RM: nil,
                rpe: AdvancedTuning.deloadRPE,
                rir: nil
            )
        }

        // Working phases: interpolate phase adjustments relative to template anchor.
        let (startAdjustment, endAdjustment) = phase.percentageAnchorAdjustmentRange
        let t = schedule.phaseLength > 1
            ? Double(schedule.phaseWeekIndex) / Double(schedule.phaseLength - 1)
            : 0.0
        let phaseAdjustment = startAdjustment + (endAdjustment - startAdjustment) * t

        if let anchor = exercise.percentage1RM {
            let pct = clampedPercentage(
                anchor: anchor,
                candidate: anchor + phaseAdjustment,
                minOffset: AdvancedTuning.maxNegativeOffset,
                maxOffset: AdvancedTuning.maxPositiveOffset
            )
            return ExerciseParams(
                sets: phase.defaultSets,
                reps: phase.midReps,
                percentage1RM: pct,
                rpe: nil,
                rir: nil
            )
        }

        let rpeAnchor = exercise.targetRPE ?? 7.0
        return ExerciseParams(
            sets: phase.defaultSets,
            reps: phase.midReps,
            percentage1RM: nil,
            rpe: clampedRPE(rpeAnchor + phase.rpeAnchorOffset),
            rir: nil
        )
    }

    // MARK: - Week Schedule Builder

    private struct WeekSchedule {
        let weekNumber: Int
        let isDeload: Bool
        /// 0-based count of completed working weeks used to drive linear progression.
        /// Deload weeks carry the same index as the preceding working week.
        let progressionIndex: Int
        /// Active phase for advanced periodization (carries previous phase through deload weeks).
        let advancedPhase: AdvancedPhaseType?
        /// 0-based week within the current phase, used for % interpolation.
        let phaseWeekIndex: Int
        /// Total working weeks in the current phase.
        let phaseLength: Int
    }

    private func buildWeekSchedules(
        strategy: ProgressionStrategy,
        durationWeeks: Int,
        focusProfile: ProgramFocusProgrammingProfile
    ) -> [WeekSchedule] {
        switch strategy.family {
        case .strengthSkill:
            switch strategy.level {
            case .advanced:
                return buildAdvancedWeekSchedules(durationWeeks: durationWeeks)
            case .beginner, .intermediate:
                return buildLinearWeekSchedules(durationWeeks: durationWeeks, deloadEvery: 4)
            }
        case .mixedStrengthHypertrophy:
            switch strategy.level {
            case .advanced:
                return buildMixedAdvancedWeekSchedules(durationWeeks: durationWeeks)
            case .beginner, .intermediate:
                return buildLinearWeekSchedules(durationWeeks: durationWeeks, deloadEvery: 4)
            }
        case .hypertrophyVolume:
            return buildLinearWeekSchedules(durationWeeks: durationWeeks, deloadEvery: 5)
        case .balancedTraining:
            let deloadInterval = strategy.level == .advanced ? 5 : 4
            return buildLinearWeekSchedules(durationWeeks: durationWeeks, deloadEvery: deloadInterval)
        case .enduranceConditioning:
            if focusProfile.defaultDeloadStyle == .enduranceStepBack {
                return buildLinearWeekSchedules(durationWeeks: durationWeeks, deloadEvery: 3)
            }
            return buildLinearWeekSchedules(durationWeeks: durationWeeks, deloadEvery: 4)
        }
    }

    /// Linear schedule with configurable deload interval and progression index.
    private func buildLinearWeekSchedules(durationWeeks: Int, deloadEvery: Int) -> [WeekSchedule] {
        var result: [WeekSchedule] = []
        var workingIdx = 0
        var lastWorkingIdx = 0
        let interval = max(2, deloadEvery)

        for week in 1...durationWeeks {
            let isDeload = week % interval == 0
            result.append(WeekSchedule(
                weekNumber: week,
                isDeload: isDeload,
                progressionIndex: isDeload ? lastWorkingIdx : workingIdx,
                advancedPhase: nil,
                phaseWeekIndex: 0,
                phaseLength: 1
            ))
            if !isDeload {
                lastWorkingIdx = workingIdx
                workingIdx += 1
            }
        }
        return result
    }

    /// Advanced: hypertrophy → deload → strength → deload → peaking (→ deload) blocks.
    private func buildAdvancedWeekSchedules(durationWeeks: Int) -> [WeekSchedule] {
        let sequence = advancedPhaseSequence(durationWeeks: durationWeeks)
        var result: [WeekSchedule] = []
        var weekNumber = 1
        var progressionIdx = 0
        var lastPhase: AdvancedPhaseType = .hypertrophy

        for (phaseOpt, count) in sequence {
            let isDeload = phaseOpt == nil
            // Deload weeks carry the previous phase so advancedParams can use correct rep scheme.
            let phase = phaseOpt ?? lastPhase

            for weekInPhase in 0..<count {
                result.append(WeekSchedule(
                    weekNumber: weekNumber,
                    isDeload: isDeload,
                    progressionIndex: progressionIdx,
                    advancedPhase: phase,
                    phaseWeekIndex: weekInPhase,
                    phaseLength: count
                ))
                weekNumber += 1
                if !isDeload { progressionIdx += 1 }
            }

            if let p = phaseOpt { lastPhase = p }
        }
        return result
    }

    private func advancedPhaseSequence(durationWeeks: Int) -> [(AdvancedPhaseType?, Int)] {
        switch durationWeeks {
        case 6:  return [(.hypertrophy, 2), (nil, 1), (.strength, 2), (.peaking, 1)]
        case 8:  return [(.hypertrophy, 3), (nil, 1), (.strength, 2), (.peaking, 1), (nil, 1)]
        case 10: return [(.hypertrophy, 3), (nil, 1), (.strength, 3), (nil, 1), (.peaking, 2)]
        case 12: return [(.hypertrophy, 4), (nil, 1), (.strength, 3), (nil, 1), (.peaking, 2), (nil, 1)]
        default: return [(.hypertrophy, 4), (nil, 1), (.strength, 3), (nil, 1), (.peaking, 2), (nil, 1)]
        }
    }

    /// Mixed strategy keeps long hypertrophy exposure and short strength exposure.
    private func buildMixedAdvancedWeekSchedules(durationWeeks: Int) -> [WeekSchedule] {
        let sequence = mixedAdvancedPhaseSequence(durationWeeks: durationWeeks)
        var result: [WeekSchedule] = []
        var weekNumber = 1
        var progressionIdx = 0
        var lastPhase: AdvancedPhaseType = .hypertrophy

        for (phaseOpt, count) in sequence {
            let isDeload = phaseOpt == nil
            let phase = phaseOpt ?? lastPhase

            for weekInPhase in 0..<count {
                result.append(WeekSchedule(
                    weekNumber: weekNumber,
                    isDeload: isDeload,
                    progressionIndex: progressionIdx,
                    advancedPhase: phase,
                    phaseWeekIndex: weekInPhase,
                    phaseLength: count
                ))
                weekNumber += 1
                if !isDeload { progressionIdx += 1 }
            }

            if let p = phaseOpt { lastPhase = p }
        }
        return result
    }

    private func mixedAdvancedPhaseSequence(durationWeeks: Int) -> [(AdvancedPhaseType?, Int)] {
        switch durationWeeks {
        case 6:  return [(.hypertrophy, 3), (nil, 1), (.strength, 2)]
        case 8:  return [(.hypertrophy, 4), (nil, 1), (.strength, 2), (nil, 1)]
        case 10: return [(.hypertrophy, 5), (nil, 1), (.strength, 3), (nil, 1)]
        case 12: return [(.hypertrophy, 6), (nil, 1), (.strength, 4), (nil, 1)]
        default: return [(.hypertrophy, 6), (nil, 1), (.strength, 4), (nil, 1)]
        }
    }

    // MARK: - Accessory Planning (Volume + Fatigue Aware)

    private struct ExerciseLoadEstimate {
        let hardSetsByMuscle: [ProgramVolumeMuscle: Double]
        let fatigueScore: Double
        let highFatigueScore: Double
    }

    private struct AccessoryCandidate {
        let exercise: TemplateExercise
        let estimate: ExerciseLoadEstimate
        let score: Double
    }

    private func buildAdaptiveAccessoryPlan(
        sessionDefs: [SessionDefinition],
        schedules: [WeekSchedule],
        focus: ProgramFocus,
        focusProfile: ProgramFocusProgrammingProfile,
        level: ProgramLevel,
        sessionsPerWeek: Int,
        seed: Int
    ) -> [Int: [[TemplateExercise]]] {
        let volumeTargets = ProgramExerciseMetadataService.weeklyVolumeTargets(focus: focus, level: level)
        let movementTargets = ProgramExerciseMetadataService.weeklyMovementPatternTargets(
            focus: focus,
            sessionsPerWeek: sessionsPerWeek
        )
        let fatigueBudgets = ProgramExerciseMetadataService.fatigueBudgets(
            focus: focus,
            level: level,
            sessionsPerWeek: sessionsPerWeek
        )

        var planByWeek: [Int: [[TemplateExercise]]] = [:]
        var lastUsedWeekBySession: [Int: [String: Int]] = [:]
        var previousWeekLastSessionFatigue = 0.0
        var previousWeekLastSessionHighFatigue = 0.0
        var rng = SeededRNG(seed: seed)

        for schedule in schedules {
            var weeklyMuscleSets = emptyMuscleTotals()
            var weeklyFatigue = 0.0
            var sessionFatigue = Array(repeating: 0.0, count: sessionDefs.count)
            var sessionHighFatigue = Array(repeating: 0.0, count: sessionDefs.count)
            var weekAccessories = Array(repeating: [TemplateExercise](), count: sessionDefs.count)
            var sessionPatternCoverage = Array(repeating: Set<ProgramMovementPattern>(), count: sessionDefs.count)
            var weeklyPatternExposure = Dictionary(uniqueKeysWithValues: ProgramMovementPattern.allCases.map { ($0, 0) })

            // Baseline from primaries/variations establishes the week's starting deficits and fatigue.
            for (sessionIdx, sessionDef) in sessionDefs.enumerated() {
                for primary in sessionDef.primaryExercises {
                    let estimate = estimateLoad(
                        for: primary,
                        focusProfile: focusProfile,
                        level: level,
                        schedule: schedule,
                        sessionIdx: sessionIdx,
                        sessionsPerWeek: sessionsPerWeek
                    )
                    addMuscleSets(estimate.hardSetsByMuscle, into: &weeklyMuscleSets)
                    sessionFatigue[sessionIdx] += estimate.fatigueScore
                    sessionHighFatigue[sessionIdx] += estimate.highFatigueScore
                    weeklyFatigue += estimate.fatigueScore
                    sessionPatternCoverage[sessionIdx].formUnion(
                        ProgramExerciseMetadataService.movementPatterns(for: primary.exerciseName)
                    )
                }
            }
            for patterns in sessionPatternCoverage {
                for pattern in patterns {
                    weeklyPatternExposure[pattern, default: 0] += 1
                }
            }

            // Accessory picks are selected to fill under-target muscles first, then maintain variability.
            for (sessionIdx, sessionDef) in sessionDefs.enumerated() {
                let selectionCount = resolvedAccessorySelectionCount(
                    focus: focus,
                    sessionName: sessionDef.sessionName,
                    requested: sessionDef.accessoryCount,
                    available: sessionDef.accessoryPool.count
                )
                guard selectionCount > 0 else { continue }

                let isDeadliftHeavy = isDeadliftHeavySession(sessionDef)
                let sessionAccessoryPatterns = sessionDef.accessoryPool.reduce(into: Set<ProgramMovementPattern>()) {
                    $0.formUnion(ProgramExerciseMetadataService.movementPatterns(for: $1.exerciseName))
                }
                var chosen: [TemplateExercise] = []
                var chosenNames: Set<String> = []

                while chosen.count < selectionCount {
                    let remaining = sessionDef.accessoryPool
                        .filter { !chosenNames.contains($0.exerciseName) }
                        .sorted { $0.exerciseName < $1.exerciseName }
                    guard !remaining.isEmpty else { break }

                    let previousSessionFatigue = sessionIdx > 0
                        ? sessionFatigue[sessionIdx - 1]
                        : previousWeekLastSessionFatigue
                    let previousSessionHighFatigue = sessionIdx > 0
                        ? sessionHighFatigue[sessionIdx - 1]
                        : previousWeekLastSessionHighFatigue

                    var best: AccessoryCandidate?

                    for candidate in remaining {
                        let estimate = estimateLoad(
                            for: candidate,
                            focusProfile: focusProfile,
                            level: level,
                            schedule: schedule,
                            sessionIdx: sessionIdx,
                            sessionsPerWeek: sessionsPerWeek
                        )
                        let candidatePatterns = ProgramExerciseMetadataService.movementPatterns(
                            for: candidate.exerciseName
                        )

                        if focus == .bodybuilding,
                           isJunkBodybuildingAccessory(
                            estimate: estimate,
                            currentWeeklyMuscleSets: weeklyMuscleSets,
                            volumeTargets: volumeTargets,
                            sessionName: sessionDef.sessionName
                           ) {
                            continue
                        }

                        if shouldRejectMovementCandidate(
                            focus: focus,
                            sessionName: sessionDef.sessionName,
                            candidatePatterns: candidatePatterns,
                            currentSessionPatterns: sessionPatternCoverage[sessionIdx],
                            movementTargets: movementTargets,
                            weeklyPatternExposure: weeklyPatternExposure,
                            sessionAccessoryPatterns: sessionAccessoryPatterns
                        ) {
                            continue
                        }

                        if violatesFatigueBudgets(
                            estimate: estimate,
                            currentWeekFatigue: weeklyFatigue,
                            currentSessionFatigue: sessionFatigue[sessionIdx],
                            previousSessionFatigue: previousSessionFatigue,
                            fatigueBudgets: fatigueBudgets,
                            isDeadliftHeavySession: isDeadliftHeavy
                        ) {
                            continue
                        }

                        let lastUsed = lastUsedWeekBySession[sessionIdx]?[candidate.exerciseName]
                        let score = scoreAccessoryCandidate(
                            estimate: estimate,
                            currentWeeklyMuscleSets: weeklyMuscleSets,
                            volumeTargets: volumeTargets,
                            currentWeekFatigue: weeklyFatigue,
                            currentSessionFatigue: sessionFatigue[sessionIdx],
                            previousSessionFatigue: previousSessionFatigue,
                            previousSessionHighFatigue: previousSessionHighFatigue,
                            fatigueBudgets: fatigueBudgets,
                            isDeadliftHeavySession: isDeadliftHeavy,
                            focus: focus,
                            sessionName: sessionDef.sessionName,
                            currentWeekNumber: schedule.weekNumber,
                            lastUsedWeek: lastUsed,
                            movementTargets: movementTargets,
                            weeklyPatternExposure: weeklyPatternExposure,
                            currentSessionPatterns: sessionPatternCoverage[sessionIdx],
                            candidatePatterns: candidatePatterns,
                            rng: &rng
                        )

                        let scored = AccessoryCandidate(exercise: candidate, estimate: estimate, score: score)
                        if let best, scored.score <= best.score { continue }
                        best = scored
                    }

                    guard let best else { break }

                    chosen.append(best.exercise)
                    chosenNames.insert(best.exercise.exerciseName)
                    weekAccessories[sessionIdx].append(best.exercise)

                    addMuscleSets(best.estimate.hardSetsByMuscle, into: &weeklyMuscleSets)
                    weeklyFatigue += best.estimate.fatigueScore
                    sessionFatigue[sessionIdx] += best.estimate.fatigueScore
                    sessionHighFatigue[sessionIdx] += best.estimate.highFatigueScore
                    let selectedPatterns = ProgramExerciseMetadataService.movementPatterns(
                        for: best.exercise.exerciseName
                    )
                    let newlyAdded = selectedPatterns.subtracting(sessionPatternCoverage[sessionIdx])
                    sessionPatternCoverage[sessionIdx].formUnion(selectedPatterns)
                    for pattern in newlyAdded {
                        weeklyPatternExposure[pattern, default: 0] += 1
                    }

                    var history = lastUsedWeekBySession[sessionIdx] ?? [:]
                    history[best.exercise.exerciseName] = schedule.weekNumber
                    lastUsedWeekBySession[sessionIdx] = history
                }
            }

            previousWeekLastSessionFatigue = sessionFatigue.last ?? 0
            previousWeekLastSessionHighFatigue = sessionHighFatigue.last ?? 0
            planByWeek[schedule.weekNumber] = weekAccessories
        }

        return planByWeek
    }

    private func violatesFatigueBudgets(
        estimate: ExerciseLoadEstimate,
        currentWeekFatigue: Double,
        currentSessionFatigue: Double,
        previousSessionFatigue: Double,
        fatigueBudgets: ProgramFatigueBudgets,
        isDeadliftHeavySession: Bool
    ) -> Bool {
        let sessionBudget = isDeadliftHeavySession
            ? fatigueBudgets.deadliftSessionBudget
            : fatigueBudgets.sessionBudget
        let projectedSessionFatigue = currentSessionFatigue + estimate.fatigueScore
        if projectedSessionFatigue > sessionBudget { return true }

        let projectedWeekFatigue = currentWeekFatigue + estimate.fatigueScore
        if projectedWeekFatigue > fatigueBudgets.weekBudget { return true }

        let projectedAdjacentFatigue = previousSessionFatigue + projectedSessionFatigue
        if projectedAdjacentFatigue > fatigueBudgets.adjacentSessionPairBudget { return true }

        return false
    }

    private func scoreAccessoryCandidate(
        estimate: ExerciseLoadEstimate,
        currentWeeklyMuscleSets: [ProgramVolumeMuscle: Double],
        volumeTargets: ProgramWeeklyVolumeTargets,
        currentWeekFatigue: Double,
        currentSessionFatigue: Double,
        previousSessionFatigue: Double,
        previousSessionHighFatigue: Double,
        fatigueBudgets: ProgramFatigueBudgets,
        isDeadliftHeavySession: Bool,
        focus: ProgramFocus,
        sessionName: String,
        currentWeekNumber: Int,
        lastUsedWeek: Int?,
        movementTargets: [ProgramMovementPattern: Int],
        weeklyPatternExposure: [ProgramMovementPattern: Int],
        currentSessionPatterns: Set<ProgramMovementPattern>,
        candidatePatterns: Set<ProgramMovementPattern>,
        rng: inout SeededRNG
    ) -> Double {
        var score = 0.0

        for muscle in ProgramVolumeMuscle.allCases {
            let current = currentWeeklyMuscleSets[muscle] ?? 0
            let added = estimate.hardSetsByMuscle[muscle] ?? 0
            guard added > 0 else { continue }

            let target = volumeTargets.range(for: muscle)
            let deficit = max(0, target.minHardSets - current)
            let usefulTowardDeficit = min(deficit, added)
            score += usefulTowardDeficit * 2.6

            let roomToMax = max(0, target.maxHardSets - current)
            score += min(roomToMax, added) * 0.40

            let overshoot = max(0, current + added - target.maxHardSets)
            score -= overshoot * 1.9
        }

        let sessionBudget = isDeadliftHeavySession ? fatigueBudgets.deadliftSessionBudget : fatigueBudgets.sessionBudget
        let projectedSessionFatigue = currentSessionFatigue + estimate.fatigueScore
        let projectedWeekFatigue = currentWeekFatigue + estimate.fatigueScore
        let projectedAdjacentFatigue = previousSessionFatigue + projectedSessionFatigue

        if projectedSessionFatigue > sessionBudget {
            score -= (projectedSessionFatigue - sessionBudget) * 3.3
        }
        if projectedWeekFatigue > fatigueBudgets.weekBudget {
            score -= (projectedWeekFatigue - fatigueBudgets.weekBudget) * 2.6
        }
        if projectedAdjacentFatigue > fatigueBudgets.adjacentSessionPairBudget {
            score -= (projectedAdjacentFatigue - fatigueBudgets.adjacentSessionPairBudget) * 2.8
        }

        if previousSessionHighFatigue > (fatigueBudgets.sessionBudget * 0.35) {
            score -= estimate.highFatigueScore * 2.3
        }
        if isDeadliftHeavySession {
            score -= estimate.highFatigueScore * 3.4
        }
        if projectedSessionFatigue > (sessionBudget * 0.90) {
            score -= estimate.highFatigueScore * 1.8
        }

        if let lastUsedWeek {
            let weeksSince = max(0, currentWeekNumber - lastUsedWeek)
            score += min(1.2, Double(weeksSince) * 0.20)
            if weeksSince == 0 { score -= 1.5 }
        } else {
            score += 1.0
        }

        let patternsAddingNewExposure = candidatePatterns.subtracting(currentSessionPatterns)
        for pattern in patternsAddingNewExposure {
            let currentExposure = weeklyPatternExposure[pattern] ?? 0
            let targetExposure = movementTargets[pattern] ?? 0
            guard targetExposure > 0 else { continue }

            if currentExposure < targetExposure {
                score += 3.0
            } else {
                score += 0.25
            }
        }

        if focus == .fullBody {
            let sessionCombined = currentSessionPatterns.union(candidatePatterns)
            if !sessionCombined.contains(.squatKneeDominant) && !sessionCombined.contains(.hinge) {
                score -= 4.0
            }
            if !sessionCombined.contains(.horizontalPush) && !sessionCombined.contains(.verticalPush) {
                score -= 3.2
            }
            if !sessionCombined.contains(.horizontalPull) && !sessionCombined.contains(.verticalPull) {
                score -= 3.2
            }
            if !sessionCombined.contains(.trunk) {
                score -= 0.8
            }
        }

        if focus == .generalFitness {
            let sessionCombined = currentSessionPatterns.union(candidatePatterns)
            if !sessionCombined.contains(.squatKneeDominant) && !sessionCombined.contains(.hinge) {
                score -= 1.8
            }
            if !sessionCombined.contains(.horizontalPush) && !sessionCombined.contains(.verticalPush) {
                score -= 1.4
            }
            if !sessionCombined.contains(.horizontalPull) && !sessionCombined.contains(.verticalPull) {
                score -= 1.4
            }
        }

        if focus == .pushPull {
            let lower = sessionName.lowercased()
            let combined = currentSessionPatterns.union(candidatePatterns)

            if lower.contains("push") {
                if !combined.contains(.horizontalPush) && !combined.contains(.verticalPush) {
                    score -= 3.4
                }
                if combined.contains(.verticalPull) || combined.contains(.horizontalPull) {
                    score -= 0.3
                }
            } else if lower.contains("pull") {
                if !combined.contains(.horizontalPull) && !combined.contains(.verticalPull) {
                    score -= 3.4
                }
                if combined.contains(.horizontalPush) || combined.contains(.verticalPush) {
                    score -= 0.3
                }
            } else if lower.contains("leg") || lower.contains("lower") {
                if !combined.contains(.squatKneeDominant) && !combined.contains(.hinge) {
                    score -= 3.0
                }
            }
        }

        if focus == .bodybuilding {
            let sessionTargets = bodybuildingSessionPriorityMuscles(sessionName: sessionName)
            let targetContribution = sessionTargets.reduce(0.0) { partial, muscle in
                partial + (estimate.hardSetsByMuscle[muscle] ?? 0)
            }
            score += targetContribution * 1.4

            let offTargetContribution = ProgramVolumeMuscle.allCases
                .filter { !sessionTargets.contains($0) }
                .reduce(0.0) { partial, muscle in
                    partial + (estimate.hardSetsByMuscle[muscle] ?? 0)
                }
            score -= offTargetContribution * 0.30
        }

        score += randomJitter(using: &rng, magnitude: 0.16)
        return score
    }

    private func resolvedAccessorySelectionCount(
        focus: ProgramFocus,
        sessionName: String,
        requested: Int,
        available: Int
    ) -> Int {
        var count = min(requested, available)
        switch focus {
        case .generalFitness:
            count = min(count, 3)
            return max(2, count)
        case .fullBody:
            count = min(count, 2)
            return max(1, count)
        case .pushPull:
            if sessionName.lowercased().contains("legs") || sessionName.lowercased().contains("lower") {
                count = min(count, 3)
            } else {
                count = min(count, 2)
            }
            return max(1, count)
        case .bodybuilding:
            if sessionName.lowercased().contains("arms") {
                count = min(count, 3)
            } else {
                count = min(count, 4)
            }
            return max(1, count)
        default:
            return count
        }
    }

    private func shouldRejectMovementCandidate(
        focus: ProgramFocus,
        sessionName: String,
        candidatePatterns: Set<ProgramMovementPattern>,
        currentSessionPatterns: Set<ProgramMovementPattern>,
        movementTargets: [ProgramMovementPattern: Int],
        weeklyPatternExposure: [ProgramMovementPattern: Int],
        sessionAccessoryPatterns: Set<ProgramMovementPattern>
    ) -> Bool {
        if focus == .fullBody {
            let combined = currentSessionPatterns.union(candidatePatterns)
            let hasLower = combined.contains(.squatKneeDominant) || combined.contains(.hinge)
            let hasPush = combined.contains(.horizontalPush) || combined.contains(.verticalPush)
            let hasPull = combined.contains(.horizontalPull) || combined.contains(.verticalPull)
            if !hasLower && !candidatePatterns.contains(.squatKneeDominant) && !candidatePatterns.contains(.hinge) {
                return true
            }
            if !hasPush && !candidatePatterns.contains(.horizontalPush) && !candidatePatterns.contains(.verticalPush) {
                return true
            }
            if !hasPull && !candidatePatterns.contains(.horizontalPull) && !candidatePatterns.contains(.verticalPull) {
                return true
            }
        }

        if focus == .pushPull {
            let lower = sessionName.lowercased()
            if (lower.contains("push") && candidatePatterns.isDisjoint(with: Set([.horizontalPush, .verticalPush]))) ||
                (lower.contains("pull") && candidatePatterns.isDisjoint(with: Set([.horizontalPull, .verticalPull]))) ||
                ((lower.contains("leg") || lower.contains("lower")) && candidatePatterns.isDisjoint(with: Set([.squatKneeDominant, .hinge, .singleLeg]))) {
                return true
            }
        }

        if focus == .generalFitness || focus == .fullBody || focus == .pushPull {
            let combined = currentSessionPatterns.union(candidatePatterns)
            let unresolvedCriticalPatterns = movementTargets
                .filter { $0.value > 0 }
                .filter { (weeklyPatternExposure[$0.key] ?? 0) < $0.value }
                .filter { sessionAccessoryPatterns.contains($0.key) }
                .map(\.key)

            if !unresolvedCriticalPatterns.isEmpty &&
                unresolvedCriticalPatterns.allSatisfy({ !candidatePatterns.contains($0) }) &&
                combined.contains(.horizontalPush) &&
                combined.contains(.horizontalPull) {
                return true
            }
        }

        return false
    }

    private func isJunkBodybuildingAccessory(
        estimate: ExerciseLoadEstimate,
        currentWeeklyMuscleSets: [ProgramVolumeMuscle: Double],
        volumeTargets: ProgramWeeklyVolumeTargets,
        sessionName: String
    ) -> Bool {
        let usefulTowardDeficit = ProgramVolumeMuscle.allCases.reduce(0.0) { total, muscle in
            let current = currentWeeklyMuscleSets[muscle] ?? 0
            let deficit = max(0, volumeTargets.range(for: muscle).minHardSets - current)
            let added = estimate.hardSetsByMuscle[muscle] ?? 0
            return total + min(deficit, added)
        }

        let sessionTargets = bodybuildingSessionPriorityMuscles(sessionName: sessionName)
        let targetContribution = sessionTargets.reduce(0.0) { partial, muscle in
            partial + (estimate.hardSetsByMuscle[muscle] ?? 0)
        }

        // Reject accessories that neither address meaningful weekly deficits nor reinforce session identity.
        return usefulTowardDeficit < 0.8 && targetContribution < 1.0
    }

    private func bodybuildingSessionPriorityMuscles(sessionName: String) -> Set<ProgramVolumeMuscle> {
        let lower = sessionName.lowercased()

        if lower.contains("chest") && lower.contains("tricep") {
            return [.chest, .triceps, .shoulders]
        }
        if lower.contains("back") && lower.contains("biceps") {
            return [.upperBackLats, .biceps, .hamstrings]
        }
        if lower.contains("shoulder") {
            return [.shoulders, .triceps, .upperBackLats]
        }
        if lower.contains("quad") {
            return [.quads, .glutes, .calves]
        }
        if lower.contains("hamstring") || lower.contains("glute") {
            return [.hamstrings, .glutes, .calves]
        }
        if lower.contains("leg") {
            return [.quads, .hamstrings, .glutes, .calves]
        }
        if lower.contains("arm") {
            return [.biceps, .triceps, .shoulders]
        }
        if lower.contains("chest") {
            return [.chest, .shoulders, .triceps]
        }
        if lower.contains("back") {
            return [.upperBackLats, .biceps, .hamstrings]
        }
        return [.chest, .upperBackLats, .quads, .hamstrings, .shoulders]
    }

    private func estimateLoad(
        for exercise: TemplateExercise,
        focusProfile: ProgramFocusProgrammingProfile,
        level: ProgramLevel,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ExerciseLoadEstimate {
        if exercise.role == .cardio {
            let mins = cardioDurationMinutes(progressionIndex: schedule.progressionIndex, isDeload: schedule.isDeload)
            return ExerciseLoadEstimate(
                hardSetsByMuscle: emptyMuscleTotals(),
                fatigueScore: Double(mins) * 0.08,
                highFatigueScore: 0
            )
        }

        let strategy = resolveProgressionStrategy(focusProfile: focusProfile, level: level)
        let params = computeParams(
            exercise: exercise,
            strategy: strategy,
            focusProfile: focusProfile,
            schedule: schedule,
            sessionIdx: sessionIdx,
            sessionsPerWeek: sessionsPerWeek
        )
        let effectiveWorkingSets = schedule.isDeload ? max(2, params.sets / 2) : params.sets
        let blocks = buildWorkingSetBlocks(
            exercise: exercise,
            isSessionOpener: exercise.role == .primary,
            focusProfile: focusProfile,
            level: level,
            schedule: schedule,
            params: params,
            totalWorkingSets: effectiveWorkingSets
        )
        let totalWorkingSets = blocks.reduce(0) { $0 + $1.sets }
        guard totalWorkingSets > 0 else {
            return ExerciseLoadEstimate(
                hardSetsByMuscle: emptyMuscleTotals(),
                fatigueScore: 0,
                highFatigueScore: 0
            )
        }

        let metadata = ProgramExerciseMetadataService.metadata(for: exercise.exerciseName)
        var hardSetsByMuscle = emptyMuscleTotals()
        for (muscle, weight) in metadata.muscleContributions {
            hardSetsByMuscle[muscle, default: 0] += Double(totalWorkingSets) * weight
        }

        let maxPct = blocks.compactMap(\.percentage1RM).max()
        let minReps = blocks.map(\.reps).min() ?? params.reps
        let hasTopSet = blocks.contains { $0.style == .topSet }
        let fatigueTier = ProgramExerciseMetadataService.fatigueTier(
            for: exercise.exerciseName,
            role: exercise.role,
            maxPercentage1RM: maxPct,
            minReps: minReps,
            hasTopSet: hasTopSet
        )

        var intensityMultiplier = 1.0
        if let maxPct {
            switch maxPct {
            case let p where p >= 0.90: intensityMultiplier += 0.25
            case let p where p >= 0.82: intensityMultiplier += 0.15
            case let p where p <= 0.65: intensityMultiplier -= 0.05
            default: break
            }
        } else if let rpe = params.rpe {
            if rpe >= 8.5 { intensityMultiplier += 0.15 }
            if rpe <= 6.5 { intensityMultiplier -= 0.05 }
        } else if let rir = params.rir {
            if rir <= 1.0 { intensityMultiplier += 0.15 }
            else if rir >= 3.0 { intensityMultiplier -= 0.08 }
        }
        if schedule.isDeload {
            intensityMultiplier *= 0.78
        }

        let setCount = Double(totalWorkingSets)
        let fatigueScore = setCount * fatigueTier.baseScorePerSet * intensityMultiplier
        let highFatigueScore = setCount * fatigueTier.highFatigueWeight * intensityMultiplier

        return ExerciseLoadEstimate(
            hardSetsByMuscle: hardSetsByMuscle,
            fatigueScore: fatigueScore,
            highFatigueScore: highFatigueScore
        )
    }

    private func estimateLoad(for exercise: ProgramSessionExercise) -> ExerciseLoadEstimate {
        if exercise.targetSets == nil {
            let mins = Double(exercise.targetReps ?? 0)
            return ExerciseLoadEstimate(
                hardSetsByMuscle: emptyMuscleTotals(),
                fatigueScore: mins * 0.08,
                highFatigueScore: 0
            )
        }

        let setCount = max(0, exercise.targetSets ?? 0)
        guard setCount > 0 else {
            return ExerciseLoadEstimate(
                hardSetsByMuscle: emptyMuscleTotals(),
                fatigueScore: 0,
                highFatigueScore: 0
            )
        }

        let metadata = ProgramExerciseMetadataService.metadata(for: exercise.exerciseName)
        var hardSetsByMuscle = emptyMuscleTotals()
        for (muscle, weight) in metadata.muscleContributions {
            hardSetsByMuscle[muscle, default: 0] += Double(setCount) * weight
        }

        let fatigueTier = ProgramExerciseMetadataService.fatigueTier(
            for: exercise.exerciseName,
            role: .accessory,
            maxPercentage1RM: exercise.targetPercentage1RM,
            minReps: exercise.targetReps ?? 8,
            hasTopSet: exercise.workingSetStyle == .topSet
        )

        var intensityMultiplier = 1.0
        if let pct = exercise.targetPercentage1RM {
            if pct >= 0.90 { intensityMultiplier += 0.25 }
            else if pct >= 0.82 { intensityMultiplier += 0.15 }
            else if pct <= 0.65 { intensityMultiplier -= 0.05 }
        } else if let rpe = exercise.targetRPE {
            if rpe >= 8.5 { intensityMultiplier += 0.15 }
            else if rpe <= 6.5 { intensityMultiplier -= 0.05 }
        } else if let rir = exercise.targetRIR {
            if rir <= 1.0 { intensityMultiplier += 0.15 }
            else if rir >= 3.0 { intensityMultiplier -= 0.08 }
        }

        let sets = Double(setCount)
        return ExerciseLoadEstimate(
            hardSetsByMuscle: hardSetsByMuscle,
            fatigueScore: sets * fatigueTier.baseScorePerSet * intensityMultiplier,
            highFatigueScore: sets * fatigueTier.highFatigueWeight * intensityMultiplier
        )
    }

    private func emptyMuscleTotals() -> [ProgramVolumeMuscle: Double] {
        Dictionary(uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map { ($0, 0.0) })
    }

    private func addMuscleSets(
        _ source: [ProgramVolumeMuscle: Double],
        into target: inout [ProgramVolumeMuscle: Double]
    ) {
        for muscle in ProgramVolumeMuscle.allCases {
            target[muscle, default: 0] += source[muscle] ?? 0
        }
    }

    private func isDeadliftHeavySession(_ sessionDef: SessionDefinition) -> Bool {
        sessionDef.primaryExercises.contains { exercise in
            let lower = exercise.exerciseName.lowercased()
            return lower.contains(CanonicalLift.deadlift.rawValue) || lower.contains("block pull")
        }
    }

    private func randomJitter(using rng: inout SeededRNG, magnitude: Double) -> Double {
        let unit = Double(rng.next() % 10_000) / 10_000.0
        return (unit - 0.5) * magnitude
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: - Helpers

    private func resolvedSessionDefs(from template: FocusTemplate, frequency: Int) -> [SessionDefinition] {
        if let defs = template.sessionDefinitions[frequency] { return defs }
        // Snap to nearest supported frequency.
        let supported = template.sessionDefinitions.keys.sorted()
        let closest = supported.min(by: { abs($0 - frequency) < abs($1 - frequency) }) ?? frequency
        return template.sessionDefinitions[closest] ?? []
    }

    /// Duration in minutes for cardio exercises.
    /// Base is 20 min; adds 3 min per completed working week; resets to 20 on deload.
    private func cardioDurationMinutes(progressionIndex: Int, isDeload: Bool) -> Int {
        isDeload ? 20 : 20 + progressionIndex * 3
    }

    private func periodizationDescription(for strategy: ProgressionStrategy) -> String {
        switch strategy.family {
        case .strengthSkill:
            switch strategy.level {
            case .beginner:
                return "Maximal-strength linear progression around each lift's anchor %1RM with scheduled deloads every 4th week."
            case .intermediate:
                return "Strength-specific DUP with heavy/moderate/light exposures that progress from each lift's anchor %1RM and deload every 4th week."
            case .advanced:
                return "Strength block periodization with hypertrophy, strength, and peaking phases plus explicit deload transitions."
            }
        case .mixedStrengthHypertrophy:
            switch strategy.level {
            case .beginner:
                return "Mixed strength and hypertrophy linear progression, preserving anchor-relative loading while building base volume."
            case .intermediate:
                return "Mixed DUP progression balancing heavy strength exposures with moderate hypertrophy sessions and 4-week deload rhythm."
            case .advanced:
                return "Mixed advanced blocks with extended hypertrophy accumulation and dedicated strength realization phases."
            }
        case .hypertrophyVolume:
            return "Hypertrophy-focused progression emphasizing higher-rep volume progression with periodic step-back deload weeks."
        case .balancedTraining:
            return "Balanced training progression combining moderate DUP-style stress distribution with recovery-preserving deload spacing."
        case .enduranceConditioning:
            return "Endurance-first progression emphasizing aerobic workload growth with frequent step-back recovery weeks."
        }
    }

    private func clampedPercentage(
        anchor: Double,
        candidate: Double,
        minOffset: Double,
        maxOffset: Double
    ) -> Double {
        let lower = max(0.50, anchor + minOffset)
        let upper = min(0.97, anchor + maxOffset)
        return min(upper, max(lower, candidate))
    }

    private func clampedRPE(_ value: Double) -> Double {
        min(10.0, max(5.5, value))
    }
}

// MARK: - Seeded Random Number Generator

/// Deterministic RNG used to keep accessory selection reproducible within a generation call.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed &+ 1)) | 1
    }

    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}
