import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature18AuditFixRegressionTests {

    @Test func cloudSyncManagerRemovesSubmittedPendingBatchesAfterAcceptedPush() async throws {
        let harness = try await makeCloudSyncHarness(initialLastSuccessfulSyncAt: day(10))
        defer { harness.cleanup() }

        let pendingBatch = PendingCloudSyncBatch(
            createdAt: day(1),
            reason: "Queued workout sync",
            payload: CloudSyncBatchPayload(
                workouts: [makeWorkoutDTO(
                    stableID: "pending-workout-a",
                    lastModifiedAt: day(1),
                    exerciseName: "Bench Press",
                    weight: 225
                )]
            )
        )
        harness.stateStore.setPendingBatches([pendingBatch])

        harness.backend.pushHandler = { request, _ in
            #expect(request.payload.workouts.map { $0.metadata.stableID } == ["pending-workout-a"])
            return CloudSyncPushResponse(
                acceptedBatchID: request.batchID,
                payload: CloudSyncBatchPayload()
            )
        }
        let pulledCursor = CloudSyncCollectionCursorDTO(
            collection: .workouts,
            nextCursor: "cursor-after-pull",
            lastSuccessfulSyncAt: day(3)
        )
        harness.backend.pullHandler = { _, _ in
            CloudSyncResponse(
                serverTime: day(3),
                payload: CloudSyncBatchPayload(),
                cursors: [pulledCursor]
            )
        }

        await harness.manager.retryNow()

        #expect(harness.stateStore.pendingBatches().isEmpty)
        #expect(harness.stateStore.lastSuccessfulSyncAt() == day(3))
        #expect(harness.stateStore.cursors() == [pulledCursor])
    }

    @Test func cloudSyncManagerPreservesPendingBatchesQueuedDuringPush() async throws {
        let harness = try await makeCloudSyncHarness(initialLastSuccessfulSyncAt: day(10))
        defer { harness.cleanup() }

        let submittedBatch = PendingCloudSyncBatch(
            createdAt: day(1),
            reason: "Submitted workout sync",
            payload: CloudSyncBatchPayload(
                workouts: [makeWorkoutDTO(
                    stableID: "submitted-workout",
                    lastModifiedAt: day(1),
                    exerciseName: "Bench Press",
                    weight: 225
                )]
            )
        )
        let retainedBatch = PendingCloudSyncBatch(
            createdAt: day(2),
            reason: "Retained workout sync",
            payload: CloudSyncBatchPayload(
                workouts: [makeWorkoutDTO(
                    stableID: "retained-workout",
                    lastModifiedAt: day(2),
                    exerciseName: "Deadlift",
                    weight: 405
                )]
            )
        )
        harness.stateStore.setPendingBatches([submittedBatch])

        harness.backend.pushHandler = { request, _ in
            #expect(request.payload.workouts.map { $0.metadata.stableID } == ["submitted-workout"])
            await MainActor.run {
                harness.stateStore.enqueuePendingBatch(retainedBatch)
            }
            return CloudSyncPushResponse(
                acceptedBatchID: request.batchID,
                payload: CloudSyncBatchPayload()
            )
        }
        harness.backend.pullHandler = { _, _ in
            CloudSyncResponse(
                serverTime: day(4),
                payload: CloudSyncBatchPayload(),
                cursors: []
            )
        }

        await harness.manager.retryNow()

        #expect(harness.stateStore.pendingBatches() == [retainedBatch])
    }

    @Test func cloudSyncManagerDoesNotAdvancePullProgressUntilPullSucceeds() async throws {
        let originalCursor = CloudSyncCollectionCursorDTO(
            collection: .workouts,
            nextCursor: "cursor-old",
            lastSuccessfulSyncAt: day(1)
        )
        let harness = try await makeCloudSyncHarness(
            initialCursors: [originalCursor],
            initialLastSuccessfulSyncAt: day(1)
        )
        defer { harness.cleanup() }

        let pendingBatch = PendingCloudSyncBatch(
            createdAt: day(2),
            reason: "Queued workout sync",
            payload: CloudSyncBatchPayload(
                workouts: [makeWorkoutDTO(
                    stableID: "retry-workout",
                    lastModifiedAt: day(2),
                    exerciseName: "Bench Press",
                    weight: 225
                )]
            )
        )
        harness.stateStore.setPendingBatches([pendingBatch])

        harness.backend.pushHandler = { request, _ in
            CloudSyncPushResponse(
                acceptedBatchID: request.batchID,
                payload: CloudSyncBatchPayload()
            )
        }

        var pullAttempts = 0
        let updatedCursor = CloudSyncCollectionCursorDTO(
            collection: .workouts,
            nextCursor: "cursor-new",
            lastSuccessfulSyncAt: day(5)
        )
        harness.backend.pullHandler = { request, _ in
            pullAttempts += 1
            if pullAttempts == 1 {
                throw CloudBackendClientError.network("Pull failed")
            }
            return CloudSyncResponse(
                serverTime: day(5),
                payload: CloudSyncBatchPayload(),
                cursors: [updatedCursor]
            )
        }

        await harness.manager.retryNow()

        #expect(harness.stateStore.lastSuccessfulSyncAt() == day(1))
        #expect(harness.stateStore.cursors() == [originalCursor])
        #expect(harness.stateStore.pendingBatches().isEmpty)

        await harness.manager.retryNow()

        #expect(harness.backend.pullRequests.count == 2)
        #expect(harness.backend.pullRequests[1].cursors == [originalCursor])
        #expect(harness.stateStore.lastSuccessfulSyncAt() == day(5))
        #expect(harness.stateStore.cursors() == [updatedCursor])
    }

    @Test func cloudSyncManagerPausesWhenConsumerHealthConsentIsMissing() async throws {
        let harness = try await makeCloudSyncHarness(
            initialLastSuccessfulSyncAt: day(10),
            includesConsumerHealthConsent: false
        )
        defer { harness.cleanup() }

        await harness.manager.retryNow()

        #expect(harness.manager.phase == .consentRequired)
        #expect(harness.backend.pushRequests.isEmpty)
        #expect(harness.backend.pullRequests.isEmpty)
    }

    @Test func cloudSyncManagerMapsBackendConsentRequiredToConsentPhase() async throws {
        let harness = try await makeCloudSyncHarness(initialLastSuccessfulSyncAt: day(10))
        defer { harness.cleanup() }

        harness.stateStore.setPendingBatches([
            PendingCloudSyncBatch(
                createdAt: day(1),
                reason: "Queued workout sync",
                payload: CloudSyncBatchPayload(
                    workouts: [makeWorkoutDTO(
                        stableID: "consent-required-workout",
                        lastModifiedAt: day(1),
                        exerciseName: "Bench Press",
                        weight: 225
                    )]
                )
            )
        ])
        harness.backend.pushHandler = { _, _ in
            throw CloudBackendClientError.httpStatus(403)
        }

        await harness.manager.retryNow()

        #expect(harness.manager.phase == .consentRequired)
        #expect(harness.manager.lastErrorMessage == nil)
        #expect(harness.backend.pushRequests.count == 1)
        #expect(harness.backend.pullRequests.isEmpty)
    }

    @Test func dailyCheckInCanonicalThenTombstoneKeepsCanonicalRecord() throws {
        let container = try makeInMemoryContainer()
        let repository = LocalSyncRepository(modelContext: container.mainContext)
        let context = container.mainContext

        let existing = DailyCoachCheckIn(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            syncStableID: "checkin-old",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            date: day(1),
            dayStart: day(1),
            createdAt: day(1),
            updatedAt: day(1)
        )
        context.insert(existing)
        try context.save()

        let canonical = makeCheckInDTO(
            stableID: "checkin-new",
            dayStart: day(1),
            lastModifiedAt: day(2)
        )
        let tombstone = makeCheckInDTO(
            stableID: "checkin-old",
            dayStart: day(1),
            lastModifiedAt: day(3),
            deletedAt: day(3)
        )

        try repository.upsertDailyCheckInPayloads([canonical, tombstone])

        let checkIns = try fetchAll(DailyCoachCheckIn.self, context)
        #expect(checkIns.count == 1)
        #expect(checkIns[0].resolvedSyncStableID == "checkin-new")
    }

    @Test func dailyCheckInTombstoneThenCanonicalKeepsCanonicalRecord() throws {
        let container = try makeInMemoryContainer()
        let repository = LocalSyncRepository(modelContext: container.mainContext)
        let context = container.mainContext

        let existing = DailyCoachCheckIn(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            syncStableID: "checkin-old",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            date: day(1),
            dayStart: day(1),
            createdAt: day(1),
            updatedAt: day(1)
        )
        context.insert(existing)
        try context.save()

        let canonical = makeCheckInDTO(
            stableID: "checkin-new",
            dayStart: day(1),
            lastModifiedAt: day(2)
        )
        let tombstone = makeCheckInDTO(
            stableID: "checkin-old",
            dayStart: day(1),
            lastModifiedAt: day(3),
            deletedAt: day(3)
        )

        try repository.upsertDailyCheckInPayloads([tombstone, canonical])

        let checkIns = try fetchAll(DailyCoachCheckIn.self, context)
        #expect(checkIns.count == 1)
        #expect(checkIns[0].resolvedSyncStableID == "checkin-new")
    }

    @Test func weeklyReviewCanonicalThenTombstoneKeepsCanonicalRecord() throws {
        let container = try makeInMemoryContainer()
        let repository = LocalSyncRepository(modelContext: container.mainContext)
        let context = container.mainContext

        let existing = DailyCoachWeeklyReview(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            syncStableID: "review-old",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            weekStart: day(1),
            weekEnd: day(6),
            headline: "Old",
            winText: "Old",
            watchoutText: "Old",
            nextActionText: "Old",
            createdAt: day(1)
        )
        context.insert(existing)
        try context.save()

        let canonical = makeWeeklyReviewDTO(
            stableID: "review-new",
            weekStart: day(1),
            lastModifiedAt: day(2)
        )
        let tombstone = makeWeeklyReviewDTO(
            stableID: "review-old",
            weekStart: day(1),
            lastModifiedAt: day(3),
            deletedAt: day(3)
        )

        try repository.upsertWeeklyReviewPayloads([canonical, tombstone])

        let reviews = try fetchAll(DailyCoachWeeklyReview.self, context)
        #expect(reviews.count == 1)
        #expect(reviews[0].resolvedSyncStableID == "review-new")
    }

    @Test func weeklyReviewTombstoneThenCanonicalKeepsCanonicalRecord() throws {
        let container = try makeInMemoryContainer()
        let repository = LocalSyncRepository(modelContext: container.mainContext)
        let context = container.mainContext

        let existing = DailyCoachWeeklyReview(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            syncStableID: "review-old",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            weekStart: day(1),
            weekEnd: day(6),
            headline: "Old",
            winText: "Old",
            watchoutText: "Old",
            nextActionText: "Old",
            createdAt: day(1)
        )
        context.insert(existing)
        try context.save()

        let canonical = makeWeeklyReviewDTO(
            stableID: "review-new",
            weekStart: day(1),
            lastModifiedAt: day(2)
        )
        let tombstone = makeWeeklyReviewDTO(
            stableID: "review-old",
            weekStart: day(1),
            lastModifiedAt: day(3),
            deletedAt: day(3)
        )

        try repository.upsertWeeklyReviewPayloads([tombstone, canonical])

        let reviews = try fetchAll(DailyCoachWeeklyReview.self, context)
        #expect(reviews.count == 1)
        #expect(reviews[0].resolvedSyncStableID == "review-new")
    }

    @Test func trainingPreferencesWithoutMetadataDoNotExportIncrementally() throws {
        let suiteName = "Feature18TrainingPreferencesAudit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(WeightUnit.kg.rawValue, forKey: "globalWeightUnit")
        defaults.set(150, forKey: "defaultRestTimerSeconds")
        defaults.set(0b0011100, forKey: "coachPreferredDays")

        let container = try makeInMemoryContainer()
        let repository = LocalSyncRepository(
            modelContext: container.mainContext,
            userDefaults: defaults
        )

        let bootstrapPayload = try repository.fetchTrainingPreferencesPayload(since: nil)
        let requiredBootstrapPayload = try #require(bootstrapPayload)
        #expect(requiredBootstrapPayload.metadata.lastModifiedAt == Date(timeIntervalSince1970: 0))
        #expect(try repository.fetchTrainingPreferencesPayload(since: day(0)) == nil)
        #expect(try repository.fetchTrainingPreferencesPayload(since: day(0)) == nil)

        TrainingPreferencesStore.markUpdated(userDefaults: defaults, at: day(2))
        let incrementalPayload = try repository.fetchTrainingPreferencesPayload(since: day(1))
        let requiredIncrementalPayload = try #require(incrementalPayload)
        #expect(requiredIncrementalPayload.metadata.lastModifiedAt == day(2))
    }

    @Test func cloudSyncManagerPullInsertAndDeleteRecomputeOnlyAffectedPersonalRecords() async throws {
        let harness = try await makeCloudSyncHarness(initialLastSuccessfulSyncAt: day(10))
        defer { harness.cleanup() }
        let context = harness.container.mainContext

        try seedWorkout(
            stableID: "squat-workout",
            exerciseName: "Squat",
            weight: 315,
            at: day(1),
            context: context
        )
        disableAdaptiveBackfill(in: context)
        try PersonalRecordMaintenanceService.recomputePRs(for: ["Squat"], context: context)
        try context.save()

        var pullResponses: [CloudSyncResponse] = [
            CloudSyncResponse(
                serverTime: day(12),
                payload: CloudSyncBatchPayload(
                    workouts: [makeWorkoutDTO(
                        stableID: "deadlift-workout",
                        lastModifiedAt: day(11),
                        exerciseName: "Deadlift",
                        weight: 405
                    )]
                ),
                cursors: [CloudSyncCollectionCursorDTO(
                    collection: .workouts,
                    nextCursor: "cursor-insert",
                    lastSuccessfulSyncAt: day(12)
                )]
            ),
            CloudSyncResponse(
                serverTime: day(14),
                payload: CloudSyncBatchPayload(
                    workouts: [makeWorkoutDTO(
                        stableID: "deadlift-workout",
                        lastModifiedAt: day(13),
                        exerciseName: "Deadlift",
                        weight: 405,
                        deletedAt: day(13)
                    )]
                ),
                cursors: [CloudSyncCollectionCursorDTO(
                    collection: .workouts,
                    nextCursor: "cursor-delete",
                    lastSuccessfulSyncAt: day(14)
                )]
            )
        ]
        harness.backend.pullHandler = { _, _ in
            pullResponses.removeFirst()
        }

        await harness.manager.retryNow()

        var prs = try fetchAll(PersonalRecord.self, context)
        #expect(Set(prs.map(\.exerciseName)) == Set(["Squat", "Deadlift"]))

        await harness.manager.retryNow()

        prs = try fetchAll(PersonalRecord.self, context)
        #expect(Set(prs.map(\.exerciseName)) == Set(["Squat"]))
    }

    @Test func cloudSyncManagerPullRenameRecomputesOldAndNewExerciseNamesWithoutTouchingUnrelatedRecords() async throws {
        let harness = try await makeCloudSyncHarness(initialLastSuccessfulSyncAt: day(10))
        defer { harness.cleanup() }
        let context = harness.container.mainContext

        try seedWorkout(
            stableID: "bench-workout",
            exerciseName: "Bench Press",
            weight: 225,
            at: day(1),
            context: context
        )
        try seedWorkout(
            stableID: "squat-workout",
            exerciseName: "Squat",
            weight: 315,
            at: day(2),
            context: context
        )
        disableAdaptiveBackfill(in: context)
        try PersonalRecordMaintenanceService.recomputePRs(
            for: ["Bench Press", "Squat"],
            context: context
        )
        try context.save()

        harness.backend.pullHandler = { _, _ in
            CloudSyncResponse(
                serverTime: day(12),
                payload: CloudSyncBatchPayload(
                    workouts: [makeWorkoutDTO(
                        stableID: "bench-workout",
                        lastModifiedAt: day(11),
                        exerciseName: "Incline Bench Press",
                        weight: 235
                    )]
                ),
                cursors: [CloudSyncCollectionCursorDTO(
                    collection: .workouts,
                    nextCursor: "cursor-rename",
                    lastSuccessfulSyncAt: day(12)
                )]
            )
        }

        await harness.manager.retryNow()

        let prs = try fetchAll(PersonalRecord.self, context)
        #expect(Set(prs.map(\.exerciseName)) == Set(["Incline Bench Press", "Squat"]))
        #expect(prs.contains(where: { $0.exerciseName == "Bench Press" }) == false)
    }
}

