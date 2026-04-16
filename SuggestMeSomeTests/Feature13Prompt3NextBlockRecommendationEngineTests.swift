//
//  Feature13Prompt3NextBlockRecommendationEngineTests.swift
//  SuggestMeSomeTests
//
//  Feature 13 Prompt 3 — Ranked next-block recommendation engine.
//

import Foundation
import Testing
@testable import SuggestMeSome

struct Feature13Prompt3NextBlockRecommendationEngineTests {

    @Test func strongHypertrophyOutcomeRanksStrengthOrientedFollowUpFirst() {
        let input = MesocycleRecommendationInputPayload(
            programRunStableID: "run-1",
            trainingProgramStableID: "program-1",
            currentFocus: .bodybuilding,
            inferredCurrentLevel: .intermediate,
            progressionModel: .dup,
            sessionSummary: MesocycleSessionCompletionSummary(
                plannedSessions: 20,
                completedSessions: 18,
                uniqueCompletedSessions: 18,
                duplicateWorkoutCount: 0,
                missedSessions: 2
            ),
            workoutSummary: MesocycleWorkoutDurationSummary(
                programWorkoutCount: 18,
                standaloneWorkoutCount: 1,
                totalWorkoutCount: 19,
                totalDurationSeconds: 57_000,
                averageDurationSeconds: 3_000
            ),
            personalRecordSummary: MesocyclePersonalRecordSummary(
                achievedSetCount: 4,
                uniqueExerciseCount: 2,
                notableExercises: ["Bench Press", "Barbell Row"]
            ),
            exerciseConsistencySummary: MesocycleExerciseConsistencySummary(
                repeatedExerciseCount: 4,
                anchorExercises: [
                    MesocycleExerciseFrequency(exerciseName: "Bench Press", workoutCount: 12, appearancePercentage: 67),
                    MesocycleExerciseFrequency(exerciseName: "Barbell Row", workoutCount: 10, appearancePercentage: 56),
                ],
                summaryText: "Anchor hypertrophy lifts stayed consistent."
            ),
            liftHighlights: [
                MesocycleLiftHighlight(
                    liftKey: "bench",
                    displayName: "Bench Press",
                    firstEstimatedOneRepMaxLbs: 220,
                    bestEstimatedOneRepMaxLbs: 235,
                    improvementPercentage: 7,
                    sourcedFromStandaloneWorkout: false
                )
            ],
            movementPatterns: [],
            standaloneInfluence: MesocycleStandaloneWorkoutInfluenceSummary(
                includedWorkoutCount: 1,
                totalDurationSeconds: 1_800,
                dominantPatterns: [
                    MesocycleMovementPatternCount(pattern: .horizontalPull, workoutCount: 1)
                ],
                summaryText: "One extra upper-back session supported the block.",
                influencePolicyText: "Standalone work is informative but conservative."
            ),
            frictionSignalKinds: []
        )

        let recommendations = NextBlockRecommendationEngine.rankedRecommendations(
            input: input,
            currentDurationWeeks: 8,
            currentSessionsPerWeek: 4,
            completionEndDate: day(20),
            personalRecords: [],
            workoutsInWindow: []
        )

        #expect(recommendations.count == 3)
        #expect(recommendations[0].isPrimaryRecommendation)
        #expect(recommendations[0].kind == .pivotFocus)
        #expect(recommendations[0].targetFocus == .powerbuilding)
        #expect(recommendations[0].fitScore > recommendations[1].fitScore)
        #expect(recommendations[0].requiresExplicitAcceptance)
    }

