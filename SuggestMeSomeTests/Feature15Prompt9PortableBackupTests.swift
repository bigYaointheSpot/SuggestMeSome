import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature15Prompt9PortableBackupTests {
    @Test func portableBackupRoundTripsFullLocalData() throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceDefaults = makeDefaults(prefix: "roundtrip.source")
        defer { clearDefaults(sourceDefaults) }

        let fixture = try seedPortableBackupFixture(
            context: sourceContainer.mainContext,
            defaults: sourceDefaults,
            variantLabel: "source"
        )
        let sourceService = PortableBackupService(userDefaults: sourceDefaults)
        let envelope = try sourceService.exportBackupEnvelope(
            context: sourceContainer.mainContext,
            generatedAt: day(30)
        )

        let destinationContainer = try makeInMemoryContainer()
        let destinationDefaults = makeDefaults(prefix: "roundtrip.destination")
        defer { clearDefaults(destinationDefaults) }

        let destinationService = PortableBackupService(userDefaults: destinationDefaults)
        let result = try destinationService.restoreBackup(
            envelope,
            context: destinationContainer.mainContext
        )

        #expect(result.restoredManifest == envelope.manifest)
        try assertFixtureRestored(
            fixture,
            in: destinationContainer.mainContext,
            defaults: destinationDefaults
        )
    }

    @Test func portableBackupReplaceImportReplacesExistingDestinationDataAndDefaults() throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceDefaults = makeDefaults(prefix: "replace.source")
        defer { clearDefaults(sourceDefaults) }

        let sourceFixture = try seedPortableBackupFixture(
            context: sourceContainer.mainContext,
            defaults: sourceDefaults,
            variantLabel: "source"
        )
        let sourceEnvelope = try PortableBackupService(userDefaults: sourceDefaults)
            .exportBackupEnvelope(context: sourceContainer.mainContext, generatedAt: day(30))

        let destinationContainer = try makeInMemoryContainer()
        let destinationDefaults = makeDefaults(prefix: "replace.destination")
        defer { clearDefaults(destinationDefaults) }

        let destinationFixture = try seedPortableBackupFixture(
            context: destinationContainer.mainContext,
            defaults: destinationDefaults,
            variantLabel: "destination"
        )

        #expect(try fetchAll(Workout.self, in: destinationContainer.mainContext).count == 2)
        #expect(
            PortableBackupPreferences(defaults: destinationDefaults).appColorScheme !=
            PortableBackupPreferences(defaults: sourceDefaults).appColorScheme
        )

        let restoreResult = try PortableBackupService(userDefaults: destinationDefaults)
            .restoreBackup(sourceEnvelope, context: destinationContainer.mainContext)

        #expect(restoreResult.restoredManifest.totalSwiftDataRecordCount == sourceEnvelope.manifest.totalSwiftDataRecordCount)
        try assertFixtureRestored(
            sourceFixture,
            in: destinationContainer.mainContext,
            defaults: destinationDefaults
        )

        let restoredWorkoutIDs = Set(try fetchAll(Workout.self, in: destinationContainer.mainContext).map(\.id))
        #expect(restoredWorkoutIDs.contains(destinationFixture.primaryWorkoutID) == false)
        #expect(restoredWorkoutIDs.contains(sourceFixture.primaryWorkoutID))
    }

    @Test func portableBackupPreservesProgramGraphAndAdaptiveRelationships() throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceDefaults = makeDefaults(prefix: "fidelity.source")
        defer { clearDefaults(sourceDefaults) }

        let fixture = try seedPortableBackupFixture(
            context: sourceContainer.mainContext,
            defaults: sourceDefaults,
            variantLabel: "source"
        )
        let envelope = try PortableBackupService(userDefaults: sourceDefaults)
            .exportBackupEnvelope(context: sourceContainer.mainContext, generatedAt: day(30))

        let destinationContainer = try makeInMemoryContainer()
        let destinationDefaults = makeDefaults(prefix: "fidelity.destination")
        defer { clearDefaults(destinationDefaults) }

        _ = try PortableBackupService(userDefaults: destinationDefaults)
            .restoreBackup(envelope, context: destinationContainer.mainContext)

        let context = destinationContainer.mainContext
        let restoredProgram = try #require(
            try fetchAll(TrainingProgram.self, in: context).first { $0.id == fixture.programID }
        )
        #expect(restoredProgram.weeks.count == 1)
        #expect(restoredProgram.weeks.first?.sessions.count == 1)
        let restoredProgramExercises = restoredProgram.weeks.first?.sessions.first?.exercises
            .sorted { $0.orderIndex < $1.orderIndex } ?? []
        #expect(restoredProgramExercises.map(\.id) == [
            fixture.programSessionExerciseID,
            fixture.programAccessoryExerciseID
        ])

        let restoredRun = try #require(
            try fetchAll(ProgramRun.self, in: context).first { $0.id == fixture.programRunID }
        )
        #expect(restoredRun.program?.id == fixture.programID)

        let restoredWorkout = try #require(
            try fetchAll(Workout.self, in: context).first { $0.id == fixture.primaryWorkoutID }
        )
        let restoredEntry = try #require(
            restoredWorkout.exerciseEntries.first { $0.id == fixture.primaryExerciseEntryID }
        )
        #expect(restoredEntry.sourceProgramSessionExerciseID == fixture.programSessionExerciseID)

        let restoredAnalysis = try #require(
            try fetchAll(WeeklyTrainingAnalysis.self, in: context).first { $0.id == fixture.analysisID }
        )
        let restoredOutcome = try #require(
            restoredAnalysis.outcomes.first { $0.id == fixture.outcomeID }
        )
        #expect(restoredOutcome.workout?.id == fixture.primaryWorkoutID)
        #expect(restoredOutcome.exerciseEntry?.id == fixture.primaryExerciseEntryID)

        let restoredTrend = try #require(
            try fetchAll(LiftPerformanceTrend.self, in: context).first { $0.id == fixture.trendID }
        )
        let restoredSnapshot = try #require(
            restoredTrend.snapshots.first { $0.id == fixture.snapshotID }
        )
        #expect(restoredSnapshot.analysis?.id == fixture.analysisID)

        let restoredProposal = try #require(
            try fetchAll(AdaptationProposal.self, in: context).first { $0.id == fixture.proposalID }
        )
        #expect(restoredProposal.sourceAnalysis?.id == fixture.analysisID)
        #expect(restoredProposal.targetProgramSessionExerciseID == fixture.programSessionExerciseID)

        let restoredOverlay = try #require(
            try fetchAll(AppliedProgramOverlay.self, in: context).first { $0.id == fixture.overlayID }
        )
        let restoredAdjustment = try #require(
            restoredOverlay.adjustments.first { $0.id == fixture.adjustmentID }
        )
        #expect(restoredOverlay.sourceProposal?.id == fixture.proposalID)
        #expect(restoredAdjustment.targetProgramSessionExerciseID == fixture.programSessionExerciseID)

        let restoredEvent = try #require(
            try fetchAll(AdaptationEventHistory.self, in: context).first { $0.id == fixture.eventID }
        )
        #expect(restoredEvent.analysis?.id == fixture.analysisID)
        #expect(restoredEvent.proposal?.id == fixture.proposalID)
        #expect(restoredEvent.overlay?.id == fixture.overlayID)
    }

    @Test func portableBackupPreviewRejectsUnsupportedVersion() throws {
        let container = try makeInMemoryContainer()
        let defaults = makeDefaults(prefix: "preview.unsupported")
        defer { clearDefaults(defaults) }

        _ = try seedPortableBackupFixture(
            context: container.mainContext,
            defaults: defaults,
            variantLabel: "source"
        )

        var envelope = try PortableBackupService(userDefaults: defaults)
            .exportBackupEnvelope(context: container.mainContext, generatedAt: day(30))
        envelope.backupVersion = PortableBackupVersion.current + 99

        let fileURL = try writeBackupFile(envelope, name: "unsupported-version")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try PortableBackupService(userDefaults: defaults).previewBackup(from: fileURL)
            Issue.record("Expected unsupported backup version to be rejected.")
        } catch let error as PortableBackupError {
            switch error {
            case .validationFailed(let issues):
                #expect(issues.first?.contains("unsupported version") == true)
            default:
                Issue.record("Unexpected backup error: \(error.localizedDescription)")
            }
        }
    }

    @Test func portableBackupPreviewRejectsMalformedJSON() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("portable-backup-malformed-\(UUID().uuidString).json")
        try Data("not valid backup json".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try PortableBackupService().previewBackup(from: fileURL)
            Issue.record("Expected malformed backup JSON to be rejected.")
        } catch let error as PortableBackupError {
            #expect(error == .invalidBackupFile)
        }
    }

    @Test func portableBackupPreviewRejectsMissingReferencedIDs() throws {
        let container = try makeInMemoryContainer()
        let defaults = makeDefaults(prefix: "preview.missing")
        defer { clearDefaults(defaults) }

        _ = try seedPortableBackupFixture(
            context: container.mainContext,
            defaults: defaults,
            variantLabel: "source"
        )

        var envelope = try PortableBackupService(userDefaults: defaults)
            .exportBackupEnvelope(context: container.mainContext, generatedAt: day(30))
        envelope.payload.adaptationProposals[0].sourceAnalysisID = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!

        let fileURL = try writeBackupFile(envelope, name: "missing-reference")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try PortableBackupService(userDefaults: defaults).previewBackup(from: fileURL)
            Issue.record("Expected missing references to be rejected.")
        } catch let error as PortableBackupError {
            switch error {
            case .validationFailed(let issues):
                #expect(issues.contains { $0.contains("missing weekly analysis") })
            default:
                Issue.record("Unexpected backup error: \(error.localizedDescription)")
            }
        }
    }

    @Test func portableBackupViewModelSurfacesImportPreviewAndRestoreMessaging() throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceDefaults = makeDefaults(prefix: "viewmodel.source")
        defer { clearDefaults(sourceDefaults) }

        _ = try seedPortableBackupFixture(
            context: sourceContainer.mainContext,
            defaults: sourceDefaults,
            variantLabel: "source"
        )

        let sourceService = PortableBackupService(userDefaults: sourceDefaults)
        let envelope = try sourceService.exportBackupEnvelope(
            context: sourceContainer.mainContext,
            generatedAt: day(30)
        )
        let fileURL = try writeBackupFile(envelope, name: "viewmodel-success")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let destinationContainer = try makeInMemoryContainer()
        let destinationDefaults = makeDefaults(prefix: "viewmodel.destination")
        defer { clearDefaults(destinationDefaults) }

        let viewModel = PortableBackupViewModel(
            backupService: PortableBackupService(userDefaults: destinationDefaults)
        )

        viewModel.handleImportSelection(.success(fileURL))
        #expect(viewModel.importPreview?.fileName == fileURL.lastPathComponent)
        #expect(viewModel.errorMessage == nil)

        let accountManager = AccountManager(
            authService: LocalContractAuthService(userDefaults: destinationDefaults)
        )
        let complianceStateStore = ComplianceStateStore(userDefaults: destinationDefaults)

        viewModel.restoreImport(
            context: destinationContainer.mainContext,
            accountManager: accountManager,
            complianceStateStore: complianceStateStore
        )

        #expect(viewModel.importPreview == nil)
        #expect(viewModel.statusMessage?.contains("Imported backup") == true)
        #expect(accountManager.currentUser?.email == "source@example.com")
        #expect(complianceStateStore.hasCompletedRequiredOnboarding)
    }

    @Test func portableBackupViewModelSurfacesImportErrors() throws {
        let defaults = makeDefaults(prefix: "viewmodel.error")
        defer { clearDefaults(defaults) }

        let viewModel = PortableBackupViewModel(
            backupService: PortableBackupService(userDefaults: defaults)
        )
        let invalidURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("portable-backup-error-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: invalidURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: invalidURL) }

        viewModel.handleImportSelection(.success(invalidURL))

        #expect(viewModel.importPreview == nil)
        #expect(viewModel.errorMessage?.isEmpty == false)
    }

    private func assertFixtureRestored(
        _ fixture: PortableBackupFixture,
        in context: ModelContext,
        defaults: UserDefaults
    ) throws {
        #expect(try fetchAll(MuscleGroup.self, in: context).count == 3)
        #expect(try fetchAll(Exercise.self, in: context).count == 4)
        #expect(try fetchAll(Workout.self, in: context).count == 2)
        #expect(try fetchAll(ExerciseEntry.self, in: context).count == 3)
        #expect(try fetchAll(SetEntry.self, in: context).count == 2)
        #expect(try fetchAll(PersonalRecord.self, in: context).count == 1)
        #expect(try fetchAll(TrainingProgram.self, in: context).count == 1)
        #expect(try fetchAll(ProgramWeekTemplate.self, in: context).count == 1)
        #expect(try fetchAll(ProgramSessionTemplate.self, in: context).count == 1)
        #expect(try fetchAll(ProgramSessionExercise.self, in: context).count == 2)
        #expect(try fetchAll(ProgramRun.self, in: context).count == 1)
        #expect(try fetchAll(DailyCoachCheckIn.self, in: context).count == 1)
        #expect(try fetchAll(DailyCoachWeeklyReview.self, in: context).count == 1)
        #expect(try fetchAll(WeeklyTrainingAnalysis.self, in: context).count == 1)
        #expect(try fetchAll(ExercisePerformanceOutcome.self, in: context).count == 1)
        #expect(try fetchAll(WeeklyVolumeMetric.self, in: context).count == 1)
        #expect(try fetchAll(LiftPerformanceTrend.self, in: context).count == 1)
        #expect(try fetchAll(LiftTrendSnapshot.self, in: context).count == 1)
        #expect(try fetchAll(AdaptationProposal.self, in: context).count == 1)
        #expect(try fetchAll(AppliedProgramOverlay.self, in: context).count == 1)
        #expect(try fetchAll(AppliedOverlayAdjustment.self, in: context).count == 1)
        #expect(try fetchAll(AdaptationEventHistory.self, in: context).count == 1)
        #expect(try fetchAll(HealthKitDailySummary.self, in: context).count == 1)

        let restoredWorkout = try #require(
            try fetchAll(Workout.self, in: context).first { $0.id == fixture.primaryWorkoutID }
        )
        #expect(restoredWorkout.exerciseEntries.count == 2)
        #expect(restoredWorkout.programRun?.id == fixture.programRunID)

        let cardioEntry = try #require(
            try fetchAll(ExerciseEntry.self, in: context).first { $0.id == fixture.cardioExerciseEntryID }
        )
        #expect(cardioEntry.isCardio)
        #expect(cardioEntry.cardioDurationSeconds == 900)

        let preferences = PortableBackupPreferences(defaults: defaults)
        #expect(preferences.defaultWeightUnit == .kg)
        #expect(preferences.appColorScheme == fixture.expectedColorScheme)
        #expect(preferences.defaultRestTimerSeconds == 120)
        #expect(preferences.coachPreferredDays == 42)
        #expect(preferences.healthKitEnabled)
        #expect(preferences.useHealthKitInDailyCoach)
        #expect(preferences.importHealthKitWorkouts)
        #expect(preferences.writeAppWorkoutsToHealthKit == false)
        #expect(preferences.generatorAIFocus == .powerlifting)
        #expect(preferences.generatorAILevel == .intermediate)
        #expect(preferences.generatorAIDurationWeeks == 8)
        #expect(preferences.generatorAIFrequency == 4)
        #expect(preferences.generatorFlowMode == .push)
        #expect(preferences.generatorFlowGoal == .strength)
        #expect(preferences.generatorFlowEquipment == .fullGym)
        #expect(preferences.generatorFlowDurationMinutes == 45)
        #expect(preferences.generatorFlowIntensity == 4)

        let complianceData = try #require(
            defaults.data(forKey: ComplianceStateStore.persistenceKey)
        )
        let complianceState = try JSONDecoder().decode(
            ComplianceOnboardingState.self,
            from: complianceData
        )
        #expect(complianceState.isComplete())

        let accountData = try #require(
            defaults.data(forKey: LocalContractAuthService.persistenceKey)
        )
        let accountState = try JSONDecoder().decode(
            AccountBackendContractState.self,
            from: accountData
        )
        let productionAccountData = try #require(
            defaults.data(forKey: ProductionBackendAuthService.persistenceKey)
        )
        let productionAccountState = try JSONDecoder().decode(
            AccountBackendContractState.self,
            from: productionAccountData
        )
        #expect(accountState.currentAccountID == fixture.accountID)
        #expect(accountState.knownAccounts.first?.email == "\(fixture.variantLabel)@example.com")
        #expect(accountState.privacyRequests.first?.accountID == fixture.accountID)
        #expect(accountState.consumerHealthConsents.first?.accountID == fixture.accountID)
        #expect(productionAccountState.currentAccountID == fixture.accountID)
        #expect(productionAccountState.knownAccounts.first?.email == "\(fixture.variantLabel)@example.com")
    }

    private func seedPortableBackupFixture(
        context: ModelContext,
        defaults: UserDefaults,
        variantLabel: String
    ) throws -> PortableBackupFixture {
        let ids = PortableBackupFixture.make(variantLabel: variantLabel)

        let chest = MuscleGroup(name: "\(variantLabel.capitalized) Chest")
        let legs = MuscleGroup(name: "\(variantLabel.capitalized) Legs")
        let cardio = MuscleGroup(name: "\(variantLabel.capitalized) Cardio")

        let bench = Exercise(
            name: "\(variantLabel.capitalized) Bench Press",
            exerciseType: .compound,
            muscleGroup: chest
        )
        let incline = Exercise(
            name: "\(variantLabel.capitalized) Incline Press",
            exerciseType: .accessory,
            muscleGroup: chest
        )
        let squat = Exercise(
            name: "\(variantLabel.capitalized) Back Squat",
            exerciseType: .compound,
            muscleGroup: legs
        )
        let bike = Exercise(
            name: "\(variantLabel.capitalized) Bike",
            exerciseType: .cardio,
            muscleGroup: cardio
        )

        chest.exercises = [bench, incline]
        legs.exercises = [squat]
        cardio.exercises = [bike]

        context.insert(chest)
        context.insert(legs)
        context.insert(cardio)
        context.insert(bench)
        context.insert(incline)
        context.insert(squat)
        context.insert(bike)

        let program = TrainingProgram(
            id: ids.programID,
            syncStableID: "\(variantLabel)-program-stable",
            syncVersion: 4,
            syncLastModifiedAt: day(1),
            name: "\(variantLabel.capitalized) Strength Block",
            lengthInWeeks: 8,
            sessionsPerWeek: 4,
            createdDate: day(1),
            source: .aiGenerated,
            descriptionText: "Portable backup fixture program",
            progressionModel: .dup,
            usedLiftMapping: true,
            usedVolumeBalancing: true,
            usedFatigueBalancing: true,
            usedTopSetBackoff: true
        )
        let week = ProgramWeekTemplate(
            id: ids.weekID,
            weekNumber: 1,
            isDeloadWeek: false,
            progressionPhase: .dupHeavy,
            plannedFatigueScore: 6.2
        )
        let session = ProgramSessionTemplate(
            id: ids.sessionID,
            sessionNumber: 1,
            sessionName: "Heavy Bench",
            plannedFatigueScore: 3.1,
            explainabilityReason: .specificityExposure
        )
        let programExercise = ProgramSessionExercise(
            id: ids.programSessionExerciseID,
            syncStableID: "\(variantLabel)-session-exercise-primary",
            syncVersion: 3,
            syncLastModifiedAt: day(1),
            exerciseName: bench.name,
            orderIndex: 0,
            targetSets: 3,
            targetReps: 5,
            targetPercentage1RM: 0.80,
            targetRPE: nil,
            targetRIR: 2,
            isWarmup: false,
            prescribedWeight: 225,
            prescribedWeightUnit: WeightUnit.lbs.rawValue,
            workingSetStyle: .topSet,
            backoffPercentageDrop: 0.06,
            targetEffortType: .percentage1RM,
            baseLiftUsed: bench.name,
            effectiveOneRepMax: 275,
            effectiveOneRepMaxUnit: WeightUnit.lbs.rawValue,
            usedMappedSourceLift: false,
            progressionPhase: .dupHeavy,
            estimatedFatigueScore: 2.7,
            topBackoffGroupID: ids.topBackoffGroupID,
            explainabilityPurpose: .specificity,
            explainabilitySelectionReason: .sessionSpecificity
        )
        let accessoryExercise = ProgramSessionExercise(
            id: ids.programAccessoryExerciseID,
            syncStableID: "\(variantLabel)-session-exercise-accessory",
            syncVersion: 2,
            syncLastModifiedAt: day(1),
            exerciseName: incline.name,
            orderIndex: 1,
            targetSets: 3,
            targetReps: 10,
            targetPercentage1RM: nil,
            targetRPE: 8.0,
            targetRIR: nil,
            isWarmup: false,
            prescribedWeight: 70,
            prescribedWeightUnit: WeightUnit.lbs.rawValue,
            workingSetStyle: .straight,
            backoffPercentageDrop: nil,
            targetEffortType: .rpe,
            baseLiftUsed: nil,
            effectiveOneRepMax: nil,
            effectiveOneRepMaxUnit: nil,
            usedMappedSourceLift: nil,
            progressionPhase: .dupModerate,
            estimatedFatigueScore: 1.4,
            topBackoffGroupID: nil,
            explainabilityPurpose: .volumeFill,
            explainabilitySelectionReason: .muscleDeficit
        )

        program.weeks = [week]
        week.program = program
        week.sessions = [session]
        session.week = week
        session.exercises = [programExercise, accessoryExercise]
        programExercise.session = session
        accessoryExercise.session = session

        context.insert(program)
        context.insert(week)
        context.insert(session)
        context.insert(programExercise)
        context.insert(accessoryExercise)

        let run = ProgramRun(
            id: ids.programRunID,
            syncStableID: "\(variantLabel)-run-stable",
            syncVersion: 2,
            syncLastModifiedAt: day(2),
            startDate: day(2),
            endDate: nil,
            isCompleted: false,
            previousProgramRunStableID: "\(variantLabel)-previous-run",
            recommendationDecisionHistoryJSON: #"{"decision":"accepted"}"#,
            continuitySnapshotJSON: #"{"source":"portable-backup"}"#
        )
        run.program = program
        context.insert(run)

        let workout = Workout(
            id: ids.primaryWorkoutID,
            syncStableID: "\(variantLabel)-workout-stable",
            syncVersion: 5,
            syncLastModifiedAt: day(3),
            syncDeletedAt: nil,
            date: day(3),
            startTime: day(3),
            durationSeconds: 3_600,
            caloriesBurned: 430,
            comments: "Felt strong.",
            programRun: run,
            programWeekNumber: 1,
            programSessionNumber: 1,
            sourceType: .loggedInApp
        )
        let primaryEntry = ExerciseEntry(
            id: ids.primaryExerciseEntryID,
            syncStableID: "\(variantLabel)-entry-primary",
            syncVersion: 2,
            syncLastModifiedAt: day(3),
            exerciseName: bench.name,
            unit: .lbs,
            orderIndex: 0,
            isCardio: false,
            cardioDurationSeconds: nil,
            sourceProgramSessionExerciseID: ids.programSessionExerciseID,
            prescribedTargetSets: 3,
            prescribedTargetReps: 5,
            prescribedTargetPercentage1RM: 0.80,
            prescribedTargetRPE: nil,
            prescribedTargetRIR: 2,
            prescribedWeight: 225,
            prescribedWeightUnit: WeightUnit.lbs.rawValue,
            prescribedWorkingSetStyle: .topSet,
            prescribedTargetEffortType: .percentage1RM
        )
        primaryEntry.effortFeedback = .onTarget
        primaryEntry.topSetRPE = 8.5
        let primarySet = SetEntry(
            id: ids.primarySetID,
            syncStableID: "\(variantLabel)-set-primary",
            syncVersion: 2,
            syncLastModifiedAt: day(3),
            setNumber: 1,
            reps: 5,
            weight: 225,
            isPR: true
        )
        let secondSet = SetEntry(
            id: ids.secondarySetID,
            syncStableID: "\(variantLabel)-set-secondary",
            syncVersion: 2,
            syncLastModifiedAt: day(3),
            setNumber: 2,
            reps: 5,
            weight: 215,
            isPR: false
        )
        primaryEntry.sets = [primarySet, secondSet]
        primarySet.exerciseEntry = primaryEntry
        secondSet.exerciseEntry = primaryEntry

        let accessoryEntry = ExerciseEntry(
            id: ids.accessoryExerciseEntryID,
            syncStableID: "\(variantLabel)-entry-accessory",
            syncVersion: 2,
            syncLastModifiedAt: day(3),
            exerciseName: incline.name,
            unit: .lbs,
            orderIndex: 1,
            isCardio: false,
            cardioDurationSeconds: nil,
            sourceProgramSessionExerciseID: ids.programAccessoryExerciseID,
            prescribedTargetSets: 3,
            prescribedTargetReps: 10,
            prescribedTargetPercentage1RM: nil,
            prescribedTargetRPE: 8.0,
            prescribedTargetRIR: nil,
            prescribedWeight: 70,
            prescribedWeightUnit: WeightUnit.lbs.rawValue,
            prescribedWorkingSetStyle: .straight,
            prescribedTargetEffortType: .rpe
        )
        accessoryEntry.effortFeedback = .tooEasy
        accessoryEntry.topSetRPE = 7.0

        workout.exerciseEntries = [primaryEntry, accessoryEntry]
        primaryEntry.workout = workout
        accessoryEntry.workout = workout

        let cardioWorkout = Workout(
            id: ids.cardioWorkoutID,
            syncStableID: "\(variantLabel)-workout-cardio",
            syncVersion: 3,
            syncLastModifiedAt: day(4),
            syncDeletedAt: nil,
            date: day(4),
            startTime: day(4),
            durationSeconds: 1_800,
            caloriesBurned: 220,
            comments: "Easy conditioning.",
            programRun: nil,
            programWeekNumber: nil,
            programSessionNumber: nil,
            sourceType: .healthKitImported,
            sourceExternalIdentifier: "\(variantLabel)-hk-1",
            sourceDisplayName: "Apple Health",
            sourceWorkoutTypeIdentifier: "37",
            sourceWorkoutTypeDisplayName: "Cycling",
            sourceImportedAt: day(4),
            healthKitExportedAt: day(4),
            healthKitWritebackIdentifier: "\(variantLabel)-writeback"
        )
        let cardioEntry = ExerciseEntry(
            id: ids.cardioExerciseEntryID,
            syncStableID: "\(variantLabel)-entry-cardio",
            syncVersion: 1,
            syncLastModifiedAt: day(4),
            exerciseName: bike.name,
            unit: .lbs,
            orderIndex: 0,
            isCardio: true,
            cardioDurationSeconds: 900,
            sourceProgramSessionExerciseID: nil,
            prescribedTargetSets: nil,
            prescribedTargetReps: nil,
            prescribedTargetPercentage1RM: nil,
            prescribedTargetRPE: nil,
            prescribedTargetRIR: nil,
            prescribedWeight: nil,
            prescribedWeightUnit: nil,
            prescribedWorkingSetStyle: nil,
            prescribedTargetEffortType: nil
        )
        cardioWorkout.exerciseEntries = [cardioEntry]
        cardioEntry.workout = cardioWorkout

        context.insert(workout)
        context.insert(primaryEntry)
        context.insert(primarySet)
        context.insert(secondSet)
        context.insert(accessoryEntry)
        context.insert(cardioWorkout)
        context.insert(cardioEntry)

        let record = PersonalRecord(
            id: ids.personalRecordID,
            syncStableID: "\(variantLabel)-pr-stable",
            syncVersion: 2,
            syncLastModifiedAt: day(3),
            exerciseName: bench.name,
            repCount: 5,
            weight: 225,
            unit: .lbs,
            dateAchieved: day(3)
        )
        context.insert(record)

        let checkIn = DailyCoachCheckIn(
            id: ids.checkInID,
            syncStableID: "\(variantLabel)-checkin-stable",
            syncVersion: 2,
            syncLastModifiedAt: day(5),
            date: day(5),
            dayStart: day(5),
            sleepQuality: 4,
            soreness: 2,
            energy: 4,
            stress: 2,
            availableTimeMinutes: 70,
            hasPainOrDiscomfort: false,
            painNotes: nil,
            programRun: run,
            createdAt: day(5),
            updatedAt: day(5)
        )
        context.insert(checkIn)

        let analysis = WeeklyTrainingAnalysis(
            id: ids.analysisID,
            createdAt: day(6),
            weekStartDate: day(0),
            weekEndDate: day(6),
            programRun: run,
            trainingProgram: program,
            programWeekNumber: 1,
            focusSnapshot: .powerlifting,
            programWorkoutCount: 1,
            standaloneWorkoutCount: 1,
            totalOutcomeCount: 1,
            totalSignalWeight: 1.6,
            programSignalWeight: 1.0,
            standaloneSignalWeight: 0.6,
            weightedPerformanceScore: 0.88,
            adherenceScore: 0.94,
            plannedFatigueScore: 6.2,
            observedFatigueScore: 5.3,
            fatigueStatus: .manageable,
            totalCompletedHardSets: 7,
            totalCompletedTonnage: 4_200,
            isFinalized: true,
            finalizedAt: day(6)
        )
        let outcome = ExercisePerformanceOutcome(
            id: ids.outcomeID,
            createdAt: day(6),
            analysis: analysis,
            programRun: run,
            workout: workout,
            exerciseEntry: primaryEntry,
            workoutDate: day(3),
            programWeekNumber: 1,
            programSessionNumber: 1,
            sourceProgramSessionExerciseID: ids.programSessionExerciseID,
            exerciseName: bench.name,
            canonicalLiftKey: "bench",
            signalSource: .programLinked,
            signalConfidence: .high,
            signalWeight: 1.0,
            prescribedSets: 3,
            prescribedReps: 5,
            prescribedWeight: 225,
            prescribedWeightUnit: WeightUnit.lbs.rawValue,
            prescribedTargetPercentage1RM: 0.80,
            prescribedTargetRPE: nil,
            prescribedTargetRIR: 2,
            prescribedWorkingSetStyle: .topSet,
            prescribedTargetEffortType: .percentage1RM,
            actualSetCount: 2,
            actualAverageReps: 5,
            actualAverageWeight: 220,
            actualTopSetReps: 5,
            actualTopSetWeight: 225,
            actualTopSetEstimated1RM: 262,
            completionRatio: 0.67,
            loadDeltaPercent: 0.01,
            repsDelta: 0,
            performanceScoreValue: 0.88,
            performanceScore: .overperformance,
            inferredFatigueStatus: .manageable,
            isTopSetSignal: true,
            notes: "Beat target cleanly."
        )
        let volumeMetric = WeeklyVolumeMetric(
            id: ids.volumeMetricID,
            analysis: analysis,
            muscle: .chest,
            plannedHardSets: 6,
            completedHardSets: 7,
            weightedCompletedHardSets: 7,
            deltaHardSets: 1
        )
        analysis.outcomes = [outcome]
        analysis.volumeMetrics = [volumeMetric]

        let weeklyReview = DailyCoachWeeklyReview(
            id: ids.reviewID,
            syncStableID: "\(variantLabel)-review-stable",
            syncVersion: 2,
            syncLastModifiedAt: day(6),
            weekStart: day(0),
            weekEnd: day(6),
            isProgramWeek: true,
            programRun: run,
            headline: "Solid week",
            winText: "Bench trended up.",
            watchoutText: "Keep shoulder fatigue in check.",
            nextActionText: "Progress bench load next week.",
            sourceWeeklyAnalysisIDText: ids.analysisID.uuidString,
            hasBeenSeen: true,
            createdAt: day(6)
        )

        let trend = LiftPerformanceTrend(
            id: ids.trendID,
            updatedAt: day(6),
            programRun: run,
            trainingProgram: program,
            canonicalLiftKey: "bench",
            liftDisplayName: bench.name,
            totalDataPoints: 3,
            programLinkedDataPoints: 2,
            standaloneDataPoints: 1,
            weightedSignalCount: 2.6,
            confidenceScore: 0.82,
            firstObservationDate: day(1),
            lastObservationDate: day(6),
            currentEstimated1RM: 262,
            previousEstimated1RM: 257,
            rollingBestEstimated1RM: 262,
            fourWeekChangePercent: 1.9,
            trendStatus: .improving,
            fatigueStatus: .manageable,
            latestTopSetWeight: 225,
            latestTopSetReps: 5,
            latestPerformanceScoreValue: 0.88,
            lastPerformanceScore: .overperformance
        )
        let snapshot = LiftTrendSnapshot(
            id: ids.snapshotID,
            createdAt: day(6),
            trend: trend,
            analysis: analysis,
            programRun: run,
            trainingProgram: program,
            canonicalLiftKey: "bench",
            liftDisplayName: bench.name,
            weekStartDate: day(0),
            weekEndDate: day(6),
            programWeekNumber: 1,
            totalDataPoints: 3,
            programLinkedDataPoints: 2,
            standaloneDataPoints: 1,
            weightedSignalCount: 2.6,
            weightedProgramSignal: 2.0,
            weightedStandaloneSignal: 0.6,
            confidenceScore: 0.82,
            currentEstimated1RM: 262,
            baselineEstimated1RM: 255,
            rollingBestEstimated1RM: 262,
            changePercent: 2.7,
            trendStatus: .improving,
            fatigueStatus: .manageable,
            latestTopSetWeight: 225,
            latestTopSetReps: 5,
            latestPerformanceScoreValue: 0.88,
            note: "Trend improving."
        )
        analysis.trendSnapshots = [snapshot]
        trend.snapshots = [snapshot]

        let proposal = AdaptationProposal(
            id: ids.proposalID,
            syncStableID: "\(variantLabel)-proposal-stable",
            syncVersion: 2,
            syncLastModifiedAt: day(6),
            createdAt: day(6),
            decidedAt: day(7),
            programRun: run,
            trainingProgram: program,
            sourceAnalysis: analysis,
            proposalType: .increaseLoad,
            proposalStatus: .confirmed,
            requiresUserConfirmation: true,
            autoApplyEligible: false,
            confidenceScore: 0.84,
            priority: 9,
            targetWeekStart: 2,
            targetWeekEnd: nil,
            targetSessionNumber: 1,
            targetProgramSessionExerciseID: ids.programSessionExerciseID,
            targetLiftKey: "bench",
            proposedLoadPercentDelta: 0.025,
            proposedSetDelta: nil,
            proposedRepDelta: nil,
            proposedDeloadFactor: nil,
            swapFromExerciseName: nil,
            swapToExerciseName: nil,
            adjustmentReason: .positiveLiftTrend,
            summaryText: "Increase bench load next week.",
            detailText: "Top-set performance and trend support a small bump.",
            expiresAt: day(10)
        )

        let overlay = AppliedProgramOverlay(
            id: ids.overlayID,
            syncStableID: "\(variantLabel)-overlay-stable",
            syncVersion: 2,
            syncLastModifiedAt: day(7),
            createdAt: day(7),
            appliedAt: day(7),
            programRun: run,
            trainingProgram: program,
            sourceProposal: proposal,
            effectiveWeekStart: 2,
            effectiveWeekEnd: nil,
            overlayStatus: .active,
            appliedByUserConfirmation: true,
            adjustmentReason: .positiveLiftTrend,
            summaryText: "Bench load bump"
        )
        let adjustment = AppliedOverlayAdjustment(
            id: ids.adjustmentID,
            syncStableID: "\(variantLabel)-adjustment-stable",
            syncVersion: 2,
            syncLastModifiedAt: day(7),
            overlay: overlay,
            sequence: 1,
            targetProgramSessionExerciseID: ids.programSessionExerciseID,
            targetWeekNumber: 2,
            targetSessionNumber: 1,
            adjustmentType: .load,
            loadPercentDelta: 0.025,
            absolutePrescribedWeight: nil,
            setDelta: nil,
            absoluteTargetSets: nil,
            repDelta: nil,
            absoluteTargetReps: nil,
            replacementExerciseName: nil,
            adjustmentReason: .positiveLiftTrend,
            isAutoApplied: false
        )
        overlay.adjustments = [adjustment]
        proposal.appliedOverlays = [overlay]

        let event = AdaptationEventHistory(
            id: ids.eventID,
            timestamp: day(7),
            programRun: run,
            trainingProgram: program,
            analysis: analysis,
            proposal: proposal,
            overlay: overlay,
            eventType: .overlayApplied,
            analysisWeekNumber: 1,
            targetLiftKey: "bench",
            message: "Applied bench increase.",
            explanation: "Trend and outcome quality supported a small load jump.",
            adjustmentReason: .positiveLiftTrend,
            performanceScoreSnapshot: .overperformance,
            fatigueStatusSnapshot: .manageable,
            liftTrendStatusSnapshot: .improving,
            confidenceSnapshot: 0.84,
            requiresUserAction: false,
            userActionTaken: true
        )

        let healthSummary = HealthKitDailySummary(
            id: ids.healthSummaryID,
            syncStableID: "\(variantLabel)-health-stable",
            syncVersion: 2,
            syncLastModifiedAt: day(7),
            dayStart: day(5),
            sleepDurationSeconds: 28_800,
            timeInBedSeconds: 30_000,
            restingHeartRateBPM: 55,
            heartRateVariabilityMS: 68,
            activeEnergyKilocalories: 640,
            stepCount: 10_500,
            bodyMassKilograms: 81.8,
            sourceUpdatedAt: day(5),
            createdAt: day(5),
            updatedAt: day(7)
        )

        context.insert(checkIn)
        context.insert(analysis)
        context.insert(outcome)
        context.insert(volumeMetric)
        context.insert(weeklyReview)
        context.insert(trend)
        context.insert(snapshot)
        context.insert(proposal)
        context.insert(overlay)
        context.insert(adjustment)
        context.insert(event)
        context.insert(healthSummary)

        try context.save()

        try seedPortableBackupDefaults(
            defaults: defaults,
            fixture: ids
        )

        return ids
    }

    private func seedPortableBackupDefaults(
        defaults: UserDefaults,
        fixture: PortableBackupFixture
    ) throws {
        defaults.set(WeightUnit.kg.rawValue, forKey: "globalWeightUnit")
        defaults.set(fixture.expectedColorScheme, forKey: "appColorScheme")
        defaults.set(120, forKey: "defaultRestTimerSeconds")
        defaults.set(42, forKey: "coachPreferredDays")
        defaults.set(true, forKey: HealthKitSettingsStorage.healthKitEnabledKey)
        defaults.set(true, forKey: HealthKitSettingsStorage.dailyCoachEnabledKey)
        defaults.set(true, forKey: "healthkit.importWorkouts")
        defaults.set(false, forKey: "healthkit.writeWorkouts")
        HealthKitSettingsStorage.setDate(
            day(8),
            forKey: HealthKitSettingsStorage.recoveryLastSyncTimestampKey,
            defaults: defaults
        )
        HealthKitSettingsStorage.setDate(
            day(9),
            forKey: HealthKitSettingsStorage.workoutImportLastSyncTimestampKey,
            defaults: defaults
        )

        defaults.set(ProgramFocus.powerlifting.rawValue, forKey: "generator.ai.focus")
        defaults.set(ProgramLevel.intermediate.rawValue, forKey: "generator.ai.level")
        defaults.set(8, forKey: "generator.ai.duration")
        defaults.set(4, forKey: "generator.ai.frequency")
        defaults.set(SuggestMeSomeSessionMode.push.rawValue, forKey: "generator.flow.mode")
        defaults.set(SuggestMeSomeGenerationGoal.strength.rawValue, forKey: "generator.flow.goal")
        defaults.set(SuggestMeSomeEquipmentProfile.fullGym.rawValue, forKey: "generator.flow.equipment")
        defaults.set(45, forKey: "generator.flow.duration")
        defaults.set(4, forKey: "generator.flow.intensity")

        let markerDate = day(10)
        let complianceState = ComplianceOnboardingState(
            confirmedAdultAt: markerDate,
            acknowledgedWellnessDisclaimerAt: markerDate,
            acknowledgedAutomationDisclosureAt: markerDate,
            acceptedDocumentRecords: ComplianceConfiguration.requiredOnboardingDocumentIDs
                .sorted()
                .map { LegalDocumentRecord(documentID: $0, acceptedAt: markerDate) },
            completedAt: markerDate
        )
        let account = UserAccount(
            id: fixture.accountID,
            displayName: fixture.variantLabel.capitalized,
            email: "\(fixture.variantLabel)@example.com",
            createdAt: day(1),
            lastSignedInAt: day(9),
            launchMode: .localContractValidation
        )
        let privacyRequest = PrivacyRequestRecord(
            id: fixture.privacyRequestID,
            accountID: fixture.accountID,
            type: .export,
            status: .completed,
            requestedAt: day(7),
            completedAt: day(8),
            notes: "Portable export ready."
        )
        let consent = ConsumerHealthConsentRecord(
            id: fixture.consentID,
            accountID: fixture.accountID,
            categories: ["fitness", "consumer-health"],
            purpose: "Sync recovery insights for training guidance.",
            acceptedAt: day(6),
            withdrawnAt: nil
        )
        let accountState = AccountBackendContractState(
            knownAccounts: [account],
            currentAccountID: fixture.accountID,
            privacyRequests: [privacyRequest],
            consumerHealthConsents: [consent]
        )

        defaults.set(
            try JSONEncoder().encode(complianceState),
            forKey: ComplianceStateStore.persistenceKey
        )
        defaults.set(
            try JSONEncoder().encode(accountState),
            forKey: LocalContractAuthService.persistenceKey
        )
    }

    private func writeBackupFile(
        _ envelope: PortableBackupEnvelope,
        name: String
    ) throws -> URL {
        let data = try PortableBackupJSONCodec.makeEncoder().encode(envelope)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).suggestmesomebackup")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func fetchAll<T: PersistentModel>(
        _ type: T.Type,
        in context: ModelContext
    ) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
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

    private func makeDefaults(prefix: String) -> UserDefaults {
        let suiteName = "Feature15Prompt9PortableBackupTests.\(prefix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(suiteName, forKey: "__portableBackupSuiteName")
        return defaults
    }

    private func clearDefaults(_ defaults: UserDefaults) {
        guard let suiteName = defaults.string(forKey: "__portableBackupSuiteName") else { return }
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_712_000_000 + TimeInterval(offset * 86_400))
    }
}

