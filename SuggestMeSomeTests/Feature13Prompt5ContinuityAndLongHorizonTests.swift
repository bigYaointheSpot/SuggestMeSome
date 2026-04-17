//
//  Feature13Prompt5ContinuityAndLongHorizonTests.swift
//  SuggestMeSomeTests
//
//  Feature 13 Prompt 5 — Continuity snapshots and long-horizon summaries.
//

import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
struct Feature13Prompt5ContinuityAndLongHorizonTests {
    @Test func acceptedAndDeclinedRecommendationsPersistAndLinkAcrossRuns() {
        let sourceProgram = makeProgram(
            stableID: "program-source",
            name: "Powerbuilding Block",
            lengthInWeeks: 2,
            sessionsPerWeek: 3
        )
        let sourceRun = ProgramRun(
            syncStableID: "run-source",
            startDate: day(0),
            endDate: day(13),
            isCompleted: true
        )
        sourceRun.program = sourceProgram

        let review = makeReviewSnapshot(sourceRunStableID: sourceRun.resolvedSyncStableID)
        let acceptedRecommendation = review.rankedRecommendations[0]
        let declinedRecommendation = review.rankedRecommendations[1]
        let editedPrefill = NextBlockPrefillContext(
            sourceProgramRunStableID: acceptedRecommendation.prefill.sourceProgramRunStableID,
            recommendationStableID: acceptedRecommendation.prefill.recommendationStableID,
            focus: acceptedRecommendation.prefill.focus,
            style: acceptedRecommendation.prefill.style,
            level: acceptedRecommendation.prefill.level,
            durationWeeks: acceptedRecommendation.prefill.durationWeeks,
            sessionsPerWeek: acceptedRecommendation.prefill.sessionsPerWeek + 1,
            oneRepMaxSuggestions: [
                MesocycleOneRepMaxPrefill(
                    exerciseName: "Bench Press",
                    weight: 255,
                    unit: .lbs,
                    sourceSummary: "Edited after reviewing the recommendation."
                )
            ],
            preservedExerciseNames: acceptedRecommendation.prefill.preservedExerciseNames,
            rationaleText: acceptedRecommendation.prefill.rationaleText,
            valueSources: acceptedRecommendation.prefill.valueSources,
            intensityContext: acceptedRecommendation.prefill.intensityContext,
            notes: acceptedRecommendation.prefill.notes
        )

        ProgramRunContinuityService.recordDecision(
            on: sourceRun,
            review: review,
            recommendation: declinedRecommendation,
            decision: .declined,
            decidedAt: day(14)
        )
        ProgramRunContinuityService.recordDecision(
            on: sourceRun,
            review: review,
            recommendation: acceptedRecommendation,
            decision: .accepted,
            editedPrefill: editedPrefill,
            decidedAt: day(15)
        )

        let history = sourceRun.recommendationDecisionHistorySnapshot
        #expect(history?.selectedRecommendationStableID == acceptedRecommendation.stableID)
        #expect(history?.declinedRecommendationStableIDs == [declinedRecommendation.stableID])
        #expect(history?.decisionEvents.count == 2)
        #expect(history?.userEditedFields.contains(.sessionsPerWeek) == true)
        #expect(history?.userEditedFields.contains(.trainingMaxes) == true)

        let nextRun = ProgramRun(startDate: day(16))
        let carriedInput = editedPrefill.programGenerationInput
        ProgramRunContinuityService.applyAcceptedContinuity(
            to: nextRun,
            sourceRun: sourceRun,
            input: carriedInput,
            startedAt: day(16)
        )

        let continuity = nextRun.continuitySnapshot
        #expect(nextRun.previousProgramRunStableID == sourceRun.resolvedSyncStableID)
        #expect(continuity?.selectedRecommendationStableID == acceptedRecommendation.stableID)
        #expect(continuity?.decisionEvents.count == 2)
        #expect(continuity?.carriedForwardContext?.recommendationStableID == acceptedRecommendation.stableID)
        #expect(continuity?.userEditedFields.contains(.sessionsPerWeek) == true)
    }

