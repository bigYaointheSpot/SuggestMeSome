//
//  Feature13Prompt1MesocycleReviewTests.swift
//  SuggestMeSomeTests
//
//  Feature 13 Prompt 1 — Mesocycle review domain foundation.
//

import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
struct Feature13Prompt1MesocycleReviewTests {

    @Test func reviewBuildsFromCompletedRunAndConservativeStandaloneInfluence() {
        let program = makeProgram(
            name: "Increase Max Bench — Intermediate 2wk",
            lengthInWeeks: 2,
            sessionsPerWeek: 2,
            progressionModel: .dup
        )
        let run = ProgramRun(
            startDate: day(0),
            endDate: day(13),
            isCompleted: true
        )
        run.program = program

        let programWorkouts = [
            makeProgramWorkout(
                date: day(0),
                run: run,
                week: 1,
                session: 1,
                exerciseName: "Bench Press",
                sets: [(5, 185, false), (5, 185, false)]
            ),
            makeProgramWorkout(
                date: day(4),
                run: run,
                week: 1,
                session: 2,
                exerciseName: "Bench Press",
                sets: [(5, 190, false), (5, 190, false)]
            ),
            makeProgramWorkout(
                date: day(9),
                run: run,
                week: 2,
                session: 1,
                exerciseName: "Bench Press",
                sets: [(5, 205, true), (4, 205, false)]
            ),
        ]

        let standaloneWorkouts = [
            makeStandaloneWorkout(
                date: day(10),
                entries: [
                    makeCardioEntry(name: "Treadmill", seconds: 1_200)
                ]
            ),
            makeStandaloneWorkout(
                date: day(11),
                entries: [
                    makeStrengthEntry(
                        exerciseName: "Dumbbell Row",
                        sets: [(10, 80, false), (10, 80, false)]
                    )
                ]
            )
        ]

        let personalRecords = [
            PersonalRecord(
                exerciseName: "Bench Press",
                repCount: 5,
                weight: 205,
                unit: .lbs,
                dateAchieved: day(9)
            )
        ]

        let review = MesocycleReviewService.buildReview(
            for: run,
            programWorkouts: programWorkouts,
            standaloneWorkouts: standaloneWorkouts,
            personalRecords: personalRecords
        )

        #expect(review.focus == .increaseMaxBench)
        #expect(review.inferredCurrentLevel == .intermediate)
        #expect(review.headlineMetrics.sessionSummary.plannedSessions == 4)
        #expect(review.headlineMetrics.sessionSummary.completedSessions == 3)
        #expect(review.headlineMetrics.adherencePercentage == 75)
        #expect(review.standaloneInfluence.includedWorkoutCount == 2)
        #expect(review.standaloneInfluence.influencePolicyText.contains("do not increase planned-session adherence"))
        #expect(review.frictionSignals.contains { $0.kind == .missedPlannedSessions })
        #expect(review.rankedRecommendations.count == 3)
        #expect(Set(review.rankedRecommendations.map(\.targetFocus)).count == 3)
        #expect(review.rankedRecommendations[0].kind == .consolidateFocus)
        #expect(review.defaultNextBlockPrefill.focus == .increaseMaxBench)

        let benchPrefill = review.defaultNextBlockPrefill.oneRepMaxSuggestions.first {
            $0.exerciseName == "Bench Press"
        }
        #expect(benchPrefill?.weight == 240)
        #expect(benchPrefill?.unit == .lbs)
    }

    @Test func plannedVsCompletedIgnoresDuplicateSessionLogs() {
        let program = makeProgram(
            name: "Full Body — Beginner 2wk",
            lengthInWeeks: 2,
            sessionsPerWeek: 2,
            progressionModel: .linear
        )
        let run = ProgramRun(
            startDate: day(0),
            endDate: day(7),
            isCompleted: true
        )
        run.program = program

        let duplicatedWorkouts = [
            makeProgramWorkout(
                date: day(0),
                run: run,
                week: 1,
                session: 1,
                exerciseName: "Back Squats",
                sets: [(5, 225, false)]
            ),
            makeProgramWorkout(
                date: day(1),
                run: run,
                week: 1,
                session: 1,
                exerciseName: "Back Squats",
                sets: [(5, 230, false)]
            ),
            makeProgramWorkout(
                date: day(3),
                run: run,
                week: 1,
                session: 2,
                exerciseName: "Bench Press",
                sets: [(5, 165, false)]
            ),
        ]

        let summary = MesocycleReviewService.plannedVsCompletedSessions(
            for: run,
            programWorkouts: duplicatedWorkouts
        )

        #expect(summary.plannedSessions == 4)
        #expect(summary.uniqueCompletedSessions == 2)
        #expect(summary.completedSessions == 2)
        #expect(summary.duplicateWorkoutCount == 1)
        #expect(summary.missedSessions == 2)
        #expect(MesocycleReviewService.adherencePercentage(sessionSummary: summary) == 50)
    }

