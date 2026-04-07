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

// MARK: - Service

struct ProgramGenerationService {

    // MARK: - Public API

    /// Generates a new program with a random accessory shuffle.
    func generateProgram(input: ProgramGenerationInput, context: ModelContext) -> TrainingProgram {
        buildProgram(input: input, context: context, shuffleSeed: Int.random(in: 1..<Int.max))
    }

    /// Generates a program using different random accessory selections than a previous call.
    func regenerateProgram(input: ProgramGenerationInput, context: ModelContext) -> TrainingProgram {
        buildProgram(input: input, context: context, shuffleSeed: Int.random(in: 1..<Int.max))
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

        // Step 5: Create TrainingProgram
        let program = TrainingProgram(
            name: "\(template.displayName) — \(input.level.rawValue.capitalized) \(input.durationWeeks)wk",
            lengthInWeeks: input.durationWeeks,
            sessionsPerWeek: input.sessionsPerWeek,
            source: .aiGenerated,
            descriptionText: periodizationDescription(for: input.level)
        )
        context.insert(program)

        // Steps 3–4: Build periodized week schedules
        let schedules = buildWeekSchedules(level: input.level, durationWeeks: input.durationWeeks)

        // Step 6: Build accessory rotation pools (per session definition)
        let accessoryRotations = buildAccessoryRotations(
            sessionDefs: sessionDefs,
            totalWeeks: input.durationWeeks,
            focus: input.focus,
            seed: shuffleSeed
        )

        // Step 4: Build week-by-week structure
        for schedule in schedules {
            let weekTemplate = ProgramWeekTemplate(weekNumber: schedule.weekNumber)
            context.insert(weekTemplate)
            weekTemplate.program = program

            for (sessionIdx, sessionDef) in sessionDefs.enumerated() {
                let sessionTemplate = ProgramSessionTemplate(
                    sessionNumber: sessionIdx + 1,
                    sessionName: sessionDef.sessionName
                )
                context.insert(sessionTemplate)
                sessionTemplate.week = weekTemplate

                let accessories = accessoryRotations[sessionIdx][schedule.weekNumber - 1]
                var orderIdx = 0

                for primary in sessionDef.primaryExercises {
                    orderIdx = populateExercise(
                        primary, isPrimary: true,
                        schedule: schedule, sessionIdx: sessionIdx,
                        sessionsPerWeek: input.sessionsPerWeek, level: input.level,
                        oneRepMaxes: input.oneRepMaxes,
                        session: sessionTemplate, orderIdx: orderIdx, context: context
                    )
                }

                for accessory in accessories {
                    orderIdx = populateExercise(
                        accessory, isPrimary: false,
                        schedule: schedule, sessionIdx: sessionIdx,
                        sessionsPerWeek: input.sessionsPerWeek, level: input.level,
                        oneRepMaxes: input.oneRepMaxes,
                        session: sessionTemplate, orderIdx: orderIdx, context: context
                    )
                }
            }
        }

        return program
    }

    // MARK: - Exercise Population

    @discardableResult
    private func populateExercise(
        _ templateEx: TemplateExercise,
        isPrimary: Bool,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int,
        level: ProgramLevel,
        oneRepMaxes: [String: (weight: Double, unit: String)],
        session: ProgramSessionTemplate,
        orderIdx: Int,
        context: ModelContext
    ) -> Int {
        var idx = orderIdx

        // Cardio exercises: encode target duration as targetReps (minutes); no sets.
        if templateEx.role == .cardio {
            let mins = cardioDurationMinutes(progressionIndex: schedule.progressionIndex, isDeload: schedule.isDeload)
            let ex = ProgramSessionExercise(
                exerciseName: templateEx.exerciseName,
                orderIndex: idx,
                targetSets: nil,
                targetReps: mins
            )
            context.insert(ex)
            ex.session = session
            return idx + 1
        }

        let params = computeParams(
            exercise: templateEx, isPrimary: isPrimary,
            level: level, schedule: schedule,
            sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek
        )

        // Warmup sets: 3 sets at 40 / 55 / 70% of the working weight.
        // Applied to primary/variation exercises with a %1RM target; skipped during deloads.
        if isPrimary, let workingPct = params.percentage1RM, !schedule.isDeload {
            for (i, multiplier) in [0.40, 0.55, 0.70].enumerated() {
                let warmupPct = workingPct * multiplier
                let wt = computePrescribedWeight(
                    exerciseName: templateEx.exerciseName,
                    percentage1RM: warmupPct,
                    oneRepMaxes: oneRepMaxes
                )
                let warmup = ProgramSessionExercise(
                    exerciseName: templateEx.exerciseName,
                    orderIndex: idx + i,
                    targetSets: 1,
                    targetReps: params.reps,
                    targetPercentage1RM: warmupPct,
                    isWarmup: true,
                    prescribedWeight: wt?.weight,
                    prescribedWeightUnit: wt?.unit
                )
                context.insert(warmup)
                warmup.session = session
            }
            idx += 3
        }

        // Working set(s): halve set count on deload weeks.
        let workingSets = schedule.isDeload ? max(2, params.sets / 2) : params.sets
        let wt = computePrescribedWeight(
            exerciseName: templateEx.exerciseName,
            percentage1RM: params.percentage1RM,
            oneRepMaxes: oneRepMaxes
        )
        let working = ProgramSessionExercise(
            exerciseName: templateEx.exerciseName,
            orderIndex: idx,
            targetSets: workingSets,
            targetReps: params.reps,
            targetPercentage1RM: params.percentage1RM,
            targetRPE: params.rpe,
            prescribedWeight: wt?.weight,
            prescribedWeightUnit: wt?.unit
        )
        context.insert(working)
        working.session = session
        return idx + 1
    }