    @Test func longHorizonSummaryPullsReadableSignalsFromRecentBlocks() {
        let run1Program = makeProgram(
            stableID: "program-1",
            name: "Bench Focus A",
            lengthInWeeks: 2,
            sessionsPerWeek: 4
        )
        let run2Program = makeProgram(
            stableID: "program-2",
            name: "Bench Focus B",
            lengthInWeeks: 2,
            sessionsPerWeek: 3
        )
        let run3Program = makeProgram(
            stableID: "program-3",
            name: "Bench Focus C",
            lengthInWeeks: 2,
            sessionsPerWeek: 3
        )

        let run1 = ProgramRun(
            syncStableID: "run-1",
            startDate: day(0),
            endDate: day(13),
            isCompleted: true
        )
        run1.program = run1Program

        let run2 = ProgramRun(
            syncStableID: "run-2",
            startDate: day(20),
            endDate: day(33),
            isCompleted: true
        )
        run2.program = run2Program

        let run3 = ProgramRun(
            syncStableID: "run-3",
            startDate: day(40),
            endDate: day(53),
            isCompleted: true
        )
        run3.program = run3Program

        let workouts = [
            makeProgramWorkout(date: day(0), run: run1, week: 1, session: 1, exerciseName: "Bench Press", weight: 185),
            makeProgramWorkout(date: day(2), run: run1, week: 1, session: 2, exerciseName: "Bench Press", weight: 190),
            makeProgramWorkout(date: day(4), run: run1, week: 1, session: 3, exerciseName: "Bench Press", weight: 195),
            makeProgramWorkout(date: day(7), run: run1, week: 2, session: 1, exerciseName: "Bench Press", weight: 200),
            makeProgramWorkout(date: day(10), run: run1, week: 2, session: 2, exerciseName: "Bench Press", weight: 200),
            makeStandaloneConditioningWorkout(date: day(11)),

            makeProgramWorkout(date: day(20), run: run2, week: 1, session: 1, exerciseName: "Bench Press", weight: 205),
            makeProgramWorkout(date: day(23), run: run2, week: 1, session: 2, exerciseName: "Bench Press", weight: 210),
            makeProgramWorkout(date: day(26), run: run2, week: 1, session: 3, exerciseName: "Bench Press", weight: 210),
            makeProgramWorkout(date: day(29), run: run2, week: 2, session: 1, exerciseName: "Bench Press", weight: 215),
            makeProgramWorkout(date: day(32), run: run2, week: 2, session: 2, exerciseName: "Bench Press", weight: 220),
            makeStandaloneConditioningWorkout(date: day(31)),

            makeProgramWorkout(date: day(40), run: run3, week: 1, session: 1, exerciseName: "Bench Press", weight: 225),
            makeProgramWorkout(date: day(42), run: run3, week: 1, session: 2, exerciseName: "Bench Press", weight: 225),
            makeProgramWorkout(date: day(44), run: run3, week: 1, session: 3, exerciseName: "Bench Press", weight: 230),
            makeProgramWorkout(date: day(47), run: run3, week: 2, session: 1, exerciseName: "Bench Press", weight: 230),
            makeProgramWorkout(date: day(50), run: run3, week: 2, session: 2, exerciseName: "Bench Press", weight: 235),
            makeProgramWorkout(date: day(53), run: run3, week: 2, session: 3, exerciseName: "Bench Press", weight: 240),
            makeStandaloneConditioningWorkout(date: day(52)),
        ]

        let summary = LongHorizonAdaptationSummaryService.buildSummary(
            endingWith: run3,
            completedRuns: [run1, run2, run3],
            allWorkouts: workouts
        )

        #expect(summary.blockCount == 3)
        #expect(summary.includedStandaloneWorkoutCount == 3)
        #expect(summary.headline.contains("Across the last 3 blocks"))
        #expect(summary.insights.contains {
            $0.kind == .adherenceTrend && $0.detail.contains("trended up")
        })
        #expect(summary.insights.contains {
            $0.kind == .toleratedFrequency && $0.detail.contains("3 sessions per week")
        })
        #expect(summary.insights.contains {
            $0.kind == .movementContinuity && $0.detail.contains("Bench Press")
        })
        #expect(summary.insights.contains {
            $0.kind == .standaloneInfluence && $0.detail.lowercased().contains("conditioning")
        })
    }

    @Test func longHorizonSummaryDegradesGracefullyWithSingleCompletedBlock() {
        let program = makeProgram(
            stableID: "program-solo",
            name: "General Fitness",
            lengthInWeeks: 2,
            sessionsPerWeek: 2
        )
        let run = ProgramRun(
            syncStableID: "run-solo",
            startDate: day(0),
            endDate: day(13),
            isCompleted: true
        )
        run.program = program

        let workouts = [
            makeProgramWorkout(date: day(0), run: run, week: 1, session: 1, exerciseName: "Goblet Squat", weight: 80),
            makeProgramWorkout(date: day(6), run: run, week: 1, session: 2, exerciseName: "Goblet Squat", weight: 85),
        ]

        let summary = LongHorizonAdaptationSummaryService.buildSummary(
            endingWith: run,
            completedRuns: [run],
            allWorkouts: workouts
        )

        #expect(summary.blockCount == 1)
        #expect(summary.headline.contains("baseline"))
        #expect(summary.insights.contains {
            $0.kind == .insufficientData && $0.detail.contains("Finish another block")
        })
    }

    private func makeProgram(
        stableID: String,
        name: String,
        lengthInWeeks: Int,
        sessionsPerWeek: Int
    ) -> TrainingProgram {
        TrainingProgram(
            syncStableID: stableID,
            name: name,
            lengthInWeeks: lengthInWeeks,
            sessionsPerWeek: sessionsPerWeek,
            createdDate: day(0),
            source: .aiGenerated,
            progressionModel: .dup
        )
    }

    private func makeReviewSnapshot(
        sourceRunStableID: String
    ) -> MesocycleReviewSnapshot {
        let recommendationInput = MesocycleRecommendationInputPayload(
            programRunStableID: sourceRunStableID,
            trainingProgramStableID: "program-source",
            currentFocus: .powerbuilding,
            inferredCurrentLevel: .intermediate,
            progressionModel: .dup,
            sessionSummary: MesocycleSessionCompletionSummary(
                plannedSessions: 6,
                completedSessions: 5,
                uniqueCompletedSessions: 5,
                duplicateWorkoutCount: 0,
                missedSessions: 1
            ),
            workoutSummary: MesocycleWorkoutDurationSummary(
                programWorkoutCount: 5,
                standaloneWorkoutCount: 1,
                totalWorkoutCount: 6,
                totalDurationSeconds: 18_000,
                averageDurationSeconds: 3_000
            ),
            personalRecordSummary: MesocyclePersonalRecordSummary(
                achievedSetCount: 2,
                uniqueExerciseCount: 1,
                notableExercises: ["Bench Press"]
            ),
            exerciseConsistencySummary: MesocycleExerciseConsistencySummary(
                repeatedExerciseCount: 2,
                anchorExercises: [
                    MesocycleExerciseFrequency(
                        exerciseName: "Bench Press",
                        workoutCount: 5,
                        appearancePercentage: 100
                    )
                ],
                summaryText: "Bench Press stayed anchored."
            ),
            liftHighlights: [
                MesocycleLiftHighlight(
                    liftKey: "bench",
                    displayName: "Bench Press",
                    firstEstimatedOneRepMaxLbs: 225,
                    bestEstimatedOneRepMaxLbs: 245,
                    improvementPercentage: 9,
                    sourcedFromStandaloneWorkout: false
                )
            ],
            movementPatterns: [],
            standaloneInfluence: MesocycleStandaloneWorkoutInfluenceSummary(
                includedWorkoutCount: 1,
                totalDurationSeconds: 1_800,
                dominantPatterns: [
                    MesocycleMovementPatternCount(pattern: .conditioning, workoutCount: 1)
                ],
                summaryText: "One conditioning session supplemented the block.",
                influencePolicyText: "Standalone conditioning informs continuity without changing planned-session adherence."
            ),
            frictionSignalKinds: [.missedPlannedSessions]
        )

        let primaryPrefill = NextBlockPrefillContext(
            sourceProgramRunStableID: sourceRunStableID,
            recommendationStableID: "rec-accepted",
            focus: .powerbuilding,
            style: .dup,
            level: .intermediate,
            durationWeeks: 8,
            sessionsPerWeek: 3,
            oneRepMaxSuggestions: [
                MesocycleOneRepMaxPrefill(
                    exerciseName: "Bench Press",
                    weight: 245,
                    unit: .lbs,
                    sourceSummary: "Latest block benchmark."
                )
            ],
            preservedExerciseNames: ["Bench Press"],
            rationaleText: "Carry bench momentum into the next block.",
            valueSources: [
                NextBlockPrefillValueSource(
                    field: .focus,
                    source: .recommendation,
                    note: "Primary option stays close to the completed block."
                ),
                NextBlockPrefillValueSource(
                    field: .trainingMaxes,
                    source: .carryForwardHistory,
                    note: "Bench estimate carried from the completed block."
                )
            ],
            intensityContext: NextBlockIntensityContext(
                suggestedProgressionModel: .dup,
                carriedOneRepMaxes: [
                    MesocycleOneRepMaxPrefill(
                        exerciseName: "Bench Press",
                        weight: 245,
                        unit: .lbs,
                        sourceSummary: "Latest block benchmark."
                    )
                ],
                notableLiftDisplayNames: ["Bench Press"],
                sourceNotes: ["Use the latest bench estimate as the starting anchor."]
            ),
            notes: ["Carry bench momentum into the next block."]
        )

        let secondaryPrefill = NextBlockPrefillContext(
            sourceProgramRunStableID: sourceRunStableID,
            recommendationStableID: "rec-declined",
            focus: .generalFitness,
            style: .linear,
            level: .intermediate,
            durationWeeks: 6,
            sessionsPerWeek: 2,
            oneRepMaxSuggestions: [
                MesocycleOneRepMaxPrefill(
                    exerciseName: "Bench Press",
                    weight: 240,
                    unit: .lbs,
                    sourceSummary: "Conservative carry-forward option."
                )
            ],
            preservedExerciseNames: ["Bench Press"],
            rationaleText: "Lower weekly friction while keeping pressing continuity.",
            valueSources: [
                NextBlockPrefillValueSource(
                    field: .focus,
                    source: .recommendation,
                    note: "Alternative low-friction path."
                )
            ],
            notes: ["Lower weekly friction while keeping pressing continuity."]
        )

        let accepted = MesocycleNextBlockRecommendation(
            stableID: "rec-accepted",
            rank: 1,
            kind: .consolidateFocus,
            title: "Stay with powerbuilding",
            summary: "Your current focus still has productive room to run.",
            rationale: [
                "Bench momentum stayed strong.",
                "Adherence supported the current cadence."
            ],
            targetFocus: .powerbuilding,
            targetFocusDisplayName: "Powerbuilding",
            suggestedLevel: .intermediate,
            suggestedDurationWeeks: 8,
            suggestedSessionsPerWeek: 3,
            decision: .pending,
            prefill: primaryPrefill,
            isPrimaryRecommendation: true,
            fitScore: 92,
            fitNote: "Strong fit"
        )
        let declined = MesocycleNextBlockRecommendation(
            stableID: "rec-declined",
            rank: 2,
            kind: .rebuildConsistency,
            title: "Rebuild with general fitness",
            summary: "Lower weekly friction if life stress is still high.",
            rationale: [
                "Two-session structure is easier to recover from.",
            ],
            targetFocus: .generalFitness,
            targetFocusDisplayName: "General Fitness",
            suggestedLevel: .intermediate,
            suggestedDurationWeeks: 6,
            suggestedSessionsPerWeek: 2,
            decision: .pending,
            prefill: secondaryPrefill,
            fitScore: 71,
            fitNote: "Fallback path"
        )

        return MesocycleReviewSnapshot(
            reviewStableID: "\(sourceRunStableID)::review",
            programRunStableID: sourceRunStableID,
            trainingProgramStableID: "program-source",
            programName: "Powerbuilding Block",
            focus: .powerbuilding,
            focusDisplayName: "Powerbuilding",
            inferredCurrentLevel: .intermediate,
            progressionModel: .dup,
            startDate: day(0),
            endDate: day(13),
            headlineMetrics: MesocycleHeadlineMetrics(
                sessionSummary: recommendationInput.sessionSummary,
                adherencePercentage: 83,
                workoutSummary: recommendationInput.workoutSummary,
                personalRecordSummary: recommendationInput.personalRecordSummary,
                exerciseConsistencySummary: recommendationInput.exerciseConsistencySummary
            ),
            performanceHighlights: [],
            frictionSignals: [],
            narrativeSummary: "Strong pressing momentum with one missed session.",
            phaseRecap: [],
            standaloneInfluence: recommendationInput.standaloneInfluence,
            recommendationInput: recommendationInput,
            rankedRecommendations: [accepted, declined],
            defaultNextBlockPrefill: primaryPrefill
        )
    }

    private func makeProgramWorkout(
        date: Date,
        run: ProgramRun,
        week: Int,
        session: Int,
        exerciseName: String,
        weight: Double
    ) -> Workout {
        let entry = makeStrengthEntry(
            exerciseName: exerciseName,
            sets: [(5, weight), (5, weight)]
        )
        let workout = Workout(
            date: date,
            startTime: date,
            durationSeconds: 3_600,
            programRun: run,
            programWeekNumber: week,
            programSessionNumber: session
        )
        workout.exerciseEntries = [entry]
        entry.workout = workout
        for set in entry.sets {
            set.exerciseEntry = entry
        }
        return workout
    }

    private func makeStandaloneConditioningWorkout(date: Date) -> Workout {
        let cardioEntry = ExerciseEntry(
            exerciseName: "Treadmill",
            unit: .lbs,
            orderIndex: 0,
            isCardio: true,
            cardioDurationSeconds: 1_800
        )
        let workout = Workout(
            date: date,
            startTime: date,
            durationSeconds: 1_800
        )
        workout.exerciseEntries = [cardioEntry]
        cardioEntry.workout = workout
        return workout
    }

    private func makeStrengthEntry(
        exerciseName: String,
        sets: [(Int, Double)]
    ) -> ExerciseEntry {
        let entry = ExerciseEntry(
            exerciseName: exerciseName,
            unit: .lbs,
            orderIndex: 0
        )
        entry.sets = sets.enumerated().map { index, set in
            SetEntry(
                setNumber: index + 1,
                reps: set.0,
                weight: set.1,
                isPR: false
            )
        }
        return entry
    }

    private func day(_ offset: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: offset,
            to: Date(timeIntervalSince1970: 1_710_000_000)
        ) ?? Date(timeIntervalSince1970: 1_710_000_000)
    }
}
