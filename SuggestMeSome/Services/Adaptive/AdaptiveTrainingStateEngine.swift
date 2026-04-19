//
//  AdaptiveTrainingStateEngine.swift
//  SuggestMeSome
//
//  Feature 15 Prompt 2 — shared adaptive state and dose target derivation.
//

import Foundation
import SwiftData

struct AdaptiveTrainingStateEngine {
    private let context: ModelContext
    private let preferenceLearner: SuggestMeSomePreferenceLearnerService

    init(
        context: ModelContext,
        preferenceLearner: SuggestMeSomePreferenceLearnerService = SuggestMeSomePreferenceLearnerService()
    ) {
        self.context = context
        self.preferenceLearner = preferenceLearner
    }

    func buildSnapshot(
        focus: ProgramFocus? = nil,
        level: ProgramLevel? = nil,
        sessionsPerWeek: Int? = nil,
        activeRunOverride: ProgramRun? = nil,
        referenceDate: Date = Date()
    ) -> TrainingStateSnapshot {
        let recentHistory = TrainingReadRepository.fetchWorkouts(
            limit: 40,
            context: context
        )
        let runIndex = TrainingReadRepository.programRunIndexSnapshot(
            context: context,
            activeLimit: 2,
            completedLimit: 3
        )
        let recentWorkouts = TrainingContextQueryService.recentWorkouts(from: recentHistory, limit: 16)
        let activeRun = activeRunOverride ?? TrainingContextQueryService.activeProgramRuns(from: runIndex.activeRuns).first
        let preferences = preferenceLearner.learnPreferences(from: recentWorkouts)
        let fatigueStatus = resolvedFatigueStatus(activeRun: activeRun, referenceDate: referenceDate)
        let adherence = resolvedAdherenceTier(
            activeRun: activeRun,
            completedRuns: runIndex.completedRuns,
            recentWorkouts: recentWorkouts,
            sessionsPerWeek: sessionsPerWeek
        )
        let volumeCompletion = resolvedVolumeCompletionRate(
            activeRun: activeRun,
            recentWorkouts: recentWorkouts,
            referenceDate: referenceDate,
            sessionsPerWeek: sessionsPerWeek
        )
        let momentum = resolvedLiftMomentum(activeRun: activeRun, referenceDate: referenceDate)
        let stressSaturation = resolvedStressSaturation(
            focus: focus,
            level: level,
            recentWorkouts: recentWorkouts
        )
        let dailyContext = buildDailyProgramContext(
            snapshot: nil,
            request: nil,
            activeRunOverride: activeRun,
            referenceDate: referenceDate
        )

        let sparseHistory = recentWorkouts.count < 6
        return TrainingStateSnapshot(
            historyWindowWorkoutCount: recentWorkouts.count,
            hasSparseHistory: sparseHistory,
            adherenceTier: sparseHistory ? .sparseHistory : adherence,
            recentVolumeCompletionRate: volumeCompletion,
            fatigueStatus: fatigueStatus,
            recoveryPressure: resolvedRecoveryPressure(
                fatigueStatus: fatigueStatus,
                volumeCompletion: volumeCompletion,
                adherenceTier: adherence
            ),
            liftMomentumByCanonicalLift: momentum,
            perMuscleStressSaturation: stressSaturation,
            preferredAnchorExerciseNames: preferences.frequentlyUsedExercises,
            underusedExerciseNames: preferences.underusedExercises,
            activeProgramInterferenceRisk: dailyContext.interferenceScore,
            equipmentReliabilityScore: resolvedEquipmentReliabilityScore(from: recentWorkouts),
            continuityBias: resolvedContinuityBias(activeRun: activeRun, completedRuns: runIndex.completedRuns),
            blockedCanonicalLifts: dailyContext.blockedCanonicalLifts
        )
    }