private struct PortableBackupFixture {
    let variantLabel: String
    let expectedColorScheme: String
    let accountID: UUID
    let privacyRequestID: UUID
    let consentID: UUID
    let programID: UUID
    let weekID: UUID
    let sessionID: UUID
    let programSessionExerciseID: UUID
    let programAccessoryExerciseID: UUID
    let topBackoffGroupID: UUID
    let programRunID: UUID
    let primaryWorkoutID: UUID
    let cardioWorkoutID: UUID
    let primaryExerciseEntryID: UUID
    let accessoryExerciseEntryID: UUID
    let cardioExerciseEntryID: UUID
    let primarySetID: UUID
    let secondarySetID: UUID
    let personalRecordID: UUID
    let checkInID: UUID
    let reviewID: UUID
    let analysisID: UUID
    let outcomeID: UUID
    let volumeMetricID: UUID
    let trendID: UUID
    let snapshotID: UUID
    let proposalID: UUID
    let overlayID: UUID
    let adjustmentID: UUID
    let eventID: UUID
    let healthSummaryID: UUID

    static func make(variantLabel: String) -> PortableBackupFixture {
        let prefix = variantLabel == "source" ? "1000" : "2000"
        func uuid(_ suffix: String) -> UUID {
            UUID(uuidString: "\(prefix)0000-0000-0000-0000-\(suffix)")!
        }

        return PortableBackupFixture(
            variantLabel: variantLabel,
            expectedColorScheme: variantLabel == "source" ? "dark" : "light",
            accountID: uuid("000000000001"),
            privacyRequestID: uuid("000000000002"),
            consentID: uuid("000000000003"),
            programID: uuid("000000000004"),
            weekID: uuid("000000000005"),
            sessionID: uuid("000000000006"),
            programSessionExerciseID: uuid("000000000007"),
            programAccessoryExerciseID: uuid("000000000008"),
            topBackoffGroupID: uuid("000000000009"),
            programRunID: uuid("000000000010"),
            primaryWorkoutID: uuid("000000000011"),
            cardioWorkoutID: uuid("000000000012"),
            primaryExerciseEntryID: uuid("000000000013"),
            accessoryExerciseEntryID: uuid("000000000014"),
            cardioExerciseEntryID: uuid("000000000015"),
            primarySetID: uuid("000000000016"),
            secondarySetID: uuid("000000000017"),
            personalRecordID: uuid("000000000018"),
            checkInID: uuid("000000000019"),
            reviewID: uuid("000000000020"),
            analysisID: uuid("000000000021"),
            outcomeID: uuid("000000000022"),
            volumeMetricID: uuid("000000000023"),
            trendID: uuid("000000000024"),
            snapshotID: uuid("000000000025"),
            proposalID: uuid("000000000026"),
            overlayID: uuid("000000000027"),
            adjustmentID: uuid("000000000028"),
            eventID: uuid("000000000029"),
            healthSummaryID: uuid("000000000030")
        )
    }
}
