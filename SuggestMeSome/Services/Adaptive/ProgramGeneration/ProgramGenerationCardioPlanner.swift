import Foundation

struct ProgramGenerationCardioPlanner {

    func resolveCardioPrescription(
        sessionName: String,
        focusProfile: ProgramFocusProgrammingProfile,
        schedule: ProgramGenerationWeekSchedule
    ) -> ProgramGenerationCardioPrescription {
        let sessionType = resolveCardioSessionType(sessionName: sessionName)
        let fallbackRule = defaultCardioSessionRule(for: sessionType)
        let rule = focusProfile.cardioProgrammingProfile?.sessionRules[sessionType] ?? fallbackRule

        let workingIndex = schedule.progressionIndex
        let baseMinutes = cardioMinutes(for: rule, progressionIndex: workingIndex)
        let adjustedMinutes: Int
        if schedule.isDeload {
            adjustedMinutes = max(15, Int((Double(baseMinutes) * rule.deloadDurationScale).rounded()))
        } else {
            adjustedMinutes = baseMinutes
        }

        let adjustedRPE = schedule.isDeload
            ? clampedRPE(rule.targetRPE - 0.8)
            : clampedRPE(rule.targetRPE)
        let fatiguePerMinute = cardioFatiguePerMinute(targetRPE: adjustedRPE)
        let highFatiguePerMinute = cardioHighFatiguePerMinute(targetRPE: adjustedRPE)

        return ProgramGenerationCardioPrescription(
            minutes: adjustedMinutes,
            targetRPE: adjustedRPE,
            estimatedFatigueScore: Double(adjustedMinutes) * fatiguePerMinute,
            highFatigueScore: Double(adjustedMinutes) * highFatiguePerMinute
        )
    }

    func resolveCardioSessionType(sessionName: String) -> ProgramCardioSessionType {
        let lower = sessionName.lowercased()
        if lower.contains("recovery") { return .recovery }
        if lower.contains("long") { return .longSession }
        if lower.contains("interval") || lower.contains("vo2") || lower.contains("hiit") {
            return .interval
        }
        if lower.contains("threshold") || lower.contains("tempo") {
            return .threshold
        }
        return .easyAerobic
    }

    func cardioFatiguePerMinute(targetRPE: Double?) -> Double {
        let rpe = targetRPE ?? 6.0
        switch rpe {
        case ..<5.5: return 0.065
        case ..<7.0: return 0.080
        case ..<8.0: return 0.092
        case ..<9.0: return 0.112
        default: return 0.128
        }
    }

    func cardioHighFatiguePerMinute(targetRPE: Double?) -> Double {
        let rpe = targetRPE ?? 6.0
        switch rpe {
        case ..<7.5: return 0.002
        case ..<8.5: return 0.008
        default: return 0.016
        }
    }

    private func cardioMinutes(
        for rule: ProgramCardioSessionRule,
        progressionIndex: Int
    ) -> Int {
        switch rule.progressionMethod {
        case .duration:
            return max(15, rule.baseDurationMinutes + progressionIndex * rule.durationStepPerWorkingWeek)
        case .intervalCount, .intervalDensity, .workBlockDuration:
            guard let workRest = rule.workRestProgression else {
                return max(15, rule.baseDurationMinutes + progressionIndex * rule.durationStepPerWorkingWeek)
            }
            let stepEvery = max(1, workRest.stepEveryWorkingWeeks)
            let progressionSteps = progressionIndex / stepEvery

            let intervalCount = min(
                workRest.maxIntervals,
                max(1, workRest.initialIntervals + progressionSteps * workRest.intervalStep)
            )
            let workSeconds = max(30, workRest.initialWorkSeconds + progressionSteps * workRest.workSecondsStep)
            let restSeconds = max(15, workRest.initialRestSeconds + progressionSteps * workRest.restSecondsStep)

            let densityAdjustedRest: Int
            switch rule.progressionMethod {
            case .intervalDensity:
                densityAdjustedRest = max(10, restSeconds - (progressionSteps * 5))
            default:
                densityAdjustedRest = restSeconds
            }

            let totalMinutes = Double(intervalCount * (workSeconds + densityAdjustedRest)) / 60.0
            return max(15, Int(totalMinutes.rounded()))
        }
    }

    private func defaultCardioSessionRule(
        for sessionType: ProgramCardioSessionType
    ) -> ProgramCardioSessionRule {
        switch sessionType {
        case .easyAerobic:
            return .init(
                sessionType: .easyAerobic,
                targetRPE: 6.0,
                progressionMethod: .duration,
                baseDurationMinutes: 30,
                durationStepPerWorkingWeek: 3,
                deloadDurationScale: 0.72,
                workRestProgression: nil
            )
        case .threshold:
            return .init(
                sessionType: .threshold,
                targetRPE: 7.6,
                progressionMethod: .workBlockDuration,
                baseDurationMinutes: 30,
                durationStepPerWorkingWeek: 2,
                deloadDurationScale: 0.75,
                workRestProgression: .init(
                    initialIntervals: 3,
                    intervalStep: 0,
                    stepEveryWorkingWeeks: 2,
                    maxIntervals: 4,
                    initialWorkSeconds: 360,
                    workSecondsStep: 30,
                    initialRestSeconds: 180,
                    restSecondsStep: -15
                )
            )
        case .interval:
            return .init(
                sessionType: .interval,
                targetRPE: 8.8,
                progressionMethod: .intervalCount,
                baseDurationMinutes: 22,
                durationStepPerWorkingWeek: 1,
                deloadDurationScale: 0.70,
                workRestProgression: .init(
                    initialIntervals: 5,
                    intervalStep: 1,
                    stepEveryWorkingWeeks: 1,
                    maxIntervals: 9,
                    initialWorkSeconds: 120,
                    workSecondsStep: 0,
                    initialRestSeconds: 120,
                    restSecondsStep: -10
                )
            )
        case .longSession:
            return .init(
                sessionType: .longSession,
                targetRPE: 6.2,
                progressionMethod: .duration,
                baseDurationMinutes: 46,
                durationStepPerWorkingWeek: 4,
                deloadDurationScale: 0.74,
                workRestProgression: nil
            )
        case .recovery:
            return .init(
                sessionType: .recovery,
                targetRPE: 4.8,
                progressionMethod: .duration,
                baseDurationMinutes: 24,
                durationStepPerWorkingWeek: 2,
                deloadDurationScale: 0.68,
                workRestProgression: nil
            )
        }
    }

    private func clampedRPE(_ value: Double) -> Double {
        min(10.0, max(5.5, value))
    }
}