    func buildDoseTargetProfile(
        focus: ProgramFocus,
        level: ProgramLevel,
        sessionsPerWeek: Int,
        snapshot: TrainingStateSnapshot,
        steeringProfile: AdaptiveSteeringProfile = .balanced
    ) -> DoseTargetProfile {
        guard !snapshot.hasSparseHistory else {
            return DoseTargetProfile(
                weeklyVolumeScale: 1.0,
                fatigueBudgetScale: 1.0,
                intensityScale: 1.0,
                rirOffset: 0.0,
                sessionStressScale: 1.0,
                deloadIntervalOverride: nil,
                accessoryCountAdjustment: 0,
                cardioDurationScale: 1.0,
                preserveAnchorBias: 0.5,
                interferencePenaltyScale: 1.0
            )
        }

        var weeklyVolumeScale = 1.0
        var fatigueBudgetScale = 1.0
        var intensityScale = 1.0
        var rirOffset = 0.0
        var sessionStressScale = 1.0
        var deloadIntervalOverride: Int?
        var accessoryAdjustment = 0
        var cardioDurationScale = 1.0

        switch snapshot.adherenceTier {
        case .high:
            weeklyVolumeScale += 0.08
            fatigueBudgetScale += 0.04
            sessionStressScale += 0.05
            accessoryAdjustment += 1
        case .moderate:
            break
        case .low:
            weeklyVolumeScale -= 0.10
            fatigueBudgetScale -= 0.08
            sessionStressScale -= 0.10
            rirOffset += 1.0
            accessoryAdjustment -= 1
        case .sparseHistory:
            break
        }

        switch snapshot.fatigueStatus {
        case .low, .manageable, nil:
            break
        case .elevated:
            weeklyVolumeScale -= 0.06
            intensityScale -= 0.03
            sessionStressScale -= 0.07
            rirOffset += 0.5
            deloadIntervalOverride = max(3, defaultDeloadInterval(for: focus, level: level) - 1)
        case .high, .critical:
            weeklyVolumeScale -= 0.14
            fatigueBudgetScale -= 0.12
            intensityScale -= 0.06
            sessionStressScale -= 0.15
            cardioDurationScale -= 0.08
            rirOffset += 1.0
            accessoryAdjustment -= 1
            deloadIntervalOverride = max(3, defaultDeloadInterval(for: focus, level: level) - 1)
        }

        let improvingLifts = snapshot.liftMomentumByCanonicalLift.values.filter { $0 == .improving }.count
        let decliningLifts = snapshot.liftMomentumByCanonicalLift.values.filter { $0 == .declining }.count
        if improvingLifts >= 2 {
            intensityScale += 0.02
            cardioDurationScale += focus == .cardioEndurance ? 0.05 : 0.0
        }
        if decliningLifts >= 1 {
            intensityScale -= 0.03
            rirOffset += 0.5
        }

        if snapshot.activeProgramInterferenceRisk >= 0.65 {
            sessionStressScale -= 0.08
            cardioDurationScale -= focus == .cardioEndurance ? 0.0 : 0.10
            accessoryAdjustment -= 1
        }

        if focus == .cardioEndurance {
            weeklyVolumeScale = 1.0
            accessoryAdjustment = 0
            cardioDurationScale = min(1.12, max(0.82, cardioDurationScale))
        }

        switch steeringProfile.progressionBias {
        case .conservative:
            weeklyVolumeScale -= 0.05
            intensityScale -= 0.02
            sessionStressScale -= 0.05
            rirOffset += 0.5
        case .balanced:
            break
        case .push:
            weeklyVolumeScale += snapshot.shouldBiasRecovery ? 0.0 : 0.05
            intensityScale += snapshot.shouldBiasRecovery ? 0.0 : 0.02
            sessionStressScale += snapshot.shouldBiasRecovery ? 0.0 : 0.04
            accessoryAdjustment += snapshot.shouldBiasRecovery ? 0 : 1
        }
        switch steeringProfile.recoveryBias {
        case .protectRecovery:
            weeklyVolumeScale -= 0.04
            sessionStressScale -= 0.06
            rirOffset += 0.5
        case .balanced:
            break
        case .trainThrough:
            weeklyVolumeScale += snapshot.shouldBiasRecovery ? 0.0 : 0.02
            sessionStressScale += snapshot.shouldBiasRecovery ? 0.0 : 0.03
            intensityScale += snapshot.shouldBiasRecovery ? 0.0 : 0.01
        }
        switch steeringProfile.continuityBias {
        case .preserveAnchors:
            break
        case .balanced:
            break
        case .rotateMore:
            accessoryAdjustment += 1
        }

        return DoseTargetProfile(
            weeklyVolumeScale: clamped(weeklyVolumeScale, min: 0.80, max: 1.15),
            fatigueBudgetScale: clamped(fatigueBudgetScale, min: 0.82, max: 1.10),
            intensityScale: clamped(intensityScale, min: 0.90, max: 1.05),
            rirOffset: clamped(rirOffset, min: 0.0, max: 1.5),
            sessionStressScale: clamped(sessionStressScale, min: 0.80, max: 1.10),
            deloadIntervalOverride: deloadIntervalOverride,
            accessoryCountAdjustment: max(-1, min(1, accessoryAdjustment)),
            cardioDurationScale: clamped(cardioDurationScale, min: 0.80, max: 1.12),
            preserveAnchorBias: clamped(
                0.50 +
                snapshot.continuityBias * 0.35 +
                (steeringProfile.continuityBias == .preserveAnchors ? 0.20 : 0.0) -
                (steeringProfile.continuityBias == .rotateMore ? 0.20 : 0.0),
                min: 0.25,
                max: 0.90
            ),
            interferencePenaltyScale: clamped(1.0 + snapshot.activeProgramInterferenceRisk * 0.45, min: 1.0, max: 1.35)
        )
    }

