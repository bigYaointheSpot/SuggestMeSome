import Foundation

struct ProgramGenerationWeekScheduleBuilder {

    func buildWeekSchedules(
        strategy: ProgramGenerationProgressionStrategy,
        durationWeeks: Int,
        focusProfile: ProgramFocusProgrammingProfile,
        trainingState: TrainingStateSnapshot? = nil,
        doseTargetProfile: DoseTargetProfile? = nil
    ) -> [ProgramGenerationWeekSchedule] {
        let adaptiveDeloadInterval = doseTargetProfile?.deloadIntervalOverride
        let schedules: [ProgramGenerationWeekSchedule]
        switch strategy.family {
        case .strengthSkill:
            switch strategy.level {
            case .advanced:
                schedules = buildAdvancedWeekSchedules(durationWeeks: durationWeeks)
            case .beginner, .intermediate:
                schedules = buildLinearWeekSchedules(
                    durationWeeks: durationWeeks,
                    deloadEvery: adaptiveDeloadInterval ?? 4
                )
            }
        case .mixedStrengthHypertrophy:
            switch strategy.level {
            case .advanced:
                schedules = buildMixedAdvancedWeekSchedules(durationWeeks: durationWeeks)
            case .beginner, .intermediate:
                schedules = buildLinearWeekSchedules(
                    durationWeeks: durationWeeks,
                    deloadEvery: adaptiveDeloadInterval ?? 4
                )
            }
        case .hypertrophyVolume:
            schedules = buildLinearWeekSchedules(
                durationWeeks: durationWeeks,
                deloadEvery: adaptiveDeloadInterval ?? 5
            )
        case .balancedTraining:
            let deloadInterval = strategy.level == .advanced ? 5 : 4
            schedules = buildLinearWeekSchedules(
                durationWeeks: durationWeeks,
                deloadEvery: adaptiveDeloadInterval ?? deloadInterval
            )
        case .enduranceConditioning:
            if focusProfile.defaultDeloadStyle == .enduranceStepBack {
                schedules = buildLinearWeekSchedules(
                    durationWeeks: durationWeeks,
                    deloadEvery: adaptiveDeloadInterval ?? 3
                )
            } else {
                schedules = buildLinearWeekSchedules(
                    durationWeeks: durationWeeks,
                    deloadEvery: adaptiveDeloadInterval ?? 4
                )
            }
        }

        return applyAdaptiveRecoveryBias(
            to: schedules,
            trainingState: trainingState,
            doseTargetProfile: doseTargetProfile
        )
    }

    private func buildLinearWeekSchedules(
        durationWeeks: Int,
        deloadEvery: Int
    ) -> [ProgramGenerationWeekSchedule] {
        var result: [ProgramGenerationWeekSchedule] = []
        var workingIdx = 0
        var lastWorkingIdx = 0
        let interval = max(2, deloadEvery)

        for week in 1...durationWeeks {
            let isDeload = week % interval == 0
            result.append(ProgramGenerationWeekSchedule(
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

    private func buildAdvancedWeekSchedules(durationWeeks: Int) -> [ProgramGenerationWeekSchedule] {
        let sequence = advancedPhaseSequence(durationWeeks: durationWeeks)
        return buildPhasedSchedules(from: sequence)
    }

    private func buildMixedAdvancedWeekSchedules(durationWeeks: Int) -> [ProgramGenerationWeekSchedule] {
        let sequence = mixedAdvancedPhaseSequence(durationWeeks: durationWeeks)
        return buildPhasedSchedules(from: sequence)
    }

    private func applyAdaptiveRecoveryBias(
        to schedules: [ProgramGenerationWeekSchedule],
        trainingState: TrainingStateSnapshot?,
        doseTargetProfile: DoseTargetProfile?
    ) -> [ProgramGenerationWeekSchedule] {
        guard
            let trainingState,
            !trainingState.hasSparseHistory,
            trainingState.shouldBiasRecovery || doseTargetProfile?.deloadIntervalOverride != nil,
            !schedules.contains(where: { $0.weekNumber <= 3 && $0.isDeload }),
            schedules.count >= 3
        else {
            return schedules
        }

        let earlyDeloadWeek = min(3, schedules.count)
        var workingIndex = 0
        var lastWorkingIndex = 0

        return schedules.map { schedule in
            let isDeload = schedule.isDeload || schedule.weekNumber == earlyDeloadWeek
            let updated = ProgramGenerationWeekSchedule(
                weekNumber: schedule.weekNumber,
                isDeload: isDeload,
                progressionIndex: isDeload ? lastWorkingIndex : workingIndex,
                advancedPhase: schedule.advancedPhase,
                phaseWeekIndex: schedule.phaseWeekIndex,
                phaseLength: schedule.phaseLength
            )
            if !isDeload {
                lastWorkingIndex = workingIndex
                workingIndex += 1
            }
            return updated
        }
    }

    private func buildPhasedSchedules(
        from sequence: [(ProgramGenerationAdvancedPhaseType?, Int)]
    ) -> [ProgramGenerationWeekSchedule] {
        var result: [ProgramGenerationWeekSchedule] = []
        var weekNumber = 1
        var progressionIdx = 0
        var lastPhase: ProgramGenerationAdvancedPhaseType = .hypertrophy

        for (phaseOpt, count) in sequence {
            let isDeload = phaseOpt == nil
            let phase = phaseOpt ?? lastPhase

            for weekInPhase in 0..<count {
                result.append(ProgramGenerationWeekSchedule(
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

            if let phaseOpt { lastPhase = phaseOpt }
        }

        return result
    }

    private func advancedPhaseSequence(
        durationWeeks: Int
    ) -> [(ProgramGenerationAdvancedPhaseType?, Int)] {
        switch durationWeeks {
        case 6: return [(.hypertrophy, 2), (nil, 1), (.strength, 2), (.peaking, 1)]
        case 8: return [(.hypertrophy, 3), (nil, 1), (.strength, 2), (.peaking, 1), (nil, 1)]
        case 10: return [(.hypertrophy, 3), (nil, 1), (.strength, 3), (nil, 1), (.peaking, 2)]
        case 12: return [(.hypertrophy, 4), (nil, 1), (.strength, 3), (nil, 1), (.peaking, 2), (nil, 1)]
        default: return [(.hypertrophy, 4), (nil, 1), (.strength, 3), (nil, 1), (.peaking, 2), (nil, 1)]
        }
    }

    private func mixedAdvancedPhaseSequence(
        durationWeeks: Int
    ) -> [(ProgramGenerationAdvancedPhaseType?, Int)] {
        switch durationWeeks {
        case 6: return [(.hypertrophy, 3), (nil, 1), (.strength, 2)]
        case 8: return [(.hypertrophy, 4), (nil, 1), (.strength, 2), (nil, 1)]
        case 10: return [(.hypertrophy, 5), (nil, 1), (.strength, 3), (nil, 1)]
        case 12: return [(.hypertrophy, 6), (nil, 1), (.strength, 4), (nil, 1)]
        default: return [(.hypertrophy, 6), (nil, 1), (.strength, 4), (nil, 1)]
        }
    }
}
