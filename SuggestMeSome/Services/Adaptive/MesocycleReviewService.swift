//
//  MesocycleReviewService.swift
//  SuggestMeSome
//
//  Feature 13 — Deterministic payoff-layer analytics for completed blocks.
//

import Foundation

enum MesocycleReviewService {
    static func isEligible(for run: ProgramRun) -> Bool {
        run.isCompleted
    }

    static func relevantStandaloneWorkouts(
        for run: ProgramRun,
        in allWorkouts: [Workout]
    ) -> [Workout] {
        let programWorkouts = allWorkouts.filter { $0.programRun?.id == run.id }
        let endDate = resolvedEndDate(
            run: run,
            programWorkouts: programWorkouts,
            standaloneWorkouts: []
        )

        return allWorkouts
            .filter {
                $0.programRun == nil &&
                $0.date >= run.startDate &&
                $0.date <= endDate
            }
            .sorted { $0.date < $1.date }
    }

    static func buildReview(
        for run: ProgramRun,
        allWorkouts: [Workout],
        personalRecords: [PersonalRecord] = []
    ) -> MesocycleReviewSnapshot {
        let programWorkouts = allWorkouts
            .filter { $0.programRun?.id == run.id }
            .sorted { $0.date < $1.date }
        let standaloneWorkouts = relevantStandaloneWorkouts(for: run, in: allWorkouts)
        return buildReview(
            for: run,
            programWorkouts: programWorkouts,
            standaloneWorkouts: standaloneWorkouts,
            personalRecords: personalRecords
        )
    }

    static func buildReview(
        for run: ProgramRun,
        programWorkouts: [Workout],
        standaloneWorkouts: [Workout],
        personalRecords: [PersonalRecord] = []
    ) -> MesocycleReviewSnapshot {
        let sortedProgramWorkouts = programWorkouts.sorted { $0.date < $1.date }
        let sortedStandaloneWorkouts = standaloneWorkouts.sorted { $0.date < $1.date }
        let endDate = resolvedEndDate(
            run: run,
            programWorkouts: sortedProgramWorkouts,
            standaloneWorkouts: sortedStandaloneWorkouts
        )
        let focus = inferredFocus(for: run.program)
        let inferredLevel = inferredLevel(for: run.program)

        let sessionSummary = plannedVsCompletedSessions(
            for: run,
            programWorkouts: sortedProgramWorkouts
        )
        let adherence = adherencePercentage(sessionSummary: sessionSummary)
        let workoutSummary = workoutDurationSummary(
            programWorkouts: sortedProgramWorkouts,
            standaloneWorkouts: sortedStandaloneWorkouts
        )
        let prSummary = personalRecordSummary(
            workouts: sortedProgramWorkouts + sortedStandaloneWorkouts,
            personalRecords: personalRecords,
            startDate: run.startDate,
            endDate: endDate
        )
        let exerciseConsistency = exerciseConsistencySummary(programWorkouts: sortedProgramWorkouts)
        let standaloneInfluence = standaloneWorkoutInfluenceSummary(
            standaloneWorkouts: sortedStandaloneWorkouts
        )
        let liftHighlights = liftHighlights(
            workouts: sortedProgramWorkouts + sortedStandaloneWorkouts
        )
        let frictionSignals = buildFrictionSignals(
            run: run,
            sessionSummary: sessionSummary,
            programWorkouts: sortedProgramWorkouts,
            standaloneWorkouts: sortedStandaloneWorkouts
        )
        let performanceHighlights = buildPerformanceHighlights(
            adherencePercentage: adherence,
            prSummary: prSummary,
            exerciseConsistency: exerciseConsistency,
            liftHighlights: liftHighlights,
            standaloneInfluence: standaloneInfluence
        )
        let phaseRecap = buildPhaseRecap(
            for: run,
            sessionSummary: sessionSummary,
            programWorkouts: sortedProgramWorkouts
        )
        let movementPatterns = movementPatternCounts(
            workouts: sortedProgramWorkouts + sortedStandaloneWorkouts
        )

        let headlineMetrics = MesocycleHeadlineMetrics(
            sessionSummary: sessionSummary,
            adherencePercentage: adherence,
            workoutSummary: workoutSummary,
            personalRecordSummary: prSummary,
            exerciseConsistencySummary: exerciseConsistency
        )

        let recommendationInput = MesocycleRecommendationInputPayload(
            programRunStableID: run.resolvedSyncStableID,
            trainingProgramStableID: run.program?.resolvedSyncStableID,
            currentFocus: focus,
            inferredCurrentLevel: inferredLevel,
            progressionModel: run.program?.progressionModel,
            sessionSummary: sessionSummary,
            workoutSummary: workoutSummary,
            personalRecordSummary: prSummary,
            exerciseConsistencySummary: exerciseConsistency,
            liftHighlights: liftHighlights,
            movementPatterns: movementPatterns,
            standaloneInfluence: standaloneInfluence,
            frictionSignalKinds: frictionSignals.map(\.kind)
        )

        let recommendations = NextBlockRecommendationEngine.rankedRecommendations(
            input: recommendationInput,
            currentDurationWeeks: run.program?.lengthInWeeks ?? 6,
            currentSessionsPerWeek: run.program?.sessionsPerWeek ?? 3,
            completionEndDate: endDate,
            personalRecords: personalRecords,
            workoutsInWindow: sortedProgramWorkouts + sortedStandaloneWorkouts,
            continuitySnapshot: run.continuitySnapshot
        )

        let defaultPrefill = recommendations.first(where: \.isPrimaryRecommendation)?.prefill ?? recommendations.first?.prefill ?? NextBlockRecommendationEngine.fallbackPrefill(
            runStableID: run.resolvedSyncStableID,
            recommendationStableID: nil,
            focus: focus ?? .generalFitness,
            level: inferredLevel,
            durationWeeks: run.program?.lengthInWeeks ?? 6,
            sessionsPerWeek: run.program?.sessionsPerWeek ?? 3,
            endDate: endDate,
            personalRecords: personalRecords,
            workoutsInWindow: sortedProgramWorkouts + sortedStandaloneWorkouts,
            note: "Fallback prefill built from the completed block snapshot.",
            input: recommendationInput,
            steeringProfile: run.continuitySnapshot?.latestConfirmedSteeringProfile
        )

        return MesocycleReviewSnapshot(
            reviewStableID: "\(run.resolvedSyncStableID)::mesocycle-review",
            programRunStableID: run.resolvedSyncStableID,
            trainingProgramStableID: run.program?.resolvedSyncStableID,
            programName: run.program?.name ?? "Completed Block",
            focus: focus,
            focusDisplayName: focus.map { FocusTemplateLibrary.template(for: $0).displayName },
            inferredCurrentLevel: inferredLevel,
            progressionModel: run.program?.progressionModel,
            startDate: run.startDate,
            endDate: endDate,
            headlineMetrics: headlineMetrics,
            performanceHighlights: performanceHighlights,
            frictionSignals: frictionSignals,
            narrativeSummary: buildNarrativeSummary(
                programName: run.program?.name ?? "This block",
                headlineMetrics: headlineMetrics,
                performanceHighlights: performanceHighlights,
                frictionSignals: frictionSignals,
                standaloneInfluence: standaloneInfluence,
                liftHighlights: liftHighlights
            ),
            phaseRecap: phaseRecap,
            standaloneInfluence: standaloneInfluence,
            recommendationInput: recommendationInput,
            rankedRecommendations: recommendations,
            defaultNextBlockPrefill: defaultPrefill
        )
    }

