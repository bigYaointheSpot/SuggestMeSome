import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct BackendScalabilityWorkoutSavePipelineTests {

    @Test func saveResultCapturesNonFatalSideEffectFailuresWithoutLosingWorkout() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let logger = TestWorkoutSaveIssueLogger()

        let coordinator = WorkoutSaveCoordinator(
            modelContext: context,
            outcomePersistor: { _, _ in
                throw TestInjectedError.sideEffectFailure
            },
            weeklyAnalyzer: { _, _ in
                throw TestInjectedError.sideEffectFailure
            },
            issueLogger: logger
        )

        let result = coordinator.saveWorkoutResult(using: WorkoutSaveRequest(
            startTime: day(0),
            endTime: day(0).addingTimeInterval(1_800),
            caloriesText: "200",
            comments: "pipeline",
            exerciseEntries: [
                DraftExerciseEntry(
                    exerciseName: "Bench Press",
                    unit: .lbs,
                    orderIndex: 0,
                    sets: [DraftSet(setNumber: 1, repsText: "5", weightText: "185")]
                )
            ],
            programContext: nil,
            healthKitEnabled: false,
            healthKitWritebackEnabled: false
        ))

        let workouts = try fetchAll(Workout.self, context)

        #expect(result.didPersistWorkout)
        #expect(workouts.contains { $0.id == result.workout.id })
        #expect(result.savedWorkoutSummary.workoutID == result.workout.id)
        #expect(result.savedWorkoutSummary.completedAt == day(0).addingTimeInterval(1_800))
        #expect(result.savedWorkoutSummary.durationSeconds == 1_800)
        #expect(result.savedWorkoutSummary.personalRecordCount == 1)
        #expect(result.sideEffectReports.contains {
            $0.kind == .healthKitWriteback && $0.status == .skipped
        })
        #expect(result.nonFatalFailures.count == 2)
        #expect(Set(result.nonFatalFailures.map(\.kind)) == Set([
            WorkoutSaveSideEffectKind.outcomePersistence,
            WorkoutSaveSideEffectKind.weeklyAnalysis,
        ]))
        #expect(logger.recordedReports.count == 2)
    }

    @Test func saveSummarySurvivesSavedWorkoutInvalidation() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let coordinator = WorkoutSaveCoordinator(
            modelContext: context,
            outcomePersistor: { _, _ in },
            weeklyAnalyzer: { _, _ in }
        )

        let result = coordinator.saveWorkoutResult(using: WorkoutSaveRequest(
            startTime: day(3),
            endTime: day(3).addingTimeInterval(1_200),
            caloriesText: "120",
            comments: "summary survives delete",
            exerciseEntries: [
                DraftExerciseEntry(
                    exerciseName: "Front Squat",
                    unit: .lbs,
                    orderIndex: 0,
                    sets: [DraftSet(setNumber: 1, repsText: "3", weightText: "225")]
                )
            ],
            programContext: nil,
            healthKitEnabled: false,
            healthKitWritebackEnabled: false
        ))
        let summary = result.savedWorkoutSummary
        let savedWorkout = result.workout
        let savedWorkoutID = savedWorkout.id
        #expect(summary.workoutID == savedWorkoutID)

        context.delete(savedWorkout)
        try context.save()

        #expect(summary.workoutID == savedWorkoutID)
        #expect(summary.completedAt == day(3).addingTimeInterval(1_200))
        #expect(summary.durationSeconds == 1_200)
        #expect(summary.personalRecordCount == 1)
    }

    @Test func saveResultMarksProgramCompletionAndReportsSuccess() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = makeProgram(lengthInWeeks: 1, sessionsPerWeek: 1)
        let run = ProgramRun(startDate: day(0))
        run.program = program
        context.insert(program)
        context.insert(run)
        try context.save()

        let coordinator = WorkoutSaveCoordinator(
            modelContext: context,
            outcomePersistor: { _, _ in },
            weeklyAnalyzer: { _, _ in }
        )

        let result = coordinator.saveWorkoutResult(using: WorkoutSaveRequest(
            startTime: day(1),
            endTime: day(1).addingTimeInterval(2_400),
            caloriesText: "300",
            comments: "program finish",
            exerciseEntries: [],
            programContext: WorkoutSaveProgramContext(run: run, weekNumber: 1, sessionNumber: 1),
            healthKitEnabled: false,
            healthKitWritebackEnabled: false
        ))

        #expect(result.didPersistWorkout)
        #expect(result.didMarkProgramComplete)
        #expect(run.isCompleted)
        #expect(result.sideEffectReports.contains {
            $0.kind == .programCompletion && $0.status == .succeeded
        })
    }

    @Test func writebackIsScheduledAndPersistsExportMetadataWhenWriterSucceeds() async throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let logger = TestWorkoutSaveIssueLogger()
        let writer = TestHealthKitWorkoutWriter(
            shouldAttempt: true,
            result: HealthKitWorkoutWriteResult(
                writebackIdentifier: "hk-writeback-1",
                exportedAt: day(2)
            )
        )
        let coordinator = WorkoutSaveCoordinator(
            modelContext: context,
            writebackCoordinator: WorkoutSaveHealthKitWritebackCoordinator(writer: writer),
            outcomePersistor: { _, _ in },
            weeklyAnalyzer: { _, _ in },
            issueLogger: logger
        )

        let result = coordinator.saveWorkoutResult(using: WorkoutSaveRequest(
            startTime: day(1),
            endTime: day(1).addingTimeInterval(900),
            caloriesText: "150",
            comments: "writeback",
            exerciseEntries: [],
            programContext: nil,
            healthKitEnabled: true,
            healthKitWritebackEnabled: true
        ))

        #expect(result.sideEffectReports.contains {
            $0.kind == .healthKitWriteback && $0.status == .scheduled
        })

        for _ in 0..<20 where result.workout.healthKitWritebackIdentifier == nil {
            await Task.yield()
        }

        #expect(result.workout.healthKitWritebackIdentifier == "hk-writeback-1")
        #expect(result.workout.healthKitExportedAt == day(2))
        #expect(logger.recordedReports.isEmpty)
    }

    private func makeProgram(lengthInWeeks: Int, sessionsPerWeek: Int) -> TrainingProgram {
        let program = TrainingProgram(
            name: "Scalability Block",
            lengthInWeeks: lengthInWeeks,
            sessionsPerWeek: sessionsPerWeek
        )

        let weeks = (1...lengthInWeeks).map { weekNumber in
            let week = ProgramWeekTemplate(weekNumber: weekNumber)
            let sessions = (1...sessionsPerWeek).map { sessionNumber in
                ProgramSessionTemplate(sessionNumber: sessionNumber)
            }
            for session in sessions {
                session.week = week
            }
            week.sessions = sessions
            week.program = program
            return week
        }

        program.weeks = weeks
        return program
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Workout.self,
            ProgramRun.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AppliedOverlayAdjustment.self,
            AdaptationEventHistory.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            ExercisePerformanceOutcome.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            ExerciseEntry.self,
            SetEntry.self,
            Exercise.self,
            MuscleGroup.self,
            PersonalRecord.self,
            DailyCoachCheckIn.self,
            DailyCoachWeeklyReview.self,
            HealthKitDailySummary.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    private func day(_ offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let anchor = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 5, hour: 12, minute: 0, second: 0)
        ) ?? Date()
        return calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }
}