    func buildSessionConstructionProfile(
        request: SuggestMeSomeGenerationRequest,
        snapshot: TrainingStateSnapshot,
        dailyContext: DailyProgramContext?,
        steeringProfile: AdaptiveSteeringProfile = .balanced
    ) -> SessionConstructionProfile {
        let mode = request.sessionMode ?? inferredMode(for: request)
        let goal = request.goal ?? inferredGoal(for: request)
        let prioritizeAnchors = steeringProfile.continuityBias == .rotateMore
            ? false
            : !snapshot.preferredAnchorExerciseNames.isEmpty &&
                snapshot.equipmentReliabilityScore >= 0.55
        let interferencePenalty = dailyContext?.interferenceScore ?? snapshot.activeProgramInterferenceRisk
        let preferUnderused = steeringProfile.continuityBias == .rotateMore
        let intensityAdjustment =
            (steeringProfile.progressionBias == .push ? 1 : steeringProfile.progressionBias == .conservative ? -1 : 0) +
            (steeringProfile.recoveryBias == .trainThrough ? 1 : steeringProfile.recoveryBias == .protectRecovery ? -1 : 0)

        switch (mode, goal) {
        case (.recovery, _), (_, .recovery):
            return SessionConstructionProfile(
                requiredSlots: [.mobilityTempo, .trunkStability],
                optionalSlots: [.cardioPrimary, .cardioFinisher],
                strengthTimeShare: 0.45,
                cardioTimeShare: 0.55,
                prioritizePreferredAnchors: false,
                preferUnderusedMovements: false,
                allowAutomaticCardioAppend: true,
                interferencePenaltyScale: 1.0 + interferencePenalty,
                prescriptionStyle: .recoveryTechnique,
                prescribedIntensityAdjustment: -1
            )
        case (.conditioning, _), (_, .conditioning):
            return SessionConstructionProfile(
                requiredSlots: [.cardioPrimary, .trunkStability],
                optionalSlots: [.lowerPattern, .posteriorChain, .cardioFinisher],
                strengthTimeShare: 0.30,
                cardioTimeShare: 0.70,
                prioritizePreferredAnchors: false,
                preferUnderusedMovements: preferUnderused,
                allowAutomaticCardioAppend: true,
                interferencePenaltyScale: 1.0 + interferencePenalty,
                prescriptionStyle: .conditioningIntervals,
                prescribedIntensityAdjustment: clampedIntensityAdjustment(intensityAdjustment)
            )
        case (_, .strength):
            let required = requiredSlotsForStrength(mode: mode)
            return SessionConstructionProfile(
                requiredSlots: required,
                optionalSlots: [.secondaryCompound, .trunkStability, .armAccessory],
                strengthTimeShare: 1.0,
                cardioTimeShare: 0.0,
                prioritizePreferredAnchors: prioritizeAnchors,
                preferUnderusedMovements: preferUnderused,
                allowAutomaticCardioAppend: false,
                interferencePenaltyScale: 1.0 + interferencePenalty,
                prescriptionStyle: required.contains(.anchorCompound) ? .strengthTopSetBackoff : .strengthStraightSets,
                prescribedIntensityAdjustment: clampedIntensityAdjustment(intensityAdjustment)
            )
        case (_, .hypertrophy):
            return SessionConstructionProfile(
                requiredSlots: requiredSlotsForHypertrophy(mode: mode),
                optionalSlots: [.armAccessory, .shoulderAccessory, .trunkStability],
                strengthTimeShare: 1.0,
                cardioTimeShare: 0.0,
                prioritizePreferredAnchors: prioritizeAnchors,
                preferUnderusedMovements: preferUnderused,
                allowAutomaticCardioAppend: false,
                interferencePenaltyScale: 1.0 + interferencePenalty,
                prescriptionStyle: .hypertrophyDoubleProgression,
                prescribedIntensityAdjustment: clampedIntensityAdjustment(intensityAdjustment)
            )
        default:
            return SessionConstructionProfile(
                requiredSlots: requiredSlotsForGeneralMode(mode),
                optionalSlots: [.trunkStability, .cardioFinisher, .armAccessory],
                strengthTimeShare: mode == .fullBody ? 0.85 : 1.0,
                cardioTimeShare: mode == .fullBody ? 0.15 : 0.0,
                prioritizePreferredAnchors: prioritizeAnchors,
                preferUnderusedMovements: preferUnderused,
                allowAutomaticCardioAppend: mode == .fullBody && !snapshot.shouldBiasRecovery,
                interferencePenaltyScale: 1.0 + interferencePenalty,
                prescriptionStyle: .hypertrophyDoubleProgression,
                prescribedIntensityAdjustment: clampedIntensityAdjustment(intensityAdjustment)
            )
        }
    }

