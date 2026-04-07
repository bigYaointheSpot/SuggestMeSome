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
            exercise: templateEx,
            level: level, schedule: schedule,
            sessionIdx: sessionIdx, sessionsPerWeek: sessionsPerWeek
        )

        // Warmup sets: 3 sets at 40 / 55 / 70% of the working weight.
        // Applied to primary/variation exercises with a %1RM target; skipped during deloads.
        if isPrimary, let workingPct = params.percentage1RM, !schedule.isDeload {
            for (i, multiplier) in [0.40, 0.55, 0.70].enumerated() {
                let warmupPct = workingPct * multiplier
                let wt = computePrescribedWeight(
                    exercise: templateEx,
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
            exercise: templateEx,
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
        exercise: TemplateExercise,
        percentage1RM: Double?,
        oneRepMaxes: [String: (weight: Double, unit: String)]
    ) -> (weight: Double, unit: String)? {
        guard let pct = percentage1RM else { return nil }

        let orm: (weight: Double, unit: String)?
        if let direct = oneRepMaxes[exercise.exerciseName] {
            orm = direct
        } else if let sourceLift = exercise.loadSourceLift, let sourceORM = oneRepMaxes[sourceLift] {
            let multiplier = exercise.loadMultiplier ?? 1.0
            orm = (weight: sourceORM.weight * multiplier, unit: sourceORM.unit)
        } else {
            orm = nil
        }

        guard let orm else { return nil }
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
