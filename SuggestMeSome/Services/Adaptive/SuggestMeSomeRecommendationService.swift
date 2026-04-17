import Foundation
import SwiftData

/// Conflict-aware recommendation stage for SuggestMeSome generation.
///
/// This service is intentionally lightweight: it produces an opinionated session direction
/// and a concrete generation request, but it does not perform any proposal/overlay logic,
/// periodization, or long-horizon planning.
struct SuggestMeSomeRecommendationService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func recommendSession(
        configuration: SuggestMeSomeSessionConfiguration,
        allMuscleGroups: [MuscleGroup],
        coachContext: SuggestMeSomeCoachContext? = nil
    ) -> SuggestMeSomeSessionRecommendation {
        let snapshot = TrainingReadRepository.recommendationContextSnapshot(
            context: context,
            recentWorkoutLimit: 24
        )
        let recentWorkouts = snapshot.recentWorkouts
        let activeRun = snapshot.activeRun

        // Pain/discomfort is the highest-priority override — it forces recovery mode and
        // caps intensity to 1 regardless of all other signals.
        let painForced = coachContext?.hasPainOrDiscomfort ?? false

        let resolvedMode = resolveMode(configuration.mode, configuration: configuration, recentWorkouts: recentWorkouts)
        var adjustedIntensity = adjustedIntensity(for: configuration, resolvedMode: resolvedMode)

        // Apply coach context intensity caps before any conflict analysis.
        adjustedIntensity = applyCoachContextIntensityCap(
            adjustedIntensity,
            coachContext: coachContext,
            painForced: painForced
        )

        let heavyLiftExposures = mostRecentHardCanonicalExposures(in: recentWorkouts)
        let blockedLifts = blockedCanonicalLifts(
            exposures: heavyLiftExposures,
            now: Date(),
            requestedIntensity: adjustedIntensity,
            requestedGoal: configuration.goal
        )

        let recentMuscleExposure = recentMuscleExposureSet(in: recentWorkouts, allMuscleGroups: allMuscleGroups)
        let modeMuscleTargets = targetMuscleNames(for: resolvedMode)
        let overlapCount = modeMuscleTargets.intersection(recentMuscleExposure).count

        let programConflict = analyzeProgramContextConflict(
            activeRun: activeRun,
            recentWorkouts: recentWorkouts,
            blockedLifts: blockedLifts,
            allMuscleGroups: allMuscleGroups
        )

        // Coach-context recovery bias: fatigue, overlays, deload proposals, and pain all
        // contribute additionally to the existing overlap/conflict/blocked-lift signals.
        let coachBiasesRecovery = shouldCoachBiasRecovery(
            coachContext: coachContext,
            painForced: painForced
        )
        let shouldBiasRecovery = coachBiasesRecovery
            || (overlapCount >= 2 && adjustedIntensity >= 4)
            || !blockedLifts.isEmpty
            || programConflict.hasConflict

        let finalMode = adjustedMode(
            baseMode: painForced ? .recovery : resolvedMode,
            shouldBiasRecovery: shouldBiasRecovery,
            durationMinutes: configuration.durationMinutes
        )

        let finalGoal = adjustedGoal(
            baseGoal: configuration.goal,
            finalMode: finalMode,
            shouldBiasRecovery: shouldBiasRecovery
        )

        let movementPriorities = movementPriorities(for: finalMode, goal: finalGoal, recoveryBias: shouldBiasRecovery)
        let candidateFamilies = candidateExerciseFamilies(
            mode: finalMode,
            goal: finalGoal,
            blockedLifts: blockedLifts,
            overlapCount: overlapCount,
            equipmentProfile: configuration.equipmentProfile,
            coachContext: coachContext
        )

        let anchorLifts = candidateAnchorLifts(
            mode: finalMode,
            allMuscleGroups: allMuscleGroups,
            blockedLifts: blockedLifts,
            equipmentProfile: configuration.equipmentProfile,
            preferences: coachContext?.exercisePreferences
        )

        let selectedMuscleGroups = selectedGroups(for: finalMode, allMuscleGroups: allMuscleGroups)
        let selectedExercises = selectedAnchorExercises(
            anchorNames: anchorLifts,
            allMuscleGroups: allMuscleGroups
        )

        let buildable = configuration.durationMinutes >= 20
        let request = buildable ? SuggestMeSomeGenerationRequest(
            generationType: generationType(for: finalMode),
            durationMinutes: Double(configuration.durationMinutes),
            intensity: adjustedIntensity,
            selectedMuscleGroups: selectedMuscleGroups,
            selectedExercises: selectedExercises,
            goal: finalGoal,
            equipmentProfile: configuration.equipmentProfile,
            sessionMode: finalMode
        ) : nil

        let chips = buildReasonChips(
            equipmentProfile: configuration.equipmentProfile,
            durationMinutes: configuration.durationMinutes,
            adjustedIntensity: adjustedIntensity,
            configuredMode: configuration.mode,
            finalMode: finalMode,
            blockedLifts: blockedLifts,
            overlapCount: overlapCount,
            hasProgramConflict: programConflict.hasConflict,
            coachContext: coachContext
        )
        let continuitySummary = buildContinuitySummary(
            recentWorkouts: recentWorkouts,
            activeRun: activeRun,
            finalMode: finalMode,
            durationMinutes: configuration.durationMinutes,
            equipmentProfile: configuration.equipmentProfile,
            overlapCount: overlapCount,
            blockedLifts: blockedLifts,
            coachContext: coachContext
        )
        let nextActionGuidance = buildNextActionGuidance(
            finalMode: finalMode,
            buildable: buildable,
            durationMinutes: configuration.durationMinutes,
            activeRun: activeRun,
            coachContext: coachContext
        )

        return SuggestMeSomeSessionRecommendation(
            title: recommendationTitle(mode: finalMode, goal: finalGoal),
            summary: summaryText(
                mode: finalMode,
                overlapCount: overlapCount,
                blockedLifts: blockedLifts,
                hasProgramConflict: programConflict.hasConflict,
                durationMinutes: configuration.durationMinutes,
                buildable: buildable,
                coachContext: coachContext
            ),
            rationale: rationaleText(
                configuredMode: configuration.mode,
                finalMode: finalMode,
                goal: finalGoal,
                equipmentProfile: configuration.equipmentProfile,
                adjustedIntensity: adjustedIntensity,
                blockedLifts: blockedLifts,
                overlapCount: overlapCount,
                programConflictReason: programConflict.reason,
                coachContext: coachContext
            ),
            reasonChips: chips,
            wasRedirected: finalMode != configuration.mode,
            mode: finalMode,
            goal: finalGoal,
            continuitySummary: continuitySummary,
            nextActionGuidance: nextActionGuidance,
            recommendedMovementPriorities: movementPriorities,
            candidateExerciseFamilies: candidateFamilies,
            candidateAnchorLifts: anchorLifts,
            isBuildableIntoWorkout: buildable,
            request: request
        )
    }
    // MARK: - Coach context integration helpers

    /// Applies intensity caps derived from coach context signals.
    ///
    /// Priority order (highest to lowest):
    ///   1. Pain/discomfort → cap at 1 (manual override, always respected)
    ///   2. Critical fatigue → cap at 1
    ///   3. High fatigue → cap at 2
    ///   4. Elevated fatigue → cap at 3
    ///   5. Low readiness tier → cap at 3
    ///   6. HealthKit caution → nudge down by 1 (medium influence only)
    ///
    /// HealthKit caution cannot override a cap that came from manual readiness or fatigue.
    private func applyCoachContextIntensityCap(
        _ intensity: Int,
        coachContext: SuggestMeSomeCoachContext?,
        painForced: Bool
    ) -> Int {
        guard let ctx = coachContext else { return intensity }
        var result = intensity

        // 1. Pain — highest priority, always forces floor.
        if painForced {
            return 1
        }

        // 2–4. Fatigue caps.
        if let fatigue = ctx.fatigueStatus {
            switch fatigue {
            case .critical:
                result = min(result, 1)
            case .high:
                result = min(result, 2)
            case .elevated:
                result = min(result, 3)
            case .low, .manageable:
                break
            }
        }

        // 5. Low readiness tier.
        if let tier = ctx.readinessTier, tier == .low {
            result = min(result, 3)
        }

        // 6. HealthKit caution — medium influence, nudge only, cannot override prior caps.
        if let hk = ctx.objectiveRecoveryInsight, hk.status == .caution {
            result = max(1, result - 1)
        }

        return result
    }

    /// Returns true if any coach context signal independently warrants biasing toward recovery.
    ///
    /// This complements (does not replace) the existing overlap/blocked-lift/program-conflict signals.
    private func shouldCoachBiasRecovery(
        coachContext: SuggestMeSomeCoachContext?,
        painForced: Bool
    ) -> Bool {
        guard let ctx = coachContext else { return false }

        if painForced { return true }

        if let fatigue = ctx.fatigueStatus, fatigue == .elevated || fatigue == .high || fatigue == .critical {
            return true
        }

        if let tier = ctx.readinessTier, tier == .low {
            return true
        }

        // An active deload overlay means the coach already approved conservative loading.
        let hasDeloadOverlay = ctx.activeOverlaySummaries.contains { $0.localizedCaseInsensitiveContains("deload") }
        if hasDeloadOverlay { return true }

        // A pending deload proposal means the system recommends conservative loading soon.
        if ctx.pendingProposals.contains(where: { $0.proposalType == .deload }) {
            return true
        }

        return false
    }

    // MARK: - Mode / goal normalization

    private func resolveMode(
        _ mode: SuggestMeSomeSessionMode,
        configuration: SuggestMeSomeSessionConfiguration,
        recentWorkouts: [Workout]
    ) -> SuggestMeSomeSessionMode {
        guard mode == .surpriseMe else { return mode }

        let candidates: [SuggestMeSomeSessionMode] = [
            .fullBody,
            .upper,
            .lower,
            .push,
            .pull,
            .armsShoulders,
            .conditioning,
            .recovery,
        ]

        let recencyToken = recentWorkouts.first?.id.uuidString ?? "none"
        let seedInput = [
            configuration.goal.rawValue,
            configuration.equipmentProfile.rawValue,
            String(configuration.durationMinutes),
            String(configuration.intensity),
            String(recentWorkouts.count),
            recencyToken,
        ].joined(separator: "|")

        let index = stableHash(seedInput) % candidates.count
        return candidates[index]
    }

    private func adjustedIntensity(
        for configuration: SuggestMeSomeSessionConfiguration,
        resolvedMode: SuggestMeSomeSessionMode
    ) -> Int {
        let base = min(5, max(1, configuration.intensity))
        let adjusted: Int

        switch configuration.goal {
        case .recovery:
            adjusted = min(base, 2)
        case .conditioning, .fatLoss:
            adjusted = min(base + 1, 5)
        case .strength:
            adjusted = max(base, 4)
        case .hypertrophy, .generalFitness:
            adjusted = base
        }

        if resolvedMode == .recovery {
            return min(adjusted, 2)
        }
        if resolvedMode == .conditioning {
            return min(max(adjusted, 3), 5)
        }

        return adjusted
    }

    private func adjustedMode(
        baseMode: SuggestMeSomeSessionMode,
        shouldBiasRecovery: Bool,
        durationMinutes: Int
    ) -> SuggestMeSomeSessionMode {
        guard shouldBiasRecovery else { return baseMode }
        guard baseMode != .conditioning, baseMode != .recovery else { return baseMode }

        if durationMinutes <= 35 {
            return .conditioning
        }
        return .recovery
    }

    private func adjustedGoal(
        baseGoal: SuggestMeSomeGenerationGoal,
        finalMode: SuggestMeSomeSessionMode,
        shouldBiasRecovery: Bool
    ) -> SuggestMeSomeGenerationGoal {
        if finalMode == .recovery {
            return .recovery
        }
        if finalMode == .conditioning {
            return .conditioning
        }
        if shouldBiasRecovery, baseGoal == .strength {
            return .generalFitness
        }
        return baseGoal
    }

    // MARK: - Conflict analysis

    private func mostRecentHardCanonicalExposures(in workouts: [Workout]) -> [CanonicalLift: Date] {
        var latestByLift: [CanonicalLift: Date] = [:]

        for workout in workouts {
            for entry in workout.exerciseEntries {
                guard let lift = CanonicalLift.from(exerciseName: entry.exerciseName) else { continue }
                guard isHardExposure(entry) else { continue }

                if let existing = latestByLift[lift] {
                    if workout.date > existing {
                        latestByLift[lift] = workout.date
                    }
                } else {
                    latestByLift[lift] = workout.date
                }
            }
        }

        return latestByLift
    }

    private func blockedCanonicalLifts(
        exposures: [CanonicalLift: Date],
        now: Date,
        requestedIntensity: Int,
        requestedGoal: SuggestMeSomeGenerationGoal
    ) -> Set<CanonicalLift> {
        let heavyWindowHours: Double
        if requestedIntensity >= 4 || requestedGoal == .strength {
            heavyWindowHours = 72
        } else {
            heavyWindowHours = 48
        }

        return Set(exposures.compactMap { lift, date in
            let hoursSince = now.timeIntervalSince(date) / 3600.0
            return hoursSince < heavyWindowHours ? lift : nil
        })
    }

    private func isHardExposure(_ entry: ExerciseEntry) -> Bool {
        if let topSetRPE = entry.topSetRPE, topSetRPE >= 8.0 {
            return true
        }

        let heavyLowRepSets = entry.sets.filter { $0.weight > 0 && $0.reps <= 6 }
        return !heavyLowRepSets.isEmpty
    }

    private func recentMuscleExposureSet(
        in workouts: [Workout],
        allMuscleGroups: [MuscleGroup]
    ) -> Set<String> {
        let calendar = Calendar.current
        let threshold = calendar.date(byAdding: .hour, value: -48, to: Date()) ?? Date.distantPast

        let lookup = Dictionary(uniqueKeysWithValues: allMuscleGroups.flatMap { group in
            group.exercises.map { ($0.name.lowercased(), group.name) }
        })

        var result: Set<String> = []

        for workout in workouts where workout.date >= threshold {
            for entry in workout.exerciseEntries {
                if let groupName = lookup[entry.exerciseName.lowercased()] {
                    result.insert(groupName)
                } else if let canonical = CanonicalLift.from(exerciseName: entry.exerciseName) {
                    result.formUnion(defaultMuscleNames(for: canonical))
                }
            }
        }

        return result
    }

    private func analyzeProgramContextConflict(
        activeRun: ProgramRun?,
        recentWorkouts: [Workout],
        blockedLifts: Set<CanonicalLift>,
        allMuscleGroups: [MuscleGroup]
    ) -> (hasConflict: Bool, reason: String?) {
        guard let run = activeRun, let program = run.program else {
            return (false, nil)
        }

        guard let nextSession = nextProgramSession(run: run, program: program, workouts: recentWorkouts) else {
            return (false, nil)
        }

        let nextCanonical = Set(nextSession.exercises.compactMap { CanonicalLift.from(exerciseName: $0.exerciseName) })
        if !nextCanonical.intersection(blockedLifts).isEmpty {
            let liftNames = nextCanonical.intersection(blockedLifts).map(\.displayName).sorted().joined(separator: ", ")
            return (true, "Active program next session also includes \(liftNames), so today is biased away from redundant heavy overlap.")
        }

        let recentMuscles = recentMuscleExposureSet(in: recentWorkouts, allMuscleGroups: allMuscleGroups)
        let nextSessionMuscles = Set(nextSession.exercises.flatMap { musclesForExerciseName($0.exerciseName, allMuscleGroups: allMuscleGroups) })

        if nextSessionMuscles.intersection(recentMuscles).count >= 3 {
            return (true, "Recent sessions and the next active-program session already overlap heavily, so recommendation shifts more recovery-aware.")
        }

        return (false, nil)
    }

    private func nextProgramSession(
        run: ProgramRun,
        program: TrainingProgram,
        workouts: [Workout]
    ) -> ProgramSessionTemplate? {
        let runWorkouts = TrainingContextQueryService.runScopedWorkouts(for: run, in: workouts)

        let sortedWeeks = program.weeks.sorted { $0.weekNumber < $1.weekNumber }
        for week in sortedWeeks {
            let sortedSessions = week.sessions.sorted { $0.sessionNumber < $1.sessionNumber }
            for session in sortedSessions {
                let done = runWorkouts.contains {
                    $0.programWeekNumber == week.weekNumber &&
                    $0.programSessionNumber == session.sessionNumber
                }
                if !done {
                    return session
                }
            }
        }

        return sortedWeeks.first?.sessions.sorted { $0.sessionNumber < $1.sessionNumber }.first
    }

    // MARK: - Recommendation composition

    private func generationType(for mode: SuggestMeSomeSessionMode) -> WorkoutGenerationType {
        mode == .fullBody ? .fullBody : .custom
    }

    private func selectedGroups(
        for mode: SuggestMeSomeSessionMode,
        allMuscleGroups: [MuscleGroup]
    ) -> [MuscleGroup] {
        let targetNames = targetMuscleNames(for: mode)
        guard !targetNames.isEmpty else { return [] }
        return allMuscleGroups.filter { targetNames.contains($0.name) }
    }

    private func targetMuscleNames(for mode: SuggestMeSomeSessionMode) -> Set<String> {
        switch mode {
        case .fullBody, .surpriseMe:
            return []
        case .upper:
            return ["Chest", "Back", "Shoulders", "Arms"]
        case .lower:
            return ["Legs", "Core"]
        case .push:
            return ["Chest", "Shoulders", "Arms"]
        case .pull:
            return ["Back", "Arms"]
        case .armsShoulders:
            return ["Arms", "Shoulders"]
        case .recovery:
            return ["Core", "Cardio"]
        case .conditioning:
            return ["Cardio", "Legs", "Core"]
        }
    }

    private func selectedAnchorExercises(anchorNames: [String], allMuscleGroups: [MuscleGroup]) -> [Exercise] {
        guard !anchorNames.isEmpty else { return [] }
        let byLowerName = Dictionary(uniqueKeysWithValues: allMuscleGroups.flatMap { group in
            group.exercises.map { ($0.name.lowercased(), $0) }
        })

        return anchorNames.compactMap { byLowerName[$0.lowercased()] }
    }

    private func movementPriorities(
        for mode: SuggestMeSomeSessionMode,
        goal: SuggestMeSomeGenerationGoal,
        recoveryBias: Bool
    ) -> [String] {
        switch mode {
        case .fullBody:
            return recoveryBias
                ? ["Stable squat/hinge pattern", "Submax push", "Submax pull", "Short trunk finisher"]
                : ["Primary lower-body compound", "Upper push", "Upper pull", "Trunk stability"]
        case .upper:
            return ["Horizontal push", "Horizontal pull", "Vertical push", "Arm assistance"]
        case .lower:
            return ["Knee-dominant main pattern", "Hinge pattern", "Single-leg support", "Core bracing"]
        case .push:
            return ["Primary pressing pattern", "Secondary pressing pattern", "Triceps assistance"]
        case .pull:
            return ["Primary row/pull pattern", "Secondary pull pattern", "Posterior chain support"]
        case .armsShoulders:
            return ["Overhead or incline press", "Lateral/rear deltoid work", "Arm superset density"]
        case .recovery:
            return ["Low-impact movement", "Trunk stability", "Mobility tempo work"]
        case .conditioning:
            if goal == .fatLoss || goal == .conditioning {
                return ["Heart-rate raising intervals", "Lower-impact conditioning", "Short trunk finish"]
            }
            return ["Short mixed-conditioning intervals", "Light posterior-chain support", "Core stability"]
        case .surpriseMe:
            return ["Balanced movement mix"]
        }
    }

    private func candidateExerciseFamilies(
        mode: SuggestMeSomeSessionMode,
        goal: SuggestMeSomeGenerationGoal,
        blockedLifts: Set<CanonicalLift>,
        overlapCount: Int,
        equipmentProfile: SuggestMeSomeEquipmentProfile,
        coachContext: SuggestMeSomeCoachContext? = nil
    ) -> [String] {
        var families: [String]

        switch mode {
        case .recovery:
            families = [
                "Low-impact cardio",
                "Core stability",
                "Mobility and tempo accessories",
            ]
        case .conditioning:
            families = [
                "Cardio intervals",
                "Bodyweight or dumbbell density circuits",
                "Light trunk/accessory finishers",
            ]
        case .lower:
            families = ["Knee-dominant compounds", "Hip hinges", "Single-leg accessories"]
        case .upper:
            families = ["Horizontal push", "Horizontal pull", "Vertical pressing", "Upper-back accessories"]
        case .push:
            families = ["Pressing compounds", "Shoulder accessories", "Triceps work"]
        case .pull:
            families = ["Rows and pulls", "Hinge support", "Biceps accessories"]
        case .armsShoulders:
            families = ["Shoulder presses", "Lateral/rear delt work", "Arm supersets"]
        case .fullBody, .surpriseMe:
            families = ["Big compounds", "Push/pull balance", "Core and simple conditioning"]
        }

        if overlapCount >= 2 {
            families.insert("Recovery-biased accessories", at: 0)
        }

        if blockedLifts.contains(.squat) || blockedLifts.contains(.deadlift) {
            families.append("Lower-load posterior-chain accessories")
        }
        if blockedLifts.contains(.bench) || blockedLifts.contains(.overheadPress) {
            families.append("Higher-rep pressing accessories")
        }

        if equipmentProfile == .bodyweightOnly {
            families = families.map { family in
                switch family {
                case "Big compounds":
                    return "Bodyweight compounds"
                case "Pressing compounds":
                    return "Push-up and dip patterns"
                default:
                    return family
                }
            }
        }

        // Coach context additions: overlay and proposal context, underused variety hint.
        if let ctx = coachContext {
            if !ctx.activeOverlaySummaries.isEmpty {
                families.insert("Coach-approved overlay in effect", at: 0)
            }
            if ctx.pendingProposals.contains(where: { $0.proposalType == .variationSwap }) {
                families.append("Variation swap candidate (pending proposal)")
            }
            if let prefs = ctx.exercisePreferences, !prefs.underusedExercises.isEmpty {
                families.append("Variety rotation available")
            }
        }

        return uniquePreservingOrder(families)
    }

    private func candidateAnchorLifts(
        mode: SuggestMeSomeSessionMode,
        allMuscleGroups: [MuscleGroup],
        blockedLifts: Set<CanonicalLift>,
        equipmentProfile: SuggestMeSomeEquipmentProfile,
        preferences: SuggestMeSomeExercisePreferences? = nil
    ) -> [String] {
        var canonicalCandidates: [CanonicalLift]

        switch mode {
        case .upper:
            canonicalCandidates = [.bench, .overheadPress]
        case .lower:
            canonicalCandidates = [.squat, .deadlift]
        case .push:
            canonicalCandidates = [.bench, .overheadPress]
        case .pull:
            canonicalCandidates = [.deadlift]
        case .armsShoulders:
            canonicalCandidates = [.overheadPress, .bench]
        case .fullBody:
            canonicalCandidates = [.squat, .bench, .deadlift, .overheadPress]
        case .conditioning, .recovery, .surpriseMe:
            canonicalCandidates = []
        }

        canonicalCandidates.removeAll { blockedLifts.contains($0) }

        var anchors: [String] = canonicalCandidates.compactMap {
            preferenceAwareAnchorName(
                for: $0,
                allMuscleGroups: allMuscleGroups,
                equipmentProfile: equipmentProfile,
                preferences: preferences
            )
        }

        if anchors.isEmpty {
            switch mode {
            case .recovery:
                anchors = fallbackAnchors(["Plank", "Dead Bug", "Bird Dog"], allMuscleGroups: allMuscleGroups, equipmentProfile: equipmentProfile)
            case .conditioning:
                anchors = fallbackAnchors(["Exercise Bike", "Rowing Machine", "Jump Rope"], allMuscleGroups: allMuscleGroups, equipmentProfile: equipmentProfile)
            case .lower:
                anchors = fallbackAnchors(["Leg Press", "Bulgarian Split Squat", "Romanian Deadlift"], allMuscleGroups: allMuscleGroups, equipmentProfile: equipmentProfile)
            case .upper:
                anchors = fallbackAnchors(["Bench Press", "Barbell Row", "Pull-ups"], allMuscleGroups: allMuscleGroups, equipmentProfile: equipmentProfile)
            case .push:
                anchors = fallbackAnchors(["Bench Press", "Overhead Press", "DB Shoulder Press"], allMuscleGroups: allMuscleGroups, equipmentProfile: equipmentProfile)
            case .pull:
                anchors = fallbackAnchors(["Barbell Row", "Pull-ups", "Lat Pulldown"], allMuscleGroups: allMuscleGroups, equipmentProfile: equipmentProfile)
            case .armsShoulders:
                anchors = fallbackAnchors(["Overhead Press", "DB Shoulder Press", "Dips"], allMuscleGroups: allMuscleGroups, equipmentProfile: equipmentProfile)
            case .fullBody:
                anchors = fallbackAnchors(["Back Squats", "Bench Press", "Barbell Row"], allMuscleGroups: allMuscleGroups, equipmentProfile: equipmentProfile)
            case .surpriseMe:
                anchors = []
            }
        }

        return Array(anchors.prefix(3))
    }

    /// Returns the best anchor name for a canonical lift, with preference signal bias.
    ///
    /// If the user has a frequently-used variation that is available and equipment-compatible,
    /// that variation is preferred over the default canonical ordering. Falls back to
    /// `bestAnchorName` when no preference match is found.
    private func preferenceAwareAnchorName(
        for canonical: CanonicalLift,
        allMuscleGroups: [MuscleGroup],
        equipmentProfile: SuggestMeSomeEquipmentProfile,
        preferences: SuggestMeSomeExercisePreferences?
    ) -> String? {
        guard let prefs = preferences, !prefs.frequentlyUsedExercises.isEmpty else {
            return bestAnchorName(for: canonical, allMuscleGroups: allMuscleGroups, equipmentProfile: equipmentProfile)
        }

        let availableNames = Set(allMuscleGroups.flatMap { group in
            group.exercises.map { $0.name.lowercased() }
        })

        let frequentLower = Set(prefs.frequentlyUsedExercises.map { $0.lowercased() })

        // Scan variation names; return the first that is frequently used AND available AND compatible.
        for variation in canonical.variationNames {
            let lower = variation.lowercased()
            guard availableNames.contains(lower) else { continue }
            guard isLikelyCompatible(variation, with: equipmentProfile) else { continue }
            guard frequentLower.contains(lower) else { continue }
            return allMuscleGroups
                .flatMap { $0.exercises }
                .first(where: { $0.name.lowercased() == lower })?
                .name
        }

        return bestAnchorName(for: canonical, allMuscleGroups: allMuscleGroups, equipmentProfile: equipmentProfile)
    }

    private func bestAnchorName(
        for canonical: CanonicalLift,
        allMuscleGroups: [MuscleGroup],
        equipmentProfile: SuggestMeSomeEquipmentProfile
    ) -> String? {
        let availableNames = Set(allMuscleGroups.flatMap { group in
            group.exercises.map { $0.name.lowercased() }
        })

        for variation in canonical.variationNames {
            let lower = variation.lowercased()
            guard availableNames.contains(lower) else { continue }
            guard isLikelyCompatible(variation, with: equipmentProfile) else { continue }
            return allMuscleGroups
                .flatMap { $0.exercises }
                .first(where: { $0.name.lowercased() == lower })?
                .name
        }

        return nil
    }

    private func fallbackAnchors(
        _ preferred: [String],
        allMuscleGroups: [MuscleGroup],
        equipmentProfile: SuggestMeSomeEquipmentProfile
    ) -> [String] {
        let available = allMuscleGroups.flatMap { $0.exercises.map(\.name) }
        var chosen: [String] = []

        for name in preferred {
            guard available.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            guard isLikelyCompatible(name, with: equipmentProfile) else { continue }
            chosen.append(name)
        }

        if chosen.isEmpty, equipmentProfile == .bodyweightOnly {
            let bodyweightFallback = ["Push-ups", "Plank", "Crunches", "Dead Bug", "Bird Dog"]
            for name in bodyweightFallback where available.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                chosen.append(name)
            }
        }

        return uniquePreservingOrder(chosen)
    }

    private func isLikelyCompatible(_ exerciseName: String, with profile: SuggestMeSomeEquipmentProfile) -> Bool {
        let lower = exerciseName.lowercased()

        let needsBarbell = lower.contains("barbell") || lower.contains("squat") || lower.contains("deadlift") || lower.contains("strict press")
        let needsCable = lower.contains("cable")
        let needsMachine = lower.contains("machine") || lower.contains("leg press") || lower.contains("stairmaster")
        let needsDumbbell = lower.contains("dumbbell") || lower.hasPrefix("db ")
        let isBodyweight = lower.contains("push-up") || lower.contains("plank") || lower.contains("crunch") || lower.contains("bird dog") || lower.contains("dead bug") || lower.contains("dip") || lower.contains("pull-up") || lower.contains("chin-up")

        switch profile {
        case .fullGym:
            return true
        case .homeGym:
            return !needsCable && !needsMachine
        case .dumbbellsOnly:
            return (needsDumbbell || isBodyweight || lower.contains("jump rope")) && !needsBarbell
        case .barbellRackOnly:
            return needsBarbell || isBodyweight || lower.contains("bench press")
        case .hotelGym:
            return !needsBarbell
        case .bodyweightOnly:
            return isBodyweight || lower.contains("jump rope")
        }
    }

    private func recommendationTitle(mode: SuggestMeSomeSessionMode, goal: SuggestMeSomeGenerationGoal) -> String {
        // Avoid redundant "Recovery · Recovery" or "Conditioning · Conditioning" labels.
        if mode.title == goal.title { return mode.title }
        return "\(mode.title) · \(goal.title)"
    }

    private func summaryText(
        mode: SuggestMeSomeSessionMode,
        overlapCount: Int,
        blockedLifts: Set<CanonicalLift>,
        hasProgramConflict: Bool,
        durationMinutes: Int,
        buildable: Bool,
        coachContext: SuggestMeSomeCoachContext? = nil
    ) -> String {
        guard buildable else {
            return "Increase the duration to at least 20 minutes to build a session from this recommendation."
        }

        var parts: [String] = []

        // Pain/discomfort — highest priority, always surfaces first.
        if coachContext?.hasPainOrDiscomfort == true {
            parts.append("Pain or discomfort flagged — today's session is conservative to protect recovery.")
        }

        // Fatigue signal.
        if let fatigue = coachContext?.fatigueStatus {
            switch fatigue {
            case .critical:
                parts.append("Critical fatigue detected — intensity is capped to protect your training capacity.")
            case .high:
                parts.append("High fatigue from recent training — volume and intensity are reduced today.")
            case .elevated:
                parts.append("Elevated fatigue from recent training — a conservative session is recommended.")
            default:
                break
            }
        }

        // Readiness.
        if let tier = coachContext?.readinessTier, tier == .low, coachContext?.hasPainOrDiscomfort != true {
            parts.append("Today's readiness check-in shows low energy or high stress — keeping intensity conservative.")
        }

        // Active overlay.
        if let overlays = coachContext?.activeOverlaySummaries, !overlays.isEmpty {
            parts.append("Coach-approved adjustment is active: \(overlays.first!).")
        }

        // HealthKit caution — medium signal, never overrides manual flags.
        if let hk = coachContext?.objectiveRecoveryInsight, hk.status == .caution {
            parts.append("Apple Health recovery data suggests caution — intensity nudged down by one step.")
        }

        if !blockedLifts.isEmpty {
            let liftLabel = blockedLifts.map(\.displayName).sorted().joined(separator: " and ")
            parts.append("Recent hard \(liftLabel) exposure — steering away from high-intensity work on \(blockedLifts.count == 1 ? "it" : "these") today.")
        }

        if overlapCount >= 2 {
            parts.append("Your last session covered similar muscle groups, so today's volume is kept recovery-friendly.")
        }

        if hasProgramConflict {
            parts.append("This recommendation avoids redundant overlap with your active training program.")
        }

        if parts.isEmpty {
            switch mode {
            case .recovery:
                return "A light session to maintain movement quality and let hard-worked muscles recover."
            case .conditioning:
                return "A conditioning session to raise your heart rate and build metabolic fitness."
            case .fullBody:
                return "A balanced session covering all major muscle groups."
            case .upper:
                return "An upper-body session emphasizing horizontal push, pull, and vertical press patterns."
            case .lower:
                return "A lower-body session centered on knee-dominant and hip-hinge patterns."
            case .push:
                return "A pressing session targeting chest, shoulders, and triceps."
            case .pull:
                return "A pulling session targeting back, rear delts, and biceps."
            case .armsShoulders:
                return "A focused session for shoulder and arm development."
            case .surpriseMe:
                return "A mixed session selected based on your current training context."
            }
        }

        return parts.joined(separator: " ")
    }

    private func rationaleText(
        configuredMode: SuggestMeSomeSessionMode,
        finalMode: SuggestMeSomeSessionMode,
        goal: SuggestMeSomeGenerationGoal,
        equipmentProfile: SuggestMeSomeEquipmentProfile,
        adjustedIntensity: Int,
        blockedLifts: Set<CanonicalLift>,
        overlapCount: Int,
        programConflictReason: String?,
        coachContext: SuggestMeSomeCoachContext? = nil
    ) -> String {
        var reasons: [String] = []

        if finalMode != configuredMode {
            reasons.append("Session shifted from \(configuredMode.title) to \(finalMode.title) to reduce near-term fatigue conflict.")
        } else {
            reasons.append("\(finalMode.title) recommended for your \(goal.title.lowercased()) goal at intensity \(adjustedIntensity).")
        }

        if !blockedLifts.isEmpty {
            let blocked = blockedLifts.map(\.displayName).sorted().joined(separator: " and ")
            reasons.append("Recent hard exposure on \(blocked) — avoided in today's anchor selection.")
        }

        if overlapCount >= 2 {
            reasons.append("Recent history shows substantial muscle overlap within 48 hours.")
        }

        if let programConflictReason {
            reasons.append(programConflictReason)
        }

        if let ctx = coachContext {
            if ctx.hasPainOrDiscomfort {
                reasons.append("Pain or discomfort flagged — intensity capped to 1 and recovery mode forced.")
            }

            if let fatigue = ctx.fatigueStatus {
                switch fatigue {
                case .critical:
                    reasons.append("Critical fatigue status from weekly analysis — intensity hard-capped at 1.")
                case .high:
                    reasons.append("High fatigue status from weekly analysis — intensity hard-capped at 2.")
                case .elevated:
                    reasons.append("Elevated fatigue from weekly analysis — intensity capped at 3.")
                default:
                    break
                }
            }

            if let tier = ctx.readinessTier, tier == .low {
                reasons.append("Low readiness tier from today's check-in — intensity kept at or below 3.")
            }

            if let hk = ctx.objectiveRecoveryInsight, hk.status == .caution {
                reasons.append("Apple Health recovery caution (\(hk.compactSummary)) — intensity nudged down 1 step.")
            }

            if !ctx.activeOverlaySummaries.isEmpty {
                reasons.append("Active coach overlay in effect — session shaped around existing approved adjustments.")
            }

            if ctx.pendingProposals.contains(where: { $0.proposalType == .deload }) {
                reasons.append("Pending deload proposal — biasing session conservative ahead of planned deload.")
            }

            if let prefs = ctx.exercisePreferences, !prefs.frequentlyUsedExercises.isEmpty {
                reasons.append("Anchor lifts biased toward your frequently-trained exercise patterns.")
            }
        }

        return reasons.joined(separator: " ")
    }

    private func buildReasonChips(
        equipmentProfile: SuggestMeSomeEquipmentProfile,
        durationMinutes: Int,
        adjustedIntensity: Int,
        configuredMode: SuggestMeSomeSessionMode,
        finalMode: SuggestMeSomeSessionMode,
        blockedLifts: Set<CanonicalLift>,
        overlapCount: Int,
        hasProgramConflict: Bool,
        coachContext: SuggestMeSomeCoachContext? = nil
    ) -> [String] {
        var chips: [String] = []

        chips.append(equipmentProfile.title)
        chips.append("\(durationMinutes) min")
        chips.append("Intensity \(adjustedIntensity)")

        if finalMode != configuredMode {
            chips.append("Mode adjusted")
        }

        for lift in blockedLifts.map(\.displayName).sorted() {
            chips.append("\(lift) avoided")
        }

        if overlapCount >= 2 {
            chips.append("High recent overlap")
        }

        if hasProgramConflict {
            chips.append("Program-aware")
        }

        // Coach context chips — each one maps to an explicit decision factor.
        if let ctx = coachContext {
            if ctx.hasPainOrDiscomfort {
                chips.append("Pain override")
            }

            if let fatigue = ctx.fatigueStatus {
                switch fatigue {
                case .critical: chips.append("Critical fatigue")
                case .high:     chips.append("High fatigue")
                case .elevated: chips.append("Elevated fatigue")
                default:        break
                }
            }

            if let tier = ctx.readinessTier, tier == .low {
                chips.append("Low readiness")
            }

            if !ctx.activeOverlaySummaries.isEmpty {
                chips.append("Overlay active")
            }

            if ctx.pendingProposals.contains(where: { $0.proposalType == .deload }) {
                chips.append("Deload proposed")
            }

            if let hk = ctx.objectiveRecoveryInsight, hk.status == .caution {
                chips.append("Apple Health nudge")
            }

            if let prefs = ctx.exercisePreferences, !prefs.frequentlyUsedExercises.isEmpty {
                chips.append("Preference-biased")
            }
        }

        return chips
    }

    private func buildContinuitySummary(
        recentWorkouts: [Workout],
        activeRun: ProgramRun?,
        finalMode: SuggestMeSomeSessionMode,
        durationMinutes: Int,
        equipmentProfile: SuggestMeSomeEquipmentProfile,
        overlapCount: Int,
        blockedLifts: Set<CanonicalLift>,
        coachContext: SuggestMeSomeCoachContext?
    ) -> String {
        let latestStandalone = recentWorkouts.first(where: { $0.programRun == nil })
        let hoursSince = latestStandalone.map { max(0, Int(Date().timeIntervalSince($0.date) / 3600)) }
        var parts: [String] = []

        if activeRun != nil {
            parts.append("Active program context is present; SuggestMeSome is following that broader training continuity.")
        } else if let hoursSince {
            let timeLabel: String
            if hoursSince < 24 {
                timeLabel = "within the last 24 hours"
            } else {
                let days = max(1, hoursSince / 24)
                timeLabel = "\(days) day\(days == 1 ? "" : "s") ago"
            }
            parts.append("Last standalone session was \(timeLabel).")
        } else {
            parts.append("No recent standalone session found, so continuity is based on your current setup inputs.")
        }

        if !blockedLifts.isEmpty {
            let blocked = blockedLifts.map(\.displayName).sorted().joined(separator: " and ")
            parts.append("Recent heavy exposure on \(blocked) is being de-emphasized to avoid immediate repeat stress.")
        } else if overlapCount >= 2 {
            parts.append("Recent muscle-group overlap is high, so today's plan leans recovery-aware.")
        } else {
            parts.append("Recent overlap is manageable, so the recommendation keeps normal progression intent.")
        }

        if let fatigue = coachContext?.fatigueStatus, fatigue == .elevated || fatigue == .high || fatigue == .critical {
            parts.append("Current fatigue status reinforced a conservative mode/intensity choice.")
        }

        parts.append("Session shape is constrained to \(durationMinutes) minutes with \(equipmentProfile.title.lowercased()) compatibility.")
        parts.append("Recommended mode today: \(finalMode.title).")
        return parts.joined(separator: " ")
    }

    private func buildNextActionGuidance(
        finalMode: SuggestMeSomeSessionMode,
        buildable: Bool,
        durationMinutes: Int,
        activeRun: ProgramRun?,
        coachContext: SuggestMeSomeCoachContext?
    ) -> String {
        guard buildable else {
            return "Increase duration to at least 20 minutes, then rebuild this recommendation."
        }

        if coachContext?.hasPainOrDiscomfort == true {
            return "Build a light recovery session only, then log pain-safe movement outcomes before your next recommendation."
        }

        let path: String
        switch finalMode {
        case .recovery:
            path = "Build a low-stress recovery session and keep intensity controlled."
        case .conditioning:
            path = "Build a short conditioning-focused session and keep pacing consistent."
        default:
            path = "Build this session, then log effort feedback to decide whether to progress or downshift next time."
        }

        if activeRun != nil {
            return "\(path) Keep it aligned with your active program sequence."
        }
        return "\(path) If the session runs long, reduce accessory volume first to stay inside \(durationMinutes) minutes."
    }

    // MARK: - Utility helpers

    private func stableHash(_ text: String) -> Int {
        var hash = 5381
        for scalar in text.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
        return abs(hash)
    }

    private func uniquePreservingOrder<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var output: [T] = []
        for value in values where !seen.contains(value) {
            output.append(value)
            seen.insert(value)
        }
        return output
    }

    private func musclesForExerciseName(_ exerciseName: String, allMuscleGroups: [MuscleGroup]) -> Set<String> {
        for group in allMuscleGroups {
            if group.exercises.contains(where: { $0.name.caseInsensitiveCompare(exerciseName) == .orderedSame }) {
                return [group.name]
            }
        }

        if let canonical = CanonicalLift.from(exerciseName: exerciseName) {
            return defaultMuscleNames(for: canonical)
        }

        return []
    }

    private func defaultMuscleNames(for canonical: CanonicalLift) -> Set<String> {
        switch canonical {
        case .bench:
            return ["Chest", "Shoulders", "Arms"]
        case .squat:
            return ["Legs", "Core"]
        case .deadlift:
            return ["Back", "Legs", "Core"]
        case .overheadPress:
            return ["Shoulders", "Arms", "Chest"]
        }
    }
}