    static func plannedVsCompletedSessions(
        for run: ProgramRun,
        programWorkouts: [Workout]
    ) -> MesocycleSessionCompletionSummary {
        let plannedSessions = {
            guard let program = run.program else { return max(programWorkouts.count, 0) }
            return max(0, program.lengthInWeeks * program.sessionsPerWeek)
        }()

        let sessionKeys = programWorkouts.compactMap { workout -> ProgramSessionCompletionKey? in
            guard
                let weekNumber = workout.programWeekNumber,
                let sessionNumber = workout.programSessionNumber
            else {
                return nil
            }
            return ProgramSessionCompletionKey(
                weekNumber: weekNumber,
                sessionNumber: sessionNumber
            )
        }

        let uniqueCompletedSessions: Int
        let duplicateWorkoutCount: Int
        if sessionKeys.isEmpty {
            uniqueCompletedSessions = programWorkouts.count
            duplicateWorkoutCount = 0
        } else {
            let uniqueKeys = Set(sessionKeys)
            uniqueCompletedSessions = uniqueKeys.count
            duplicateWorkoutCount = max(0, programWorkouts.count - uniqueKeys.count)
        }

        let completedSessions = plannedSessions > 0
            ? min(plannedSessions, uniqueCompletedSessions)
            : uniqueCompletedSessions

        return MesocycleSessionCompletionSummary(
            plannedSessions: plannedSessions,
            completedSessions: completedSessions,
            uniqueCompletedSessions: uniqueCompletedSessions,
            duplicateWorkoutCount: duplicateWorkoutCount,
            missedSessions: max(0, plannedSessions - completedSessions)
        )
    }

    static func adherencePercentage(
        sessionSummary: MesocycleSessionCompletionSummary
    ) -> Int {
        guard sessionSummary.plannedSessions > 0 else {
            return sessionSummary.completedSessions > 0 ? 100 : 0
        }

        let percentage = (Double(sessionSummary.completedSessions) / Double(sessionSummary.plannedSessions)) * 100
        return Int(percentage.rounded())
    }

    static func workoutDurationSummary(
        programWorkouts: [Workout],
        standaloneWorkouts: [Workout]
    ) -> MesocycleWorkoutDurationSummary {
        let totalWorkoutCount = programWorkouts.count + standaloneWorkouts.count
        let totalDurationSeconds = (programWorkouts + standaloneWorkouts)
            .map(\.durationSeconds)
            .reduce(0, +)
        let averageDuration = totalWorkoutCount > 0
            ? Int((Double(totalDurationSeconds) / Double(totalWorkoutCount)).rounded())
            : 0

        return MesocycleWorkoutDurationSummary(
            programWorkoutCount: programWorkouts.count,
            standaloneWorkoutCount: standaloneWorkouts.count,
            totalWorkoutCount: totalWorkoutCount,
            totalDurationSeconds: totalDurationSeconds,
            averageDurationSeconds: averageDuration
        )
    }

    static func personalRecordSummary(
        workouts: [Workout],
        personalRecords: [PersonalRecord],
        startDate: Date,
        endDate: Date
    ) -> MesocyclePersonalRecordSummary {
        let prSetPairs = workouts.flatMap { workout in
            workout.exerciseEntries.flatMap { entry in
                entry.sets.compactMap { set -> (exerciseName: String, date: Date)? in
                    guard set.isPR else { return nil }
                    return (exerciseName: entry.exerciseName, date: workout.date)
                }
            }
        }

        let recordExercises = personalRecords
            .filter { $0.dateAchieved >= startDate && $0.dateAchieved <= endDate }
            .map(\.exerciseName)

        let notableExercises = Array(
            Set(prSetPairs.map(\.exerciseName) + recordExercises)
        )
        .sorted()

        let achievedSetCount = prSetPairs.isEmpty
            ? personalRecords.filter {
                $0.dateAchieved >= startDate && $0.dateAchieved <= endDate
            }.count
            : prSetPairs.count

        return MesocyclePersonalRecordSummary(
            achievedSetCount: achievedSetCount,
            uniqueExerciseCount: notableExercises.count,
            notableExercises: Array(notableExercises.prefix(3))
        )
    }

    static func exerciseConsistencySummary(
        programWorkouts: [Workout]
    ) -> MesocycleExerciseConsistencySummary {
        guard !programWorkouts.isEmpty else {
            return MesocycleExerciseConsistencySummary(
                repeatedExerciseCount: 0,
                anchorExercises: [],
                summaryText: "No program workouts were logged, so exercise consistency is unavailable."
            )
        }

        let workoutCount = programWorkouts.count
        var counts: [String: Int] = [:]

        for workout in programWorkouts {
            let exerciseNames = Set(
                workout.exerciseEntries
                    .filter { !$0.isCardio }
                    .map(\.exerciseName)
            )
            for exerciseName in exerciseNames {
                counts[exerciseName, default: 0] += 1
            }
        }

        let repeated = counts
            .filter { $0.value >= 2 }
            .map { exerciseName, count in
                MesocycleExerciseFrequency(
                    exerciseName: exerciseName,
                    workoutCount: count,
                    appearancePercentage: Int(
                        (Double(count) / Double(workoutCount) * 100).rounded()
                    )
                )
            }
            .sorted {
                if $0.workoutCount == $1.workoutCount {
                    return $0.exerciseName < $1.exerciseName
                }
                return $0.workoutCount > $1.workoutCount
            }

        let anchors = repeated.filter {
            $0.workoutCount >= max(2, Int(ceil(Double(workoutCount) * 0.5)))
        }

        let summaryText: String
        if anchors.isEmpty {
            summaryText = "Exercise selection rotated often, so there were few repeat anchors across the block."
        } else {
            let names = anchors.prefix(3).map(\.exerciseName).joined(separator: ", ")
            summaryText = "The block stayed anchored around \(names), which kept week-to-week continuity visible."
        }

        return MesocycleExerciseConsistencySummary(
            repeatedExerciseCount: repeated.count,
            anchorExercises: Array(anchors.prefix(3)),
            summaryText: summaryText
        )
    }