    func buildDailyProgramContext(
        snapshot: TrainingStateSnapshot? = nil,
        request: SuggestMeSomeGenerationRequest? = nil,
        activeRunOverride: ProgramRun? = nil,
        referenceDate: Date = Date()
    ) -> DailyProgramContext {
        let recommendationSnapshot = TrainingReadRepository.recommendationContextSnapshot(
            context: context,
            recentWorkoutLimit: 24
        )
        let activeRun = activeRunOverride ?? recommendationSnapshot.activeRun
        let recentWorkouts = recommendationSnapshot.recentWorkouts

        guard
            let run = activeRun,
            let program = run.program,
            let nextSession = nextProgramSession(run: run, program: program, workouts: recentWorkouts)
        else {
            return DailyProgramContext(
                shouldSupportActiveProgram: false,
                activeProgramName: activeRun?.program?.name,
                nextSessionName: nil,
                nextSessionMode: nil,
                nextSessionAnchorExercises: [],
                missedMovementFamilies: [],
                blockedCanonicalLifts: [],
                interferenceScore: snapshot?.activeProgramInterferenceRisk ?? 0
            )
        }

        let nextSessionCanonical = Array(Set(nextSession.exercises.compactMap {
            CanonicalLift.from(exerciseName: $0.exerciseName)
        })).sorted { $0.rawValue < $1.rawValue }
        let recentBlocked = blockedLifts(from: recentWorkouts, referenceDate: referenceDate)
        let intersection = Set(nextSessionCanonical).intersection(recentBlocked)
        let nextMuscleFamilies = Set(nextSession.exercises.flatMap {
            ProgramExerciseMetadataService.movementPatterns(for: $0.exerciseName).map(\.rawValue)
        })
        let missedFamilies = unresolvedProgramMovementFamilies(run: run, program: program, workouts: recentWorkouts)
        let interferenceScore = min(
            1.0,
            Double(intersection.count) * 0.35 +
                Double(nextMuscleFamilies.intersection(Set(missedFamilies)).count) * 0.08
        )

        return DailyProgramContext(
            shouldSupportActiveProgram: true,
            activeProgramName: program.name,
            nextSessionName: nextSession.sessionName,
            nextSessionMode: inferredMode(from: nextSession),
            nextSessionAnchorExercises: Array(Set(nextSession.exercises.map(\.exerciseName))).sorted(),
            missedMovementFamilies: missedFamilies,
            blockedCanonicalLifts: Array(intersection).sorted { $0.rawValue < $1.rawValue },
            interferenceScore: interferenceScore
        )
    }

