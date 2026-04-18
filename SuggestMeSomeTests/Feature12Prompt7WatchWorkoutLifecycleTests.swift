import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature12Prompt7WatchWorkoutLifecycleTests {

    @Test func activeWorkoutSessionPauseResumeExcludesPausedTime() {
        let suiteName = "Feature12Prompt7WatchWorkoutLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = ActiveWorkoutSessionStore(
            userDefaults: defaults,
            persistenceKey: "activeWorkoutLifecycle"
        )
        let start = Date(timeIntervalSince1970: 1_800_100_000)
        store.startSession(
            id: UUID(),
            startTime: start,
            exerciseEntries: []
        )

        store.pauseSession(at: start.addingTimeInterval(125))
        #expect(store.session?.lifecycleState == .paused)
        #expect(store.resolvedElapsedSeconds(at: start.addingTimeInterval(900)) == 125)

        store.resumeSession(at: start.addingTimeInterval(900))
        #expect(store.session?.lifecycleState == .running)
        #expect(store.resolvedElapsedSeconds(at: start.addingTimeInterval(945)) == 170)
    }

    @Test func watchMetricsUpdateMarksLinkedHealthSessionAvailability() {
        let suiteName = "Feature12Prompt7WatchWorkoutLifecycleTests.metrics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let workoutID = UUID()
        let store = ActiveWorkoutSessionStore(
            userDefaults: defaults,
            persistenceKey: "activeWorkoutMetrics"
        )
        store.startSession(id: workoutID, startTime: .now, exerciseEntries: [])

        store.updateLatestWatchMetrics(
            WatchWorkoutMetricsPayload(
                workoutID: workoutID,
                sessionVersionStableID: nil,
                lifecycleState: .running,
                isLinkedHealthSessionActive: false,
                heartRateBPM: nil,
                activeEnergyKilocalories: nil,
                capturedAt: .now
            )
        )
        #expect(store.session?.usesLinkedWatchHealthSession == false)

        store.updateLatestWatchMetrics(
            WatchWorkoutMetricsPayload(
                workoutID: workoutID,
                sessionVersionStableID: nil,
                lifecycleState: .running,
                isLinkedHealthSessionActive: true,
                heartRateBPM: 138,
                activeEnergyKilocalories: 212,
                capturedAt: .now
            )
        )
        #expect(store.session?.usesLinkedWatchHealthSession == true)
        #expect(store.latestWatchMetrics?.heartRateBPM == 138)
    }

    @Test func watchHealthSummaryHandlerStampsPersistedWorkout() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let workout = Workout(
            id: UUID(),
            date: day(0),
            startTime: day(0),
            durationSeconds: 1_800
        )
        context.insert(workout)
        try context.save()

        let suiteName = "Feature12Prompt7WatchWorkoutLifecycleTests.summary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ActiveWorkoutSessionStore(
            userDefaults: defaults,
            persistenceKey: "activeWorkoutSummary"
        )
        store.startSession(id: workout.id, startTime: workout.startTime, exerciseEntries: [])

        let bridge = MockWatchCompanionBridge()
        let coordinator = WatchSessionCoordinator(bridge: bridge)
        coordinator.installCompanionHandlers(
            activeWorkoutSessionStore: store,
            modelContext: context
        )

        let payload = WatchWorkoutHealthSummaryPayload(
            workoutID: workout.id,
            sessionVersionStableID: nil,
            healthKitWorkoutUUID: "hk-watch-123",
            exportedAt: day(1),
            totalActiveEnergyKilocalories: 246,
            finalHeartRateBPM: 142
        )
        bridge.workoutHealthSummaryHandler?(payload)

        #expect(store.latestWatchHealthSummary == payload)
        #expect(workout.healthKitWritebackIdentifier == "hk-watch-123")
        #expect(workout.healthKitExportedAt == day(1))
        #expect(workout.caloriesBurned == 246)
    }

    @Test func workoutSaveCoordinatorSkipsPhoneWritebackWhenLinkedWatchOwnsExport() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let writer = Prompt7HealthKitWorkoutWriter(
            shouldAttempt: true,
            result: HealthKitWorkoutWriteResult(
                writebackIdentifier: "should-not-run",
                exportedAt: day(1)
            )
        )
        let coordinator = WorkoutSaveCoordinator(
            modelContext: context,
            writebackCoordinator: WorkoutSaveHealthKitWritebackCoordinator(writer: writer),
            outcomePersistor: { _, _ in },
            weeklyAnalyzer: { _, _ in }
        )

        let result = coordinator.saveWorkoutResult(using: WorkoutSaveRequest(
            workoutID: UUID(),
            startTime: day(0),
            endTime: day(0).addingTimeInterval(1_200),
            durationSeconds: 1_200,
            caloriesText: "",
            comments: "linked watch",
            exerciseEntries: [],
            programContext: nil,
            healthKitEnabled: true,
            healthKitWritebackEnabled: true,
            skipHealthKitWriteback: true
        ))

        #expect(result.sideEffectReports.contains {
            $0.kind == .healthKitWriteback && $0.status == .skipped
        })
        #expect(writer.writeCallCount == 0)
        #expect(result.workout.healthKitWritebackIdentifier == nil)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            PersonalRecord.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            ProgramRun.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_800_000_000))!
    }
}

@MainActor
private final class Prompt7HealthKitWorkoutWriter: HealthKitWorkoutWriting {
    let shouldAttempt: Bool
    let result: HealthKitWorkoutWriteResult
    private(set) var writeCallCount = 0

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
        writeCallCount += 1
        return result
    }
}