    static func standaloneWorkoutInfluenceSummary(
        standaloneWorkouts: [Workout]
    ) -> MesocycleStandaloneWorkoutInfluenceSummary {
        let totalDuration = standaloneWorkouts.map(\.durationSeconds).reduce(0, +)
        let dominantPatterns = Array(
            movementPatternCounts(workouts: standaloneWorkouts).prefix(3)
        )

        let summaryText: String
        if standaloneWorkouts.isEmpty {
            summaryText = "No standalone workouts were included, so the review reflects program sessions only."
        } else {
            summaryText = "\(standaloneWorkouts.count) standalone workout\(standaloneWorkouts.count == 1 ? "" : "s") inside the block window were counted as supporting context for workload and movement continuity."
        }

        return MesocycleStandaloneWorkoutInfluenceSummary(
            includedWorkoutCount: standaloneWorkouts.count,
            totalDurationSeconds: totalDuration,
            dominantPatterns: dominantPatterns,
            summaryText: summaryText,
            influencePolicyText: "Standalone workouts influence continuity, workload, and movement-pattern context, but they do not increase planned-session adherence."
        )
    }

    static func liftHighlights(
        workouts: [Workout]
    ) -> [MesocycleLiftHighlight] {
        let sortedWorkouts = workouts.sorted { $0.date < $1.date }

        return CanonicalLift.allCases.compactMap { lift in
            let signals = sortedWorkouts.compactMap { workout -> LiftWorkoutSignal? in
                let bestEstimatedOneRepMax = workout.exerciseEntries
                    .filter { CanonicalLift.from(exerciseName: $0.exerciseName) == lift }
                    .compactMap { entry -> Double? in
                        entry.sets
                            .filter { $0.reps > 0 && $0.weight > 0 }
                            .map { estimatedOneRepMax(weightLbs: inLbs($0.weight, unit: entry.unit), reps: $0.reps) }
                            .max()
                    }
                    .max()

                guard let bestEstimatedOneRepMax else { return nil }

                return LiftWorkoutSignal(
                    estimatedOneRepMaxLbs: bestEstimatedOneRepMax,
                    sourcedFromStandaloneWorkout: workout.programRun == nil
                )
            }

            guard
                let first = signals.first,
                let best = signals.max(by: { $0.estimatedOneRepMaxLbs < $1.estimatedOneRepMaxLbs }),
                signals.count >= 2,
                best.estimatedOneRepMaxLbs > first.estimatedOneRepMaxLbs
            else {
                return nil
            }

            let improvement = ((best.estimatedOneRepMaxLbs - first.estimatedOneRepMaxLbs) / first.estimatedOneRepMaxLbs) * 100
            guard improvement >= 1 else { return nil }

            return MesocycleLiftHighlight(
                liftKey: lift.rawValue,
                displayName: lift.displayName,
                firstEstimatedOneRepMaxLbs: Int(first.estimatedOneRepMaxLbs.rounded()),
                bestEstimatedOneRepMaxLbs: Int(best.estimatedOneRepMaxLbs.rounded()),
                improvementPercentage: Int(improvement.rounded()),
                sourcedFromStandaloneWorkout: best.sourcedFromStandaloneWorkout
            )
        }
        .sorted {
            if $0.improvementPercentage == $1.improvementPercentage {
                return $0.displayName < $1.displayName
            }
            return $0.improvementPercentage > $1.improvementPercentage
        }
    }

    private static func buildPerformanceHighlights(
        adherencePercentage: Int,
        prSummary: MesocyclePersonalRecordSummary,
        exerciseConsistency: MesocycleExerciseConsistencySummary,
        liftHighlights: [MesocycleLiftHighlight],
        standaloneInfluence: MesocycleStandaloneWorkoutInfluenceSummary
    ) -> [MesocyclePerformanceHighlight] {
        var highlights: [MesocyclePerformanceHighlight] = []

        if adherencePercentage >= 85 {
            highlights.append(
                MesocyclePerformanceHighlight(
                    kind: .completion,
                    title: "Adherence held up",
                    detail: "\(adherencePercentage)% of planned sessions were completed during the block."
                )
            )
        }

        if prSummary.achievedSetCount > 0 {
            let exercises = prSummary.notableExercises.joined(separator: ", ")
            let suffix = exercises.isEmpty ? "" : " led by \(exercises)"
            highlights.append(
                MesocyclePerformanceHighlight(
                    kind: .personalRecord,
                    title: "New PRs landed",
                    detail: "\(prSummary.achievedSetCount) PR moments showed up\(suffix)."
                )
            )
        }

        if let topLift = liftHighlights.first {
            highlights.append(
                MesocyclePerformanceHighlight(
                    kind: .liftMomentum,
                    title: "\(topLift.displayName) moved well",
                    detail: "Best estimated 1RM improved by \(topLift.improvementPercentage)% across the block."
                )
            )
        }

        if !exerciseConsistency.anchorExercises.isEmpty {
            let names = exerciseConsistency.anchorExercises.map(\.exerciseName).joined(separator: ", ")
            highlights.append(
                MesocyclePerformanceHighlight(
                    kind: .exerciseConsistency,
                    title: "Exercise continuity stayed clear",
                    detail: "\(names) showed up often enough to give the block a stable backbone."
                )
            )
        }

        if standaloneInfluence.includedWorkoutCount > 0 &&
            standaloneInfluence.includedWorkoutCount <= max(2, exerciseConsistency.anchorExercises.count + 1) {
            highlights.append(
                MesocyclePerformanceHighlight(
                    kind: .standaloneSupport,
                    title: "Standalone work supported the block",
                    detail: standaloneInfluence.summaryText
                )
            )
        }

        return Array(highlights.prefix(4))
    }

