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
        // Step 1: Retrieve template
        let template = FocusTemplateLibrary.template(for: input.focus)

        // Step 2: Select session definitions for chosen frequency
        let sessionDefs = resolvedSessionDefs(from: template, frequency: input.sessionsPerWeek)
        let resolvedFrequency = max(1, sessionDefs.count)
        let progressionModel = progressionModel(for: input.level)
        var usedLiftMapping = false
        var usedTopSetBackoff = false

        // Step 5: Create TrainingProgram
        let program = TrainingProgram(
            name: "\(template.displayName) — \(input.level.rawValue.capitalized) \(input.durationWeeks)wk",
            lengthInWeeks: input.durationWeeks,
            sessionsPerWeek: resolvedFrequency,
            source: .aiGenerated,
            descriptionText: periodizationDescription(for: input.level),
            progressionModel: progressionModel,
            usedLiftMapping: false,
            usedVolumeBalancing: true,
            usedFatigueBalancing: true,
            usedTopSetBackoff: false
        )
        context.insert(program)

        // Steps 3–4: Build periodized week schedules
        let schedules = buildWeekSchedules(level: input.level, durationWeeks: input.durationWeeks)

        // Step 6: Build weekly accessory selections using volume and fatigue accounting.
        let weeklyAccessoryPlan = buildAdaptiveAccessoryPlan(
            sessionDefs: sessionDefs,
            schedules: schedules,
            focus: input.focus,
            level: input.level,
            sessionsPerWeek: resolvedFrequency,
            seed: shuffleSeed
        )

        // Step 4: Build week-by-week structure
        for schedule in schedules {
            let weekTemplate = ProgramWeekTemplate(
                weekNumber: schedule.weekNumber,
                isDeloadWeek: schedule.isDeload,
                progressionPhase: weekProgressionPhase(for: input.level, schedule: schedule)
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
                        focus: input.focus,
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
                        focus: input.focus,
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
        focus: ProgramFocus,
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
            for: level,
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
            level: level, schedule: schedule,
            sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek
        )
        let effectiveWorkingSets = schedule.isDeload ? max(2, params.sets / 2) : params.sets
        let workingBlocks = buildWorkingSetBlocks(
            exercise: templateEx,
            focus: focus,
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
                prescribedWeight: load.prescribedWeight,
                prescribedWeightUnit: load.prescribedWeightUnit,
                workingSetStyle: block.style,
                backoffPercentageDrop: block.backoffDrop,
                targetEffortType: resolveTargetEffortType(
                    percentage1RM: block.percentage1RM,
                    targetRPE: block.rpe,
                    targetRIR: nil
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
        let backoffDrop: Double?
    }

    private func buildWorkingSetBlocks(
        exercise: TemplateExercise,
        focus: ProgramFocus,
        level: ProgramLevel,
        schedule: WeekSchedule,
        params: ExerciseParams,
        totalWorkingSets: Int
    ) -> [WorkingSetBlock] {
        // Straight sets remain the default and all deload weeks use straight work.
        guard !schedule.isDeload else {
            return [straightSetBlock(from: params, sets: totalWorkingSets)]
        }

        guard shouldUseTopBackoff(for: exercise, focus: focus, level: level, params: params),
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
                backoffDrop: nil
            ),
            WorkingSetBlock(
                style: .backoff,
                sets: backoffSets,
                reps: backoffReps,
                percentage1RM: backoffPct,
                rpe: params.rpe,
                backoffDrop: drop
            )
        ]
    }

    private func shouldUseTopBackoff(
        for exercise: TemplateExercise,
        focus: ProgramFocus,
        level: ProgramLevel,
        params: ExerciseParams
    ) -> Bool {
        // Beginner and bodybuilding templates stay predominantly straight-set.
        if level == .beginner || focus == .bodybuilding { return false }
        // High-rep hypertrophy work should stay straight-set.
        if params.reps >= 8 { return false }
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

    private func progressionModel(for level: ProgramLevel) -> ProgramProgressionModel {
        switch level {
        case .beginner: return .linear
        case .intermediate: return .dup
        case .advanced: return .block
        }
    }

    private func weekProgressionPhase(for level: ProgramLevel, schedule: WeekSchedule) -> ProgramProgressionPhase {
        if schedule.isDeload { return .deload }
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

    private func progressionPhase(
        for level: ProgramLevel,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ProgramProgressionPhase {
        if schedule.isDeload { return .deload }

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
    }

    private func computeParams(
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
                schedule: schedule, sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek
            )
        case .advanced:
            return advancedParams(exercise: exercise, schedule: schedule)
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
                    rpe: nil
                )
            }
            return ExerciseParams(
                sets: exercise.defaultSets,
                reps: exercise.defaultReps,
                percentage1RM: nil,
                rpe: BeginnerTuning.deloadRPE
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
                rpe: nil
            )
        }

        // RPE-based work keeps template intent during working weeks.
        return ExerciseParams(
            sets: exercise.defaultSets,
            reps: exercise.defaultReps,
            percentage1RM: nil,
            rpe: exercise.targetRPE ?? 7.0
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

    private func intermediateParams(
        exercise: TemplateExercise,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ExerciseParams {
        let tier = dupTier(sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek)

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
                    rpe: nil
                )
            }
            return ExerciseParams(
                sets: baseSets,
                reps: DUPTier.light.repCount,
                percentage1RM: nil,
                rpe: IntermediateTuning.deloadRPE
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
                rpe: nil
            )
        }

        let rpeAnchor = exercise.targetRPE ?? 7.0
        return ExerciseParams(
            sets: tier.defaultSets,
            reps: tier.repCount,
            percentage1RM: nil,
            rpe: clampedRPE(rpeAnchor + tier.rpeAnchorOffset)
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
                    rpe: nil
                )
            }
            return ExerciseParams(
                sets: phase.defaultSets,
                reps: phase.midReps,
                percentage1RM: nil,
                rpe: AdvancedTuning.deloadRPE
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
                rpe: nil
            )
        }

        let rpeAnchor = exercise.targetRPE ?? 7.0
        return ExerciseParams(
            sets: phase.defaultSets,
            reps: phase.midReps,
            percentage1RM: nil,
            rpe: clampedRPE(rpeAnchor + phase.rpeAnchorOffset)
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

    private func buildWeekSchedules(level: ProgramLevel, durationWeeks: Int) -> [WeekSchedule] {
        switch level {
        case .beginner, .intermediate:
            return buildLinearWeekSchedules(durationWeeks: durationWeeks)
        case .advanced:
            return buildAdvancedWeekSchedules(durationWeeks: durationWeeks)
        }
    }

    /// Beginner / Intermediate: deload every 4th week, linear progression index.
    private func buildLinearWeekSchedules(durationWeeks: Int) -> [WeekSchedule] {
        var result: [WeekSchedule] = []
        var workingIdx = 0
        var lastWorkingIdx = 0

        for week in 1...durationWeeks {
            let isDeload = week % 4 == 0
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
        level: ProgramLevel,
        sessionsPerWeek: Int,
        seed: Int
    ) -> [Int: [[TemplateExercise]]] {
        let volumeTargets = ProgramExerciseMetadataService.weeklyVolumeTargets(focus: focus, level: level)
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

            // Baseline from primaries/variations establishes the week's starting deficits and fatigue.
            for (sessionIdx, sessionDef) in sessionDefs.enumerated() {
                for primary in sessionDef.primaryExercises {
                    let estimate = estimateLoad(
                        for: primary,
                        focus: focus,
                        level: level,
                        schedule: schedule,
                        sessionIdx: sessionIdx,
                        sessionsPerWeek: sessionsPerWeek
                    )
                    addMuscleSets(estimate.hardSetsByMuscle, into: &weeklyMuscleSets)
                    sessionFatigue[sessionIdx] += estimate.fatigueScore
                    sessionHighFatigue[sessionIdx] += estimate.highFatigueScore
                    weeklyFatigue += estimate.fatigueScore
                }
            }

            // Accessory picks are selected to fill under-target muscles first, then maintain variability.
            for (sessionIdx, sessionDef) in sessionDefs.enumerated() {
                let selectionCount = min(sessionDef.accessoryCount, sessionDef.accessoryPool.count)
                guard selectionCount > 0 else { continue }

                let isDeadliftHeavy = isDeadliftHeavySession(sessionDef)
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
                            focus: focus,
                            level: level,
                            schedule: schedule,
                            sessionIdx: sessionIdx,
                            sessionsPerWeek: sessionsPerWeek
                        )

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
                            currentWeekNumber: schedule.weekNumber,
                            lastUsedWeek: lastUsed,
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
        currentWeekNumber: Int,
        lastUsedWeek: Int?,
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

        score += randomJitter(using: &rng, magnitude: 0.16)
        return score
    }

    private func estimateLoad(
        for exercise: TemplateExercise,
        focus: ProgramFocus,
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

        let params = computeParams(
            exercise: exercise,
            level: level,
            schedule: schedule,
            sessionIdx: sessionIdx,
            sessionsPerWeek: sessionsPerWeek
        )
        let effectiveWorkingSets = schedule.isDeload ? max(2, params.sets / 2) : params.sets
        let blocks = buildWorkingSetBlocks(
            exercise: exercise,
            focus: focus,
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

    private func periodizationDescription(for level: ProgramLevel) -> String {
        switch level {
        case .beginner:
            return "Linear progression around each exercise's template anchor %1RM, with small weekly increases and a deload every 4th week."
        case .intermediate:
            return "Daily undulating periodization (DUP): heavy/moderate/light sessions adjust each exercise relative to its template anchor, with weekly progression and deloads every 4th week."
        case .advanced:
            return "Block periodization: hypertrophy, strength, and peaking phases apply anchor-relative intensity shifts, with explicit deload weeks between blocks."
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
