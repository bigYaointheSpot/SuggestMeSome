import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct BackendScalabilityPersistenceTests {

    @Test func syncMetadataAuditRepairsMissingAndDuplicateStableIDs() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let first = Workout(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            syncStableID: "duplicate-workout",
            syncVersion: 0,
            syncLastModifiedAt: .distantPast,
            date: day(0),
            startTime: day(0),
            durationSeconds: 1800
        )
        let second = Workout(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            syncStableID: "duplicate-workout",
            syncVersion: 1,
            syncLastModifiedAt: day(1),
            date: day(1),
            startTime: day(1),
            durationSeconds: 2000
        )
        let blankStableID = PersonalRecord(
            exerciseName: "Bench Press",
            repCount: 5,
            weight: 225,
            unit: .lbs,
            dateAchieved: day(1)
        )
        blankStableID.syncStableID = "   "
        blankStableID.syncVersion = 0
        blankStableID.syncLastModifiedAt = .distantPast

        context.insert(first)
        context.insert(second)
        context.insert(blankStableID)
        try context.save()

        let auditedAt = day(4)
        let report = SyncMetadataAuditService.auditAndRepair(
            context: context,
            auditedAt: auditedAt
        )

        #expect(report.repairedRows == 3)
        #expect(report.duplicateStableIDRepairs == 1)
        #expect(first.syncStableID == first.id.uuidString)
        #expect(second.syncStableID == "duplicate-workout")
        #expect(first.syncVersion >= 2)
        #expect(second.syncVersion >= 2)
        #expect(blankStableID.syncStableID == blankStableID.id.uuidString)
        #expect(blankStableID.syncLastModifiedAt == auditedAt)
    }

    @Test func persistenceMaintenanceCoordinatorStoresCurrentSchemaVersion() throws {
        let container = try makeInMemoryContainer()
        let suiteName = "BackendScalabilityPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let report = PersistenceMaintenanceCoordinator.runStartupMaintenance(
            context: container.mainContext,
            userDefaults: defaults,
            now: day(10)
        )

        #expect(report.previousSchemaVersion == nil)
        #expect(report.currentSchemaVersion == PersistenceSchemaVersion.current)
        #expect(report.didRunSyncMetadataAudit)
        #expect(
            defaults.integer(forKey: PersistenceMaintenanceCoordinator.schemaVersionDefaultsKey)
            == PersistenceSchemaVersion.current
        )
        #expect(
            PersistenceMaintenanceCoordinator.storedSchemaVersion(userDefaults: defaults)
            == PersistenceSchemaVersion.current
        )
        #expect(
            PersistenceMaintenanceCoordinator.storedLastAuditAt(userDefaults: defaults)
            == day(10)
        )
    }

    @Test func blockingStartupMaintenanceDefersAuditUntilExplicitFollowUpPass() throws {
        let container = try makeInMemoryContainer()
        let suiteName = "BackendScalabilityPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let blockingReport = PersistenceMaintenanceCoordinator.runBlockingStartupMaintenance(
            context: container.mainContext,
            userDefaults: defaults,
            now: day(10)
        )

        #expect(blockingReport.previousSchemaVersion == nil)
        #expect(blockingReport.currentSchemaVersion == PersistenceSchemaVersion.current)
        #expect(blockingReport.shouldRunDeferredSyncMetadataAudit)
        #expect(
            PersistenceMaintenanceCoordinator.storedLastAuditAt(userDefaults: defaults) == nil
        )

        let deferredReport = PersistenceMaintenanceCoordinator.runDeferredStartupSyncAuditIfNeeded(
            context: container.mainContext,
            shouldRunSyncAudit: blockingReport.shouldRunDeferredSyncMetadataAudit,
            userDefaults: defaults,
            now: day(10)
        )

        #expect(deferredReport.didRunSyncMetadataAudit)
        #expect(
            PersistenceMaintenanceCoordinator.storedLastAuditAt(userDefaults: defaults)
            == day(10)
        )
    }

    @Test func persistenceMaintenanceCoordinatorSkipsAuditWhenSchemaUnchangedAndAuditIsFreshWithinSevenDays() throws {
        let container = try makeInMemoryContainer()
        let suiteName = "BackendScalabilityPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            PersistenceSchemaVersion.current,
            forKey: PersistenceMaintenanceCoordinator.schemaVersionDefaultsKey
        )
        defaults.set(
            day(12).timeIntervalSince1970,
            forKey: PersistenceMaintenanceCoordinator.lastAuditAtDefaultsKey
        )

        let report = PersistenceMaintenanceCoordinator.runStartupMaintenance(
            context: container.mainContext,
            userDefaults: defaults,
            now: day(18)
        )

        #expect(report.previousSchemaVersion == PersistenceSchemaVersion.current)
        #expect(report.didRunSyncMetadataAudit == false)
        #expect(report.syncAuditReport.entityReports.isEmpty)
        #expect(report.performedSteps.contains("syncMetadataAuditSkipped"))
        #expect(
            PersistenceMaintenanceCoordinator.storedLastAuditAt(userDefaults: defaults)
            == day(12)
        )
    }

    @Test func persistenceMaintenanceCoordinatorRunsAuditAgainAfterSevenDayCadenceExpires() throws {
        let container = try makeInMemoryContainer()
        let suiteName = "BackendScalabilityPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            PersistenceSchemaVersion.current,
            forKey: PersistenceMaintenanceCoordinator.schemaVersionDefaultsKey
        )
        defaults.set(
            day(11).timeIntervalSince1970,
            forKey: PersistenceMaintenanceCoordinator.lastAuditAtDefaultsKey
        )

        let report = PersistenceMaintenanceCoordinator.runStartupMaintenance(
            context: container.mainContext,
            userDefaults: defaults,
            now: day(18)
        )

        #expect(report.previousSchemaVersion == PersistenceSchemaVersion.current)
        #expect(report.didRunSyncMetadataAudit)
        #expect(report.performedSteps.contains("syncMetadataAuditAndRepair"))
        #expect(
            PersistenceMaintenanceCoordinator.storedLastAuditAt(userDefaults: defaults)
            == day(12)
        )
    }

    @Test func continuityCodecDecodesLegacyRawPayloadAndEncodesVersionedEnvelope() throws {
        let snapshot = makeContinuitySnapshot()

        let rawEncoder = JSONEncoder()
        rawEncoder.dateEncodingStrategy = .millisecondsSince1970
        rawEncoder.outputFormatting = [.sortedKeys]
        let rawData = try rawEncoder.encode(snapshot)
        let rawJSON = String(decoding: rawData, as: UTF8.self)

        let decodedLegacy: ProgramBlockContinuitySnapshot? = ProgramRunContinuityCodec.decode(rawJSON)
        #expect(decodedLegacy == snapshot)

        let encoded = ProgramRunContinuityCodec.encode(snapshot)
        let payloadData = try #require(encoded?.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])

        #expect(object["schemaVersion"] as? Int == ProgramRunContinuityContractVersion.current)
        #expect(object["payload"] != nil)

        let decodedCurrent: ProgramBlockContinuitySnapshot? = ProgramRunContinuityCodec.decode(encoded)
        #expect(decodedCurrent == snapshot)
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

    private func makeContinuitySnapshot() -> ProgramBlockContinuitySnapshot {
        let recommendation = MesocycleNextBlockRecommendation(
            stableID: "rec-1",
            rank: 1,
            kind: .repeatFocus,
            title: "Stay the course",
            summary: "Keep pushing the same focus with slightly more frequency.",
            rationale: ["Adherence stayed high."],
            targetFocus: .increaseMaxBench,
            targetFocusDisplayName: "Bench Press",
            suggestedLevel: .intermediate,
            suggestedDurationWeeks: 8,
            suggestedSessionsPerWeek: 4,
            decision: .accepted,
            prefill: NextBlockPrefillContext(
                sourceProgramRunStableID: "run-source",
                recommendationStableID: "rec-1",
                focus: .increaseMaxBench,
                style: .dup,
                level: .intermediate,
                durationWeeks: 8,
                sessionsPerWeek: 4,
                oneRepMaxSuggestions: [
                    MesocycleOneRepMaxPrefill(
                        exerciseName: "Bench Press",
                        weight: 250,
                        unit: .lbs,
                        sourceSummary: "Current top estimated 1RM."
                    )
                ],
                preservedExerciseNames: ["Bench Press"],
                rationaleText: "Maintain momentum.",
                valueSources: [
                    NextBlockPrefillValueSource(
                        field: .durationWeeks,
                        source: .recommendation,
                        note: "Matches the highest-ranked recommendation."
                    ),
                    NextBlockPrefillValueSource(
                        field: .sessionsPerWeek,
                        source: .recommendation,
                        note: "Fits recent adherence."
                    ),
                ],
                intensityContext: NextBlockIntensityContext(
                    suggestedProgressionModel: .dup,
                    carriedOneRepMaxes: [
                        MesocycleOneRepMaxPrefill(
                            exerciseName: "Bench Press",
                            weight: 250,
                            unit: .lbs,
                            sourceSummary: "Current top estimated 1RM."
                        )
                    ],
                    notableLiftDisplayNames: ["Bench Press"],
                    sourceNotes: ["Recent adherence supports another DUP block."]
                ),
                notes: ["Seeded from test fixture."]
            ),
            isPrimaryRecommendation: true,
            fitScore: 92,
            fitNote: "Fits recent adherence."
        )

        return ProgramBlockContinuitySnapshot(
            sourceProgramRunStableID: "run-source",
            sourceTrainingProgramStableID: "program-source",
            reviewStableID: "run-source::mesocycle-review",
            sourceProgramName: "Bench Focus",
            snapshotRecordedAt: day(5),
            recommendationSnapshots: [ProgramRunRecommendationSnapshot(recommendation: recommendation)],
            selectedRecommendationStableID: "rec-1",
            selectedRecommendationSnapshot: ProgramRunRecommendationSnapshot(recommendation: recommendation),
            declinedRecommendationStableIDs: ["rec-2"],
            decisionEvents: [
                ProgramRunRecommendationDecisionEvent(
                    recommendationStableID: "rec-1",
                    decision: .accepted,
                    decidedAt: day(5),
                    userEditedFields: [.sessionsPerWeek]
                )
            ],
            carriedForwardContext: recommendation.prefill.carryForwardContext,
            editedPrefillSnapshot: recommendation.prefill,
            userEditedFields: [.sessionsPerWeek]
        )
    }

    private func day(_ offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12)) ?? Date()
        return calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }
}