    private func resolvedAdherenceTier(
        activeRun: ProgramRun?,
        completedRuns: [ProgramRun],
        recentWorkouts: [Workout],
        sessionsPerWeek: Int?
    ) -> TrainingStateAdherenceTier {
        if let activeRun, let program = activeRun.program {
            let runSnapshot = TrainingReadRepository.programRunProgressSnapshot(for: activeRun, context: context)
            let expectedSessions = expectedWorkoutCount(
                startDate: activeRun.startDate,
                endDate: Date(),
                sessionsPerWeek: sessionsPerWeek ?? program.sessionsPerWeek
            )
            let ratio = Double(runSnapshot.completedWorkoutCount) / Double(max(1, expectedSessions))
            return adherenceTier(for: ratio)
        }

        if let latestCompleted = TrainingContextQueryService.latestCompletedRun(from: completedRuns),
           let program = latestCompleted.program {
            let completionRatio = Double(
                TrainingContextQueryService.runScopedWorkouts(for: latestCompleted, in: recentWorkouts).count
            ) / Double(max(1, program.lengthInWeeks * program.sessionsPerWeek))
            return adherenceTier(for: completionRatio)
        }

        if recentWorkouts.count >= 10 { return .moderate }
        return .sparseHistory
    }

    private func resolvedVolumeCompletionRate(
        activeRun: ProgramRun?,
        recentWorkouts: [Workout],
        referenceDate: Date,
        sessionsPerWeek: Int?
    ) -> Double {
        guard let activeRun else {
            if recentWorkouts.count >= 8 { return 0.75 }
            if recentWorkouts.count >= 4 { return 0.60 }
            return 0.50
        }

        let pipeline = TrainingReadRepository.adaptiveProposalPipelineSnapshot(
            for: activeRun,
            referenceDate: referenceDate,
            context: context
        )
        if let latest = TrainingContextQueryService.latestWeeklyAnalysis(
            for: activeRun,
            in: pipeline.finalizedAnalyses
        ) {
            return clamped(latest.adherenceScore, min: 0.35, max: 1.10)
        }

        let expected = expectedWorkoutCount(
            startDate: activeRun.startDate,
            endDate: referenceDate,
            sessionsPerWeek: sessionsPerWeek ?? activeRun.program?.sessionsPerWeek ?? 3
        )
        let completed = TrainingReadRepository.programRunProgressSnapshot(
            for: activeRun,
            context: context
        ).completedWorkoutCount
        return clamped(Double(completed) / Double(max(1, expected)), min: 0.35, max: 1.0)
    }

    private func resolvedFatigueStatus(
        activeRun: ProgramRun?,
        referenceDate: Date
    ) -> FatigueStatus? {
        guard let activeRun else { return nil }
        let pipeline = TrainingReadRepository.adaptiveProposalPipelineSnapshot(
            for: activeRun,
            referenceDate: referenceDate,
            context: context
        )
        if let latest = TrainingContextQueryService.latestWeeklyAnalysis(
            for: activeRun,
            in: pipeline.finalizedAnalyses
        ) {
            return latest.fatigueStatus
        }

        let activeDeloadProposal = pipeline.proposals.contains {
            $0.proposalType == .deload &&
                ($0.proposalStatus == .pendingUserConfirmation || $0.proposalStatus == .pendingAutoApply)
        }
        return activeDeloadProposal ? .elevated : nil
    }