    private static func buildFrictionSignals(
        run: ProgramRun,
        sessionSummary: MesocycleSessionCompletionSummary,
        programWorkouts: [Workout],
        standaloneWorkouts: [Workout]
    ) -> [MesocycleFrictionSignal] {
        var signals: [MesocycleFrictionSignal] = []

        if programWorkouts.isEmpty {
            signals.append(
                MesocycleFrictionSignal(
                    kind: .sparseProgramData,
                    severity: .high,
                    title: "Program data is sparse.",
                    detail: "The run ended without any program-linked workouts, so the review can only offer conservative guidance."
                )
            )
        }

        if sessionSummary.missedSessions > 0 {
            let missed = sessionSummary.missedSessions
            let severity: MesocycleSignalSeverity
            switch adherencePercentage(sessionSummary: sessionSummary) {
            case ..<60: severity = .high
            case ..<80: severity = .medium
            default: severity = .low
            }

            signals.append(
                MesocycleFrictionSignal(
                    kind: .missedPlannedSessions,
                    severity: severity,
                    title: "Planned sessions were left on the table.",
                    detail: "\(missed) planned session\(missed == 1 ? "" : "s") were missed before the block ended."
                )
            )
        }

        if sessionSummary.duplicateWorkoutCount > 0 {
            signals.append(
                MesocycleFrictionSignal(
                    kind: .duplicateSessionLogs,
                    severity: .low,
                    title: "Some sessions were logged more than once.",
                    detail: "\(sessionSummary.duplicateWorkoutCount) extra workout log\(sessionSummary.duplicateWorkoutCount == 1 ? "" : "s") mapped onto already-completed sessions."
                )
            )
        }

        if let gapSignal = longestGapSignal(run: run, programWorkouts: programWorkouts) {
            signals.append(gapSignal)
        }

        if standaloneWorkouts.count >= max(2, programWorkouts.count) {
            signals.append(
                MesocycleFrictionSignal(
                    kind: .standaloneDrift,
                    severity: programWorkouts.isEmpty ? .high : .medium,
                    title: "Standalone work pulled attention away from the plan.",
                    detail: "\(standaloneWorkouts.count) standalone workout\(standaloneWorkouts.count == 1 ? "" : "s") were logged during the block window, which suggests the plan may have been harder to stick with than the user’s spontaneous training choices."
                )
            )
        }

        return signals
    }

    private static func longestGapSignal(
        run: ProgramRun,
        programWorkouts: [Workout]
    ) -> MesocycleFrictionSignal? {
        guard programWorkouts.count >= 2 else { return nil }

        let longestGap = zip(programWorkouts, programWorkouts.dropFirst())
            .map { wholeDaysBetween($0.date, $1.date) }
            .max() ?? 0

        let expectedGap = {
            guard let sessionsPerWeek = run.program?.sessionsPerWeek, sessionsPerWeek > 0 else { return 7 }
            return Int(ceil(7.0 / Double(sessionsPerWeek))) + 2
        }()

        guard longestGap > expectedGap else { return nil }

        let severity: MesocycleSignalSeverity = longestGap >= expectedGap + 4 ? .high : .medium
        return MesocycleFrictionSignal(
            kind: .longGapBetweenSessions,
            severity: severity,
            title: "Session spacing drifted wide.",
            detail: "The longest gap between program workouts stretched to \(longestGap) days, which likely diluted block-to-block momentum."
        )
    }

    private static func buildNarrativeSummary(
        programName: String,
        headlineMetrics: MesocycleHeadlineMetrics,
        performanceHighlights: [MesocyclePerformanceHighlight],
        frictionSignals: [MesocycleFrictionSignal],
        standaloneInfluence: MesocycleStandaloneWorkoutInfluenceSummary,
        liftHighlights: [MesocycleLiftHighlight]
    ) -> String {
        var sentences: [String] = []

        let sessionSummary = headlineMetrics.sessionSummary
        sentences.append(
            "\(programName) closed with \(sessionSummary.completedSessions)/\(sessionSummary.plannedSessions) planned sessions completed (\(headlineMetrics.adherencePercentage)% adherence) across \(headlineMetrics.workoutSummary.totalWorkoutCount) total workouts."
        )

        if let prHighlight = performanceHighlights.first(where: { $0.kind == .personalRecord }) {
            sentences.append(prHighlight.detail)
        } else if let liftHighlight = liftHighlights.first {
            sentences.append(
                "\(liftHighlight.displayName) improved by \(liftHighlight.improvementPercentage)% from the first tracked exposure to the best result in the block."
            )
        } else if let consistencyHighlight = performanceHighlights.first(where: { $0.kind == .exerciseConsistency }) {
            sentences.append(consistencyHighlight.detail)
        }

        if let friction = frictionSignals.first {
            sentences.append("\(friction.title) \(friction.detail)")
        } else if standaloneInfluence.includedWorkoutCount > 0 {
            sentences.append(standaloneInfluence.summaryText)
        }

        return sentences.joined(separator: " ")
    }

