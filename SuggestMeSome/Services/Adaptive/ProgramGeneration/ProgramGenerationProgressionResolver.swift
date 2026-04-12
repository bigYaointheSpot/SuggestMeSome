import Foundation

struct ProgramGenerationProgressionResolver {

    func resolveStrategy(
        focusProfile: ProgramFocusProgrammingProfile,
        level: ProgramLevel
    ) -> ProgramGenerationProgressionStrategy {
        ProgramGenerationProgressionStrategy(
            family: focusProfile.progressionStrategyFamily,
            level: level
        )
    }

    func progressionModel(for strategy: ProgramGenerationProgressionStrategy) -> ProgramProgressionModel {
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

    func weekProgressionPhase(
        strategy: ProgramGenerationProgressionStrategy,
        schedule: ProgramGenerationWeekSchedule
    ) -> ProgramProgressionPhase {
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

    func progressionPhase(
        strategy: ProgramGenerationProgressionStrategy,
        schedule: ProgramGenerationWeekSchedule,
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

    func computeParams(
        exercise: TemplateExercise,
        strategy: ProgramGenerationProgressionStrategy,
        focusProfile: ProgramFocusProgrammingProfile,
        schedule: ProgramGenerationWeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ProgramGenerationExerciseParams {
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

    func buildWorkingSetBlocks(
        exercise: TemplateExercise,
        isSessionOpener: Bool,
        focusProfile: ProgramFocusProgrammingProfile,
        level: ProgramLevel,
        schedule: ProgramGenerationWeekSchedule,
        params: ProgramGenerationExerciseParams,
        totalWorkingSets: Int
    ) -> [ProgramGenerationWorkingSetBlock] {
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
            ProgramGenerationWorkingSetBlock(
                style: .topSet,
                sets: topSets,
                reps: topReps,
                percentage1RM: topPct,
                rpe: topRPE,
                rir: nil,
                backoffDrop: nil
            ),
            ProgramGenerationWorkingSetBlock(
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

    func resolveTargetEffortType(
        percentage1RM: Double?,
        targetRPE: Double?,
        targetRIR: Double?
    ) -> ProgramTargetEffortType {
        if percentage1RM != nil { return .percentage1RM }
        if targetRIR != nil { return .rir }
        if targetRPE != nil { return .rpe }
        return .none
    }

    func periodizationDescription(for strategy: ProgramGenerationProgressionStrategy) -> String {
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
            return "Endurance-first progression with easy/threshold/interval/long session archetypes, separated progression tracks, and frequent step-back recovery weeks."
        }
    }

    // MARK: Phase Rules

    private func strengthSkillWeekPhase(
        level: ProgramLevel,
        schedule: ProgramGenerationWeekSchedule
    ) -> ProgramProgressionPhase {
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
        schedule: ProgramGenerationWeekSchedule,
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

    private func mixedWeekPhase(
        level: ProgramLevel,
        schedule: ProgramGenerationWeekSchedule
    ) -> ProgramProgressionPhase {
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
        schedule: ProgramGenerationWeekSchedule,
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
        case .heavy, .moderate: return .dupModerate
        case .light: return .dupLight
        }
    }

    // MARK: Parameter Rules

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
        schedule: ProgramGenerationWeekSchedule
    ) -> ProgramGenerationExerciseParams {
        if schedule.isDeload {
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(
                    anchor: anchor,
                    candidate: anchor - BeginnerTuning.deloadPercentageDrop,
                    minOffset: BeginnerTuning.maxNegativeOffset,
                    maxOffset: BeginnerTuning.maxPositiveOffset
                )
                return ProgramGenerationExerciseParams(
                    sets: exercise.defaultSets,
                    reps: exercise.defaultReps,
                    percentage1RM: pct,
                    rpe: nil,
                    rir: nil
                )
            }
            return ProgramGenerationExerciseParams(
                sets: exercise.defaultSets,
                reps: exercise.defaultReps,
                percentage1RM: nil,
                rpe: BeginnerTuning.deloadRPE,
                rir: nil
            )
        }

        if let anchor = exercise.percentage1RM {
            let pct = clampedPercentage(
                anchor: anchor,
                candidate: anchor + BeginnerTuning.startingOffset + Double(schedule.progressionIndex) * BeginnerTuning.weeklyOffsetStep,
                minOffset: BeginnerTuning.maxNegativeOffset,
                maxOffset: BeginnerTuning.maxPositiveOffset
            )
            return ProgramGenerationExerciseParams(
                sets: exercise.defaultSets,
                reps: exercise.defaultReps,
                percentage1RM: pct,
                rpe: nil,
                rir: nil
            )
        }

        return ProgramGenerationExerciseParams(
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
        schedule: ProgramGenerationWeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ProgramGenerationExerciseParams {
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
        schedule: ProgramGenerationWeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ProgramGenerationExerciseParams {
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
        schedule: ProgramGenerationWeekSchedule
    ) -> ProgramGenerationExerciseParams {
        let cls = bodybuildingExerciseClass(for: exercise)
        let progressionStep = Double(schedule.progressionIndex)

        if schedule.isDeload {
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(anchor: anchor, candidate: anchor - 0.10, minOffset: -0.14, maxOffset: 0.08)
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
                return ProgramGenerationExerciseParams(
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
            return ProgramGenerationExerciseParams(
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
                return ProgramGenerationExerciseParams(sets: sets, reps: reps, percentage1RM: pct, rpe: nil, rir: nil)
            }
            return ProgramGenerationExerciseParams(
                sets: sets,
                reps: reps,
                percentage1RM: nil,
                rpe: clampedRPE((exercise.targetRPE ?? 8.0) - 0.2),
                rir: 2.0
            )

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
                return ProgramGenerationExerciseParams(sets: sets, reps: reps, percentage1RM: pct, rpe: nil, rir: nil)
            }
            let rirByLevel: [ProgramLevel: Double] = [.beginner: 2.5, .intermediate: 2.0, .advanced: 1.5]
            return ProgramGenerationExerciseParams(
                sets: sets,
                reps: reps,
                percentage1RM: nil,
                rpe: clampedRPE(exercise.targetRPE ?? 7.5),
                rir: rirByLevel[level] ?? 2.0
            )

        case .pumpIsolation:
            let repsByLevel: [ProgramLevel: Int] = [.beginner: 14, .intermediate: 13, .advanced: 12]
            let reps = max(10, repsByLevel[level] ?? 13)
            let sets = max(3, min(4, exercise.defaultSets))
            let rirByLevel: [ProgramLevel: Double] = [.beginner: 3.0, .intermediate: 2.0, .advanced: 1.0]
            return ProgramGenerationExerciseParams(
                sets: sets,
                reps: reps,
                percentage1RM: nil,
                rpe: clampedRPE((exercise.targetRPE ?? 7.0) - 0.3 + (level == .advanced ? 0.2 : 0.0)),
                rir: rirByLevel[level] ?? 2.0
            )
        }
    }

    private func hypertrophyParams(
        exercise: TemplateExercise,
        focus: ProgramFocus,
        level: ProgramLevel,
        schedule: ProgramGenerationWeekSchedule
    ) -> ProgramGenerationExerciseParams {
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
                return ProgramGenerationExerciseParams(
                    sets: max(3, exercise.defaultSets),
                    reps: targetReps,
                    percentage1RM: pct,
                    rpe: nil,
                    rir: nil
                )
            }
            return ProgramGenerationExerciseParams(
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
            return ProgramGenerationExerciseParams(
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
        return ProgramGenerationExerciseParams(
            sets: max(3, exercise.defaultSets),
            reps: targetReps,
            percentage1RM: nil,
            rpe: clampedRPE(rpeAnchor + (rpeTuningByLevel[level] ?? 0.0)),
            rir: nil
        )
    }

    private func balancedTrainingParams(
        exercise: TemplateExercise,
        level: ProgramLevel,
        schedule: ProgramGenerationWeekSchedule,
        sessionIdx: Int,
        sessionsPerWeek: Int
    ) -> ProgramGenerationExerciseParams {
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
        schedule: ProgramGenerationWeekSchedule
    ) -> ProgramGenerationExerciseParams {
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
                return ProgramGenerationExerciseParams(
                    sets: sets,
                    reps: reps,
                    percentage1RM: pct,
                    rpe: nil,
                    rir: nil
                )
            }
            return ProgramGenerationExerciseParams(
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
            return ProgramGenerationExerciseParams(
                sets: sets,
                reps: reps,
                percentage1RM: pct,
                rpe: nil,
                rir: nil
            )
        }

        let rpeAnchor = exercise.targetRPE ?? 7.0
        return ProgramGenerationExerciseParams(
            sets: sets,
            reps: reps,
            percentage1RM: nil,
            rpe: clampedRPE(rpeAnchor - 0.3),
            rir: nil
        )
    }

    private enum DUPTier {
        case heavy
        case moderate
        case light

        var percentageAnchorOffset: Double {
            switch self {
            case .heavy: return 0.03
            case .moderate: return 0.00
            case .light: return -0.06
            }
        }

        var defaultSets: Int {
            switch self {
            case .heavy, .moderate: return 4
            case .light: return 3
            }
        }

        var repCount: Int {
            switch self {
            case .heavy: return 4
            case .moderate: return 7
            case .light: return 10
            }
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
        schedule: ProgramGenerationWeekSchedule,
        tier: DUPTier
    ) -> ProgramGenerationExerciseParams {
        if schedule.isDeload {
            let baseSets = DUPTier.light.defaultSets
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(
                    anchor: anchor,
                    candidate: anchor - IntermediateTuning.deloadPercentageDrop,
                    minOffset: IntermediateTuning.maxNegativeOffset,
                    maxOffset: IntermediateTuning.maxPositiveOffset
                )
                return ProgramGenerationExerciseParams(
                    sets: baseSets,
                    reps: DUPTier.light.repCount,
                    percentage1RM: pct,
                    rpe: nil,
                    rir: nil
                )
            }
            return ProgramGenerationExerciseParams(
                sets: baseSets,
                reps: DUPTier.light.repCount,
                percentage1RM: nil,
                rpe: IntermediateTuning.deloadRPE,
                rir: nil
            )
        }

        if let anchor = exercise.percentage1RM {
            let pct = clampedPercentage(
                anchor: anchor,
                candidate: anchor + tier.percentageAnchorOffset + Double(schedule.progressionIndex) * IntermediateTuning.weeklyPercentageOffsetStep,
                minOffset: IntermediateTuning.maxNegativeOffset,
                maxOffset: IntermediateTuning.maxPositiveOffset
            )
            return ProgramGenerationExerciseParams(
                sets: tier.defaultSets,
                reps: tier.repCount,
                percentage1RM: pct,
                rpe: nil,
                rir: nil
            )
        }

        let rpeAnchor = exercise.targetRPE ?? 7.0
        return ProgramGenerationExerciseParams(
            sets: tier.defaultSets,
            reps: tier.repCount,
            percentage1RM: nil,
            rpe: clampedRPE(rpeAnchor + tier.rpeAnchorOffset),
            rir: nil
        )
    }

    private enum AdvancedTuning {
        static let maxPositiveOffset = 0.12
        static let maxNegativeOffset = -0.12
        static let deloadPercentageDrop = 0.10
        static let deloadRPE = 6.0
    }

    private func advancedParams(
        exercise: TemplateExercise,
        schedule: ProgramGenerationWeekSchedule
    ) -> ProgramGenerationExerciseParams {
        let phase = schedule.advancedPhase ?? .hypertrophy

        if schedule.isDeload {
            if let anchor = exercise.percentage1RM {
                let pct = clampedPercentage(
                    anchor: anchor,
                    candidate: anchor - AdvancedTuning.deloadPercentageDrop,
                    minOffset: AdvancedTuning.maxNegativeOffset,
                    maxOffset: AdvancedTuning.maxPositiveOffset
                )
                return ProgramGenerationExerciseParams(
                    sets: phase.defaultSets,
                    reps: phase.midReps,
                    percentage1RM: pct,
                    rpe: nil,
                    rir: nil
                )
            }
            return ProgramGenerationExerciseParams(
                sets: phase.defaultSets,
                reps: phase.midReps,
                percentage1RM: nil,
                rpe: AdvancedTuning.deloadRPE,
                rir: nil
            )
        }

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
            return ProgramGenerationExerciseParams(
                sets: phase.defaultSets,
                reps: phase.midReps,
                percentage1RM: pct,
                rpe: nil,
                rir: nil
            )
        }

        let rpeAnchor = exercise.targetRPE ?? 7.0
        return ProgramGenerationExerciseParams(
            sets: phase.defaultSets,
            reps: phase.midReps,
            percentage1RM: nil,
            rpe: clampedRPE(rpeAnchor + phase.rpeAnchorOffset),
            rir: nil
        )
    }

    // MARK: Top/Backoff Rules

    private func shouldUseTopBackoff(
        for exercise: TemplateExercise,
        isSessionOpener: Bool,
        focusProfile: ProgramFocusProgrammingProfile,
        level: ProgramLevel,
        params: ProgramGenerationExerciseParams
    ) -> Bool {
        if focusProfile.topSetBackoffPolicy == .disabled { return false }
        if level == .beginner { return false }
        if focusProfile.topSetBackoffPolicy == .compoundOpener {
            if !isSessionOpener { return false }
            if exercise.role != .primary && exercise.role != .variation { return false }
            if params.reps < 5 || params.reps > 7 { return false }
        } else if params.reps >= 8 {
            return false
        }
        if exercise.percentage1RM == nil { return false }
        return exercise.topSetPrescription != nil && exercise.backoffPrescription != nil
    }

    private func straightSetBlock(
        from params: ProgramGenerationExerciseParams,
        sets: Int
    ) -> ProgramGenerationWorkingSetBlock {
        ProgramGenerationWorkingSetBlock(
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
        if baseReps <= 2 { return baseReps }
        if baseReps == 3 { return 2 }
        return baseReps
    }

    private func resolvedBackoffReps(baseReps: Int, repDelta: Int) -> Int {
        if baseReps <= 3 {
            return min(8, max(4, baseReps + max(2, repDelta + 1)))
        }
        return min(15, max(1, baseReps + repDelta))
    }

    // MARK: Utility

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
