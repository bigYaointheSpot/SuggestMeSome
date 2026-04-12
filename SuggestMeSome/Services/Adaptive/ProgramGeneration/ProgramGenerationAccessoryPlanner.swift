import Foundation

struct ProgramGenerationAccessoryPlanner {
    private let loadEstimator = ProgramGenerationLoadEstimator()
    private let movementHelper = ProgramGenerationMovementCoverageHelper()

    private struct AccessoryCandidate {
        let exercise: TemplateExercise
        let estimate: ProgramGenerationExerciseLoadEstimate
        let reason: ProgramAccessorySelectionReason
        let score: Double
    }

    func buildAdaptiveAccessoryPlan(
        sessionDefs: [SessionDefinition],
        schedules: [ProgramGenerationWeekSchedule],
        focus: ProgramFocus,
        focusProfile: ProgramFocusProgrammingProfile,
        level: ProgramLevel,
        sessionsPerWeek: Int,
        seed: Int
    ) -> [Int: [[ProgramGenerationSelectedAccessory]]] {
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

        var planByWeek: [Int: [[ProgramGenerationSelectedAccessory]]] = [:]
        var lastUsedWeekBySession: [Int: [String: Int]] = [:]
        var previousWeekLastSessionFatigue = 0.0
        var previousWeekLastSessionHighFatigue = 0.0
        var rng = SeededRNG(seed: seed)

        for schedule in schedules {
            var weeklyMuscleSets = loadEstimator.emptyMuscleTotals()
            var weeklyFatigue = 0.0
            var sessionFatigue = Array(repeating: 0.0, count: sessionDefs.count)
            var sessionHighFatigue = Array(repeating: 0.0, count: sessionDefs.count)
            var weekAccessories = Array(repeating: [ProgramGenerationSelectedAccessory](), count: sessionDefs.count)
            var sessionPatternCoverage = Array(repeating: Set<ProgramMovementPattern>(), count: sessionDefs.count)
            var weeklyPatternExposure = Dictionary(uniqueKeysWithValues: ProgramMovementPattern.allCases.map { ($0, 0) })

            for (sessionIdx, sessionDef) in sessionDefs.enumerated() {
                for primary in sessionDef.primaryExercises {
                    let estimate = loadEstimator.estimateLoad(
                        for: primary,
                        focusProfile: focusProfile,
                        level: level,
                        schedule: schedule,
                        sessionIdx: sessionIdx,
                        sessionsPerWeek: sessionsPerWeek,
                        sessionName: sessionDef.sessionName
                    )
                    loadEstimator.addMuscleSets(estimate.hardSetsByMuscle, into: &weeklyMuscleSets)
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

            for (sessionIdx, sessionDef) in sessionDefs.enumerated() {
                let selectionCount = resolvedAccessorySelectionCount(
                    focus: focus,
                    sessionName: sessionDef.sessionName,
                    requested: sessionDef.accessoryCount,
                    available: sessionDef.accessoryPool.count
                )
                guard selectionCount > 0 else { continue }

                let isDeadliftHeavy = loadEstimator.isDeadliftHeavySession(sessionDef)
                let sessionAccessoryPatterns = sessionDef.accessoryPool.reduce(into: Set<ProgramMovementPattern>()) {
                    $0.formUnion(ProgramExerciseMetadataService.movementPatterns(for: $1.exerciseName))
                }
                var chosenNames: Set<String> = []

                while chosenNames.count < selectionCount {
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
                        let estimate = loadEstimator.estimateLoad(
                            for: candidate,
                            focusProfile: focusProfile,
                            level: level,
                            schedule: schedule,
                            sessionIdx: sessionIdx,
                            sessionsPerWeek: sessionsPerWeek,
                            sessionName: sessionDef.sessionName
                        )
                        let candidatePatterns = ProgramExerciseMetadataService.movementPatterns(for: candidate.exerciseName)

                        if focus == .bodybuilding,
                           isJunkBodybuildingAccessory(
                            estimate: estimate,
                            currentWeeklyMuscleSets: weeklyMuscleSets,
                            volumeTargets: volumeTargets,
                            sessionName: sessionDef.sessionName
                           ) {
                            continue
                        }

                        if movementHelper.shouldRejectMovementCandidate(
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

                        let reason = resolveAccessorySelectionReason(
                            focus: focus,
                            sessionName: sessionDef.sessionName,
                            estimate: estimate,
                            candidatePatterns: candidatePatterns,
                            currentWeeklyMuscleSets: weeklyMuscleSets,
                            volumeTargets: volumeTargets,
                            currentSessionFatigue: sessionFatigue[sessionIdx],
                            fatigueBudgets: fatigueBudgets,
                            currentWeekNumber: schedule.weekNumber,
                            lastUsedWeek: lastUsed
                        )
                        let scored = AccessoryCandidate(
                            exercise: candidate,
                            estimate: estimate,
                            reason: reason,
                            score: score
                        )
                        if let best, scored.score <= best.score { continue }
                        best = scored
                    }

                    guard let best else { break }

                    chosenNames.insert(best.exercise.exerciseName)
                    weekAccessories[sessionIdx].append(.init(exercise: best.exercise, reason: best.reason))

                    loadEstimator.addMuscleSets(best.estimate.hardSetsByMuscle, into: &weeklyMuscleSets)
                    weeklyFatigue += best.estimate.fatigueScore
                    sessionFatigue[sessionIdx] += best.estimate.fatigueScore
                    sessionHighFatigue[sessionIdx] += best.estimate.highFatigueScore
                    let selectedPatterns = ProgramExerciseMetadataService.movementPatterns(for: best.exercise.exerciseName)
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
        estimate: ProgramGenerationExerciseLoadEstimate,
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
        estimate: ProgramGenerationExerciseLoadEstimate,
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
            let sessionTargets = movementHelper.bodybuildingSessionPriorityMuscles(sessionName: sessionName)
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

    private func resolveAccessorySelectionReason(
        focus: ProgramFocus,
        sessionName: String,
        estimate: ProgramGenerationExerciseLoadEstimate,
        candidatePatterns: Set<ProgramMovementPattern>,
        currentWeeklyMuscleSets: [ProgramVolumeMuscle: Double],
        volumeTargets: ProgramWeeklyVolumeTargets,
        currentSessionFatigue: Double,
        fatigueBudgets: ProgramFatigueBudgets,
        currentWeekNumber: Int,
        lastUsedWeek: Int?
    ) -> ProgramAccessorySelectionReason {
        let usefulDeficitFill = ProgramVolumeMuscle.allCases.reduce(0.0) { total, muscle in
            let deficit = max(0, volumeTargets.range(for: muscle).minHardSets - (currentWeeklyMuscleSets[muscle] ?? 0))
            return total + min(deficit, estimate.hardSetsByMuscle[muscle] ?? 0)
        }
        if usefulDeficitFill >= 1.2 { return .muscleDeficit }

        if !candidatePatterns.isEmpty { return .movementCoverage }

        let projectedSessionFatigue = currentSessionFatigue + estimate.fatigueScore
        if projectedSessionFatigue >= fatigueBudgets.sessionBudget * 0.82 { return .fatigueFit }

        if focus == .bodybuilding {
            let targets = movementHelper.bodybuildingSessionPriorityMuscles(sessionName: sessionName)
            let contribution = targets.reduce(0.0) { partial, muscle in
                partial + (estimate.hardSetsByMuscle[muscle] ?? 0)
            }
            if contribution >= 1.0 { return .sessionSpecificity }
        }

        if let lastUsedWeek {
            if currentWeekNumber - lastUsedWeek >= 2 { return .noveltyRotation }
        } else {
            return .noveltyRotation
        }

        if estimate.highFatigueScore <= 0.02 { return .recoveryBias }
        return .defaultRule
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

    private func isJunkBodybuildingAccessory(
        estimate: ProgramGenerationExerciseLoadEstimate,
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

        let sessionTargets = movementHelper.bodybuildingSessionPriorityMuscles(sessionName: sessionName)
        let targetContribution = sessionTargets.reduce(0.0) { partial, muscle in
            partial + (estimate.hardSetsByMuscle[muscle] ?? 0)
        }

        return usefulTowardDeficit < 0.8 && targetContribution < 1.0
    }

    private func randomJitter(using rng: inout SeededRNG, magnitude: Double) -> Double {
        let unit = Double(rng.next() % 10_000) / 10_000.0
        return (unit - 0.5) * magnitude
    }
}

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed &+ 1)) | 1
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}