    private static func buildPhaseRecap(
        for run: ProgramRun,
        sessionSummary: MesocycleSessionCompletionSummary,
        programWorkouts: [Workout]
    ) -> [MesocyclePhaseRecap] {
        guard let program = run.program, !program.weeks.isEmpty else { return [] }

        let sortedWeeks = program.weeks.sorted { $0.weekNumber < $1.weekNumber }
        let completedKeys = Set(programWorkouts.compactMap { workout -> ProgramSessionCompletionKey? in
            guard
                let weekNumber = workout.programWeekNumber,
                let sessionNumber = workout.programSessionNumber
            else {
                return nil
            }
            return ProgramSessionCompletionKey(
                weekNumber: weekNumber,
                sessionNumber: sessionNumber
            )
        })

        var groups: [[ProgramWeekTemplate]] = []
        for week in sortedWeeks {
            guard let lastGroup = groups.last, let lastWeek = lastGroup.last else {
                groups.append([week])
                continue
            }

            if phaseLabel(for: lastWeek, progressionModel: program.progressionModel) ==
                phaseLabel(for: week, progressionModel: program.progressionModel) {
                groups[groups.count - 1].append(week)
            } else {
                groups.append([week])
            }
        }

        let fallbackSessionCount = max(1, program.sessionsPerWeek)

        return groups.compactMap { weeks in
            guard let firstWeek = weeks.first, let lastWeek = weeks.last else { return nil }
            let title = phaseLabel(for: firstWeek, progressionModel: program.progressionModel)
            let plannedCount = weeks.reduce(0) { running, week in
                let sessionCount = week.sessions.isEmpty ? fallbackSessionCount : week.sessions.count
                return running + sessionCount
            }
            let completedCount = completedKeys.filter {
                $0.weekNumber >= firstWeek.weekNumber && $0.weekNumber <= lastWeek.weekNumber
            }.count

            let summaryText: String
            if title == "Deload" {
                summaryText = "Deload weeks covered \(completedCount)/\(plannedCount) planned sessions."
            } else if sessionSummary.plannedSessions == 0 {
                summaryText = "\(title) logged \(completedCount) completed session\(completedCount == 1 ? "" : "s")."
            } else {
                summaryText = "\(title) covered \(completedCount)/\(plannedCount) planned sessions."
            }

            return MesocyclePhaseRecap(
                title: title,
                weekRangeText: weekRangeText(
                    startWeek: firstWeek.weekNumber,
                    endWeek: lastWeek.weekNumber
                ),
                plannedSessionCount: plannedCount,
                completedSessionCount: completedCount,
                summaryText: summaryText
            )
        }
    }

    private static func movementPatternCounts(
        workouts: [Workout]
    ) -> [MesocycleMovementPatternCount] {
        var counts: [ProgramMovementPattern: Int] = [:]

        for workout in workouts {
            let patterns = Set(
                workout.exerciseEntries.flatMap { entry in
                    Array(ProgramExerciseMetadataService.movementPatterns(for: entry.exerciseName))
                }
            )

            for pattern in patterns {
                counts[pattern, default: 0] += 1
            }
        }

        return counts
            .map { pattern, workoutCount in
                MesocycleMovementPatternCount(
                    pattern: pattern,
                    workoutCount: workoutCount
                )
            }
            .sorted {
                if $0.workoutCount == $1.workoutCount {
                    return $0.pattern.rawValue < $1.pattern.rawValue
                }
                return $0.workoutCount > $1.workoutCount
            }
    }

    private static func buildRankedRecommendations(
        input: MesocycleRecommendationInputPayload,
        currentDurationWeeks: Int,
        currentSessionsPerWeek: Int,
        completionEndDate: Date,
        personalRecords: [PersonalRecord],
        workoutsInWindow: [Workout]
    ) -> [MesocycleNextBlockRecommendation] {
        let primaryFocus = primaryRecommendationFocus(input: input)
        let secondaryFocus = secondaryRecommendationFocus(input: input, excluding: primaryFocus)
        let tertiaryFocus = tertiaryRecommendationFocus(input: input, excluding: [primaryFocus, secondaryFocus])

        let primaryKind = primaryRecommendationKind(input: input)
        let conservativeLevel = recommendedLevel(for: primaryKind, currentLevel: input.inferredCurrentLevel)
        let conservativeDuration = recommendedDuration(
            currentDurationWeeks: currentDurationWeeks,
            conservative: primaryKind == .rebuildConsistency || primaryKind == .consolidateFocus
        )
        let conservativeFrequency = recommendedFrequency(
            currentSessionsPerWeek: currentSessionsPerWeek,
            conservative: primaryKind == .rebuildConsistency || primaryKind == .consolidateFocus
        )

        let first = makeRecommendation(
            rank: 1,
            kind: primaryKind,
            focus: primaryFocus,
            title: primaryTitle(kind: primaryKind, focus: primaryFocus),
            summary: primarySummary(kind: primaryKind, focus: primaryFocus, input: input),
            rationale: primaryRationale(kind: primaryKind, focus: primaryFocus, input: input),
            level: conservativeLevel,
            durationWeeks: conservativeDuration,
            sessionsPerWeek: conservativeFrequency,
            input: input,
            completionEndDate: completionEndDate,
            personalRecords: personalRecords,
            workoutsInWindow: workoutsInWindow
        )

        let second = makeRecommendation(
            rank: 2,
            kind: secondaryFocus == .cardioEndurance ? .addConditioningBias : .pivotFocus,
            focus: secondaryFocus,
            title: "Pivot into \(FocusTemplateLibrary.template(for: secondaryFocus).displayName)",
            summary: "Use the last block’s signals to carry momentum into a complementary focus with a clear rationale.",
            rationale: secondaryRationale(focus: secondaryFocus, input: input),
            level: recommendedLevel(for: .pivotFocus, currentLevel: input.inferredCurrentLevel),
            durationWeeks: recommendedDuration(currentDurationWeeks: currentDurationWeeks, conservative: false),
            sessionsPerWeek: recommendedFrequency(currentSessionsPerWeek: currentSessionsPerWeek, conservative: false),
            input: input,
            completionEndDate: completionEndDate,
            personalRecords: personalRecords,
            workoutsInWindow: workoutsInWindow
        )

        let third = makeRecommendation(
            rank: 3,
            kind: tertiaryFocus == .cardioEndurance ? .addConditioningBias : .pivotFocus,
            focus: tertiaryFocus,
            title: "Keep a balanced off-ramp available",
            summary: "A lower-friction alternative stays in the ranked list so the next block can still be edited around recovery, variety, or schedule reality.",
            rationale: tertiaryRationale(focus: tertiaryFocus, input: input),
            level: recommendedLevel(for: .rebuildConsistency, currentLevel: input.inferredCurrentLevel),
            durationWeeks: recommendedDuration(currentDurationWeeks: currentDurationWeeks, conservative: true),
            sessionsPerWeek: recommendedFrequency(currentSessionsPerWeek: currentSessionsPerWeek, conservative: true),
            input: input,
            completionEndDate: completionEndDate,
            personalRecords: personalRecords,
            workoutsInWindow: workoutsInWindow
        )

        return [first, second, third]
    }

