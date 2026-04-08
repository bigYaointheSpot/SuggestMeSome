//
//  Feature6ValidationTests.swift
//  SuggestMeSomeTests
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature6ValidationTests {

    @Test func persistedModelRelationshipsRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let fixture = makeAdaptiveProgramFixture(includeWeek2Accessory: true)
        persistProgram(fixture.program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = fixture.program
        context.insert(run)

        let workout = insertWorkout(
            date: day(1),
            run: run,
            week: 1,
            session: 1,
            entries: [
                EntrySpec(
                    exerciseName: "Back Squats",
                    sourceProgramSessionExerciseID: fixture.week1Main.id,
                    prescribedTargetSets: 3,
                    prescribedTargetReps: 5,
                    prescribedWeight: 315,
                    prescribedWeightUnit: "lbs",
                    prescribedWorkingSetStyle: .topSet,
                    sets: [
                        SetSpec(setNumber: 1, reps: 5, weight: 315),
                        SetSpec(setNumber: 2, reps: 5, weight: 305),
                    ]
                )
            ],
            context: context
        )

        let analysis = WeeklyTrainingAnalysis(
            weekStartDate: day(0),
            weekEndDate: day(6),
            programRun: run,
            trainingProgram: fixture.program,
            programWeekNumber: 1,
            isFinalized: true,
            finalizedAt: day(7)
        )
        context.insert(analysis)

        let outcome = ExercisePerformanceOutcome(
            analysis: analysis,
            programRun: run,
            workout: workout,
            exerciseEntry: workout.exerciseEntries.first,
            workoutDate: workout.date,
            programWeekNumber: 1,
            programSessionNumber: 1,
            sourceProgramSessionExerciseID: fixture.week1Main.id,
            exerciseName: "Back Squats",
            canonicalLiftKey: "squat",
            signalSource: .programLinked,
            signalConfidence: .high,
            signalWeight: 1.0,
            actualSetCount: 2,
            actualAverageReps: 5,
            actualAverageWeight: 310,
            actualTopSetReps: 5,
            actualTopSetWeight: 315,
            actualTopSetEstimated1RM: 367.5,
            performanceScoreValue: 3.0,
            performanceScore: .onTarget,
            inferredFatigueStatus: .manageable,
            isTopSetSignal: true,
            notes: "validation"
        )
        analysis.outcomes.append(outcome)
        context.insert(outcome)

        let volume = WeeklyVolumeMetric(
            analysis: analysis,
            muscle: .quads,
            plannedHardSets: 10,
            completedHardSets: 9,
            weightedCompletedHardSets: 9,
            deltaHardSets: -1
        )
        analysis.volumeMetrics.append(volume)
        context.insert(volume)

        let trend = LiftPerformanceTrend(
            programRun: run,
            trainingProgram: fixture.program,
            canonicalLiftKey: "squat",
            liftDisplayName: "Squat"
        )
        context.insert(trend)

        let snapshot = LiftTrendSnapshot(
            trend: trend,
            analysis: analysis,
            programRun: run,
            trainingProgram: fixture.program,
            canonicalLiftKey: "squat",
            liftDisplayName: "Squat",
            weekStartDate: day(0),
            weekEndDate: day(6),
            programWeekNumber: 1,
            totalDataPoints: 1,
            programLinkedDataPoints: 1,
            standaloneDataPoints: 0,
            weightedSignalCount: 1,
            weightedProgramSignal: 1,
            weightedStandaloneSignal: 0,
            confidenceScore: 0.6,
            currentEstimated1RM: 367.5,
            baselineEstimated1RM: 360,
            rollingBestEstimated1RM: 367.5,
            changePercent: 2,
            trendStatus: .improving,
            fatigueStatus: .manageable
        )
        trend.snapshots.append(snapshot)
        analysis.trendSnapshots.append(snapshot)
        context.insert(snapshot)

        let proposal = AdaptationProposal(
            programRun: run,
            trainingProgram: fixture.program,
            sourceAnalysis: analysis,
            proposalType: .increaseLoad,
            proposalStatus: .pendingAutoApply,
            requiresUserConfirmation: false,
            autoApplyEligible: true,
            confidenceScore: 0.7,
            priority: 70,
            targetWeekStart: 2,
            targetWeekEnd: 2,
            targetLiftKey: "squat",
            proposedLoadPercentDelta: 0.015,
            adjustmentReason: .topSetBeatTarget,
            summaryText: "Increase squat load"
        )
        analysis.proposals.append(proposal)
        context.insert(proposal)

        let overlay = AppliedProgramOverlay(
            programRun: run,
            trainingProgram: fixture.program,
            sourceProposal: proposal,
            effectiveWeekStart: 2,
            effectiveWeekEnd: 2,
            appliedByUserConfirmation: false,
            adjustmentReason: .topSetBeatTarget,
            summaryText: "Auto-applied load increase"
        )
        proposal.appliedOverlays.append(overlay)
        context.insert(overlay)

        let adjustment = AppliedOverlayAdjustment(
            overlay: overlay,
            sequence: 0,
            targetProgramSessionExerciseID: fixture.week2Main.id,
            targetWeekNumber: 2,
            targetSessionNumber: 1,
            adjustmentType: .load,
            loadPercentDelta: 0.015,
            adjustmentReason: .topSetBeatTarget,
            isAutoApplied: true
        )
        overlay.adjustments.append(adjustment)
        context.insert(adjustment)

        let event = AdaptationEventHistory(
            programRun: run,
            trainingProgram: fixture.program,
            analysis: analysis,
            proposal: proposal,
            overlay: overlay,
            eventType: .overlayApplied,
            analysisWeekNumber: 1,
            targetLiftKey: "squat",
            message: "Overlay applied",
            adjustmentReason: .topSetBeatTarget,
            performanceScoreSnapshot: .overperformance,
            fatigueStatusSnapshot: .manageable,
            liftTrendStatusSnapshot: .improving,
            confidenceSnapshot: 0.7,
            requiresUserAction: false,
            userActionTaken: true
        )
        context.insert(event)

        try context.save()

        let fetchedOutcomes = try fetchAll(ExercisePerformanceOutcome.self, context)
        let fetchedAnalyses = try fetchAll(WeeklyTrainingAnalysis.self, context)
        let fetchedProposals = try fetchAll(AdaptationProposal.self, context)
        let fetchedOverlays = try fetchAll(AppliedProgramOverlay.self, context)
        let fetchedEvents = try fetchAll(AdaptationEventHistory.self, context)

        #expect(fetchedAnalyses.count == 1)
        #expect(fetchedOutcomes.count == 1)
        #expect(fetchedProposals.count == 1)
        #expect(fetchedOverlays.count == 1)
        #expect(fetchedEvents.count == 1)

        #expect(fetchedOutcomes[0].analysis?.id == fetchedAnalyses[0].id)
        #expect(fetchedOutcomes[0].workout?.id == workout.id)
        #expect(fetchedProposals[0].sourceAnalysis?.id == fetchedAnalyses[0].id)
        #expect(fetchedOverlays[0].sourceProposal?.id == fetchedProposals[0].id)
        #expect(fetchedOverlays[0].adjustments.count == 1)
        #expect(fetchedEvents[0].proposal?.id == fetchedProposals[0].id)
        #expect(fetchedEvents[0].overlay?.id == fetchedOverlays[0].id)
    }

    @Test func infersProgramWorkoutOutcomeFromPrescription() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let fixture = makeAdaptiveProgramFixture()
        persistProgram(fixture.program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = fixture.program
        context.insert(run)

        let workout = insertWorkout(
            date: day(1),
            run: run,
            week: 1,
            session: 1,
            entries: [
                EntrySpec(
                    exerciseName: "Back Squats",
                    sourceProgramSessionExerciseID: fixture.week1Main.id,
                    prescribedTargetSets: 3,
                    prescribedTargetReps: 5,
                    prescribedWeight: 300,
                    prescribedWeightUnit: "lbs",
                    prescribedWorkingSetStyle: .topSet,
                    sets: [
                        SetSpec(setNumber: 1, reps: 5, weight: 335),
                        SetSpec(setNumber: 2, reps: 5, weight: 325),
                        SetSpec(setNumber: 3, reps: 5, weight: 315),
                    ]
                )
            ],
            context: context
        )

        SessionOutcomeInferenceService.persistOutcomes(for: workout, context: context)
        try context.save()

        let outcomes = try fetchAll(ExercisePerformanceOutcome.self, context)
            .filter { $0.workout?.id == workout.id }

        #expect(outcomes.count == 1)
        guard let outcome = outcomes.first else { return }

        #expect(outcome.signalSource == .programLinked)
        #expect(outcome.signalConfidence == .high)
        #expect(outcome.signalWeight == AdaptiveSignalWeights.programWorkout)
        #expect(outcome.performanceScore == .overperformance || outcome.performanceScore == .exceptionalPerformance)
        #expect(outcome.completionRatio == 1.0)
        #expect(outcome.canonicalLiftKey == "squat")
        #expect(outcome.isTopSetSignal)
    }

    @Test func infersStandaloneWorkoutOutcomeFromHistoricalBaseline() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        _ = insertWorkout(
            date: day(0),
            entries: [
                EntrySpec(
                    exerciseName: "Barbell Row",
                    sets: [
                        SetSpec(setNumber: 1, reps: 5, weight: 185),
                        SetSpec(setNumber: 2, reps: 5, weight: 180),
                    ]
                )
            ],
            context: context
        )

        let currentWorkout = insertWorkout(
            date: day(7),
            entries: [
                EntrySpec(
                    exerciseName: "Barbell Row",
                    sets: [
                        SetSpec(setNumber: 1, reps: 5, weight: 205),
                        SetSpec(setNumber: 2, reps: 5, weight: 200),
                    ]
                )
            ],
            context: context
        )

        SessionOutcomeInferenceService.persistOutcomes(for: currentWorkout, context: context)
        try context.save()

        let outcomes = try fetchAll(ExercisePerformanceOutcome.self, context)
            .filter { $0.workout?.id == currentWorkout.id }

        #expect(outcomes.count == 1)
        guard let outcome = outcomes.first else { return }

        #expect(outcome.signalSource == .standalone)
        #expect(outcome.performanceScore != .insufficientData)
        #expect(outcome.signalConfidence == .low || outcome.signalConfidence == .medium)
        #expect(outcome.signalWeight < AdaptiveSignalWeights.programWorkout)
        #expect(outcome.notes?.contains("method=baseline") == true)
    }

    @Test func weeklyAnalysisAggregatesSignalsAndDedupesRepeatedProgramSessions() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Powerlifting Intermediate",
            lengthInWeeks: 2,
            sessionsPerWeek: 2,
            source: .aiGenerated
        )

        let week1 = ProgramWeekTemplate(weekNumber: 1)
        let session11 = ProgramSessionTemplate(sessionNumber: 1)
        let session12 = ProgramSessionTemplate(sessionNumber: 2)

        let squatRow = ProgramSessionExercise(
            exerciseName: "Back Squats",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 5,
            targetPercentage1RM: 0.80,
            prescribedWeight: 315,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet,
            baseLiftUsed: "Back Squats"
        )
        let benchRow = ProgramSessionExercise(
            exerciseName: "Bench Press",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 5,
            targetPercentage1RM: 0.78,
            prescribedWeight: 225,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet,
            baseLiftUsed: "Bench Press"
        )
        session11.exercises = [squatRow]
        session12.exercises = [benchRow]

        let week2 = ProgramWeekTemplate(weekNumber: 2)
        let session21 = ProgramSessionTemplate(sessionNumber: 1)
        let session22 = ProgramSessionTemplate(sessionNumber: 2)
        session21.exercises = [
            ProgramSessionExercise(
                exerciseName: "Back Squats",
                orderIndex: 0,
                targetSets: 3,
                targetReps: 4,
                targetPercentage1RM: 0.82,
                prescribedWeight: 325,
                prescribedWeightUnit: "lbs",
                workingSetStyle: .topSet,
                baseLiftUsed: "Back Squats"
            )
        ]
        session22.exercises = [
            ProgramSessionExercise(
                exerciseName: "Bench Press",
                orderIndex: 0,
                targetSets: 3,
                targetReps: 4,
                targetPercentage1RM: 0.80,
                prescribedWeight: 230,
                prescribedWeightUnit: "lbs",
                workingSetStyle: .topSet,
                baseLiftUsed: "Bench Press"
            )
        ]

        week1.sessions = [session11, session12]
        week2.sessions = [session21, session22]
        program.weeks = [week1, week2]
        persistProgram(program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = program
        context.insert(run)

        let firstSessionOriginal = insertWorkout(
            date: day(1),
            run: run,
            week: 1,
            session: 1,
            entries: [
                EntrySpec(
                    exerciseName: "Back Squats",
                    sourceProgramSessionExerciseID: squatRow.id,
                    prescribedTargetSets: 3,
                    prescribedTargetReps: 5,
                    prescribedWeight: 315,
                    prescribedWeightUnit: "lbs",
                    sets: [SetSpec(setNumber: 1, reps: 5, weight: 315)]
                )
            ],
            context: context
        )

        let firstSessionRepeat = insertWorkout(
            date: day(2),
            run: run,
            week: 1,
            session: 1,
            entries: [
                EntrySpec(
                    exerciseName: "Back Squats",
                    sourceProgramSessionExerciseID: squatRow.id,
                    prescribedTargetSets: 3,
                    prescribedTargetReps: 5,
                    prescribedWeight: 315,
                    prescribedWeightUnit: "lbs",
                    sets: [SetSpec(setNumber: 1, reps: 5, weight: 325)]
                )
            ],
            context: context
        )

        let secondSession = insertWorkout(
            date: day(3),
            run: run,
            week: 1,
            session: 2,
            entries: [
                EntrySpec(
                    exerciseName: "Bench Press",
                    sourceProgramSessionExerciseID: benchRow.id,
                    prescribedTargetSets: 3,
                    prescribedTargetReps: 5,
                    prescribedWeight: 225,
                    prescribedWeightUnit: "lbs",
                    sets: [SetSpec(setNumber: 1, reps: 5, weight: 230)]
                )
            ],
            context: context
        )

        let standalone = insertWorkout(
            date: day(4),
            entries: [
                EntrySpec(
                    exerciseName: "Barbell Row",
                    sets: [SetSpec(setNumber: 1, reps: 8, weight: 185)]
                )
            ],
            context: context
        )

        SessionOutcomeInferenceService.persistOutcomes(for: firstSessionOriginal, context: context)
        SessionOutcomeInferenceService.persistOutcomes(for: firstSessionRepeat, context: context)
        SessionOutcomeInferenceService.persistOutcomes(for: secondSession, context: context)
        SessionOutcomeInferenceService.persistOutcomes(for: standalone, context: context)

        let analysis = WeeklyTrainingAnalysisService.analyzeProgramWeek(
            run: run,
            weekNumber: 1,
            context: context
        )
        try context.save()

        #expect(analysis != nil)
        #expect(analysis?.programWorkoutCount == 2)
        #expect(analysis?.standaloneWorkoutCount == 1)
        #expect(analysis?.totalOutcomeCount == 3)
        #expect((analysis?.volumeMetrics.isEmpty ?? true) == false)
        #expect((analysis?.programSignalWeight ?? 0) > (analysis?.standaloneSignalWeight ?? 0))

        let events = try fetchAll(AdaptationEventHistory.self, context)
        let weeklyEvent = events.first { $0.eventType == .weeklyAnalysisFinalized && $0.analysis?.id == analysis?.id }
        #expect(weeklyEvent != nil)
    }

    @Test func topSetProgressionCreatesLoadProposal() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let fixture = makeAdaptiveProgramFixture(name: "Powerlifting Intermediate")
        persistProgram(fixture.program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = fixture.program
        context.insert(run)

        let analysis = WeeklyTrainingAnalysis(
            weekStartDate: day(0),
            weekEndDate: day(6),
            programRun: run,
            trainingProgram: fixture.program,
            programWeekNumber: 1,
            fatigueStatus: .manageable,
            isFinalized: true,
            finalizedAt: day(7)
        )
        context.insert(analysis)

        _ = appendOutcome(
            to: analysis,
            context: context,
            run: run,
            workoutDate: day(3),
            exerciseName: "Back Squats",
            canonicalLiftKey: "squat",
            scoreValue: 10,
            performance: .overperformance,
            fatigue: .manageable,
            source: .programLinked,
            confidence: .high,
            signalWeight: 1.0,
            isTopSet: true,
            topSetWeight: 335,
            topSetReps: 5,
            e1rm: 390
        )

        AdaptiveLoadProgressionService.generateProposals(from: analysis, context: context)
        try context.save()

        let proposals = try fetchAll(AdaptationProposal.self, context)
        let squatProposal = proposals.first {
            $0.targetLiftKey == "squat" &&
            $0.targetWeekStart == 2 &&
            $0.proposalType == .increaseLoad
        }

        #expect(squatProposal != nil)
        #expect(squatProposal?.proposalStatus == .pendingAutoApply)
        #expect(squatProposal?.requiresUserConfirmation == false)
        #expect((squatProposal?.proposedLoadPercentDelta ?? 0) > 0)
    }

    @Test func volumeEngineCreatesUserConfirmedProposal() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let fixture = makeAdaptiveProgramFixture(
            name: "Powerbuilding Intermediate",
            includeWeek2Accessory: true
        )
        persistProgram(fixture.program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = fixture.program
        context.insert(run)

        let analysis = WeeklyTrainingAnalysis(
            weekStartDate: day(0),
            weekEndDate: day(6),
            programRun: run,
            trainingProgram: fixture.program,
            programWeekNumber: 1,
            totalSignalWeight: 6,
            fatigueStatus: .high,
            isFinalized: true,
            finalizedAt: day(7)
        )
        context.insert(analysis)

        let metric = WeeklyVolumeMetric(
            analysis: analysis,
            muscle: .shoulders,
            plannedHardSets: 3,
            completedHardSets: 5,
            weightedCompletedHardSets: 5,
            deltaHardSets: 2
        )
        analysis.volumeMetrics.append(metric)
        context.insert(metric)

        AdaptiveVolumeProgressionService.generateProposals(from: analysis, context: context)
        try context.save()

        let proposals = try fetchAll(AdaptationProposal.self, context)
        let volumeProposal = proposals.first {
            $0.targetProgramSessionExerciseID == fixture.week2Accessory?.id &&
            $0.proposalType == .decreaseVolume
        }

        #expect(volumeProposal != nil)
        #expect(volumeProposal?.proposalStatus == .pendingUserConfirmation)
        #expect(volumeProposal?.requiresUserConfirmation == true)
        #expect(volumeProposal?.proposedSetDelta == -1)
    }

    @Test func fatigueEngineCreatesDeloadProposal() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let fixture = makeAdaptiveProgramFixture(name: "Powerlifting Intermediate")
        persistProgram(fixture.program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = fixture.program
        context.insert(run)

        let analysis1 = WeeklyTrainingAnalysis(
            weekStartDate: day(0),
            weekEndDate: day(6),
            programRun: run,
            trainingProgram: fixture.program,
            programWeekNumber: 1,
            fatigueStatus: .elevated,
            isFinalized: true,
            finalizedAt: day(7)
        )
        let analysis2 = WeeklyTrainingAnalysis(
            weekStartDate: day(7),
            weekEndDate: day(13),
            programRun: run,
            trainingProgram: fixture.program,
            programWeekNumber: 2,
            fatigueStatus: .high,
            isFinalized: true,
            finalizedAt: day(14)
        )
        context.insert(analysis1)
        context.insert(analysis2)

        let liftKeys = ["squat", "bench", "deadlift"]
        for (index, liftKey) in liftKeys.enumerated() {
            _ = appendOutcome(
                to: analysis1,
                context: context,
                run: run,
                workoutDate: day(2 + index),
                exerciseName: liftDisplayName(for: liftKey),
                canonicalLiftKey: liftKey,
                scoreValue: -8,
                performance: .underperformance,
                fatigue: .elevated,
                source: .programLinked,
                confidence: .high,
                signalWeight: 1.0,
                isTopSet: true,
                topSetWeight: 250,
                topSetReps: 3,
                e1rm: 275
            )
            _ = appendOutcome(
                to: analysis2,
                context: context,
                run: run,
                workoutDate: day(9 + index),
                exerciseName: liftDisplayName(for: liftKey),
                canonicalLiftKey: liftKey,
                scoreValue: -9,
                performance: .underperformance,
                fatigue: .high,
                source: .programLinked,
                confidence: .high,
                signalWeight: 1.0,
                isTopSet: true,
                topSetWeight: 245,
                topSetReps: 3,
                e1rm: 268
            )
        }

        AdaptiveFatigueDeloadService.generateProposals(from: analysis2, context: context)
        try context.save()

        let proposals = try fetchAll(AdaptationProposal.self, context)
        let deload = proposals.first {
            $0.proposalType == .deload &&
            $0.targetLiftKey == "globalFatigue" &&
            $0.targetWeekStart == 3
        }

        #expect(deload != nil)
        #expect(deload?.proposalStatus == .pendingUserConfirmation)
        #expect(deload?.requiresUserConfirmation == true)
        #expect((deload?.proposedLoadPercentDelta ?? 0) < 0)
        #expect(deload?.proposedSetDelta == -1)
    }

    @Test func liftTrendTrackingClassifiesImprovingWithProgramAndStandaloneSignals() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let fixture = makeAdaptiveProgramFixture(name: "Powerlifting Intermediate")
        persistProgram(fixture.program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = fixture.program
        context.insert(run)

        let analyses = [
            WeeklyTrainingAnalysis(
                weekStartDate: day(0),
                weekEndDate: day(6),
                programRun: run,
                trainingProgram: fixture.program,
                programWeekNumber: 1,
                isFinalized: true,
                finalizedAt: day(7)
            ),
            WeeklyTrainingAnalysis(
                weekStartDate: day(7),
                weekEndDate: day(13),
                programRun: run,
                trainingProgram: fixture.program,
                programWeekNumber: 2,
                isFinalized: true,
                finalizedAt: day(14)
            ),
            WeeklyTrainingAnalysis(
                weekStartDate: day(14),
                weekEndDate: day(20),
                programRun: run,
                trainingProgram: fixture.program,
                programWeekNumber: 3,
                isFinalized: true,
                finalizedAt: day(21)
            ),
        ]
        analyses.forEach { context.insert($0) }

        let e1rmTriples: [(Double, Double)] = [(300, 295), (310, 300), (320, 305)]
        for index in analyses.indices {
            let analysis = analyses[index]
            let (programE1RM, standaloneE1RM) = e1rmTriples[index]

            _ = appendOutcome(
                to: analysis,
                context: context,
                run: run,
                workoutDate: day((index * 7) + 2),
                exerciseName: "Back Squats",
                canonicalLiftKey: "squat",
                scoreValue: 3 + Double(index),
                performance: .overperformance,
                fatigue: .manageable,
                source: .programLinked,
                confidence: .high,
                signalWeight: 1.0,
                isTopSet: true,
                topSetWeight: programE1RM * 0.85,
                topSetReps: 3,
                e1rm: programE1RM
            )
            _ = appendOutcome(
                to: analysis,
                context: context,
                run: nil,
                workoutDate: day((index * 7) + 3),
                exerciseName: "Pause Squat",
                canonicalLiftKey: "squat",
                scoreValue: 2 + Double(index),
                performance: .onTarget,
                fatigue: .manageable,
                source: .standalone,
                confidence: .medium,
                signalWeight: AdaptiveSignalWeights.standaloneWorkout,
                isTopSet: true,
                topSetWeight: standaloneE1RM * 0.85,
                topSetReps: 3,
                e1rm: standaloneE1RM
            )
        }

        let summary = LiftTrendTrackingService.updateTrends(for: analyses[2], context: context)
        try context.save()

        #expect(summary["squat"] == .improving)

        let trends = try fetchAll(LiftPerformanceTrend.self, context)
        let squatTrend = trends.first { $0.programRun?.id == run.id && $0.canonicalLiftKey == "squat" }

        #expect(squatTrend != nil)
        #expect((squatTrend?.programLinkedDataPoints ?? 0) > 0)
        #expect((squatTrend?.standaloneDataPoints ?? 0) > 0)
        #expect(squatTrend?.trendStatus == .improving)

        let snapshots = try fetchAll(LiftTrendSnapshot.self, context)
        let latestSnapshot = snapshots.first { $0.analysis?.id == analyses[2].id && $0.canonicalLiftKey == "squat" }
        #expect(latestSnapshot != nil)
        #expect(latestSnapshot?.trendStatus == .improving)
        #expect((latestSnapshot?.weightedProgramSignal ?? 0) > (latestSnapshot?.weightedStandaloneSignal ?? 0))
    }

    @Test func variationSwapCreatesActiveOverlayWithoutMutatingBaseProgram() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let fixture = makeAdaptiveProgramFixture(name: "Powerlifting Intermediate")
        persistProgram(fixture.program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = fixture.program
        context.insert(run)

        let analysis1 = WeeklyTrainingAnalysis(
            weekStartDate: day(0),
            weekEndDate: day(6),
            programRun: run,
            trainingProgram: fixture.program,
            programWeekNumber: 1,
            fatigueStatus: .manageable,
            isFinalized: true,
            finalizedAt: day(7)
        )
        let analysis2 = WeeklyTrainingAnalysis(
            weekStartDate: day(7),
            weekEndDate: day(13),
            programRun: run,
            trainingProgram: fixture.program,
            programWeekNumber: 2,
            fatigueStatus: .high,
            isFinalized: true,
            finalizedAt: day(14)
        )
        context.insert(analysis1)
        context.insert(analysis2)

        _ = appendOutcome(
            to: analysis1,
            context: context,
            run: run,
            workoutDate: day(3),
            exerciseName: "Back Squats",
            canonicalLiftKey: "squat",
            scoreValue: -8,
            performance: .underperformance,
            fatigue: .elevated,
            source: .programLinked,
            confidence: .high,
            signalWeight: 1.0,
            isTopSet: true,
            topSetWeight: 295,
            topSetReps: 3,
            e1rm: 325
        )
        _ = appendOutcome(
            to: analysis2,
            context: context,
            run: run,
            workoutDate: day(10),
            exerciseName: "Back Squats",
            canonicalLiftKey: "squat",
            scoreValue: -9,
            performance: .underperformance,
            fatigue: .high,
            source: .programLinked,
            confidence: .high,
            signalWeight: 1.0,
            isTopSet: true,
            topSetWeight: 285,
            topSetReps: 3,
            e1rm: 312
        )

        AdaptiveVariationSwapService.generateAndApply(from: analysis2, context: context)
        try context.save()

        let overlays = try fetchAll(AppliedProgramOverlay.self, context)
        let swapOverlay = overlays.first { $0.programRun?.id == run.id && $0.overlayStatus == .active }

        #expect(swapOverlay != nil)
        #expect(swapOverlay?.appliedByUserConfirmation == false)
        #expect(swapOverlay?.adjustments.contains(where: { $0.adjustmentType == .variationSwap }) == true)

        let replacement = swapOverlay?.adjustments.first?.replacementExerciseName
        #expect(replacement != nil)
        #expect(replacement != "Back Squats")

        let proposals = try fetchAll(AdaptationProposal.self, context)
        let swapProposal = proposals.first { $0.id == swapOverlay?.sourceProposal?.id }
        #expect(swapProposal?.proposalStatus == .autoApplied)

        let baseWeek3Exercise = fixture.program.weeks
            .first(where: { $0.weekNumber == 3 })?
            .sessions.first(where: { $0.sessionNumber == 1 })?
            .exercises.first?.exerciseName
        #expect(baseWeek3Exercise == "Back Squats")

        let resolved = ProgramOverlayResolutionService.resolvedExercises(
            for: run,
            week: 3,
            session: 1,
            context: context
        )
        #expect(resolved.first?.exerciseName == replacement)
    }

    @Test func proposalApprovalAndRejectionUpdateStatusesAndOverlayActivation() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let fixture = makeAdaptiveProgramFixture(
            name: "Powerbuilding Intermediate",
            includeWeek2Accessory: true
        )
        persistProgram(fixture.program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = fixture.program
        context.insert(run)

        let analysis = WeeklyTrainingAnalysis(
            weekStartDate: day(0),
            weekEndDate: day(6),
            programRun: run,
            trainingProgram: fixture.program,
            programWeekNumber: 1,
            fatigueStatus: .elevated,
            isFinalized: true,
            finalizedAt: day(7)
        )
        context.insert(analysis)

        let approveProposal = AdaptationProposal(
            programRun: run,
            trainingProgram: fixture.program,
            sourceAnalysis: analysis,
            proposalType: .increaseVolume,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.65,
            priority: 75,
            targetWeekStart: 2,
            targetWeekEnd: 2,
            targetSessionNumber: 1,
            targetProgramSessionExerciseID: fixture.week2Accessory?.id,
            targetLiftKey: "muscle:shoulders",
            proposedSetDelta: 1,
            adjustmentReason: .accessoryOutperformance,
            summaryText: "Increase shoulder volume"
        )

        let rejectProposal = AdaptationProposal(
            programRun: run,
            trainingProgram: fixture.program,
            sourceAnalysis: analysis,
            proposalType: .deload,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.72,
            priority: 92,
            targetWeekStart: 2,
            targetWeekEnd: 2,
            targetLiftKey: "globalFatigue",
            proposedLoadPercentDelta: -0.07,
            proposedSetDelta: -1,
            proposedDeloadFactor: 0.92,
            adjustmentReason: .fatigueAccumulation,
            summaryText: "Deload week"
        )

        context.insert(approveProposal)
        context.insert(rejectProposal)

        try AdaptationProposalConfirmationService.approve(approveProposal, context: context)
        try AdaptationProposalConfirmationService.reject(rejectProposal, context: context)

        #expect(approveProposal.proposalStatus == ProposalStatus.confirmed)
        #expect(rejectProposal.proposalStatus == ProposalStatus.rejected)

        let overlays = try fetchAll(AppliedProgramOverlay.self, context)
        let approvedOverlay = overlays.first { $0.sourceProposal?.id == approveProposal.id }
        #expect(approvedOverlay != nil)
        #expect(approvedOverlay?.overlayStatus == .active)
        #expect(approvedOverlay?.appliedByUserConfirmation == true)
        #expect(approvedOverlay?.adjustments.first?.adjustmentType == .volume)

        let rejectedOverlay = overlays.first { $0.sourceProposal?.id == rejectProposal.id }
        #expect(rejectedOverlay == nil)

        let events = try fetchAll(AdaptationEventHistory.self, context)
        #expect(events.contains(where: { $0.eventType == .proposalConfirmed && $0.proposal?.id == approveProposal.id }))
        #expect(events.contains(where: { $0.eventType == .overlayApplied && $0.proposal?.id == approveProposal.id }))
        #expect(events.contains(where: { $0.eventType == .proposalRejected && $0.proposal?.id == rejectProposal.id }))
    }

    @Test func workoutAndProgramSaveFlowRemainsIntactWithAdaptiveServices() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let fixture = makeAdaptiveProgramFixture(name: "Powerlifting Intermediate")
        persistProgram(fixture.program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = fixture.program
        context.insert(run)

        let programWorkout = insertWorkout(
            date: day(1),
            run: run,
            week: 1,
            session: 1,
            entries: [
                EntrySpec(
                    exerciseName: "Back Squats",
                    sourceProgramSessionExerciseID: fixture.week1Main.id,
                    prescribedTargetSets: 3,
                    prescribedTargetReps: 5,
                    prescribedWeight: 315,
                    prescribedWeightUnit: "lbs",
                    sets: [
                        SetSpec(setNumber: 1, reps: 5, weight: 315),
                        SetSpec(setNumber: 2, reps: 5, weight: 305),
                    ]
                )
            ],
            context: context
        )

        let standaloneWorkout = insertWorkout(
            date: day(2),
            entries: [
                EntrySpec(
                    exerciseName: "Barbell Row",
                    sets: [SetSpec(setNumber: 1, reps: 8, weight: 185)]
                )
            ],
            context: context
        )

        SessionOutcomeInferenceService.persistOutcomes(for: programWorkout, context: context)
        WeeklyTrainingAnalysisService.analyzeCompletedWeeks(triggeredBy: programWorkout, context: context)

        SessionOutcomeInferenceService.persistOutcomes(for: standaloneWorkout, context: context)
        WeeklyTrainingAnalysisService.analyzeCompletedWeeks(triggeredBy: standaloneWorkout, context: context)

        try context.save()

        let workouts = try fetchAll(Workout.self, context)
        let entries = try fetchAll(ExerciseEntry.self, context)
        let sets = try fetchAll(SetEntry.self, context)
        let outcomes = try fetchAll(ExercisePerformanceOutcome.self, context)
        let analyses = try fetchAll(WeeklyTrainingAnalysis.self, context)

        #expect(workouts.count == 2)
        #expect(entries.count == 2)
        #expect(sets.count == 3)
        #expect(outcomes.count == 2)
        #expect(analyses.isEmpty == false)

        let fetchedProgramWorkout = workouts.first { $0.id == programWorkout.id }
        #expect(fetchedProgramWorkout?.programRun?.id == run.id)
        #expect(fetchedProgramWorkout?.programWeekNumber == 1)
        #expect(fetchedProgramWorkout?.programSessionNumber == 1)

        let fetchedStandalone = workouts.first { $0.id == standaloneWorkout.id }
        #expect(fetchedStandalone?.programRun == nil)
        #expect(fetchedStandalone?.programWeekNumber == nil)
        #expect(fetchedStandalone?.programSessionNumber == nil)
    }

    // MARK: - Helpers

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            PersonalRecord.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            ProgramRun.self,
            ExercisePerformanceOutcome.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AppliedOverlayAdjustment.self,
            AdaptationEventHistory.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func day(_ offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12, minute: 0, second: 0)) ?? Date()
        return calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }

    private func persistProgram(_ program: TrainingProgram, context: ModelContext) {
        for week in program.weeks {
            week.program = program
            for session in week.sessions {
                session.week = week
                for exercise in session.exercises {
                    exercise.session = session
                }
            }
        }
        context.insert(program)
    }

    @discardableResult
    private func insertWorkout(
        date: Date,
        run: ProgramRun? = nil,
        week: Int? = nil,
        session: Int? = nil,
        entries: [EntrySpec],
        context: ModelContext
    ) -> Workout {
        let start = date.addingTimeInterval(-3600)
        let workout = Workout(
            date: date,
            startTime: start,
            durationSeconds: 3600,
            programRun: run,
            programWeekNumber: week,
            programSessionNumber: session
        )
        context.insert(workout)

        for (index, spec) in entries.enumerated() {
            let entry = ExerciseEntry(
                exerciseName: spec.exerciseName,
                unit: spec.unit,
                orderIndex: spec.orderIndex ?? index,
                isCardio: spec.isCardio,
                cardioDurationSeconds: spec.cardioDurationSeconds,
                sourceProgramSessionExerciseID: spec.sourceProgramSessionExerciseID,
                prescribedTargetSets: spec.prescribedTargetSets,
                prescribedTargetReps: spec.prescribedTargetReps,
                prescribedTargetPercentage1RM: spec.prescribedTargetPercentage1RM,
                prescribedTargetRPE: spec.prescribedTargetRPE,
                prescribedTargetRIR: spec.prescribedTargetRIR,
                prescribedWeight: spec.prescribedWeight,
                prescribedWeightUnit: spec.prescribedWeightUnit,
                prescribedWorkingSetStyle: spec.prescribedWorkingSetStyle,
                prescribedTargetEffortType: spec.prescribedTargetEffortType
            )
            entry.workout = workout
            workout.exerciseEntries.append(entry)
            context.insert(entry)

            for set in spec.sets {
                let setEntry = SetEntry(setNumber: set.setNumber, reps: set.reps, weight: set.weight)
                setEntry.exerciseEntry = entry
                entry.sets.append(setEntry)
                context.insert(setEntry)
            }
        }

        return workout
    }

    @discardableResult
    private func appendOutcome(
        to analysis: WeeklyTrainingAnalysis,
        context: ModelContext,
        run: ProgramRun?,
        workoutDate: Date,
        exerciseName: String,
        canonicalLiftKey: String,
        scoreValue: Double,
        performance: PerformanceScore,
        fatigue: FatigueStatus,
        source: WorkoutSignalSource,
        confidence: WorkoutSignalConfidence,
        signalWeight: Double,
        isTopSet: Bool,
        topSetWeight: Double,
        topSetReps: Int,
        e1rm: Double
    ) -> ExercisePerformanceOutcome {
        let outcome = ExercisePerformanceOutcome(
            analysis: analysis,
            programRun: run,
            workoutDate: workoutDate,
            programWeekNumber: analysis.programWeekNumber,
            exerciseName: exerciseName,
            canonicalLiftKey: canonicalLiftKey,
            signalSource: source,
            signalConfidence: confidence,
            signalWeight: signalWeight,
            actualSetCount: 3,
            actualAverageReps: Double(topSetReps),
            actualAverageWeight: topSetWeight,
            actualTopSetReps: topSetReps,
            actualTopSetWeight: topSetWeight,
            actualTopSetEstimated1RM: e1rm,
            performanceScoreValue: scoreValue,
            performanceScore: performance,
            inferredFatigueStatus: fatigue,
            isTopSetSignal: isTopSet,
            notes: "validation-fixture"
        )
        analysis.outcomes.append(outcome)
        context.insert(outcome)
        return outcome
    }

    private func fetchAll<T: PersistentModel>(
        _ type: T.Type,
        _ context: ModelContext
    ) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    private func makeAdaptiveProgramFixture(
        name: String = "Powerlifting Intermediate",
        includeWeek2Accessory: Bool = false
    ) -> AdaptiveProgramFixture {
        let week1Main = ProgramSessionExercise(
            exerciseName: "Back Squats",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 5,
            targetPercentage1RM: 0.80,
            prescribedWeight: 315,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet,
            baseLiftUsed: "Back Squats"
        )

        let week2Main = ProgramSessionExercise(
            exerciseName: "Back Squats",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 4,
            targetPercentage1RM: 0.82,
            prescribedWeight: 325,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet,
            baseLiftUsed: "Back Squats"
        )

        let week2Accessory: ProgramSessionExercise? = includeWeek2Accessory
            ? ProgramSessionExercise(
                exerciseName: "Lateral Raises",
                orderIndex: 1,
                targetSets: 3,
                targetReps: 12,
                targetRPE: 8,
                workingSetStyle: .straight,
                baseLiftUsed: "Lateral Raises"
            )
            : nil

        let week3Main = ProgramSessionExercise(
            exerciseName: "Back Squats",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 3,
            targetPercentage1RM: 0.84,
            prescribedWeight: 335,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet,
            baseLiftUsed: "Back Squats"
        )

        let week1Session = ProgramSessionTemplate(sessionNumber: 1)
        week1Session.exercises = [week1Main]

        let week2Session = ProgramSessionTemplate(sessionNumber: 1)
        if let week2Accessory {
            week2Session.exercises = [week2Main, week2Accessory]
        } else {
            week2Session.exercises = [week2Main]
        }

        let week3Session = ProgramSessionTemplate(sessionNumber: 1)
        week3Session.exercises = [week3Main]

        let week1 = ProgramWeekTemplate(weekNumber: 1)
        week1.sessions = [week1Session]

        let week2 = ProgramWeekTemplate(weekNumber: 2)
        week2.sessions = [week2Session]

        let week3 = ProgramWeekTemplate(weekNumber: 3)
        week3.sessions = [week3Session]

        let program = TrainingProgram(
            name: name,
            lengthInWeeks: 3,
            sessionsPerWeek: 1,
            source: .aiGenerated
        )
        program.weeks = [week1, week2, week3]

        return AdaptiveProgramFixture(
            program: program,
            week1Main: week1Main,
            week2Main: week2Main,
            week2Accessory: week2Accessory,
            week3Main: week3Main
        )
    }

    private func liftDisplayName(for canonicalLiftKey: String) -> String {
        switch canonicalLiftKey {
        case "squat": return "Back Squats"
        case "bench": return "Bench Press"
        case "deadlift": return "Deadlift"
        default: return canonicalLiftKey
        }
    }
}

private struct SetSpec {
    let setNumber: Int
    let reps: Int
    let weight: Double
}

private struct EntrySpec {
    let exerciseName: String
    var unit: WeightUnit = .lbs
    var orderIndex: Int? = nil
    var isCardio: Bool = false
    var cardioDurationSeconds: Int? = nil
    var sourceProgramSessionExerciseID: UUID? = nil
    var prescribedTargetSets: Int? = nil
    var prescribedTargetReps: Int? = nil
    var prescribedTargetPercentage1RM: Double? = nil
    var prescribedTargetRPE: Double? = nil
    var prescribedTargetRIR: Double? = nil
    var prescribedWeight: Double? = nil
    var prescribedWeightUnit: String? = nil
    var prescribedWorkingSetStyle: ProgramWorkingSetStyle? = nil
    var prescribedTargetEffortType: ProgramTargetEffortType? = nil
    var sets: [SetSpec] = []
}

private struct AdaptiveProgramFixture {
    let program: TrainingProgram
    let week1Main: ProgramSessionExercise
    let week2Main: ProgramSessionExercise
    let week2Accessory: ProgramSessionExercise?
    let week3Main: ProgramSessionExercise
}