@MainActor
private final class TestWorkoutSaveIssueLogger: WorkoutSaveIssueLogging {
    private(set) var recordedReports: [WorkoutSaveSideEffectReport] = []
    private(set) var recordedTransactionStatuses: [WorkoutSaveTransactionStatus] = []

    func record(report: WorkoutSaveSideEffectReport) {
        recordedReports.append(report)
    }

    func record(transactionStatus: WorkoutSaveTransactionStatus) {
        recordedTransactionStatuses.append(transactionStatus)
    }
}

@MainActor
private final class TestHealthKitWorkoutWriter: HealthKitWorkoutWriting {
    let shouldAttempt: Bool
    let result: HealthKitWorkoutWriteResult

    init(shouldAttempt: Bool, result: HealthKitWorkoutWriteResult) {
        self.shouldAttempt = shouldAttempt
        self.result = result
    }

    func shouldAttemptWriteback(
        for workout: Workout,
        healthKitEnabled: Bool,
        writebackEnabled: Bool
    ) -> Bool {
        shouldAttempt && healthKitEnabled && writebackEnabled
    }

    func writeWorkoutSummary(_ workout: Workout) async throws -> HealthKitWorkoutWriteResult {
        result
    }
}

private enum TestInjectedError: Error {
    case sideEffectFailure
}