    private static func makeRecommendation(
        rank: Int,
        kind: MesocycleNextBlockRecommendationKind,
        focus: ProgramFocus,
        title: String,
        summary: String,
        rationale: [String],
        level: ProgramLevel,
        durationWeeks: Int,
        sessionsPerWeek: Int,
        input: MesocycleRecommendationInputPayload,
        completionEndDate: Date,
        personalRecords: [PersonalRecord],
        workoutsInWindow: [Workout]
    ) -> MesocycleNextBlockRecommendation {
        let stableID = "\(input.programRunStableID)::recommendation::\(rank)::\(focus.rawValue)"
        let prefill = fallbackPrefill(
            runStableID: input.programRunStableID,
            recommendationStableID: stableID,
            focus: focus,
            level: level,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            endDate: completionEndDate,
            personalRecords: personalRecords,
            workoutsInWindow: workoutsInWindow,
            note: rationale.first ?? "Prefilled from the completed block review."
        )

        return MesocycleNextBlockRecommendation(
            stableID: stableID,
            rank: rank,
            kind: kind,
            title: title,
            summary: summary,
            rationale: rationale,
            targetFocus: focus,
            targetFocusDisplayName: FocusTemplateLibrary.template(for: focus).displayName,
            suggestedLevel: level,
            suggestedDurationWeeks: durationWeeks,
            suggestedSessionsPerWeek: sessionsPerWeek,
            decision: .pending,
            prefill: prefill
        )
    }

    private static func primaryRecommendationKind(
        input: MesocycleRecommendationInputPayload
    ) -> MesocycleNextBlockRecommendationKind {
        if input.sessionSummary.completedSessions == 0 || input.sessionSummary.missedSessions >= max(2, input.sessionSummary.plannedSessions / 3) {
            return .rebuildConsistency
        }

        if input.sessionSummary.missedSessions > 0 ||
            input.frictionSignalKinds.contains(.longGapBetweenSessions) {
            return .consolidateFocus
        }

        return .repeatFocus
    }

    private static func primaryRecommendationFocus(
        input: MesocycleRecommendationInputPayload
    ) -> ProgramFocus {
        switch primaryRecommendationKind(input: input) {
        case .repeatFocus, .consolidateFocus:
            return input.currentFocus ?? .generalFitness
        case .rebuildConsistency:
            return consistencyResetFocus(from: input.currentFocus)
        case .pivotFocus, .addConditioningBias:
            return input.currentFocus ?? .generalFitness
        }
    }

    private static func secondaryRecommendationFocus(
        input: MesocycleRecommendationInputPayload,
        excluding primaryFocus: ProgramFocus
    ) -> ProgramFocus {
        let candidate: ProgramFocus
        if input.standaloneInfluence.dominantPatterns.contains(where: { $0.pattern == .conditioning }) &&
            primaryFocus != .cardioEndurance {
            candidate = .cardioEndurance
        } else if let currentFocus = input.currentFocus {
            candidate = adjacentGrowthFocus(from: currentFocus)
        } else {
            candidate = .fullBody
        }

        return distinctRecommendationFocus(
            preferred: [candidate, .fullBody, .generalFitness, .powerbuilding, .bodybuilding],
            excluding: [primaryFocus]
        )
    }

    private static func tertiaryRecommendationFocus(
        input: MesocycleRecommendationInputPayload,
        excluding excluded: [ProgramFocus]
    ) -> ProgramFocus {
        let preferred = balancedFallbackFocus(from: input.currentFocus)
        return distinctRecommendationFocus(
            preferred: [preferred, .generalFitness, .fullBody, .powerbuilding, .cardioEndurance],
            excluding: excluded
        )
    }

    private static func primaryTitle(
        kind: MesocycleNextBlockRecommendationKind,
        focus: ProgramFocus
    ) -> String {
        switch kind {
        case .repeatFocus:
            return "Run the focus back with context"
        case .consolidateFocus:
            return "Keep the focus, smooth the recovery cost"
        case .rebuildConsistency:
            return "Rebuild consistency with \(FocusTemplateLibrary.template(for: focus).displayName)"
        case .pivotFocus:
            return "Pivot into \(FocusTemplateLibrary.template(for: focus).displayName)"
        case .addConditioningBias:
            return "Add a conditioning-biased next block"
        }
    }

    private static func primarySummary(
        kind: MesocycleNextBlockRecommendationKind,
        focus: ProgramFocus,
        input: MesocycleRecommendationInputPayload
    ) -> String {
        switch kind {
        case .repeatFocus:
            return "The block had enough adherence and momentum to justify another run at the same focus, with the finished block prefilled as editable context."
        case .consolidateFocus:
            return "The core focus still fits, but the next version should reduce friction before pushing harder."
        case .rebuildConsistency:
            return "\(FocusTemplateLibrary.template(for: focus).displayName) offers a lower-friction bridge back into structured training."
        case .pivotFocus:
            return "A complementary focus keeps continuity while shifting the emphasis of the next block."
        case .addConditioningBias:
            return "Conditioning showed up enough during the block to deserve a ranked option in the next cycle."
        }
    }

    private static func primaryRationale(
        kind: MesocycleNextBlockRecommendationKind,
        focus: ProgramFocus,
        input: MesocycleRecommendationInputPayload
    ) -> [String] {
        switch kind {
        case .repeatFocus:
            return [
                "\(input.sessionSummary.completedSessions)/\(input.sessionSummary.plannedSessions) planned sessions were completed.",
                "The next block can keep the same focus while starting from editable prefilled context instead of an instant regenerate.",
            ]
        case .consolidateFocus:
            return [
                "The block still points at \(FocusTemplateLibrary.template(for: focus).displayName), but missed sessions or long gaps suggest reducing friction first.",
                "Keeping the same focus preserves continuity without pretending the last block was perfectly absorbed.",
            ]
        case .rebuildConsistency:
            return [
                "The strongest signal is consistency risk, not lack of ambition.",
                "\(FocusTemplateLibrary.template(for: focus).displayName) is ranked first because it is easier to execute cleanly while preserving training momentum.",
            ]
        case .pivotFocus:
            return [
                "A complementary focus lets the next block build on what worked without simply repeating the same workload.",
            ]
        case .addConditioningBias:
            return [
                "Conditioning patterns appeared often enough in standalone work to justify a dedicated next-block option.",
            ]
        }
    }

