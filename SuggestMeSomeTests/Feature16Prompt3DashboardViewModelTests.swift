import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature16Prompt3DashboardViewModelTests {

    @Test func dashboardRefreshCachesWindowedAnalyticsAndAdaptiveSnapshots() {
        let viewModel = DashboardViewModel()
        let chest = MuscleGroup(name: "Chest")
        let back = MuscleGroup(name: "Back")
        let exercises = [
            Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Barbell Row", exerciseType: .compound, muscleGroup: back),
        ]
        let program = TrainingProgram(
            name: "Strength Focus",
            lengthInWeeks: 8,
            sessionsPerWeek: 3,
            createdDate: Date(),
            source: .aiGenerated
        )
        let run = ProgramRun(startDate: daysAgo(14))
        run.program = program
        let workouts = [
            makeWorkout(
                exerciseName: "Bench Press",
                setSpecs: [(5, 225, true), (5, 215, false)],
                date: daysAgo(3),
                durationSeconds: 3600,
                programRun: run,
                programWeekNumber: 1,
                programSessionNumber: 1
            ),
            makeWorkout(
                exerciseName: "Barbell Row",
                setSpecs: [(8, 185, false)],
                date: daysAgo(10),
                durationSeconds: 2700
            ),
        ]
        let prs = [
            PersonalRecord(
                exerciseName: "Bench Press",
                repCount: 5,
                weight: 225,
                unit: .lbs,
                dateAchieved: daysAgo(3)
            )
        ]
        let analyses = [
            WeeklyTrainingAnalysis(
                weekStartDate: daysAgo(7),
                weekEndDate: daysAgo(1),
                programRun: run,
                trainingProgram: program,
                fatigueStatus: .manageable,
                isFinalized: true
            )
        ]
        let liftTrends = [
            LiftPerformanceTrend(
                canonicalLiftKey: "bench",
                liftDisplayName: CanonicalLift.bench.displayName,
                totalDataPoints: 6,
                confidenceScore: 0.6,
                fourWeekChangePercent: 2.5,
                trendStatus: .improving
            )
        ]
        let proposals = [
            AdaptationProposal(
                programRun: run,
                trainingProgram: program,
                proposalType: .increaseLoad,
                proposalStatus: .pendingUserConfirmation,
                requiresUserConfirmation: true,
                autoApplyEligible: false,
                confidenceScore: 0.8,
                priority: 90,
                targetWeekStart: 2,
                targetWeekEnd: 2,
                targetSessionNumber: 1,
                adjustmentReason: .positiveLiftTrend,
                summaryText: "Add 5 lb to the bench top set next week."
            )
        ]
        let trainingStateSnapshot = TrainingStateSnapshot(
            historyWindowWorkoutCount: 12,
            hasSparseHistory: false,
            adherenceTier: .high,
            recentVolumeCompletionRate: 0.92,
            fatigueStatus: .elevated,
            recoveryPressure: .elevated,
            liftMomentumByCanonicalLift: [.bench: .improving],
            perMuscleStressSaturation: [.chest: 1.1],
            preferredAnchorExerciseNames: ["Bench Press"],
            underusedExerciseNames: ["Barbell Row"],
            activeProgramInterferenceRisk: 0.2,
            equipmentReliabilityScore: 0.9,
            continuityBias: 0.6,
            blockedCanonicalLifts: []
        )
        let healthKitInsight = ObjectiveRecoveryInsight(
            status: .caution,
            compactSummary: "Recovery dipped",
            detailSummary: "Sleep and HRV trailed baseline.",
            evaluatedMetricsCount: 2
        )

        viewModel.refresh(
            workouts: workouts,
            activeProgramRuns: [run],
            allPRs: prs,
            exercises: exercises,
            weeklyAnalyses: analyses,
            liftTrends: liftTrends,
            allProposals: proposals,
            trainingStateSnapshot: trainingStateSnapshot,
            healthKitInsight: healthKitInsight
        )

        #expect(viewModel.workoutCount == 2)
        #expect(viewModel.prCount == 1)
        #expect(viewModel.frequencyTarget == 3)
        #expect(viewModel.pendingProposals.count == 1)
        #expect(viewModel.significantLiftTrends.count == 1)
        #expect(viewModel.volumeByMuscleGroup.first?.group == "Chest")
        #expect(viewModel.muscleGroupVolumeCounts["Chest"] == 2)
        #expect(viewModel.exerciseNameToMuscleGroup["Bench Press"] == "Chest")
        #expect(viewModel.snapshotFatigueStatus == .elevated)
        #expect(viewModel.recoveryPressure == .elevated)
        #expect(viewModel.healthKitInsight?.status == .caution)
        #expect(viewModel.hasAdaptiveSignals)
        #expect(viewModel.workoutsSparkline.isEmpty == false)
    }

    @Test func dashboardRefreshRebuildsCachedWindowWhenTimeWindowChanges() {
        let viewModel = DashboardViewModel()
        let recentWorkout = makeWorkout(
            exerciseName: "Bench Press",
            setSpecs: [(5, 205, false)],
            date: daysAgo(7),
            durationSeconds: 3000
        )
        let olderWorkout = makeWorkout(
            exerciseName: "Bench Press",
            setSpecs: [(5, 195, false)],
            date: daysAgo(120),
            durationSeconds: 3000
        )

        viewModel.refresh(
            workouts: [recentWorkout, olderWorkout],
            activeProgramRuns: [],
            allPRs: [],
            exercises: [Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: MuscleGroup(name: "Chest"))],
            weeklyAnalyses: [],
            liftTrends: [],
            allProposals: [],
            trainingStateSnapshot: nil,
            healthKitInsight: nil
        )

        #expect(viewModel.workoutCount == 1)

        viewModel.timeWindow = .all

        #expect(viewModel.workoutCount == 2)
        #expect(viewModel.filteredWorkouts.count == 2)
        #expect(viewModel.workoutFrequencyBuckets.count >= 2)
    }

    @Test func dashboardRefreshFingerprintChangesWhenExistingExerciseChangesWithoutCountDelta() {
        let chest = MuscleGroup(name: "Chest")
        let exercise = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest)

        let base = makeDashboardFingerprint(exercises: [exercise])

        exercise.name = "Incline Bench Press"
        let updated = makeDashboardFingerprint(exercises: [exercise])

        #expect(base != updated)
    }

    @Test func dashboardRefreshFingerprintChangesWhenNonLeadingWorkoutChanges() {
        let recentWorkout = Workout(
            date: daysAgo(1),
            startTime: daysAgo(1),
            durationSeconds: 3600
        )
        let olderWorkout = Workout(
            date: daysAgo(10),
            startTime: daysAgo(10),
            durationSeconds: 2700
        )

        let base = makeDashboardFingerprint(workouts: [recentWorkout, olderWorkout])

        olderWorkout.syncVersion += 1
        olderWorkout.syncLastModifiedAt = Date(timeIntervalSince1970: 1_776_000_120)
        let updated = makeDashboardFingerprint(workouts: [recentWorkout, olderWorkout])

        #expect(base != updated)
    }

    @Test func dashboardRefreshFingerprintChangesWhenNonLeadingActiveRunChanges() {
        let leadingRun = ProgramRun(startDate: daysAgo(3))
        let trailingRun = ProgramRun(startDate: daysAgo(14))

        let base = makeDashboardFingerprint(activeProgramRuns: [leadingRun, trailingRun])

        trailingRun.syncVersion += 1
        trailingRun.syncLastModifiedAt = Date(timeIntervalSince1970: 1_776_000_240)
        let updated = makeDashboardFingerprint(activeProgramRuns: [leadingRun, trailingRun])

        #expect(base != updated)
    }

    @Test func dashboardRefreshFingerprintChangesWhenNonLeadingProposalChanges() {
        let highPriority = AdaptationProposal(
            proposalType: .increaseLoad,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            confidenceScore: 0.8,
            priority: 90,
            targetWeekStart: 1,
            adjustmentReason: .positiveLiftTrend,
            summaryText: "High"
        )
        let lowPriority = AdaptationProposal(
            proposalType: .increaseLoad,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            confidenceScore: 0.6,
            priority: 10,
            targetWeekStart: 1,
            adjustmentReason: .positiveLiftTrend,
            summaryText: "Low"
        )

        let base = makeDashboardFingerprint(proposals: [highPriority, lowPriority])

        lowPriority.syncVersion += 1
        lowPriority.syncLastModifiedAt = Date(timeIntervalSince1970: 1_776_000_360)
        let updated = makeDashboardFingerprint(proposals: [highPriority, lowPriority])

        #expect(base != updated)
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    private func makeDashboardFingerprint(
        activeProgramRuns: [ProgramRun] = [],
        workouts: [Workout] = [],
        prs: [PersonalRecord] = [],
        exercises: [Exercise] = [],
        weeklyAnalyses: [WeeklyTrainingAnalysis] = [],
        liftTrends: [LiftPerformanceTrend] = [],
        proposals: [AdaptationProposal] = [],
        healthSummaries: [HealthKitDailySummary] = []
    ) -> DashboardRefreshFingerprint {
        DashboardRefreshFingerprint(
            activeProgramRuns: activeProgramRuns,
            workouts: workouts,
            prs: prs,
            exercises: exercises,
            weeklyAnalyses: weeklyAnalyses,
            liftTrends: liftTrends,
            proposals: proposals,
            healthSummaries: healthSummaries
        )
    }

    private func makeWorkout(
        exerciseName: String,
        setSpecs: [(reps: Int, weight: Double, isPR: Bool)],
        date: Date,
        durationSeconds: Int,
        programRun: ProgramRun? = nil,
        programWeekNumber: Int? = nil,
        programSessionNumber: Int? = nil
    ) -> Workout {
        let workout = Workout(
            date: date,
            startTime: date,
            durationSeconds: durationSeconds,
            programRun: programRun,
            programWeekNumber: programWeekNumber,
            programSessionNumber: programSessionNumber
        )
        let entry = ExerciseEntry(
            exerciseName: exerciseName,
            unit: .lbs,
            orderIndex: 0
        )
        entry.workout = workout
        workout.exerciseEntries = [entry]
        entry.sets = setSpecs.enumerated().map { index, spec in
            let set = SetEntry(
                setNumber: index + 1,
                reps: spec.reps,
                weight: spec.weight,
                isPR: spec.isPR
            )
            set.exerciseEntry = entry
            return set
        }
        return workout
    }
}