    @Test func lowAdherenceRebuildsConsistencyAndMapsPrefillIntoGeneratorContext() {
        let personalRecords = [
            PersonalRecord(
                exerciseName: "Back Squats",
                repCount: 5,
                weight: 255,
                unit: .lbs,
                dateAchieved: day(8)
            ),
            PersonalRecord(
                exerciseName: "Bench Press",
                repCount: 5,
                weight: 195,
                unit: .lbs,
                dateAchieved: day(7)
            ),
        ]
        let workouts = [
            makeWorkout(
                date: day(7),
                entries: [
                    makeStrengthEntry(
                        exerciseName: "Back Squats",
                        sets: [(5, 245, false), (5, 245, false)]
                    ),
                    makeStrengthEntry(
                        exerciseName: "Bench Press",
                        sets: [(5, 190, true), (5, 190, false)]
                    ),
                ]
            )
        ]
        let input = MesocycleRecommendationInputPayload(
            programRunStableID: "run-2",
            trainingProgramStableID: "program-2",
            currentFocus: .powerlifting,
            inferredCurrentLevel: .advanced,
            progressionModel: .block,
            sessionSummary: MesocycleSessionCompletionSummary(
                plannedSessions: 12,
                completedSessions: 5,
                uniqueCompletedSessions: 5,
                duplicateWorkoutCount: 0,
                missedSessions: 7
            ),
            workoutSummary: MesocycleWorkoutDurationSummary(
                programWorkoutCount: 5,
                standaloneWorkoutCount: 0,
                totalWorkoutCount: 5,
                totalDurationSeconds: 13_500,
                averageDurationSeconds: 2_700
            ),
            personalRecordSummary: MesocyclePersonalRecordSummary(
                achievedSetCount: 1,
                uniqueExerciseCount: 1,
                notableExercises: ["Bench Press"]
            ),
            exerciseConsistencySummary: MesocycleExerciseConsistencySummary(
                repeatedExerciseCount: 2,
                anchorExercises: [
                    MesocycleExerciseFrequency(exerciseName: "Back Squats", workoutCount: 4, appearancePercentage: 80),
                    MesocycleExerciseFrequency(exerciseName: "Bench Press", workoutCount: 4, appearancePercentage: 80),
                ],
                summaryText: "Only the main lifts stayed consistent."
            ),
            liftHighlights: [],
            movementPatterns: [],
            standaloneInfluence: MesocycleStandaloneWorkoutInfluenceSummary(
                includedWorkoutCount: 0,
                totalDurationSeconds: 0,
                dominantPatterns: [],
                summaryText: "No standalone support in the block window.",
                influencePolicyText: "No standalone workouts were considered."
            ),
            frictionSignalKinds: [.missedPlannedSessions, .longGapBetweenSessions]
        )

        let recommendations = NextBlockRecommendationEngine.rankedRecommendations(
            input: input,
            currentDurationWeeks: 8,
            currentSessionsPerWeek: 4,
            completionEndDate: day(10),
            personalRecords: personalRecords,
            workoutsInWindow: workouts
        )

        let primary = recommendations[0]
        let mappedInput = primary.prefill.programGenerationInput

        #expect(primary.isPrimaryRecommendation)
        #expect(primary.kind == .rebuildConsistency)
        #expect(primary.targetFocus == .fullBody)
        #expect(primary.suggestedLevel == .intermediate)
        #expect(primary.suggestedSessionsPerWeek == 2)
        #expect(primary.prefill.oneRepMaxSuggestions.contains { $0.exerciseName == "Back Squats" })
        #expect(primary.prefill.valueSources.contains {
            $0.field == .focus && $0.source == .recommendation
        })
        #expect(primary.prefill.valueSources.contains {
            $0.field == .trainingMaxes && $0.source == .carryForwardHistory
        })
        #expect(mappedInput.focus == primary.targetFocus)
        #expect(mappedInput.carryForwardContext?.rationaleText == primary.prefill.rationaleText)
        #expect(mappedInput.carryForwardContext?.preservedExerciseNames.contains("Back Squats") == true)
        #expect(mappedInput.carryForwardContext?.suggestedStyle == primary.prefill.style)
    }

    @Test func standaloneConditioningInfluenceAddsRankedOptionConservatively() {
        let input = MesocycleRecommendationInputPayload(
            programRunStableID: "run-3",
            trainingProgramStableID: "program-3",
            currentFocus: .increaseMaxBench,
            inferredCurrentLevel: .intermediate,
            progressionModel: .dup,
            sessionSummary: MesocycleSessionCompletionSummary(
                plannedSessions: 8,
                completedSessions: 6,
                uniqueCompletedSessions: 6,
                duplicateWorkoutCount: 0,
                missedSessions: 2
            ),
            workoutSummary: MesocycleWorkoutDurationSummary(
                programWorkoutCount: 6,
                standaloneWorkoutCount: 2,
                totalWorkoutCount: 8,
                totalDurationSeconds: 20_400,
                averageDurationSeconds: 2_550
            ),
            personalRecordSummary: MesocyclePersonalRecordSummary(
                achievedSetCount: 2,
                uniqueExerciseCount: 1,
                notableExercises: ["Bench Press"]
            ),
            exerciseConsistencySummary: MesocycleExerciseConsistencySummary(
                repeatedExerciseCount: 2,
                anchorExercises: [
                    MesocycleExerciseFrequency(exerciseName: "Bench Press", workoutCount: 6, appearancePercentage: 100)
                ],
                summaryText: "Bench stayed anchored."
            ),
            liftHighlights: [
                MesocycleLiftHighlight(
                    liftKey: "bench",
                    displayName: "Bench Press",
                    firstEstimatedOneRepMaxLbs: 225,
                    bestEstimatedOneRepMaxLbs: 235,
                    improvementPercentage: 4,
                    sourcedFromStandaloneWorkout: false
                )
            ],
            movementPatterns: [],
            standaloneInfluence: MesocycleStandaloneWorkoutInfluenceSummary(
                includedWorkoutCount: 2,
                totalDurationSeconds: 4_200,
                dominantPatterns: [
                    MesocycleMovementPatternCount(pattern: .conditioning, workoutCount: 2)
                ],
                summaryText: "Two conditioning sessions supported work capacity.",
                influencePolicyText: "Standalone conditioning informs ranking, but does not change planned-session adherence."
            ),
            frictionSignalKinds: [.missedPlannedSessions]
        )

        let recommendations = NextBlockRecommendationEngine.rankedRecommendations(
            input: input,
            currentDurationWeeks: 6,
            currentSessionsPerWeek: 3,
            completionEndDate: day(12),
            personalRecords: [],
            workoutsInWindow: []
        )

        #expect(recommendations.count == 3)
        #expect(recommendations[0].targetFocus != .cardioEndurance)
        #expect(recommendations.contains {
            $0.targetFocus == .cardioEndurance && $0.kind == .addConditioningBias
        })
    }

    private func makeWorkout(date: Date, entries: [ExerciseEntry]) -> Workout {
        let workout = Workout(
            date: date,
            startTime: date,
            durationSeconds: 3_600
        )
        workout.exerciseEntries = entries
        for entry in entries {
            entry.workout = workout
            for set in entry.sets {
                set.exerciseEntry = entry
            }
        }
        return workout
    }

    private func makeStrengthEntry(
        exerciseName: String,
        unit: WeightUnit = .lbs,
        sets: [(reps: Int, weight: Double, isPR: Bool)]
    ) -> ExerciseEntry {
        let entry = ExerciseEntry(
            exerciseName: exerciseName,
            unit: unit,
            orderIndex: 0
        )
        entry.sets = sets.enumerated().map { index, set in
            let setEntry = SetEntry(
                setNumber: index + 1,
                reps: set.reps,
                weight: set.weight,
                isPR: set.isPR
            )
            setEntry.exerciseEntry = entry
            return setEntry
        }
        return entry
    }

    private func day(_ offset: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(
                year: 2026,
                month: 4,
                day: 1 + offset,
                hour: 9
            )
        )!
    }
}