    @Test func completedRunWithNoLoggedSessionsStillProducesReviewSnapshot() {
        let program = makeProgram(
            name: "Custom Recovery Block",
            lengthInWeeks: 2,
            sessionsPerWeek: 2,
            progressionModel: nil
        )
        let run = ProgramRun(
            startDate: day(0),
            endDate: day(14),
            isCompleted: true
        )
        run.program = program

        let review = MesocycleReviewService.buildReview(
            for: run,
            programWorkouts: [],
            standaloneWorkouts: [],
            personalRecords: []
        )

        #expect(review.headlineMetrics.sessionSummary.completedSessions == 0)
        #expect(review.frictionSignals.contains {
            $0.kind == .sparseProgramData && $0.severity == .high
        })
        #expect(review.rankedRecommendations.count == 3)
        #expect(Set(review.rankedRecommendations.map(\.targetFocus)).count == 3)
        #expect(review.rankedRecommendations[0].kind == .rebuildConsistency)
        #expect(review.defaultNextBlockPrefill.focus == .generalFitness)
    }

    // MARK: - Helpers

    private func makeProgram(
        name: String,
        lengthInWeeks: Int,
        sessionsPerWeek: Int,
        progressionModel: ProgramProgressionModel?
    ) -> TrainingProgram {
        let program = TrainingProgram(
            name: name,
            lengthInWeeks: lengthInWeeks,
            sessionsPerWeek: sessionsPerWeek,
            createdDate: day(0),
            source: .aiGenerated,
            progressionModel: progressionModel
        )

        let weeks = (1...lengthInWeeks).map { weekNumber in
            let phase: ProgramProgressionPhase?
            switch progressionModel {
            case .linear:
                phase = .linearWorking
            case .dup:
                phase = weekNumber == lengthInWeeks ? .dupLight : .dupHeavy
            case .block:
                phase = weekNumber == lengthInWeeks ? .strength : .hypertrophy
            case nil:
                phase = nil
            }

            let week = ProgramWeekTemplate(
                weekNumber: weekNumber,
                progressionPhase: phase
            )
            week.program = program

            let sessions = (1...sessionsPerWeek).map { sessionNumber in
                let session = ProgramSessionTemplate(
                    sessionNumber: sessionNumber,
                    sessionName: "Session \(sessionNumber)"
                )
                session.week = week
                return session
            }
            week.sessions = sessions
            return week
        }

        program.weeks = weeks
        return program
    }

    private func makeProgramWorkout(
        date: Date,
        run: ProgramRun,
        week: Int,
        session: Int,
        exerciseName: String,
        sets: [(reps: Int, weight: Double, isPR: Bool)]
    ) -> Workout {
        let entry = makeStrengthEntry(exerciseName: exerciseName, sets: sets)
        let workout = Workout(
            date: date,
            startTime: date,
            durationSeconds: 3_600,
            programRun: run,
            programWeekNumber: week,
            programSessionNumber: session
        )
        attach(entries: [entry], to: workout)
        return workout
    }

    private func makeStandaloneWorkout(
        date: Date,
        entries: [ExerciseEntry]
    ) -> Workout {
        let workout = Workout(
            date: date,
            startTime: date,
            durationSeconds: 2_700
        )
        attach(entries: entries, to: workout)
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

    private func makeCardioEntry(name: String, seconds: Int) -> ExerciseEntry {
        ExerciseEntry(
            exerciseName: name,
            unit: .lbs,
            orderIndex: 0,
            isCardio: true,
            cardioDurationSeconds: seconds
        )
    }

    private func attach(entries: [ExerciseEntry], to workout: Workout) {
        workout.exerciseEntries = entries
        for entry in entries {
            entry.workout = workout
            for set in entry.sets {
                set.exerciseEntry = entry
            }
        }
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