    private func resolvedLiftMomentum(
        activeRun: ProgramRun?,
        referenceDate: Date
    ) -> [CanonicalLift: LiftTrendStatus] {
        guard let activeRun else { return [:] }
        let pipeline = TrainingReadRepository.adaptiveProposalPipelineSnapshot(
            for: activeRun,
            referenceDate: referenceDate,
            context: context
        )
        var momentum: [CanonicalLift: LiftTrendStatus] = [:]
        for trend in pipeline.performanceTrends {
            guard let lift = CanonicalLift(rawValue: trend.canonicalLiftKey) else { continue }
            momentum[lift] = trend.trendStatus
        }
        return momentum
    }

    private func resolvedStressSaturation(
        focus: ProgramFocus?,
        level: ProgramLevel?,
        recentWorkouts: [Workout]
    ) -> [ProgramVolumeMuscle: Double] {
        var totals = Dictionary(uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map { ($0, 0.0) })
        let lookbackThreshold = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        let relevant = recentWorkouts.filter { $0.date >= lookbackThreshold }

        for workout in relevant {
            for entry in workout.exerciseEntries {
                let metadata = ProgramExerciseMetadataService.metadata(for: entry.exerciseName)
                let hardSetCount = max(1.0, Double(entry.sets.count))
                for (muscle, contribution) in metadata.muscleContributions {
                    totals[muscle, default: 0] += hardSetCount * contribution
                }
            }
        }

        let targetRanges: ProgramWeeklyVolumeTargets
        if let focus, let level {
            targetRanges = ProgramExerciseMetadataService.weeklyVolumeTargets(focus: focus, level: level)
        } else {
            targetRanges = ProgramExerciseMetadataService.weeklyVolumeTargets(focus: .generalFitness, level: .intermediate)
        }

        return Dictionary(uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map { muscle in
            let maxSets = max(1.0, targetRanges.range(for: muscle).maxHardSets)
            return (muscle, clamped((totals[muscle] ?? 0) / maxSets, min: 0.0, max: 1.4))
        })
    }

    private func resolvedRecoveryPressure(
        fatigueStatus: FatigueStatus?,
        volumeCompletion: Double,
        adherenceTier: TrainingStateAdherenceTier
    ) -> TrainingStateRecoveryPressure {
        if fatigueStatus == .high || fatigueStatus == .critical { return .elevated }
        if fatigueStatus == .elevated || volumeCompletion < 0.70 || adherenceTier == .low {
            return .conservative
        }
        return .neutral
    }

    private func resolvedEquipmentReliabilityScore(from workouts: [Workout]) -> Double {
        guard !workouts.isEmpty else { return 0.55 }

        var equipmentTags: [String: Int] = [:]
        for workout in workouts.prefix(12) {
            for entry in workout.exerciseEntries {
                for tag in inferredEquipmentTags(for: entry.exerciseName) {
                    equipmentTags[tag, default: 0] += 1
                }
            }
        }

        guard let dominant = equipmentTags.values.max(), dominant > 0 else { return 0.60 }
        let total = max(1, equipmentTags.values.reduce(0, +))
        let dominance = Double(dominant) / Double(total)
        return clamped(0.45 + dominance * 0.55, min: 0.45, max: 0.95)
    }

    private func resolvedContinuityBias(
        activeRun: ProgramRun?,
        completedRuns: [ProgramRun]
    ) -> Double {
        let snapshot = activeRun?.continuitySnapshot ??
            TrainingContextQueryService.latestCompletedRun(from: completedRuns)?.continuitySnapshot
        guard let snapshot else { return 0.0 }

        var bias = snapshot.selectedRecommendationStableID == nil ? 0.15 : 0.45
        if let carried = snapshot.carriedForwardContext, !carried.preservedExerciseNames.isEmpty {
            bias += 0.15
        }
        if !snapshot.userEditedFields.isEmpty {
            bias += 0.10
        }
        if snapshot.latestConfirmedSteeringProfile?.continuityBias == .preserveAnchors {
            bias += 0.08
        } else if snapshot.latestConfirmedSteeringProfile?.continuityBias == .rotateMore {
            bias -= 0.05
        }
        return clamped(bias, min: 0.0, max: 1.0)
    }