    private static func secondaryRationale(
        focus: ProgramFocus,
        input: MesocycleRecommendationInputPayload
    ) -> [String] {
        var lines = [
            "This focus gives the next block a different payoff path while still using the finished block as structured context."
        ]

        if let lift = input.liftHighlights.first {
            lines.append("\(lift.displayName) momentum suggests there is still usable training signal to carry forward.")
        } else if input.personalRecordSummary.achievedSetCount > 0 {
            lines.append("New PR activity suggests the block produced enough upside to justify a directional follow-up.")
        }

        if focus == .cardioEndurance {
            lines.append("Standalone conditioning support made a conditioning-biased option worth ranking explicitly.")
        }

        return lines
    }

    private static func tertiaryRationale(
        focus: ProgramFocus,
        input: MesocycleRecommendationInputPayload
    ) -> [String] {
        [
            "A balanced fallback stays ranked so the next block can remain editable if schedule, recovery, or interest changes after review.",
            "\(FocusTemplateLibrary.template(for: focus).displayName) is included as the clearest low-friction alternative to the top-ranked option."
        ]
    }

    private static func recommendedLevel(
        for kind: MesocycleNextBlockRecommendationKind,
        currentLevel: ProgramLevel
    ) -> ProgramLevel {
        switch kind {
        case .repeatFocus, .pivotFocus, .addConditioningBias:
            return currentLevel
        case .consolidateFocus, .rebuildConsistency:
            return stepDownLevel(from: currentLevel)
        }
    }

    private static func recommendedDuration(
        currentDurationWeeks: Int,
        conservative: Bool
    ) -> Int {
        guard conservative else { return currentDurationWeeks }
        return currentDurationWeeks <= 6 ? 6 : 8
    }

    private static func recommendedFrequency(
        currentSessionsPerWeek: Int,
        conservative: Bool
    ) -> Int {
        guard conservative else { return currentSessionsPerWeek }
        return max(2, currentSessionsPerWeek - 1)
    }

    private static func fallbackPrefill(
        run: ProgramRun,
        focus: ProgramFocus,
        level: ProgramLevel,
        durationWeeks: Int,
        sessionsPerWeek: Int,
        endDate: Date,
        personalRecords: [PersonalRecord],
        workoutsInWindow: [Workout],
        note: String
    ) -> MesocycleNextBlockPrefill {
        fallbackPrefill(
            runStableID: run.resolvedSyncStableID,
            recommendationStableID: nil,
            focus: focus,
            level: level,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            endDate: endDate,
            personalRecords: personalRecords,
            workoutsInWindow: workoutsInWindow,
            note: note
        )
    }

    private static func fallbackPrefill(
        runStableID: String,
        recommendationStableID: String?,
        focus: ProgramFocus,
        level: ProgramLevel,
        durationWeeks: Int,
        sessionsPerWeek: Int,
        endDate: Date,
        personalRecords: [PersonalRecord],
        workoutsInWindow: [Workout],
        note: String
    ) -> MesocycleNextBlockPrefill {
        let oneRepMaxSuggestions = FocusTemplateLibrary
            .template(for: focus)
            .requiredLifts
            .compactMap {
                bestOneRepMaxPrefill(
                    for: $0,
                    endDate: endDate,
                    personalRecords: personalRecords,
                    workoutsInWindow: workoutsInWindow
                )
            }

        return MesocycleNextBlockPrefill(
            sourceProgramRunStableID: runStableID,
            recommendationStableID: recommendationStableID,
            focus: focus,
            level: level,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            oneRepMaxSuggestions: oneRepMaxSuggestions,
            notes: [note]
        )
    }

    private static func bestOneRepMaxPrefill(
        for exerciseName: String,
        endDate: Date,
        personalRecords: [PersonalRecord],
        workoutsInWindow: [Workout]
    ) -> MesocycleOneRepMaxPrefill? {
        let exactRecordCandidates = personalRecords
            .filter {
                $0.exerciseName.caseInsensitiveCompare(exerciseName) == .orderedSame &&
                $0.dateAchieved <= endDate
            }
            .map {
                OneRepMaxCandidate(
                    estimatedOneRepMaxLbs: inLbs(
                        $0.weight * (1.0 + Double($0.repCount) / 30.0),
                        unit: $0.unit
                    ),
                    displayWeight: roundOneRepMax(
                        $0.weight * (1.0 + Double($0.repCount) / 30.0),
                        unit: $0.unit
                    ),
                    unit: $0.unit,
                    sourceSummary: "Prefilled from \(exerciseName) PR history."
                )
            }

        let exactWorkoutCandidates = workoutsInWindow.flatMap { workout in
            workout.exerciseEntries.compactMap { entry -> [OneRepMaxCandidate]? in
                guard entry.exerciseName.caseInsensitiveCompare(exerciseName) == .orderedSame else {
                    return nil
                }

                let candidates = entry.sets
                    .filter { $0.reps > 0 && $0.weight > 0 }
                    .map { set in
                        let estimate = estimatedOneRepMax(
                            weightLbs: inLbs(set.weight, unit: entry.unit),
                            reps: set.reps
                        )
                        return OneRepMaxCandidate(
                            estimatedOneRepMaxLbs: estimate,
                            displayWeight: roundOneRepMax(
                                entry.unit == .kg ? estimate / 2.20462 : estimate,
                                unit: entry.unit
                            ),
                            unit: entry.unit,
                            sourceSummary: "Prefilled from logged \(exerciseName) sets in the completed block."
                        )
                    }

                return candidates.isEmpty ? nil : candidates
            }
        }
        .flatMap { $0 }

        let familyCandidates: [OneRepMaxCandidate]
        if let targetLift = CanonicalLift.from(exerciseName: exerciseName) {
            familyCandidates = workoutsInWindow.flatMap { workout in
                workout.exerciseEntries.compactMap { entry -> [OneRepMaxCandidate]? in
                    guard CanonicalLift.from(exerciseName: entry.exerciseName) == targetLift else {
                        return nil
                    }

                    let candidates = entry.sets
                        .filter { $0.reps > 0 && $0.weight > 0 }
                        .map { set in
                            let estimate = estimatedOneRepMax(
                                weightLbs: inLbs(set.weight, unit: entry.unit),
                                reps: set.reps
                            )
                            return OneRepMaxCandidate(
                                estimatedOneRepMaxLbs: estimate,
                                displayWeight: roundOneRepMax(
                                    entry.unit == .kg ? estimate / 2.20462 : estimate,
                                    unit: entry.unit
                                ),
                                unit: entry.unit,
                                sourceSummary: "Prefilled from \(targetLift.displayName) family work in the completed block."
                            )
                        }

                    return candidates.isEmpty ? nil : candidates
                }
            }
            .flatMap { $0 }
        } else {
            familyCandidates = []
        }

        let best = (exactRecordCandidates + exactWorkoutCandidates + familyCandidates)
            .max(by: { $0.estimatedOneRepMaxLbs < $1.estimatedOneRepMaxLbs })

        guard let best else { return nil }

        return MesocycleOneRepMaxPrefill(
            exerciseName: exerciseName,
            weight: best.displayWeight,
            unit: best.unit,
            sourceSummary: best.sourceSummary
        )
    }