private struct CloudSyncHarness {
    let suiteName: String
    let defaults: UserDefaults
    let container: ModelContainer
    let stateStore: CloudSyncStateStore
    let backend: AuditFixCloudBackendClient
    let manager: CloudSyncManager
    let accountID: UUID

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class AuditFixCloudBackendClient: CloudBackendClient {
    enum StubError: Error {
        case unimplemented
    }

    var pushHandler: ((CloudSyncPushRequest, String) async throws -> CloudSyncPushResponse)?
    var pullHandler: ((CloudSyncPullRequest, String) async throws -> CloudSyncResponse)?
    var pushRequests: [CloudSyncPushRequest] = []
    var pullRequests: [CloudSyncPullRequest] = []

    func exchangeAppleIdentity(_ request: CloudAuthExchangeRequest) async throws -> CloudAuthSessionResponse {
        throw StubError.unimplemented
    }

    func refreshSession(_ request: CloudSessionRefreshRequest) async throws -> CloudAuthSessionResponse {
        throw StubError.unimplemented
    }

    func bootstrap(
        _ request: CloudSyncBootstrapRequest,
        accessToken: String
    ) async throws -> CloudSyncResponse {
        CloudSyncResponse(
            serverTime: Date(timeIntervalSince1970: 0),
            payload: CloudSyncBatchPayload(),
            cursors: []
        )
    }

    func push(
        _ request: CloudSyncPushRequest,
        accessToken: String
    ) async throws -> CloudSyncPushResponse {
        pushRequests.append(request)
        if let pushHandler {
            return try await pushHandler(request, accessToken)
        }
        return CloudSyncPushResponse(
            acceptedBatchID: request.batchID,
            payload: CloudSyncBatchPayload()
        )
    }

    func pull(
        _ request: CloudSyncPullRequest,
        accessToken: String
    ) async throws -> CloudSyncResponse {
        pullRequests.append(request)
        if let pullHandler {
            return try await pullHandler(request, accessToken)
        }
        return CloudSyncResponse(
            serverTime: Date(timeIntervalSince1970: 0),
            payload: CloudSyncBatchPayload(),
            cursors: []
        )
    }

    func submitPrivacyRequest(
        _ type: PrivacyRequestType,
        accessToken: String
    ) async throws -> CloudPrivacyRequestResponse {
        throw StubError.unimplemented
    }

    func setConsumerHealthConsent(
        _ request: CloudConsumerHealthConsentRequest,
        accessToken: String
    ) async throws -> CloudPrivacyRequestResponse {
        throw StubError.unimplemented
    }

    func fetchAccountExport(accessToken: String) async throws -> CloudAccountExportResponse {
        throw StubError.unimplemented
    }

    func deleteAccount(accessToken: String) async throws -> CloudPrivacyRequestResponse {
        throw StubError.unimplemented
    }
}

@MainActor
private func makeCloudSyncHarness(
    initialCursors: [CloudSyncCollectionCursorDTO] = [],
    initialLastSuccessfulSyncAt: Date? = nil,
    includesConsumerHealthConsent: Bool = true
) async throws -> CloudSyncHarness {
    let suiteName = "Feature18AuditFixHarness.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let container = try makeInMemoryContainer()
    let stateStore = CloudSyncStateStore(userDefaults: defaults)
    if !initialCursors.isEmpty {
        stateStore.setCursors(initialCursors)
    }
    if let initialLastSuccessfulSyncAt {
        stateStore.setLastSuccessfulSyncAt(initialLastSuccessfulSyncAt)
    }

    let backend = AuditFixCloudBackendClient()
    let tokenStore = InMemoryCloudSessionTokenStore(tokens: CloudSessionTokensDTO(
        accessToken: "access-token",
        refreshToken: "refresh-token",
        accessTokenExpiresAt: Date().addingTimeInterval(3_600)
    ))
    let manager = CloudSyncManager(
        backendClient: backend,
        tokenStore: tokenStore,
        stateStore: stateStore,
        userDefaults: defaults
    )
    manager.configure(modelContext: container.mainContext, userDefaults: defaults)

    let accountID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    stateStore.setBootstrappedAccountID(accountID)
    await manager.handleAccountStateDidChange(
        signedInState(
            accountID: accountID,
            includesConsumerHealthConsent: includesConsumerHealthConsent
        )
    )

    return CloudSyncHarness(
        suiteName: suiteName,
        defaults: defaults,
        container: container,
        stateStore: stateStore,
        backend: backend,
        manager: manager,
        accountID: accountID
    )
}

private func signedInState(
    accountID: UUID,
    includesConsumerHealthConsent: Bool = true
) -> AccountBackendContractState {
    AccountBackendContractState(
        knownAccounts: [
            UserAccount(
                id: accountID,
                appleUserID: "apple-user",
                displayName: "Alex",
                email: "alex@example.com",
                createdAt: day(0),
                lastSignedInAt: day(0),
                launchMode: .productionBackend
            )
        ],
        currentAccountID: accountID,
        privacyRequests: [],
        consumerHealthConsents: includesConsumerHealthConsent ? [
            ConsumerHealthConsentRecord(
                accountID: accountID,
                categories: ComplianceConfiguration.consumerHealthConsentCategories,
                purpose: ComplianceConfiguration.consumerHealthConsentPurpose,
                acceptedAt: day(0)
            )
        ] : []
    )
}

@MainActor
private func seedWorkout(
    stableID: String,
    exerciseName: String,
    weight: Double,
    at date: Date,
    context: ModelContext
) throws {
    let set = SetEntry(
        id: UUID(),
        syncStableID: "\(stableID)-set",
        syncVersion: 1,
        syncLastModifiedAt: date,
        setNumber: 1,
        reps: 5,
        weight: weight
    )
    let entry = ExerciseEntry(
        id: UUID(),
        syncStableID: "\(stableID)-entry",
        syncVersion: 1,
        syncLastModifiedAt: date,
        exerciseName: exerciseName,
        unit: .lbs,
        orderIndex: 0
    )
    entry.sets = [set]
    set.exerciseEntry = entry

    let workout = Workout(
        id: UUID(),
        syncStableID: stableID,
        syncVersion: 1,
        syncLastModifiedAt: date,
        date: date,
        startTime: date,
        durationSeconds: 1_800
    )
    workout.exerciseEntries = [entry]
    entry.workout = workout

    context.insert(workout)
    context.insert(entry)
    context.insert(set)
    try context.save()
}

private func disableAdaptiveBackfill(in context: ModelContext) {
    let analysis = WeeklyTrainingAnalysis(
        id: UUID(),
        weekStartDate: day(-7),
        weekEndDate: day(-1)
    )
    context.insert(analysis)
}

private func makeWorkoutDTO(
    stableID: String,
    lastModifiedAt: Date,
    exerciseName: String,
    weight: Double,
    deletedAt: Date? = nil
) -> WorkoutSyncDTO {
    WorkoutSyncDTO(
        metadata: SyncRecordMetadataDTO(
            stableID: stableID,
            version: 1,
            lastModifiedAt: lastModifiedAt,
            deletedAt: deletedAt
        ),
        date: lastModifiedAt,
        startTime: lastModifiedAt,
        durationSeconds: 1_800,
        caloriesBurned: nil,
        comments: nil,
        sourceTypeRawValue: WorkoutSourceType.loggedInApp.rawValue,
        sourceExternalIdentifier: nil,
        sourceDisplayName: nil,
        sourceWorkoutTypeIdentifier: nil,
        sourceWorkoutTypeDisplayName: nil,
        sourceImportedAt: nil,
        healthKitExportedAt: nil,
        healthKitWritebackIdentifier: nil,
        programRunStableID: nil,
        programWeekNumber: nil,
        programSessionNumber: nil,
        exerciseEntries: [
            ExerciseEntrySyncDTO(
                metadata: SyncRecordMetadataDTO(
                    stableID: "\(stableID)-entry",
                    version: 1,
                    lastModifiedAt: lastModifiedAt
                ),
                exerciseName: exerciseName,
                unitRawValue: WeightUnit.lbs.rawValue,
                orderIndex: 0,
                isCardio: false,
                cardioDurationSeconds: nil,
                sourceProgramSessionExerciseStableID: nil,
                prescribedTargetSets: nil,
                prescribedTargetReps: nil,
                prescribedTargetPercentage1RM: nil,
                prescribedTargetRPE: nil,
                prescribedTargetRIR: nil,
                prescribedWeight: nil,
                prescribedWeightUnit: nil,
                prescribedWorkingSetStyleRawValue: nil,
                prescribedTargetEffortTypeRawValue: nil,
                effortFeedbackRawValue: nil,
                topSetRPE: nil,
                sets: [
                    SetEntrySyncDTO(
                        metadata: SyncRecordMetadataDTO(
                            stableID: "\(stableID)-set",
                            version: 1,
                            lastModifiedAt: lastModifiedAt
                        ),
                        setNumber: 1,
                        reps: 5,
                        weight: weight,
                        isPR: false
                    )
                ]
            )
        ]
    )
}

private func makeCheckInDTO(
    stableID: String,
    dayStart: Date,
    lastModifiedAt: Date,
    deletedAt: Date? = nil
) -> DailyCoachCheckInSyncDTO {
    DailyCoachCheckInSyncDTO(
        metadata: SyncRecordMetadataDTO(
            stableID: stableID,
            version: 1,
            lastModifiedAt: lastModifiedAt,
            deletedAt: deletedAt
        ),
        date: dayStart,
        dayStart: dayStart,
        sleepQuality: 3,
        soreness: 2,
        energy: 3,
        stress: 2,
        availableTimeMinutes: 60,
        hasPainOrDiscomfort: false,
        painNotes: nil,
        programRunStableID: nil,
        createdAt: dayStart,
        updatedAt: lastModifiedAt
    )
}

private func makeWeeklyReviewDTO(
    stableID: String,
    weekStart: Date,
    lastModifiedAt: Date,
    deletedAt: Date? = nil
) -> DailyCoachWeeklyReviewSyncDTO {
    DailyCoachWeeklyReviewSyncDTO(
        metadata: SyncRecordMetadataDTO(
            stableID: stableID,
            version: 1,
            lastModifiedAt: lastModifiedAt,
            deletedAt: deletedAt
        ),
        weekStart: weekStart,
        weekEnd: Calendar(identifier: .gregorian).date(byAdding: .day, value: 6, to: weekStart) ?? weekStart,
        isProgramWeek: false,
        programRunStableID: nil,
        headline: "Headline",
        winText: "Win",
        watchoutText: "Watchout",
        nextActionText: "Action",
        sourceWeeklyAnalysisIDText: nil,
        hasBeenSeen: false,
        createdAt: weekStart
    )
}

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
        DailyCoachCheckIn.self,
        DailyCoachWeeklyReview.self,
        HealthKitDailySummary.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

private func day(_ offset: Int) -> Date {
    let base = Date(timeIntervalSince1970: 1_765_000_000)
    return Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: base) ?? base
}

private func fetchAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> [T] {
    try context.fetch(FetchDescriptor<T>())
}