    private func clampedIntensityAdjustment(_ value: Int) -> Int {
        max(-1, min(1, value))
    }

    private func defaultDeloadInterval(for focus: ProgramFocus, level: ProgramLevel) -> Int {
        switch FocusTemplateLibrary.programmingProfile(for: focus).progressionStrategyFamily {
        case .strengthSkill, .mixedStrengthHypertrophy:
            return 4
        case .hypertrophyVolume:
            return 5
        case .balancedTraining:
            return level == .advanced ? 5 : 4
        case .enduranceConditioning:
            return focus == .cardioEndurance ? 3 : 4
        }
    }

    private func expectedWorkoutCount(startDate: Date, endDate: Date, sessionsPerWeek: Int) -> Int {
        let days = max(1.0, endDate.timeIntervalSince(startDate) / 86_400.0)
        let elapsedWeeks = max(1.0, days / 7.0)
        return Int(ceil(elapsedWeeks * Double(max(1, sessionsPerWeek))))
    }

    private func adherenceTier(for ratio: Double) -> TrainingStateAdherenceTier {
        switch ratio {
        case ..<0.60: return .low
        case ..<0.85: return .moderate
        default: return .high
        }
    }

    private func blockedLifts(from workouts: [Workout], referenceDate: Date) -> Set<CanonicalLift> {
        var latestExposure: [CanonicalLift: Date] = [:]

        for workout in workouts {
            for entry in workout.exerciseEntries {
                guard let lift = CanonicalLift.from(exerciseName: entry.exerciseName) else { continue }
                let hardLowRepSet = entry.sets.contains { $0.weight > 0 && $0.reps <= 6 }
                let hardRPE = (entry.topSetRPE ?? 0) >= 8.0
                guard hardLowRepSet || hardRPE else { continue }
                if let existing = latestExposure[lift], existing >= workout.date { continue }
                latestExposure[lift] = workout.date
            }
        }

        return Set(latestExposure.compactMap { lift, date in
            let hours = referenceDate.timeIntervalSince(date) / 3600.0
            return hours < 72 ? lift : nil
        })
    }

    private func nextProgramSession(
        run: ProgramRun,
        program: TrainingProgram,
        workouts: [Workout]
    ) -> ProgramSessionTemplate? {
        let runWorkouts = TrainingContextQueryService.runScopedWorkouts(for: run, in: workouts)
        for week in program.weeks.sorted(by: { $0.weekNumber < $1.weekNumber }) {
            for session in week.sessions.sorted(by: { $0.sessionNumber < $1.sessionNumber }) {
                let completed = runWorkouts.contains {
                    $0.programWeekNumber == week.weekNumber &&
                        $0.programSessionNumber == session.sessionNumber
                }
                if !completed { return session }
            }
        }
        return nil
    }

    private func unresolvedProgramMovementFamilies(
        run: ProgramRun,
        program: TrainingProgram,
        workouts: [Workout]
    ) -> [String] {
        let runWorkouts = TrainingContextQueryService.runScopedWorkouts(for: run, in: workouts)
        var unresolved = Set<String>()
        for week in program.weeks.sorted(by: { $0.weekNumber < $1.weekNumber }).prefix(2) {
            for session in week.sessions {
                let completed = runWorkouts.contains {
                    $0.programWeekNumber == week.weekNumber &&
                        $0.programSessionNumber == session.sessionNumber
                }
                if completed { continue }
                for exercise in session.exercises {
                    let patterns = ProgramExerciseMetadataService.movementPatterns(for: exercise.exerciseName)
                    unresolved.formUnion(patterns.map(\.rawValue))
                }
            }
        }
        return Array(unresolved).sorted()
    }