    private static func inferredFocus(
        for program: TrainingProgram?
    ) -> ProgramFocus? {
        guard let program else { return nil }
        let normalizedName = program.name.lowercased()

        if let exactPrefix = ProgramFocus.allCases.first(where: {
            normalizedName.hasPrefix(FocusTemplateLibrary.template(for: $0).displayName.lowercased())
        }) {
            return exactPrefix
        }

        return ProgramFocus.allCases.first {
            normalizedName.contains(FocusTemplateLibrary.template(for: $0).displayName.lowercased())
        }
    }

    private static func inferredLevel(
        for program: TrainingProgram?
    ) -> ProgramLevel {
        guard let program else { return .intermediate }

        if program.name.localizedCaseInsensitiveContains("Beginner") {
            return .beginner
        }
        if program.name.localizedCaseInsensitiveContains("Intermediate") {
            return .intermediate
        }
        if program.name.localizedCaseInsensitiveContains("Advanced") {
            return .advanced
        }

        switch program.progressionModel {
        case .linear:
            return .beginner
        case .dup:
            return .intermediate
        case .block:
            return .advanced
        case nil:
            return .intermediate
        }
    }

    private static func resolvedEndDate(
        run: ProgramRun,
        programWorkouts: [Workout],
        standaloneWorkouts: [Workout]
    ) -> Date {
        run.endDate ??
        programWorkouts.map(\.date).max() ??
        standaloneWorkouts.map(\.date).max() ??
        run.startDate
    }

    private static func phaseLabel(
        for week: ProgramWeekTemplate,
        progressionModel: ProgramProgressionModel?
    ) -> String {
        if week.isDeloadWeek || week.progressionPhase == .deload {
            return "Deload"
        }

        switch week.progressionPhase {
        case .linearWorking:
            return "Working Block"
        case .dupHeavy:
            return "Heavy Exposure"
        case .dupModerate:
            return "Moderate Exposure"
        case .dupLight:
            return "Light Exposure"
        case .hypertrophy:
            return "Hypertrophy Block"
        case .strength:
            return "Strength Block"
        case .peaking:
            return "Peaking Block"
        case .deload:
            return "Deload"
        case nil:
            switch progressionModel {
            case .linear: return "Working Block"
            case .dup: return "Undulating Block"
            case .block: return "Block Phase"
            case nil: return "Program Phase"
            }
        }
    }

    private static func weekRangeText(startWeek: Int, endWeek: Int) -> String {
        if startWeek == endWeek {
            return "Week \(startWeek)"
        }
        return "Weeks \(startWeek)-\(endWeek)"
    }

    private static func wholeDaysBetween(_ start: Date, _ end: Date) -> Int {
        max(0, Int(ceil(end.timeIntervalSince(start) / 86_400)))
    }

    private static func estimatedOneRepMax(weightLbs: Double, reps: Int) -> Double {
        if reps <= 1 { return weightLbs }
        return weightLbs * (1.0 + Double(reps) / 30.0)
    }

    private static func inLbs(_ weight: Double, unit: WeightUnit) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }

    private static func roundOneRepMax(_ value: Double, unit: WeightUnit) -> Double {
        switch unit {
        case .lbs:
            return (value / 5.0).rounded() * 5.0
        case .kg:
            return (value / 2.5).rounded() * 2.5
        }
    }

    private static func stepDownLevel(from level: ProgramLevel) -> ProgramLevel {
        switch level {
        case .advanced:
            return .intermediate
        case .intermediate:
            return .beginner
        case .beginner:
            return .beginner
        }
    }

    private static func consistencyResetFocus(from focus: ProgramFocus?) -> ProgramFocus {
        switch focus {
        case .cardioEndurance:
            return .cardioEndurance
        case .increaseMaxSquat, .increaseMaxBench, .increaseMaxDeadlift, .powerlifting, .fiveByFive:
            return .fullBody
        case .bodybuilding, .powerbuilding, .pushPull, .generalFitness, .fullBody:
            return .generalFitness
        case nil:
            return .generalFitness
        }
    }

    private static func adjacentGrowthFocus(from focus: ProgramFocus) -> ProgramFocus {
        switch focus {
        case .increaseMaxSquat, .increaseMaxBench, .increaseMaxDeadlift, .powerlifting, .fiveByFive:
            return .powerbuilding
        case .powerbuilding:
            return .bodybuilding
        case .bodybuilding:
            return .powerbuilding
        case .generalFitness:
            return .fullBody
        case .fullBody:
            return .powerbuilding
        case .pushPull:
            return .bodybuilding
        case .cardioEndurance:
            return .generalFitness
        }
    }

    private static func balancedFallbackFocus(from focus: ProgramFocus?) -> ProgramFocus {
        switch focus {
        case .cardioEndurance:
            return .fullBody
        case .powerlifting, .increaseMaxSquat, .increaseMaxBench, .increaseMaxDeadlift, .fiveByFive:
            return .generalFitness
        case .powerbuilding, .bodybuilding, .pushPull, .generalFitness, .fullBody:
            return .generalFitness
        case nil:
            return .fullBody
        }
    }

    private static func distinctRecommendationFocus(
        preferred candidates: [ProgramFocus],
        excluding excluded: [ProgramFocus]
    ) -> ProgramFocus {
        for candidate in candidates where !excluded.contains(candidate) {
            return candidate
        }

        return ProgramFocus.allCases.first { !excluded.contains($0) } ?? .generalFitness
    }
}

private struct LiftWorkoutSignal {
    let estimatedOneRepMaxLbs: Double
    let sourcedFromStandaloneWorkout: Bool
}

private struct OneRepMaxCandidate {
    let estimatedOneRepMaxLbs: Double
    let displayWeight: Double
    let unit: WeightUnit
    let sourceSummary: String
}