    private func computePrescribedWeight(
        exerciseName: String,
        percentage1RM: Double?,
        oneRepMaxes: [String: (weight: Double, unit: String)]
    ) -> (weight: Double, unit: String)? {
        guard let pct = percentage1RM, let orm = oneRepMaxes[exerciseName] else { return nil }
        let raw = pct * orm.weight
        let rounded: Double
        if orm.unit == "lbs" {
            rounded = max(5.0, (raw / 5.0).rounded() * 5.0)
        } else {
            rounded = max(2.5, (raw / 2.5).rounded() * 2.5)
        }
        return (weight: rounded, unit: orm.unit)
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
        isPrimary: Bool,
        level: ProgramLevel,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ExerciseParams {
        switch level {
        case .beginner:
            return beginnerParams(exercise: exercise, isPrimary: isPrimary, schedule: schedule)
        case .intermediate:
            return intermediateParams(
                exercise: exercise, isPrimary: isPrimary,
                schedule: schedule, sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek
            )
        case .advanced:
            return advancedParams(exercise: exercise, isPrimary: isPrimary, schedule: schedule)
        }
    }

    // MARK: Beginner — Linear Progression

    private func beginnerParams(
        exercise: TemplateExercise,
        isPrimary: Bool,
        schedule: WeekSchedule
    ) -> ExerciseParams {
        let isCompound = isPrimary && (exercise.role == .primary || exercise.role == .variation)

        if isCompound && exercise.percentage1RM != nil {
            // Start at 70% 1RM, increase 2.5% per working week, cap at 90%.
            // Deload weeks use same progressionIndex as the preceding working week → same weight.
            let pct = min(0.90, 0.70 + Double(schedule.progressionIndex) * 0.025)
            return ExerciseParams(
                sets: exercise.defaultSets,
                reps: exercise.defaultReps,
                percentage1RM: pct,
                rpe: nil
            )
        }

        // Accessories and RPE-based primaries: hold RPE steady, no weekly change.
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

        var basePercentage: Double {
            switch self { case .heavy: return 0.82; case .moderate: return 0.75; case .light: return 0.65 }
        }
        var capPercentage: Double {
            switch self { case .heavy: return 0.93; case .moderate: return 0.90; case .light: return 0.85 }
        }
        var defaultSets: Int {
            switch self { case .heavy, .moderate: return 4; case .light: return 3 }
        }
        var repCount: Int {
            // Middle of each rep range (3–5, 6–8, 8–12)
            switch self { case .heavy: return 4; case .moderate: return 7; case .light: return 10 }
        }
        var rpe: Double {
            switch self { case .heavy: return 8.5; case .moderate: return 7.5; case .light: return 6.5 }
        }
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
        isPrimary: Bool,
        schedule: WeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ExerciseParams {
        // Deload: all sessions at light-tier rep count, 60% 1RM (or RPE 6).
        if schedule.isDeload {
            let baseSets = DUPTier.light.defaultSets  // populateExercise will halve to 2
            if isPrimary && exercise.percentage1RM != nil {
                return ExerciseParams(sets: baseSets, reps: DUPTier.light.repCount, percentage1RM: 0.60, rpe: nil)
            }
            return ExerciseParams(sets: baseSets, reps: DUPTier.light.repCount, percentage1RM: nil, rpe: 6.0)
        }

        let tier = dupTier(sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek)
        // Weekly progression: +1.5% per working week, capped per tier.
        let progressedPct = min(tier.capPercentage, tier.basePercentage + Double(schedule.progressionIndex) * 0.015)

        // Primary compounds follow tier %1RM; accessories follow tier RPE.
        if isPrimary && exercise.percentage1RM != nil {
            return ExerciseParams(sets: tier.defaultSets, reps: tier.repCount, percentage1RM: progressedPct, rpe: nil)
        }
        return ExerciseParams(sets: tier.defaultSets, reps: tier.repCount, percentage1RM: nil, rpe: tier.rpe)
    }

    // MARK: Advanced — Block Periodization

    private enum AdvancedPhaseType {
        case hypertrophy, strength, peaking

        var percentageRange: (base: Double, top: Double) {
            switch self {
            case .hypertrophy: return (0.62, 0.72)
            case .strength:    return (0.75, 0.85)
            case .peaking:     return (0.88, 0.95)
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
        var rpe: Double {
            switch self { case .hypertrophy: return 7.0; case .strength: return 8.0; case .peaking: return 9.0 }
        }
        var midReps: Int {
            let r = repRange; return (r.min + r.max + 1) / 2
        }
    }

    private func advancedParams(
        exercise: TemplateExercise,
        isPrimary: Bool,
        schedule: WeekSchedule
    ) -> ExerciseParams {
        let phase = schedule.advancedPhase ?? .hypertrophy

        // Deload: 50% volume (populateExercise halves sets), fixed 65% 1RM for effective recovery.
        if schedule.isDeload {
            if isPrimary && exercise.percentage1RM != nil {
                return ExerciseParams(sets: phase.defaultSets, reps: phase.midReps, percentage1RM: 0.65, rpe: nil)
            }
            return ExerciseParams(sets: phase.defaultSets, reps: phase.midReps, percentage1RM: nil, rpe: 6.0)
        }

        // Linearly interpolate %1RM through the phase's percentage range.
        let (basePct, topPct) = phase.percentageRange
        let t = schedule.phaseLength > 1
            ? Double(schedule.phaseWeekIndex) / Double(schedule.phaseLength - 1)
            : 0.0
        let pct = basePct + (topPct - basePct) * t

        // Primary exercises: %1RM. Accessories: RPE using current phase's rep scheme (per spec).
        if isPrimary && exercise.percentage1RM != nil {
            return ExerciseParams(sets: phase.defaultSets, reps: phase.midReps, percentage1RM: pct, rpe: nil)
        }
        return ExerciseParams(sets: phase.defaultSets, reps: phase.midReps, percentage1RM: nil, rpe: phase.rpe)
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

    // MARK: - Accessory Rotation (Step 6)

    /// Returns a [sessionIdx][weekIdx] → [TemplateExercise] rotation table.
    private func buildAccessoryRotations(
        sessionDefs: [SessionDefinition],
        totalWeeks: Int,
        focus: ProgramFocus,
        seed: Int
    ) -> [[[TemplateExercise]]] {
        // 5×5 uses fixed accessory selections across all weeks.
        let isFixed = focus == .fiveByFive

        return sessionDefs.map { sessionDef in
            let pool = sessionDef.accessoryPool
            let count = min(sessionDef.accessoryCount, pool.count)

            guard !pool.isEmpty, count > 0 else {
                return Array(repeating: [], count: totalWeeks)
            }

            if isFixed {
                let fixed = Array(pool.prefix(count))
                return Array(repeating: fixed, count: totalWeeks)
            }

            // Shuffle the pool deterministically for this generation call.
            var rng = SeededRNG(seed: seed)
            var shuffled = pool
            shuffled.shuffle(using: &rng)

            // Cyclic rotation: each week advances the start index by `count`.
            var weeks = (0..<totalWeeks).map { weekIdx -> [TemplateExercise] in
                let start = (weekIdx * count) % shuffled.count
                return (0..<count).map { shuffled[(start + $0) % shuffled.count] }
            }

            // Bodybuilding and general fitness: guarantee no two adjacent weeks are identical.
            if (focus == .bodybuilding || focus == .generalFitness) && shuffled.count > count {
                weeks = ensureNonAdjacentIdentical(weeks: weeks, pool: shuffled, count: count)
            }

            return weeks
        }
    }

    private func ensureNonAdjacentIdentical(
        weeks: [[TemplateExercise]],
        pool: [TemplateExercise],
        count: Int
    ) -> [[TemplateExercise]] {
        var result = weeks
        for i in 1..<result.count {
            let prev = Set(result[i - 1].map { $0.exerciseName })
            let curr = Set(result[i].map { $0.exerciseName })
            guard prev == curr else { continue }
            // Shift start index by 1 to break the tie.
            let shiftedStart = (i * count + 1) % pool.count
            result[i] = (0..<count).map { pool[(shiftedStart + $0) % pool.count] }
        }
        return result
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
            return "Linear progression: weight starts at 70% 1RM, increases 2.5% per week (capped at 90%), with a deload every 4th week."
        case .intermediate:
            return "Daily undulating periodization (DUP): sessions rotate through heavy (82–93%), moderate (75–90%), and light (65–85%) tiers, progressing ~1.5% per week with deloads every 4th week."
        case .advanced:
            return "Block periodization: hypertrophy (62–72%), strength (75–85%), and peaking (88–95%) phases separated by deload weeks."
        }
    }
}

// MARK: - Seeded Random Number Generator

/// Deterministic RNG used to make accessory shuffles reproducible within a single generation call.
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