    private func requiredSlotsForStrength(mode: SuggestMeSomeSessionMode) -> [SuggestMeSomeSessionSlotKind] {
        switch mode {
        case .fullBody:
            return [.anchorCompound, .upperPush, .upperPull, .lowerPattern]
        case .upper:
            return [.anchorCompound, .upperPush, .upperPull]
        case .lower:
            return [.anchorCompound, .lowerPattern, .posteriorChain]
        case .push:
            return [.anchorCompound, .upperPush]
        case .pull:
            return [.anchorCompound, .upperPull, .posteriorChain]
        case .armsShoulders:
            return [.upperPush, .shoulderAccessory, .armAccessory]
        case .recovery, .conditioning, .surpriseMe:
            return [.anchorCompound]
        }
    }

    private func requiredSlotsForHypertrophy(mode: SuggestMeSomeSessionMode) -> [SuggestMeSomeSessionSlotKind] {
        switch mode {
        case .fullBody:
            return [.upperPush, .upperPull, .lowerPattern]
        case .upper:
            return [.upperPush, .upperPull, .shoulderAccessory]
        case .lower:
            return [.lowerPattern, .posteriorChain, .singleLeg]
        case .push:
            return [.upperPush, .shoulderAccessory, .armAccessory]
        case .pull:
            return [.upperPull, .posteriorChain, .armAccessory]
        case .armsShoulders:
            return [.shoulderAccessory, .armAccessory]
        case .recovery:
            return [.mobilityTempo, .trunkStability]
        case .conditioning:
            return [.cardioPrimary]
        case .surpriseMe:
            return [.upperPush, .upperPull]
        }
    }

    private func requiredSlotsForGeneralMode(_ mode: SuggestMeSomeSessionMode) -> [SuggestMeSomeSessionSlotKind] {
        switch mode {
        case .fullBody:
            return [.upperPush, .upperPull, .lowerPattern]
        case .upper:
            return [.upperPush, .upperPull]
        case .lower:
            return [.lowerPattern, .posteriorChain]
        case .push:
            return [.upperPush]
        case .pull:
            return [.upperPull]
        case .armsShoulders:
            return [.shoulderAccessory, .armAccessory]
        case .recovery:
            return [.mobilityTempo, .trunkStability]
        case .conditioning:
            return [.cardioPrimary, .trunkStability]
        case .surpriseMe:
            return [.upperPush, .upperPull, .lowerPattern]
        }
    }

    private func inferredMode(for request: SuggestMeSomeGenerationRequest) -> SuggestMeSomeSessionMode {
        request.sessionMode ?? (request.generationType == .fullBody ? .fullBody : .surpriseMe)
    }

    private func inferredGoal(for request: SuggestMeSomeGenerationRequest) -> SuggestMeSomeGenerationGoal {
        request.goal ?? .generalFitness
    }

    private func inferredMode(from session: ProgramSessionTemplate) -> SuggestMeSomeSessionMode? {
        let lower = (session.sessionName ?? "").lowercased()
        if lower.contains("upper") { return .upper }
        if lower.contains("lower") || lower.contains("legs") { return .lower }
        if lower.contains("push") { return .push }
        if lower.contains("pull") || lower.contains("back") { return .pull }
        if lower.contains("recovery") { return .recovery }
        if lower.contains("interval") || lower.contains("tempo") || lower.contains("steady") {
            return .conditioning
        }
        if lower.contains("full body") { return .fullBody }
        return nil
    }

    private func inferredEquipmentTags(for exerciseName: String) -> Set<String> {
        let lower = exerciseName.lowercased()
        if lower.contains("cable") { return ["cable"] }
        if lower.contains("machine") || lower.contains("bike") || lower.contains("row") || lower.contains("treadmill") || lower.contains("elliptical") || lower.contains("stair") {
            return ["machine"]
        }
        if lower.contains("dumbbell") || lower.hasPrefix("db ") { return ["dumbbell"] }
        if lower.contains("push-up") || lower.contains("pull-up") || lower.contains("plank") || lower.contains("bug") || lower.contains("bird dog") || lower.contains("rope") {
            return ["bodyweight"]
        }
        return ["barbell"]
    }

    private func clamped(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(upper, Swift.max(lower, value))
    }
}
