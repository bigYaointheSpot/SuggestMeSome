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
        allMuscleGroups: [MuscleGroup]
    ) -> SuggestMeSomeSessionRecommendation {
        let recentWorkouts = fetchRecentWorkouts(limit: 24)
        let activeRun = fetchMostRecentActiveRun()

        let resolvedMode = resolveMode(configuration.mode, configuration: configuration, recentWorkouts: recentWorkouts)
        let adjustedIntensity = adjustedIntensity(for: configuration, resolvedMode: resolvedMode)

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

        let shouldBiasRecovery = (overlapCount >= 2 && adjustedIntensity >= 4) || !blockedLifts.isEmpty || programConflict.hasConflict
        let finalMode = adjustedMode(
            baseMode: resolvedMode,
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
            equipmentProfile: configuration.equipmentProfile
        )

        let anchorLifts = candidateAnchorLifts(
            mode: finalMode,
            allMuscleGroups: allMuscleGroups,
            blockedLifts: blockedLifts,
            equipmentProfile: configuration.equipmentProfile
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
            equipmentProfile: configuration.equipmentProfile
        ) : nil

        return SuggestMeSomeSessionRecommendation(
            title: recommendationTitle(mode: finalMode, goal: finalGoal),
            summary: summaryText(
                mode: finalMode,
                overlapCount: overlapCount,
                blockedLifts: blockedLifts,
                hasProgramConflict: programConflict.hasConflict,
                durationMinutes: configuration.durationMinutes,
                buildable: buildable
            ),
            rationale: rationaleText(
                configuredMode: configuration.mode,
                finalMode: finalMode,
                goal: finalGoal,
                equipmentProfile: configuration.equipmentProfile,
                adjustedIntensity: adjustedIntensity,
                blockedLifts: blockedLifts,
                overlapCount: overlapCount,
                programConflictReason: programConflict.reason
            ),
            mode: finalMode,
            goal: finalGoal,
            recommendedMovementPriorities: movementPriorities,
            candidateExerciseFamilies: candidateFamilies,
            candidateAnchorLifts: anchorLifts,
            isBuildableIntoWorkout: buildable,
            request: request
        )
    }

    // MARK: - Query helpers

    private func fetchRecentWorkouts(limit: Int) -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\Workout.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return Array(all.prefix(max(1, limit)))
    }

    private func fetchMostRecentActiveRun() -> ProgramRun? {
        let descriptor = FetchDescriptor<ProgramRun>(
            predicate: #Predicate<ProgramRun> { !$0.isCompleted },
            sortBy: [SortDescriptor(\ProgramRun.startDate, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
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
        equipmentProfile: SuggestMeSomeEquipmentProfile
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

        return uniquePreservingOrder(families)
    }

    private func candidateAnchorLifts(
        mode: SuggestMeSomeSessionMode,
        allMuscleGroups: [MuscleGroup],
        blockedLifts: Set<CanonicalLift>,
        equipmentProfile: SuggestMeSomeEquipmentProfile
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
            bestAnchorName(for: $0, allMuscleGroups: allMuscleGroups, equipmentProfile: equipmentProfile)
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
        "\(mode.title) · \(goal.title)"
    }

    private func summaryText(
        mode: SuggestMeSomeSessionMode,
        overlapCount: Int,
        blockedLifts: Set<CanonicalLift>,
        hasProgramConflict: Bool,
        durationMinutes: Int,
        buildable: Bool
    ) -> String {
        guard buildable else {
            return "At least 20 minutes is required to build a quality session from this recommendation."
        }

        var parts: [String] = ["\(durationMinutes)-minute \(mode.title.lowercased()) recommendation."]

        if !blockedLifts.isEmpty {
            let liftLabel = blockedLifts.map(\.displayName).sorted().joined(separator: ", ")
            parts.append("Avoiding heavy \(liftLabel) due to recent hard exposure.")
        }

        if overlapCount >= 2 {
            parts.append("Recent muscle overlap is high, so volume is biased toward recovery-friendly choices.")
        }

        if hasProgramConflict {
            parts.append("Active program context suggests avoiding obvious redundant overlap today.")
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
        programConflictReason: String?
    ) -> String {
        var reasons: [String] = [
            "Inputs: mode \(configuredMode.title), goal \(goal.title), equipment \(equipmentProfile.title), intensity \(adjustedIntensity)."
        ]

        if finalMode != configuredMode {
            reasons.append("Mode shifted to \(finalMode.title) to reduce near-term fatigue conflict.")
        }

        if !blockedLifts.isEmpty {
            let blocked = blockedLifts.map(\.displayName).sorted().joined(separator: ", ")
            reasons.append("Heavy \(blocked) exposure was detected in recent workouts.")
        }

        if overlapCount >= 2 {
            reasons.append("Recent exercise history shows substantial muscle overlap within 48 hours.")
        }

        if let programConflictReason {
            reasons.append(programConflictReason)
        }

        return reasons.joined(separator: " ")
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
