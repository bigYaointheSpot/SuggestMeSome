import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let suggestMeSomeBackup = UTType(
        exportedAs: "com.alexyao.suggestmesome.portable-backup",
        conformingTo: .json
    )
}

enum PortableBackupError: LocalizedError, Equatable {
    case fileReadFailed
    case fileWriteFailed
    case invalidBackupFile
    case unsupportedVersion(Int)
    case validationFailed([String])

    var errorDescription: String? {
        switch self {
        case .fileReadFailed:
            return "The selected backup file could not be read."
        case .fileWriteFailed:
            return "The backup file could not be written."
        case .invalidBackupFile:
            return "The selected file is not a valid SuggestMeSome backup."
        case .unsupportedVersion(let version):
            return "This backup uses an unsupported version (\(version))."
        case .validationFailed(let issues):
            guard let first = issues.first else {
                return "This backup file failed validation."
            }
            return first
        }
    }
}

enum PortableBackupJSONCodec {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, container in
            var container = container.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = formatter.date(from: value) {
                return date
            }

            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date value: \(value)"
            )
        }
        return decoder
    }
}

@MainActor
final class PortableBackupService {
    private let userDefaults: UserDefaults
    private let bundle: Bundle

    init(
        userDefaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        self.userDefaults = userDefaults
        self.bundle = bundle
    }

    func exportBackupEnvelope(
        context: ModelContext,
        generatedAt: Date = .now
    ) throws -> PortableBackupEnvelope {
        let payload = try PortableBackupPayload(
            muscleGroups: exportMuscleGroups(context: context),
            workouts: exportWorkouts(context: context),
            personalRecords: exportPersonalRecords(context: context),
            trainingPrograms: exportTrainingPrograms(context: context),
            programRuns: exportProgramRuns(context: context),
            dailyCoachCheckIns: exportDailyCoachCheckIns(context: context),
            dailyCoachWeeklyReviews: exportDailyCoachWeeklyReviews(context: context),
            weeklyTrainingAnalyses: exportWeeklyTrainingAnalyses(context: context),
            liftPerformanceTrends: exportLiftPerformanceTrends(context: context),
            adaptationProposals: exportAdaptationProposals(context: context),
            appliedProgramOverlays: exportAppliedProgramOverlays(context: context),
            adaptationEventHistory: exportAdaptationEventHistory(context: context),
            healthKitDailySummaries: exportHealthKitDailySummaries(context: context),
            localState: PortableBackupLocalState(
                preferences: PortableBackupPreferences(defaults: userDefaults),
                complianceState: loadComplianceState(),
                accountState: loadAccountState()
            )
        )

        return PortableBackupEnvelope(
            backupVersion: PortableBackupVersion.current,
            generatedAt: generatedAt,
            source: makeSourceMetadata(),
            manifest: payload.computedManifest(),
            payload: payload
        )
    }

    func writeBackupFile(
        context: ModelContext,
        generatedAt: Date = .now
    ) throws -> URL {
        let envelope = try exportBackupEnvelope(context: context, generatedAt: generatedAt)
        let encoder = PortableBackupJSONCodec.makeEncoder()

        guard let data = try? encoder.encode(envelope) else {
            throw PortableBackupError.fileWriteFailed
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"

        let filename = "SuggestMeSome_Backup_\(formatter.string(from: generatedAt)).suggestmesomebackup"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            throw PortableBackupError.fileWriteFailed
        }
    }

    func previewBackup(from fileURL: URL) throws -> PortableBackupImportPreview {
        let envelope = try loadEnvelope(from: fileURL)
        return PortableBackupImportPreview(
            fileName: fileURL.lastPathComponent,
            envelope: envelope
        )
    }

    func restoreBackup(
        _ envelope: PortableBackupEnvelope,
        context: ModelContext
    ) throws -> PortableBackupRestoreResult {
        let issues = validate(envelope)
        if !issues.isEmpty {
            throw PortableBackupError.validationFailed(issues)
        }

        try LocalDataResetService.resetPortableBackupScope(
            context: context,
            userDefaults: userDefaults,
            clearUserDefaults: false
        )

        importMuscleGroups(envelope.payload.muscleGroups, context: context)
        let programGraph = importTrainingPrograms(envelope.payload.trainingPrograms, context: context)
        let programRuns = importProgramRuns(
            envelope.payload.programRuns,
            programsByID: programGraph.programsByID,
            context: context
        )
        let workouts = importWorkouts(
            envelope.payload.workouts,
            programRunsByID: programRuns,
            context: context
        )

        importPersonalRecords(envelope.payload.personalRecords, context: context)
        importDailyCoachCheckIns(
            envelope.payload.dailyCoachCheckIns,
            programRunsByID: programRuns,
            context: context
        )
        importDailyCoachWeeklyReviews(
            envelope.payload.dailyCoachWeeklyReviews,
            programRunsByID: programRuns,
            context: context
        )

        let analyses = importWeeklyTrainingAnalyses(
            envelope.payload.weeklyTrainingAnalyses,
            programRunsByID: programRuns,
            programsByID: programGraph.programsByID,
            workoutsByID: workouts.workoutsByID,
            exerciseEntriesByID: workouts.exerciseEntriesByID,
            context: context
        )
        let proposals = importAdaptationProposals(
            envelope.payload.adaptationProposals,
            programRunsByID: programRuns,
            programsByID: programGraph.programsByID,
            analysesByID: analyses,
            context: context
        )
        let overlays = importAppliedProgramOverlays(
            envelope.payload.appliedProgramOverlays,
            programRunsByID: programRuns,
            programsByID: programGraph.programsByID,
            proposalsByID: proposals,
            context: context
        )
        let trends = importLiftPerformanceTrends(
            envelope.payload.liftPerformanceTrends,
            programRunsByID: programRuns,
            programsByID: programGraph.programsByID,
            analysesByID: analyses,
            context: context
        )

        importAdaptationEventHistory(
            envelope.payload.adaptationEventHistory,
            programRunsByID: programRuns,
            programsByID: programGraph.programsByID,
            analysesByID: analyses,
            proposalsByID: proposals,
            overlaysByID: overlays,
            context: context
        )
        importHealthKitDailySummaries(
            envelope.payload.healthKitDailySummaries,
            context: context
        )

        try context.save()
        LocalDataResetService.clearPortableBackupUserDefaults(userDefaults)
        persistLocalState(envelope.payload.localState)
        _ = trends

        return PortableBackupRestoreResult(restoredManifest: envelope.manifest)
    }

    private func loadEnvelope(from fileURL: URL) throws -> PortableBackupEnvelope {
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            throw PortableBackupError.fileReadFailed
        }

        let decoder = PortableBackupJSONCodec.makeDecoder()
        guard let envelope = try? decoder.decode(PortableBackupEnvelope.self, from: data) else {
            throw PortableBackupError.invalidBackupFile
        }

        let issues = validate(envelope)
        if !issues.isEmpty {
            throw PortableBackupError.validationFailed(issues)
        }

        return envelope
    }

    private func validate(_ envelope: PortableBackupEnvelope) -> [String] {
        var issues: [String] = []

        guard envelope.backupVersion == PortableBackupVersion.current else {
            return [PortableBackupError.unsupportedVersion(envelope.backupVersion).errorDescription ?? "Unsupported backup version."]
        }

        let computedManifest = envelope.payload.computedManifest()
        if computedManifest != envelope.manifest {
            issues.append("This backup file’s manifest does not match its payload.")
        }

        var programIDs = Set<UUID>()
        var programRunIDs = Set<UUID>()
        var workoutIDs = Set<UUID>()
        var exerciseEntryIDs = Set<UUID>()
        var setIDs = Set<UUID>()
        var personalRecordIDs = Set<UUID>()
        var dailyCoachCheckInIDs = Set<UUID>()
        var dailyCoachWeeklyReviewIDs = Set<UUID>()
        var weeklyAnalysisIDs = Set<UUID>()
        var outcomeIDs = Set<UUID>()
        var volumeMetricIDs = Set<UUID>()
        var trendIDs = Set<UUID>()
        var trendSnapshotIDs = Set<UUID>()
        var proposalIDs = Set<UUID>()
        var overlayIDs = Set<UUID>()
        var overlayAdjustmentIDs = Set<UUID>()
        var eventIDs = Set<UUID>()
        var healthSummaryIDs = Set<UUID>()
        var accountIDs = Set<UUID>()
        var programSessionExerciseIDs = Set<UUID>()
        var programWeekIDs = Set<UUID>()
        var programSessionIDs = Set<UUID>()

        for program in envelope.payload.trainingPrograms {
            register(program.id, label: "training program", into: &programIDs, issues: &issues)
            for week in program.weeks {
                register(week.id, label: "program week", into: &programWeekIDs, issues: &issues)
                for session in week.sessions {
                    register(session.id, label: "program session", into: &programSessionIDs, issues: &issues)
                    for exercise in session.exercises {
                        register(exercise.id, label: "program session exercise", into: &programSessionExerciseIDs, issues: &issues)
                    }
                }
            }
        }

        for run in envelope.payload.programRuns {
            register(run.id, label: "program run", into: &programRunIDs, issues: &issues)
            if let trainingProgramID = run.trainingProgramID,
               !programIDs.contains(trainingProgramID) {
                issues.append("Program run \(run.id.uuidString) references a missing training program.")
            }
        }

        for workout in envelope.payload.workouts {
            register(workout.id, label: "workout", into: &workoutIDs, issues: &issues)
            if let programRunID = workout.programRunID,
               !programRunIDs.contains(programRunID) {
                issues.append("Workout \(workout.id.uuidString) references a missing program run.")
            }
            for entry in workout.exerciseEntries {
                register(entry.id, label: "exercise entry", into: &exerciseEntryIDs, issues: &issues)
                if let sourceID = entry.sourceProgramSessionExerciseID,
                   !programSessionExerciseIDs.contains(sourceID) {
                    issues.append("Workout entry \(entry.id.uuidString) references a missing program session exercise.")
                }
                for set in entry.sets {
                    register(set.id, label: "set entry", into: &setIDs, issues: &issues)
                }
            }
        }

        for record in envelope.payload.personalRecords {
            register(record.id, label: "personal record", into: &personalRecordIDs, issues: &issues)
        }

        for checkIn in envelope.payload.dailyCoachCheckIns {
            register(checkIn.id, label: "Daily Coach check-in", into: &dailyCoachCheckInIDs, issues: &issues)
            if let programRunID = checkIn.programRunID,
               !programRunIDs.contains(programRunID) {
                issues.append("Daily Coach check-in \(checkIn.id.uuidString) references a missing program run.")
            }
        }

        for review in envelope.payload.dailyCoachWeeklyReviews {
            register(review.id, label: "Daily Coach weekly review", into: &dailyCoachWeeklyReviewIDs, issues: &issues)
            if let programRunID = review.programRunID,
               !programRunIDs.contains(programRunID) {
                issues.append("Daily Coach weekly review \(review.id.uuidString) references a missing program run.")
            }
        }

        for analysis in envelope.payload.weeklyTrainingAnalyses {
            register(analysis.id, label: "weekly training analysis", into: &weeklyAnalysisIDs, issues: &issues)
            if let programRunID = analysis.programRunID,
               !programRunIDs.contains(programRunID) {
                issues.append("Weekly analysis \(analysis.id.uuidString) references a missing program run.")
            }
            if let trainingProgramID = analysis.trainingProgramID,
               !programIDs.contains(trainingProgramID) {
                issues.append("Weekly analysis \(analysis.id.uuidString) references a missing training program.")
            }
            for outcome in analysis.outcomes {
                register(outcome.id, label: "exercise performance outcome", into: &outcomeIDs, issues: &issues)
                if let programRunID = outcome.programRunID,
                   !programRunIDs.contains(programRunID) {
                    issues.append("Outcome \(outcome.id.uuidString) references a missing program run.")
                }
                if let workoutID = outcome.workoutID,
                   !workoutIDs.contains(workoutID) {
                    issues.append("Outcome \(outcome.id.uuidString) references a missing workout.")
                }
                if let exerciseEntryID = outcome.exerciseEntryID,
                   !exerciseEntryIDs.contains(exerciseEntryID) {
                    issues.append("Outcome \(outcome.id.uuidString) references a missing exercise entry.")
                }
                if let sourceID = outcome.sourceProgramSessionExerciseID,
                   !programSessionExerciseIDs.contains(sourceID) {
                    issues.append("Outcome \(outcome.id.uuidString) references a missing program session exercise.")
                }
            }
            for metric in analysis.volumeMetrics {
                register(metric.id, label: "weekly volume metric", into: &volumeMetricIDs, issues: &issues)
            }
        }

        for trend in envelope.payload.liftPerformanceTrends {
            register(trend.id, label: "lift performance trend", into: &trendIDs, issues: &issues)
            if let programRunID = trend.programRunID,
               !programRunIDs.contains(programRunID) {
                issues.append("Lift trend \(trend.id.uuidString) references a missing program run.")
            }
            if let trainingProgramID = trend.trainingProgramID,
               !programIDs.contains(trainingProgramID) {
                issues.append("Lift trend \(trend.id.uuidString) references a missing training program.")
            }
            for snapshot in trend.snapshots {
                register(snapshot.id, label: "lift trend snapshot", into: &trendSnapshotIDs, issues: &issues)
                if let analysisID = snapshot.analysisID,
                   !weeklyAnalysisIDs.contains(analysisID) {
                    issues.append("Lift trend snapshot \(snapshot.id.uuidString) references a missing weekly analysis.")
                }
                if let programRunID = snapshot.programRunID,
                   !programRunIDs.contains(programRunID) {
                    issues.append("Lift trend snapshot \(snapshot.id.uuidString) references a missing program run.")
                }
                if let trainingProgramID = snapshot.trainingProgramID,
                   !programIDs.contains(trainingProgramID) {
                    issues.append("Lift trend snapshot \(snapshot.id.uuidString) references a missing training program.")
                }
            }
        }

        for proposal in envelope.payload.adaptationProposals {
            register(proposal.id, label: "adaptation proposal", into: &proposalIDs, issues: &issues)
            if let programRunID = proposal.programRunID,
               !programRunIDs.contains(programRunID) {
                issues.append("Adaptation proposal \(proposal.id.uuidString) references a missing program run.")
            }
            if let trainingProgramID = proposal.trainingProgramID,
               !programIDs.contains(trainingProgramID) {
                issues.append("Adaptation proposal \(proposal.id.uuidString) references a missing training program.")
            }
            if let analysisID = proposal.sourceAnalysisID,
               !weeklyAnalysisIDs.contains(analysisID) {
                issues.append("Adaptation proposal \(proposal.id.uuidString) references a missing weekly analysis.")
            }
            if let sessionExerciseID = proposal.targetProgramSessionExerciseID,
               !programSessionExerciseIDs.contains(sessionExerciseID) {
                issues.append("Adaptation proposal \(proposal.id.uuidString) references a missing program session exercise.")
            }
        }

        for overlay in envelope.payload.appliedProgramOverlays {
            register(overlay.id, label: "applied overlay", into: &overlayIDs, issues: &issues)
            if let programRunID = overlay.programRunID,
               !programRunIDs.contains(programRunID) {
                issues.append("Applied overlay \(overlay.id.uuidString) references a missing program run.")
            }
            if let trainingProgramID = overlay.trainingProgramID,
               !programIDs.contains(trainingProgramID) {
                issues.append("Applied overlay \(overlay.id.uuidString) references a missing training program.")
            }
            if let proposalID = overlay.sourceProposalID,
               !proposalIDs.contains(proposalID) {
                issues.append("Applied overlay \(overlay.id.uuidString) references a missing proposal.")
            }
            for adjustment in overlay.adjustments {
                register(adjustment.id, label: "overlay adjustment", into: &overlayAdjustmentIDs, issues: &issues)
                if let sessionExerciseID = adjustment.targetProgramSessionExerciseID,
                   !programSessionExerciseIDs.contains(sessionExerciseID) {
                    issues.append("Overlay adjustment \(adjustment.id.uuidString) references a missing program session exercise.")
                }
            }
        }

        for event in envelope.payload.adaptationEventHistory {
            register(event.id, label: "adaptation event", into: &eventIDs, issues: &issues)
            if let programRunID = event.programRunID,
               !programRunIDs.contains(programRunID) {
                issues.append("Adaptation event \(event.id.uuidString) references a missing program run.")
            }
            if let trainingProgramID = event.trainingProgramID,
               !programIDs.contains(trainingProgramID) {
                issues.append("Adaptation event \(event.id.uuidString) references a missing training program.")
            }
            if let analysisID = event.analysisID,
               !weeklyAnalysisIDs.contains(analysisID) {
                issues.append("Adaptation event \(event.id.uuidString) references a missing weekly analysis.")
            }
            if let proposalID = event.proposalID,
               !proposalIDs.contains(proposalID) {
                issues.append("Adaptation event \(event.id.uuidString) references a missing proposal.")
            }
            if let overlayID = event.overlayID,
               !overlayIDs.contains(overlayID) {
                issues.append("Adaptation event \(event.id.uuidString) references a missing applied overlay.")
            }
        }

        for summary in envelope.payload.healthKitDailySummaries {
            register(summary.id, label: "HealthKit daily summary", into: &healthSummaryIDs, issues: &issues)
        }

        for account in envelope.payload.localState.accountState.knownAccounts {
            register(account.id, label: "local account", into: &accountIDs, issues: &issues)
        }

        if let currentAccountID = envelope.payload.localState.accountState.currentAccountID,
           !accountIDs.contains(currentAccountID) {
            issues.append("The backup’s signed-in account reference is missing from the account list.")
        }

        for request in envelope.payload.localState.accountState.privacyRequests {
            if !accountIDs.contains(request.accountID) {
                issues.append("Privacy request \(request.id.uuidString) references a missing account.")
            }
        }

        for consent in envelope.payload.localState.accountState.consumerHealthConsents {
            if !accountIDs.contains(consent.accountID) {
                issues.append("Consumer health consent \(consent.id.uuidString) references a missing account.")
            }
        }

        return issues
    }

    private func register(
        _ id: UUID,
        label: String,
        into set: inout Set<UUID>,
        issues: inout [String]
    ) {
        let inserted = set.insert(id).inserted
        if !inserted {
            issues.append("The backup contains duplicate \(label) IDs.")
        }
    }

    private func makeSourceMetadata() -> PortableBackupSourceMetadata {
        PortableBackupSourceMetadata(
            appName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                "SuggestMeSome",
            bundleIdentifier: bundle.bundleIdentifier ?? "SuggestMeSome",
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        )
    }

    private func loadComplianceState() -> ComplianceOnboardingState {
        guard let data = userDefaults.data(forKey: ComplianceStateStore.persistenceKey),
              let state = try? JSONDecoder().decode(ComplianceOnboardingState.self, from: data) else {
            return ComplianceOnboardingState()
        }
        return state
    }

    private func loadAccountState() -> AccountBackendContractState {
        let preferredKey: String
        let fallbackKey: String
        switch ComplianceConfiguration.accountBackendLaunchMode {
        case .localContractValidation:
            preferredKey = LocalContractAuthService.persistenceKey
            fallbackKey = ProductionBackendAuthService.persistenceKey
        case .productionBackend:
            preferredKey = ProductionBackendAuthService.persistenceKey
            fallbackKey = LocalContractAuthService.persistenceKey
        }

        for key in [preferredKey, fallbackKey] {
            guard let data = userDefaults.data(forKey: key),
                  let state = try? JSONDecoder().decode(AccountBackendContractState.self, from: data) else {
                continue
            }
            return state
        }
        return .empty
    }

    private func persistLocalState(_ localState: PortableBackupLocalState) {
        localState.preferences.apply(to: userDefaults)

        if let complianceData = try? JSONEncoder().encode(localState.complianceState) {
            userDefaults.set(complianceData, forKey: ComplianceStateStore.persistenceKey)
        }
        if let accountData = try? JSONEncoder().encode(localState.accountState) {
            userDefaults.set(accountData, forKey: LocalContractAuthService.persistenceKey)
            userDefaults.set(accountData, forKey: ProductionBackendAuthService.persistenceKey)
        }
    }

    private func syncMetadata(
        stableID: String?,
        version: Int,
        lastModifiedAt: Date,
        deletedAt: Date? = nil
    ) -> PortableBackupSyncMetadata {
        PortableBackupSyncMetadata(
            stableID: stableID,
            version: version,
            lastModifiedAt: lastModifiedAt,
            deletedAt: deletedAt
        )
    }

    private func exportMuscleGroups(context: ModelContext) throws -> [PortableBackupMuscleGroup] {
        let groups = try context.fetch(FetchDescriptor<MuscleGroup>())
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return groups.map { group in
            PortableBackupMuscleGroup(
                name: group.name,
                exercises: group.exercises
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    .map { PortableBackupExerciseLibraryItem(name: $0.name, exerciseType: $0.exerciseType) }
            )
        }
    }

    private func exportWorkouts(context: ModelContext) throws -> [PortableBackupWorkout] {
        let workouts = try context.fetch(FetchDescriptor<Workout>())
            .sorted {
                if $0.date == $1.date {
                    return $0.startTime < $1.startTime
                }
                return $0.date < $1.date
            }

        return workouts.map { workout in
            PortableBackupWorkout(
                id: workout.id,
                sync: syncMetadata(
                    stableID: workout.syncStableID,
                    version: workout.syncVersion,
                    lastModifiedAt: workout.syncLastModifiedAt,
                    deletedAt: workout.syncDeletedAt
                ),
                date: workout.date,
                startTime: workout.startTime,
                durationSeconds: workout.durationSeconds,
                caloriesBurned: workout.caloriesBurned,
                comments: workout.comments,
                programRunID: workout.programRun?.id,
                programWeekNumber: workout.programWeekNumber,
                programSessionNumber: workout.programSessionNumber,
                sourceType: workout.sourceType,
                sourceExternalIdentifier: workout.sourceExternalIdentifier,
                sourceDisplayName: workout.sourceDisplayName,
                sourceWorkoutTypeIdentifier: workout.sourceWorkoutTypeIdentifier,
                sourceWorkoutTypeDisplayName: workout.sourceWorkoutTypeDisplayName,
                sourceImportedAt: workout.sourceImportedAt,
                healthKitExportedAt: workout.healthKitExportedAt,
                healthKitWritebackIdentifier: workout.healthKitWritebackIdentifier,
                exerciseEntries: workout.exerciseEntries
                    .sorted { $0.orderIndex < $1.orderIndex }
                    .map { entry in
                        PortableBackupExerciseEntry(
                            id: entry.id,
                            sync: syncMetadata(
                                stableID: entry.syncStableID,
                                version: entry.syncVersion,
                                lastModifiedAt: entry.syncLastModifiedAt
                            ),
                            exerciseName: entry.exerciseName,
                            unit: entry.unit,
                            orderIndex: entry.orderIndex,
                            isCardio: entry.isCardio,
                            cardioDurationSeconds: entry.cardioDurationSeconds,
                            sourceProgramSessionExerciseID: entry.sourceProgramSessionExerciseID,
                            prescribedTargetSets: entry.prescribedTargetSets,
                            prescribedTargetReps: entry.prescribedTargetReps,
                            prescribedTargetPercentage1RM: entry.prescribedTargetPercentage1RM,
                            prescribedTargetRPE: entry.prescribedTargetRPE,
                            prescribedTargetRIR: entry.prescribedTargetRIR,
                            prescribedWeight: entry.prescribedWeight,
                            prescribedWeightUnit: entry.prescribedWeightUnit,
                            prescribedWorkingSetStyle: entry.prescribedWorkingSetStyle,
                            prescribedTargetEffortType: entry.prescribedTargetEffortType,
                            effortFeedback: entry.effortFeedback,
                            topSetRPE: entry.topSetRPE,
                            sets: entry.sets
                                .sorted { $0.setNumber < $1.setNumber }
                                .map { set in
                                    PortableBackupSetEntry(
                                        id: set.id,
                                        sync: syncMetadata(
                                            stableID: set.syncStableID,
                                            version: set.syncVersion,
                                            lastModifiedAt: set.syncLastModifiedAt
                                        ),
                                        setNumber: set.setNumber,
                                        reps: set.reps,
                                        weight: set.weight,
                                        isPR: set.isPR
                                    )
                                }
                        )
                    }
            )
        }
    }

    private func exportPersonalRecords(context: ModelContext) throws -> [PortableBackupPersonalRecord] {
        let records = try context.fetch(FetchDescriptor<PersonalRecord>())
            .sorted {
                if $0.exerciseName == $1.exerciseName {
                    return $0.repCount < $1.repCount
                }
                return $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending
            }

        return records.map { record in
            PortableBackupPersonalRecord(
                id: record.id,
                sync: syncMetadata(
                    stableID: record.syncStableID,
                    version: record.syncVersion,
                    lastModifiedAt: record.syncLastModifiedAt
                ),
                exerciseName: record.exerciseName,
                repCount: record.repCount,
                weight: record.weight,
                unit: record.unit,
                dateAchieved: record.dateAchieved
            )
        }
    }

    private func exportTrainingPrograms(context: ModelContext) throws -> [PortableBackupTrainingProgram] {
        let programs = try context.fetch(FetchDescriptor<TrainingProgram>())
            .sorted { $0.createdDate < $1.createdDate }

        return programs.map { program in
            PortableBackupTrainingProgram(
                id: program.id,
                sync: syncMetadata(
                    stableID: program.syncStableID,
                    version: program.syncVersion,
                    lastModifiedAt: program.syncLastModifiedAt
                ),
                name: program.name,
                lengthInWeeks: program.lengthInWeeks,
                sessionsPerWeek: program.sessionsPerWeek,
                createdDate: program.createdDate,
                source: program.source,
                descriptionText: program.descriptionText,
                progressionModel: program.progressionModel,
                usedLiftMapping: program.usedLiftMapping,
                usedVolumeBalancing: program.usedVolumeBalancing,
                usedFatigueBalancing: program.usedFatigueBalancing,
                usedTopSetBackoff: program.usedTopSetBackoff,
                weeks: program.weeks
                    .sorted { $0.weekNumber < $1.weekNumber }
                    .map { week in
                        PortableBackupProgramWeek(
                            id: week.id,
                            weekNumber: week.weekNumber,
                            isDeloadWeek: week.isDeloadWeek,
                            progressionPhase: week.progressionPhase,
                            plannedFatigueScore: week.plannedFatigueScore,
                            sessions: week.sessions
                                .sorted { $0.sessionNumber < $1.sessionNumber }
                                .map { session in
                                    PortableBackupProgramSession(
                                        id: session.id,
                                        sessionNumber: session.sessionNumber,
                                        sessionName: session.sessionName,
                                        plannedFatigueScore: session.plannedFatigueScore,
                                        explainabilityReason: session.explainabilityReason,
                                        exercises: session.exercises
                                            .sorted { $0.orderIndex < $1.orderIndex }
                                            .map { exercise in
                                                PortableBackupProgramSessionExercise(
                                                    id: exercise.id,
                                                    sync: syncMetadata(
                                                        stableID: exercise.syncStableID,
                                                        version: exercise.syncVersion,
                                                        lastModifiedAt: exercise.syncLastModifiedAt
                                                    ),
                                                    exerciseName: exercise.exerciseName,
                                                    orderIndex: exercise.orderIndex,
                                                    targetSets: exercise.targetSets,
                                                    targetReps: exercise.targetReps,
                                                    targetPercentage1RM: exercise.targetPercentage1RM,
                                                    targetRPE: exercise.targetRPE,
                                                    targetRIR: exercise.targetRIR,
                                                    isWarmup: exercise.isWarmup,
                                                    prescribedWeight: exercise.prescribedWeight,
                                                    prescribedWeightUnit: exercise.prescribedWeightUnit,
                                                    workingSetStyle: exercise.workingSetStyle,
                                                    backoffPercentageDrop: exercise.backoffPercentageDrop,
                                                    targetEffortType: exercise.targetEffortType,
                                                    baseLiftUsed: exercise.baseLiftUsed,
                                                    effectiveOneRepMax: exercise.effectiveOneRepMax,
                                                    effectiveOneRepMaxUnit: exercise.effectiveOneRepMaxUnit,
                                                    usedMappedSourceLift: exercise.usedMappedSourceLift,
                                                    progressionPhase: exercise.progressionPhase,
                                                    estimatedFatigueScore: exercise.estimatedFatigueScore,
                                                    topBackoffGroupID: exercise.topBackoffGroupID,
                                                    explainabilityPurpose: exercise.explainabilityPurpose,
                                                    explainabilitySelectionReason: exercise.explainabilitySelectionReason
                                                )
                                            }
                                    )
                                }
                        )
                    }
            )
        }
    }

    private func exportProgramRuns(context: ModelContext) throws -> [PortableBackupProgramRun] {
        let runs = try context.fetch(FetchDescriptor<ProgramRun>())
            .sorted { $0.startDate < $1.startDate }

        return runs.map { run in
            PortableBackupProgramRun(
                id: run.id,
                sync: syncMetadata(
                    stableID: run.syncStableID,
                    version: run.syncVersion,
                    lastModifiedAt: run.syncLastModifiedAt
                ),
                startDate: run.startDate,
                endDate: run.endDate,
                isCompleted: run.isCompleted,
                previousProgramRunStableID: run.previousProgramRunStableID,
                recommendationDecisionHistoryJSON: run.recommendationDecisionHistoryJSON,
                continuitySnapshotJSON: run.continuitySnapshotJSON,
                trainingProgramID: run.program?.id
            )
        }
    }

    private func exportDailyCoachCheckIns(context: ModelContext) throws -> [PortableBackupDailyCoachCheckIn] {
        let rows = try context.fetch(FetchDescriptor<DailyCoachCheckIn>())
            .sorted { $0.date < $1.date }

        return rows.map { row in
            PortableBackupDailyCoachCheckIn(
                id: row.id,
                sync: syncMetadata(
                    stableID: row.syncStableID,
                    version: row.syncVersion,
                    lastModifiedAt: row.syncLastModifiedAt
                ),
                date: row.date,
                dayStart: row.dayStart,
                sleepQuality: row.sleepQuality,
                soreness: row.soreness,
                energy: row.energy,
                stress: row.stress,
                availableTimeMinutes: row.availableTimeMinutes,
                hasPainOrDiscomfort: row.hasPainOrDiscomfort,
                painNotes: row.painNotes,
                programRunID: row.programRun?.id,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            )
        }
    }

    private func exportDailyCoachWeeklyReviews(context: ModelContext) throws -> [PortableBackupDailyCoachWeeklyReview] {
        let rows = try context.fetch(FetchDescriptor<DailyCoachWeeklyReview>())
            .sorted { $0.weekStart < $1.weekStart }

        return rows.map { row in
            PortableBackupDailyCoachWeeklyReview(
                id: row.id,
                sync: syncMetadata(
                    stableID: row.syncStableID,
                    version: row.syncVersion,
                    lastModifiedAt: row.syncLastModifiedAt
                ),
                weekStart: row.weekStart,
                weekEnd: row.weekEnd,
                isProgramWeek: row.isProgramWeek,
                programRunID: row.programRun?.id,
                headline: row.headline,
                winText: row.winText,
                watchoutText: row.watchoutText,
                nextActionText: row.nextActionText,
                sourceWeeklyAnalysisIDText: row.sourceWeeklyAnalysisIDText,
                hasBeenSeen: row.hasBeenSeen,
                createdAt: row.createdAt
            )
        }
    }

    private func exportWeeklyTrainingAnalyses(context: ModelContext) throws -> [PortableBackupWeeklyTrainingAnalysis] {
        let analyses = try context.fetch(FetchDescriptor<WeeklyTrainingAnalysis>())
            .sorted { $0.weekStartDate < $1.weekStartDate }

        return analyses.map { analysis in
            PortableBackupWeeklyTrainingAnalysis(
                id: analysis.id,
                createdAt: analysis.createdAt,
                weekStartDate: analysis.weekStartDate,
                weekEndDate: analysis.weekEndDate,
                programRunID: analysis.programRun?.id,
                trainingProgramID: analysis.trainingProgram?.id,
                programWeekNumber: analysis.programWeekNumber,
                focusSnapshot: analysis.focusSnapshot,
                programWorkoutCount: analysis.programWorkoutCount,
                standaloneWorkoutCount: analysis.standaloneWorkoutCount,
                totalOutcomeCount: analysis.totalOutcomeCount,
                totalSignalWeight: analysis.totalSignalWeight,
                programSignalWeight: analysis.programSignalWeight,
                standaloneSignalWeight: analysis.standaloneSignalWeight,
                weightedPerformanceScore: analysis.weightedPerformanceScore,
                adherenceScore: analysis.adherenceScore,
                plannedFatigueScore: analysis.plannedFatigueScore,
                observedFatigueScore: analysis.observedFatigueScore,
                fatigueStatus: analysis.fatigueStatus,
                totalCompletedHardSets: analysis.totalCompletedHardSets,
                totalCompletedTonnage: analysis.totalCompletedTonnage,
                isFinalized: analysis.isFinalized,
                finalizedAt: analysis.finalizedAt,
                outcomes: analysis.outcomes
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { outcome in
                        PortableBackupExercisePerformanceOutcome(
                            id: outcome.id,
                            createdAt: outcome.createdAt,
                            programRunID: outcome.programRun?.id,
                            workoutID: outcome.workout?.id,
                            exerciseEntryID: outcome.exerciseEntry?.id,
                            workoutDate: outcome.workoutDate,
                            programWeekNumber: outcome.programWeekNumber,
                            programSessionNumber: outcome.programSessionNumber,
                            sourceProgramSessionExerciseID: outcome.sourceProgramSessionExerciseID,
                            exerciseName: outcome.exerciseName,
                            canonicalLiftKey: outcome.canonicalLiftKey,
                            signalSource: outcome.signalSource,
                            signalConfidence: outcome.signalConfidence,
                            signalWeight: outcome.signalWeight,
                            prescribedSets: outcome.prescribedSets,
                            prescribedReps: outcome.prescribedReps,
                            prescribedWeight: outcome.prescribedWeight,
                            prescribedWeightUnit: outcome.prescribedWeightUnit,
                            prescribedTargetPercentage1RM: outcome.prescribedTargetPercentage1RM,
                            prescribedTargetRPE: outcome.prescribedTargetRPE,
                            prescribedTargetRIR: outcome.prescribedTargetRIR,
                            prescribedWorkingSetStyle: outcome.prescribedWorkingSetStyle,
                            prescribedTargetEffortType: outcome.prescribedTargetEffortType,
                            actualSetCount: outcome.actualSetCount,
                            actualAverageReps: outcome.actualAverageReps,
                            actualAverageWeight: outcome.actualAverageWeight,
                            actualTopSetReps: outcome.actualTopSetReps,
                            actualTopSetWeight: outcome.actualTopSetWeight,
                            actualTopSetEstimated1RM: outcome.actualTopSetEstimated1RM,
                            completionRatio: outcome.completionRatio,
                            loadDeltaPercent: outcome.loadDeltaPercent,
                            repsDelta: outcome.repsDelta,
                            performanceScoreValue: outcome.performanceScoreValue,
                            performanceScore: outcome.performanceScore,
                            inferredFatigueStatus: outcome.inferredFatigueStatus,
                            isTopSetSignal: outcome.isTopSetSignal,
                            notes: outcome.notes
                        )
                    },
                volumeMetrics: analysis.volumeMetrics
                    .sorted { $0.muscle.rawValue < $1.muscle.rawValue }
                    .map { metric in
                        PortableBackupWeeklyVolumeMetric(
                            id: metric.id,
                            muscle: metric.muscle,
                            plannedHardSets: metric.plannedHardSets,
                            completedHardSets: metric.completedHardSets,
                            weightedCompletedHardSets: metric.weightedCompletedHardSets,
                            deltaHardSets: metric.deltaHardSets
                        )
                    }
            )
        }
    }

    private func exportLiftPerformanceTrends(context: ModelContext) throws -> [PortableBackupLiftPerformanceTrend] {
        let trends = try context.fetch(FetchDescriptor<LiftPerformanceTrend>())
            .sorted { $0.updatedAt < $1.updatedAt }

        return trends.map { trend in
            PortableBackupLiftPerformanceTrend(
                id: trend.id,
                updatedAt: trend.updatedAt,
                programRunID: trend.programRun?.id,
                trainingProgramID: trend.trainingProgram?.id,
                canonicalLiftKey: trend.canonicalLiftKey,
                liftDisplayName: trend.liftDisplayName,
                totalDataPoints: trend.totalDataPoints,
                programLinkedDataPoints: trend.programLinkedDataPoints,
                standaloneDataPoints: trend.standaloneDataPoints,
                weightedSignalCount: trend.weightedSignalCount,
                confidenceScore: trend.confidenceScore,
                firstObservationDate: trend.firstObservationDate,
                lastObservationDate: trend.lastObservationDate,
                currentEstimated1RM: trend.currentEstimated1RM,
                previousEstimated1RM: trend.previousEstimated1RM,
                rollingBestEstimated1RM: trend.rollingBestEstimated1RM,
                fourWeekChangePercent: trend.fourWeekChangePercent,
                trendStatus: trend.trendStatus,
                fatigueStatus: trend.fatigueStatus,
                latestTopSetWeight: trend.latestTopSetWeight,
                latestTopSetReps: trend.latestTopSetReps,
                latestPerformanceScoreValue: trend.latestPerformanceScoreValue,
                lastPerformanceScore: trend.lastPerformanceScore,
                snapshots: trend.snapshots
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { snapshot in
                        PortableBackupLiftTrendSnapshot(
                            id: snapshot.id,
                            createdAt: snapshot.createdAt,
                            analysisID: snapshot.analysis?.id,
                            programRunID: snapshot.programRun?.id,
                            trainingProgramID: snapshot.trainingProgram?.id,
                            canonicalLiftKey: snapshot.canonicalLiftKey,
                            liftDisplayName: snapshot.liftDisplayName,
                            weekStartDate: snapshot.weekStartDate,
                            weekEndDate: snapshot.weekEndDate,
                            programWeekNumber: snapshot.programWeekNumber,
                            totalDataPoints: snapshot.totalDataPoints,
                            programLinkedDataPoints: snapshot.programLinkedDataPoints,
                            standaloneDataPoints: snapshot.standaloneDataPoints,
                            weightedSignalCount: snapshot.weightedSignalCount,
                            weightedProgramSignal: snapshot.weightedProgramSignal,
                            weightedStandaloneSignal: snapshot.weightedStandaloneSignal,
                            confidenceScore: snapshot.confidenceScore,
                            currentEstimated1RM: snapshot.currentEstimated1RM,
                            baselineEstimated1RM: snapshot.baselineEstimated1RM,
                            rollingBestEstimated1RM: snapshot.rollingBestEstimated1RM,
                            changePercent: snapshot.changePercent,
                            trendStatus: snapshot.trendStatus,
                            fatigueStatus: snapshot.fatigueStatus,
                            latestTopSetWeight: snapshot.latestTopSetWeight,
                            latestTopSetReps: snapshot.latestTopSetReps,
                            latestPerformanceScoreValue: snapshot.latestPerformanceScoreValue,
                            note: snapshot.note
                        )
                    }
            )
        }
    }

    private func exportAdaptationProposals(context: ModelContext) throws -> [PortableBackupAdaptationProposal] {
        let proposals = try context.fetch(FetchDescriptor<AdaptationProposal>())
            .sorted { $0.createdAt < $1.createdAt }

        return proposals.map { proposal in
            PortableBackupAdaptationProposal(
                id: proposal.id,
                sync: syncMetadata(
                    stableID: proposal.syncStableID,
                    version: proposal.syncVersion,
                    lastModifiedAt: proposal.syncLastModifiedAt
                ),
                createdAt: proposal.createdAt,
                decidedAt: proposal.decidedAt,
                programRunID: proposal.programRun?.id,
                trainingProgramID: proposal.trainingProgram?.id,
                sourceAnalysisID: proposal.sourceAnalysis?.id,
                proposalType: proposal.proposalType,
                proposalStatus: proposal.proposalStatus,
                requiresUserConfirmation: proposal.requiresUserConfirmation,
                autoApplyEligible: proposal.autoApplyEligible,
                confidenceScore: proposal.confidenceScore,
                priority: proposal.priority,
                targetWeekStart: proposal.targetWeekStart,
                targetWeekEnd: proposal.targetWeekEnd,
                targetSessionNumber: proposal.targetSessionNumber,
                targetProgramSessionExerciseID: proposal.targetProgramSessionExerciseID,
                targetLiftKey: proposal.targetLiftKey,
                proposedLoadPercentDelta: proposal.proposedLoadPercentDelta,
                proposedSetDelta: proposal.proposedSetDelta,
                proposedRepDelta: proposal.proposedRepDelta,
                proposedDeloadFactor: proposal.proposedDeloadFactor,
                swapFromExerciseName: proposal.swapFromExerciseName,
                swapToExerciseName: proposal.swapToExerciseName,
                adjustmentReason: proposal.adjustmentReason,
                summaryText: proposal.summaryText,
                detailText: proposal.detailText,
                expiresAt: proposal.expiresAt
            )
        }
    }

    private func exportAppliedProgramOverlays(context: ModelContext) throws -> [PortableBackupAppliedProgramOverlay] {
        let overlays = try context.fetch(FetchDescriptor<AppliedProgramOverlay>())
            .sorted { $0.appliedAt < $1.appliedAt }

        return overlays.map { overlay in
            PortableBackupAppliedProgramOverlay(
                id: overlay.id,
                sync: syncMetadata(
                    stableID: overlay.syncStableID,
                    version: overlay.syncVersion,
                    lastModifiedAt: overlay.syncLastModifiedAt
                ),
                createdAt: overlay.createdAt,
                appliedAt: overlay.appliedAt,
                programRunID: overlay.programRun?.id,
                trainingProgramID: overlay.trainingProgram?.id,
                sourceProposalID: overlay.sourceProposal?.id,
                effectiveWeekStart: overlay.effectiveWeekStart,
                effectiveWeekEnd: overlay.effectiveWeekEnd,
                overlayStatus: overlay.overlayStatus,
                appliedByUserConfirmation: overlay.appliedByUserConfirmation,
                adjustmentReason: overlay.adjustmentReason,
                summaryText: overlay.summaryText,
                adjustments: overlay.adjustments
                    .sorted { $0.sequence < $1.sequence }
                    .map { adjustment in
                        PortableBackupAppliedOverlayAdjustment(
                            id: adjustment.id,
                            sync: syncMetadata(
                                stableID: adjustment.syncStableID,
                                version: adjustment.syncVersion,
                                lastModifiedAt: adjustment.syncLastModifiedAt
                            ),
                            sequence: adjustment.sequence,
                            targetProgramSessionExerciseID: adjustment.targetProgramSessionExerciseID,
                            targetWeekNumber: adjustment.targetWeekNumber,
                            targetSessionNumber: adjustment.targetSessionNumber,
                            adjustmentType: adjustment.adjustmentType,
                            loadPercentDelta: adjustment.loadPercentDelta,
                            absolutePrescribedWeight: adjustment.absolutePrescribedWeight,
                            setDelta: adjustment.setDelta,
                            absoluteTargetSets: adjustment.absoluteTargetSets,
                            repDelta: adjustment.repDelta,
                            absoluteTargetReps: adjustment.absoluteTargetReps,
                            replacementExerciseName: adjustment.replacementExerciseName,
                            adjustmentReason: adjustment.adjustmentReason,
                            isAutoApplied: adjustment.isAutoApplied
                        )
                    }
            )
        }
    }

    private func exportAdaptationEventHistory(context: ModelContext) throws -> [PortableBackupAdaptationEventHistory] {
        let rows = try context.fetch(FetchDescriptor<AdaptationEventHistory>())
            .sorted { $0.timestamp < $1.timestamp }

        return rows.map { row in
            PortableBackupAdaptationEventHistory(
                id: row.id,
                timestamp: row.timestamp,
                programRunID: row.programRun?.id,
                trainingProgramID: row.trainingProgram?.id,
                analysisID: row.analysis?.id,
                proposalID: row.proposal?.id,
                overlayID: row.overlay?.id,
                eventType: row.eventType,
                analysisWeekNumber: row.analysisWeekNumber,
                targetLiftKey: row.targetLiftKey,
                message: row.message,
                explanation: row.explanation,
                adjustmentReason: row.adjustmentReason,
                performanceScoreSnapshot: row.performanceScoreSnapshot,
                fatigueStatusSnapshot: row.fatigueStatusSnapshot,
                liftTrendStatusSnapshot: row.liftTrendStatusSnapshot,
                confidenceSnapshot: row.confidenceSnapshot,
                requiresUserAction: row.requiresUserAction,
                userActionTaken: row.userActionTaken
            )
        }
    }

    private func exportHealthKitDailySummaries(context: ModelContext) throws -> [PortableBackupHealthKitDailySummary] {
        let rows = try context.fetch(FetchDescriptor<HealthKitDailySummary>())
            .sorted { $0.dayStart < $1.dayStart }

        return rows.map { row in
            PortableBackupHealthKitDailySummary(
                id: row.id,
                sync: syncMetadata(
                    stableID: row.syncStableID,
                    version: row.syncVersion,
                    lastModifiedAt: row.syncLastModifiedAt
                ),
                dayStart: row.dayStart,
                sleepDurationSeconds: row.sleepDurationSeconds,
                timeInBedSeconds: row.timeInBedSeconds,
                restingHeartRateBPM: row.restingHeartRateBPM,
                heartRateVariabilityMS: row.heartRateVariabilityMS,
                activeEnergyKilocalories: row.activeEnergyKilocalories,
                stepCount: row.stepCount,
                bodyMassKilograms: row.bodyMassKilograms,
                sourceUpdatedAt: row.sourceUpdatedAt,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            )
        }
    }

    private func importMuscleGroups(
        _ groups: [PortableBackupMuscleGroup],
        context: ModelContext
    ) {
        for groupDTO in groups {
            let group = MuscleGroup(name: groupDTO.name)
            context.insert(group)

            for exerciseDTO in groupDTO.exercises {
                let exercise = Exercise(
                    name: exerciseDTO.name,
                    exerciseType: exerciseDTO.exerciseType,
                    muscleGroup: group
                )
                context.insert(exercise)
            }
        }
    }

    private struct ImportedProgramGraph {
        var programsByID: [UUID: TrainingProgram]
    }

    private func importTrainingPrograms(
        _ programs: [PortableBackupTrainingProgram],
        context: ModelContext
    ) -> ImportedProgramGraph {
        var programsByID: [UUID: TrainingProgram] = [:]

        for programDTO in programs {
            let program = TrainingProgram(
                id: programDTO.id,
                syncStableID: programDTO.sync.stableID,
                syncVersion: programDTO.sync.version,
                syncLastModifiedAt: programDTO.sync.lastModifiedAt,
                name: programDTO.name,
                lengthInWeeks: programDTO.lengthInWeeks,
                sessionsPerWeek: programDTO.sessionsPerWeek,
                createdDate: programDTO.createdDate,
                source: programDTO.source,
                descriptionText: programDTO.descriptionText,
                progressionModel: programDTO.progressionModel,
                usedLiftMapping: programDTO.usedLiftMapping,
                usedVolumeBalancing: programDTO.usedVolumeBalancing,
                usedFatigueBalancing: programDTO.usedFatigueBalancing,
                usedTopSetBackoff: programDTO.usedTopSetBackoff
            )
            context.insert(program)
            programsByID[programDTO.id] = program
            var importedWeeks: [ProgramWeekTemplate] = []

            for weekDTO in programDTO.weeks {
                let week = ProgramWeekTemplate(
                    id: weekDTO.id,
                    weekNumber: weekDTO.weekNumber,
                    isDeloadWeek: weekDTO.isDeloadWeek,
                    progressionPhase: weekDTO.progressionPhase,
                    plannedFatigueScore: weekDTO.plannedFatigueScore
                )
                week.program = program
                context.insert(week)
                var importedSessions: [ProgramSessionTemplate] = []

                for sessionDTO in weekDTO.sessions {
                    let session = ProgramSessionTemplate(
                        id: sessionDTO.id,
                        sessionNumber: sessionDTO.sessionNumber,
                        sessionName: sessionDTO.sessionName,
                        plannedFatigueScore: sessionDTO.plannedFatigueScore,
                        explainabilityReason: sessionDTO.explainabilityReason
                    )
                    session.week = week
                    context.insert(session)
                    var importedExercises: [ProgramSessionExercise] = []

                    for exerciseDTO in sessionDTO.exercises {
                        let exercise = ProgramSessionExercise(
                            id: exerciseDTO.id,
                            syncStableID: exerciseDTO.sync.stableID,
                            syncVersion: exerciseDTO.sync.version,
                            syncLastModifiedAt: exerciseDTO.sync.lastModifiedAt,
                            exerciseName: exerciseDTO.exerciseName,
                            orderIndex: exerciseDTO.orderIndex,
                            targetSets: exerciseDTO.targetSets,
                            targetReps: exerciseDTO.targetReps,
                            targetPercentage1RM: exerciseDTO.targetPercentage1RM,
                            targetRPE: exerciseDTO.targetRPE,
                            targetRIR: exerciseDTO.targetRIR,
                            isWarmup: exerciseDTO.isWarmup,
                            prescribedWeight: exerciseDTO.prescribedWeight,
                            prescribedWeightUnit: exerciseDTO.prescribedWeightUnit,
                            workingSetStyle: exerciseDTO.workingSetStyle,
                            backoffPercentageDrop: exerciseDTO.backoffPercentageDrop,
                            targetEffortType: exerciseDTO.targetEffortType,
                            baseLiftUsed: exerciseDTO.baseLiftUsed,
                            effectiveOneRepMax: exerciseDTO.effectiveOneRepMax,
                            effectiveOneRepMaxUnit: exerciseDTO.effectiveOneRepMaxUnit,
                            usedMappedSourceLift: exerciseDTO.usedMappedSourceLift,
                            progressionPhase: exerciseDTO.progressionPhase,
                            estimatedFatigueScore: exerciseDTO.estimatedFatigueScore,
                            topBackoffGroupID: exerciseDTO.topBackoffGroupID,
                            explainabilityPurpose: exerciseDTO.explainabilityPurpose,
                            explainabilitySelectionReason: exerciseDTO.explainabilitySelectionReason
                        )
                        exercise.session = session
                        context.insert(exercise)
                        importedExercises.append(exercise)
                    }

                    session.exercises = importedExercises
                    importedSessions.append(session)
                }

                week.sessions = importedSessions
                importedWeeks.append(week)
            }

            program.weeks = importedWeeks
        }

        return ImportedProgramGraph(programsByID: programsByID)
    }

    private func importProgramRuns(
        _ runs: [PortableBackupProgramRun],
        programsByID: [UUID: TrainingProgram],
        context: ModelContext
    ) -> [UUID: ProgramRun] {
        var runsByID: [UUID: ProgramRun] = [:]

        for runDTO in runs {
            let run = ProgramRun(
                id: runDTO.id,
                syncStableID: runDTO.sync.stableID,
                syncVersion: runDTO.sync.version,
                syncLastModifiedAt: runDTO.sync.lastModifiedAt,
                startDate: runDTO.startDate,
                endDate: runDTO.endDate,
                isCompleted: runDTO.isCompleted,
                previousProgramRunStableID: runDTO.previousProgramRunStableID,
                recommendationDecisionHistoryJSON: runDTO.recommendationDecisionHistoryJSON,
                continuitySnapshotJSON: runDTO.continuitySnapshotJSON
            )
            run.program = runDTO.trainingProgramID.flatMap { programsByID[$0] }
            context.insert(run)
            runsByID[runDTO.id] = run
        }

        return runsByID
    }

    private struct ImportedWorkouts {
        var workoutsByID: [UUID: Workout]
        var exerciseEntriesByID: [UUID: ExerciseEntry]
    }

    private func importWorkouts(
        _ workouts: [PortableBackupWorkout],
        programRunsByID: [UUID: ProgramRun],
        context: ModelContext
    ) -> ImportedWorkouts {
        var workoutsByID: [UUID: Workout] = [:]
        var exerciseEntriesByID: [UUID: ExerciseEntry] = [:]

        for workoutDTO in workouts {
            let workout = Workout(
                id: workoutDTO.id,
                syncStableID: workoutDTO.sync.stableID,
                syncVersion: workoutDTO.sync.version,
                syncLastModifiedAt: workoutDTO.sync.lastModifiedAt,
                syncDeletedAt: workoutDTO.sync.deletedAt,
                date: workoutDTO.date,
                startTime: workoutDTO.startTime,
                durationSeconds: workoutDTO.durationSeconds,
                caloriesBurned: workoutDTO.caloriesBurned,
                comments: workoutDTO.comments,
                programRun: workoutDTO.programRunID.flatMap { programRunsByID[$0] },
                programWeekNumber: workoutDTO.programWeekNumber,
                programSessionNumber: workoutDTO.programSessionNumber,
                sourceType: workoutDTO.sourceType,
                sourceExternalIdentifier: workoutDTO.sourceExternalIdentifier,
                sourceDisplayName: workoutDTO.sourceDisplayName,
                sourceWorkoutTypeIdentifier: workoutDTO.sourceWorkoutTypeIdentifier,
                sourceWorkoutTypeDisplayName: workoutDTO.sourceWorkoutTypeDisplayName,
                sourceImportedAt: workoutDTO.sourceImportedAt,
                healthKitExportedAt: workoutDTO.healthKitExportedAt,
                healthKitWritebackIdentifier: workoutDTO.healthKitWritebackIdentifier
            )
            context.insert(workout)
            workoutsByID[workoutDTO.id] = workout
            var importedEntries: [ExerciseEntry] = []

            for entryDTO in workoutDTO.exerciseEntries {
                let entry = ExerciseEntry(
                    id: entryDTO.id,
                    syncStableID: entryDTO.sync.stableID,
                    syncVersion: entryDTO.sync.version,
                    syncLastModifiedAt: entryDTO.sync.lastModifiedAt,
                    exerciseName: entryDTO.exerciseName,
                    unit: entryDTO.unit,
                    orderIndex: entryDTO.orderIndex,
                    isCardio: entryDTO.isCardio,
                    cardioDurationSeconds: entryDTO.cardioDurationSeconds,
                    sourceProgramSessionExerciseID: entryDTO.sourceProgramSessionExerciseID,
                    prescribedTargetSets: entryDTO.prescribedTargetSets,
                    prescribedTargetReps: entryDTO.prescribedTargetReps,
                    prescribedTargetPercentage1RM: entryDTO.prescribedTargetPercentage1RM,
                    prescribedTargetRPE: entryDTO.prescribedTargetRPE,
                    prescribedTargetRIR: entryDTO.prescribedTargetRIR,
                    prescribedWeight: entryDTO.prescribedWeight,
                    prescribedWeightUnit: entryDTO.prescribedWeightUnit,
                    prescribedWorkingSetStyle: entryDTO.prescribedWorkingSetStyle,
                    prescribedTargetEffortType: entryDTO.prescribedTargetEffortType
                )
                entry.effortFeedback = entryDTO.effortFeedback
                entry.topSetRPE = entryDTO.topSetRPE
                entry.workout = workout
                context.insert(entry)
                exerciseEntriesByID[entryDTO.id] = entry
                var importedSets: [SetEntry] = []

                for setDTO in entryDTO.sets {
                    let set = SetEntry(
                        id: setDTO.id,
                        syncStableID: setDTO.sync.stableID,
                        syncVersion: setDTO.sync.version,
                        syncLastModifiedAt: setDTO.sync.lastModifiedAt,
                        setNumber: setDTO.setNumber,
                        reps: setDTO.reps,
                        weight: setDTO.weight,
                        isPR: setDTO.isPR
                    )
                    set.exerciseEntry = entry
                    context.insert(set)
                    importedSets.append(set)
                }

                entry.sets = importedSets
                importedEntries.append(entry)
            }

            workout.exerciseEntries = importedEntries
        }

        return ImportedWorkouts(
            workoutsByID: workoutsByID,
            exerciseEntriesByID: exerciseEntriesByID
        )
    }

    private func importPersonalRecords(
        _ records: [PortableBackupPersonalRecord],
        context: ModelContext
    ) {
        for recordDTO in records {
            let record = PersonalRecord(
                id: recordDTO.id,
                syncStableID: recordDTO.sync.stableID,
                syncVersion: recordDTO.sync.version,
                syncLastModifiedAt: recordDTO.sync.lastModifiedAt,
                exerciseName: recordDTO.exerciseName,
                repCount: recordDTO.repCount,
                weight: recordDTO.weight,
                unit: recordDTO.unit,
                dateAchieved: recordDTO.dateAchieved
            )
            context.insert(record)
        }
    }

    private func importDailyCoachCheckIns(
        _ rows: [PortableBackupDailyCoachCheckIn],
        programRunsByID: [UUID: ProgramRun],
        context: ModelContext
    ) {
        for rowDTO in rows {
            let row = DailyCoachCheckIn(
                id: rowDTO.id,
                syncStableID: rowDTO.sync.stableID,
                syncVersion: rowDTO.sync.version,
                syncLastModifiedAt: rowDTO.sync.lastModifiedAt,
                date: rowDTO.date,
                dayStart: rowDTO.dayStart,
                sleepQuality: rowDTO.sleepQuality,
                soreness: rowDTO.soreness,
                energy: rowDTO.energy,
                stress: rowDTO.stress,
                availableTimeMinutes: rowDTO.availableTimeMinutes,
                hasPainOrDiscomfort: rowDTO.hasPainOrDiscomfort,
                painNotes: rowDTO.painNotes,
                programRun: rowDTO.programRunID.flatMap { programRunsByID[$0] },
                createdAt: rowDTO.createdAt,
                updatedAt: rowDTO.updatedAt
            )
            context.insert(row)
        }
    }

    private func importDailyCoachWeeklyReviews(
        _ rows: [PortableBackupDailyCoachWeeklyReview],
        programRunsByID: [UUID: ProgramRun],
        context: ModelContext
    ) {
        for rowDTO in rows {
            let row = DailyCoachWeeklyReview(
                id: rowDTO.id,
                syncStableID: rowDTO.sync.stableID,
                syncVersion: rowDTO.sync.version,
                syncLastModifiedAt: rowDTO.sync.lastModifiedAt,
                weekStart: rowDTO.weekStart,
                weekEnd: rowDTO.weekEnd,
                isProgramWeek: rowDTO.isProgramWeek,
                programRun: rowDTO.programRunID.flatMap { programRunsByID[$0] },
                headline: rowDTO.headline,
                winText: rowDTO.winText,
                watchoutText: rowDTO.watchoutText,
                nextActionText: rowDTO.nextActionText,
                sourceWeeklyAnalysisIDText: rowDTO.sourceWeeklyAnalysisIDText,
                hasBeenSeen: rowDTO.hasBeenSeen,
                createdAt: rowDTO.createdAt
            )
            context.insert(row)
        }
    }

    private func importWeeklyTrainingAnalyses(
        _ analyses: [PortableBackupWeeklyTrainingAnalysis],
        programRunsByID: [UUID: ProgramRun],
        programsByID: [UUID: TrainingProgram],
        workoutsByID: [UUID: Workout],
        exerciseEntriesByID: [UUID: ExerciseEntry],
        context: ModelContext
    ) -> [UUID: WeeklyTrainingAnalysis] {
        var analysesByID: [UUID: WeeklyTrainingAnalysis] = [:]

        for analysisDTO in analyses {
            let analysis = WeeklyTrainingAnalysis(
                id: analysisDTO.id,
                createdAt: analysisDTO.createdAt,
                weekStartDate: analysisDTO.weekStartDate,
                weekEndDate: analysisDTO.weekEndDate,
                programRun: analysisDTO.programRunID.flatMap { programRunsByID[$0] },
                trainingProgram: analysisDTO.trainingProgramID.flatMap { programsByID[$0] },
                programWeekNumber: analysisDTO.programWeekNumber,
                focusSnapshot: analysisDTO.focusSnapshot,
                programWorkoutCount: analysisDTO.programWorkoutCount,
                standaloneWorkoutCount: analysisDTO.standaloneWorkoutCount,
                totalOutcomeCount: analysisDTO.totalOutcomeCount,
                totalSignalWeight: analysisDTO.totalSignalWeight,
                programSignalWeight: analysisDTO.programSignalWeight,
                standaloneSignalWeight: analysisDTO.standaloneSignalWeight,
                weightedPerformanceScore: analysisDTO.weightedPerformanceScore,
                adherenceScore: analysisDTO.adherenceScore,
                plannedFatigueScore: analysisDTO.plannedFatigueScore,
                observedFatigueScore: analysisDTO.observedFatigueScore,
                fatigueStatus: analysisDTO.fatigueStatus,
                totalCompletedHardSets: analysisDTO.totalCompletedHardSets,
                totalCompletedTonnage: analysisDTO.totalCompletedTonnage,
                isFinalized: analysisDTO.isFinalized,
                finalizedAt: analysisDTO.finalizedAt
            )
            context.insert(analysis)
            analysesByID[analysisDTO.id] = analysis
            var importedOutcomes: [ExercisePerformanceOutcome] = []

            for outcomeDTO in analysisDTO.outcomes {
                let outcome = ExercisePerformanceOutcome(
                    id: outcomeDTO.id,
                    createdAt: outcomeDTO.createdAt,
                    analysis: analysis,
                    programRun: outcomeDTO.programRunID.flatMap { programRunsByID[$0] },
                    workout: outcomeDTO.workoutID.flatMap { workoutsByID[$0] },
                    exerciseEntry: outcomeDTO.exerciseEntryID.flatMap { exerciseEntriesByID[$0] },
                    workoutDate: outcomeDTO.workoutDate,
                    programWeekNumber: outcomeDTO.programWeekNumber,
                    programSessionNumber: outcomeDTO.programSessionNumber,
                    sourceProgramSessionExerciseID: outcomeDTO.sourceProgramSessionExerciseID,
                    exerciseName: outcomeDTO.exerciseName,
                    canonicalLiftKey: outcomeDTO.canonicalLiftKey,
                    signalSource: outcomeDTO.signalSource,
                    signalConfidence: outcomeDTO.signalConfidence,
                    signalWeight: outcomeDTO.signalWeight,
                    prescribedSets: outcomeDTO.prescribedSets,
                    prescribedReps: outcomeDTO.prescribedReps,
                    prescribedWeight: outcomeDTO.prescribedWeight,
                    prescribedWeightUnit: outcomeDTO.prescribedWeightUnit,
                    prescribedTargetPercentage1RM: outcomeDTO.prescribedTargetPercentage1RM,
                    prescribedTargetRPE: outcomeDTO.prescribedTargetRPE,
                    prescribedTargetRIR: outcomeDTO.prescribedTargetRIR,
                    prescribedWorkingSetStyle: outcomeDTO.prescribedWorkingSetStyle,
                    prescribedTargetEffortType: outcomeDTO.prescribedTargetEffortType,
                    actualSetCount: outcomeDTO.actualSetCount,
                    actualAverageReps: outcomeDTO.actualAverageReps,
                    actualAverageWeight: outcomeDTO.actualAverageWeight,
                    actualTopSetReps: outcomeDTO.actualTopSetReps,
                    actualTopSetWeight: outcomeDTO.actualTopSetWeight,
                    actualTopSetEstimated1RM: outcomeDTO.actualTopSetEstimated1RM,
                    completionRatio: outcomeDTO.completionRatio,
                    loadDeltaPercent: outcomeDTO.loadDeltaPercent,
                    repsDelta: outcomeDTO.repsDelta,
                    performanceScoreValue: outcomeDTO.performanceScoreValue,
                    performanceScore: outcomeDTO.performanceScore,
                    inferredFatigueStatus: outcomeDTO.inferredFatigueStatus,
                    isTopSetSignal: outcomeDTO.isTopSetSignal,
                    notes: outcomeDTO.notes
                )
                context.insert(outcome)
                importedOutcomes.append(outcome)
            }
            analysis.outcomes = importedOutcomes

            var importedMetrics: [WeeklyVolumeMetric] = []

            for metricDTO in analysisDTO.volumeMetrics {
                let metric = WeeklyVolumeMetric(
                    id: metricDTO.id,
                    analysis: analysis,
                    muscle: metricDTO.muscle,
                    plannedHardSets: metricDTO.plannedHardSets,
                    completedHardSets: metricDTO.completedHardSets,
                    weightedCompletedHardSets: metricDTO.weightedCompletedHardSets,
                    deltaHardSets: metricDTO.deltaHardSets
                )
                context.insert(metric)
                importedMetrics.append(metric)
            }

            analysis.volumeMetrics = importedMetrics
        }

        return analysesByID
    }

    private func importLiftPerformanceTrends(
        _ trends: [PortableBackupLiftPerformanceTrend],
        programRunsByID: [UUID: ProgramRun],
        programsByID: [UUID: TrainingProgram],
        analysesByID: [UUID: WeeklyTrainingAnalysis],
        context: ModelContext
    ) -> [UUID: LiftPerformanceTrend] {
        var trendsByID: [UUID: LiftPerformanceTrend] = [:]

        for trendDTO in trends {
            let trend = LiftPerformanceTrend(
                id: trendDTO.id,
                updatedAt: trendDTO.updatedAt,
                programRun: trendDTO.programRunID.flatMap { programRunsByID[$0] },
                trainingProgram: trendDTO.trainingProgramID.flatMap { programsByID[$0] },
                canonicalLiftKey: trendDTO.canonicalLiftKey,
                liftDisplayName: trendDTO.liftDisplayName,
                totalDataPoints: trendDTO.totalDataPoints,
                programLinkedDataPoints: trendDTO.programLinkedDataPoints,
                standaloneDataPoints: trendDTO.standaloneDataPoints,
                weightedSignalCount: trendDTO.weightedSignalCount,
                confidenceScore: trendDTO.confidenceScore,
                firstObservationDate: trendDTO.firstObservationDate,
                lastObservationDate: trendDTO.lastObservationDate,
                currentEstimated1RM: trendDTO.currentEstimated1RM,
                previousEstimated1RM: trendDTO.previousEstimated1RM,
                rollingBestEstimated1RM: trendDTO.rollingBestEstimated1RM,
                fourWeekChangePercent: trendDTO.fourWeekChangePercent,
                trendStatus: trendDTO.trendStatus,
                fatigueStatus: trendDTO.fatigueStatus,
                latestTopSetWeight: trendDTO.latestTopSetWeight,
                latestTopSetReps: trendDTO.latestTopSetReps,
                latestPerformanceScoreValue: trendDTO.latestPerformanceScoreValue,
                lastPerformanceScore: trendDTO.lastPerformanceScore
            )
            context.insert(trend)
            trendsByID[trendDTO.id] = trend
            var importedSnapshots: [LiftTrendSnapshot] = []

            for snapshotDTO in trendDTO.snapshots {
                let snapshot = LiftTrendSnapshot(
                    id: snapshotDTO.id,
                    createdAt: snapshotDTO.createdAt,
                    trend: trend,
                    analysis: snapshotDTO.analysisID.flatMap { analysesByID[$0] },
                    programRun: snapshotDTO.programRunID.flatMap { programRunsByID[$0] },
                    trainingProgram: snapshotDTO.trainingProgramID.flatMap { programsByID[$0] },
                    canonicalLiftKey: snapshotDTO.canonicalLiftKey,
                    liftDisplayName: snapshotDTO.liftDisplayName,
                    weekStartDate: snapshotDTO.weekStartDate,
                    weekEndDate: snapshotDTO.weekEndDate,
                    programWeekNumber: snapshotDTO.programWeekNumber,
                    totalDataPoints: snapshotDTO.totalDataPoints,
                    programLinkedDataPoints: snapshotDTO.programLinkedDataPoints,
                    standaloneDataPoints: snapshotDTO.standaloneDataPoints,
                    weightedSignalCount: snapshotDTO.weightedSignalCount,
                    weightedProgramSignal: snapshotDTO.weightedProgramSignal,
                    weightedStandaloneSignal: snapshotDTO.weightedStandaloneSignal,
                    confidenceScore: snapshotDTO.confidenceScore,
                    currentEstimated1RM: snapshotDTO.currentEstimated1RM,
                    baselineEstimated1RM: snapshotDTO.baselineEstimated1RM,
                    rollingBestEstimated1RM: snapshotDTO.rollingBestEstimated1RM,
                    changePercent: snapshotDTO.changePercent,
                    trendStatus: snapshotDTO.trendStatus,
                    fatigueStatus: snapshotDTO.fatigueStatus,
                    latestTopSetWeight: snapshotDTO.latestTopSetWeight,
                    latestTopSetReps: snapshotDTO.latestTopSetReps,
                    latestPerformanceScoreValue: snapshotDTO.latestPerformanceScoreValue,
                    note: snapshotDTO.note
                )
                context.insert(snapshot)
                importedSnapshots.append(snapshot)
            }

            trend.snapshots = importedSnapshots
        }

        return trendsByID
    }

    private func importAdaptationProposals(
        _ proposals: [PortableBackupAdaptationProposal],
        programRunsByID: [UUID: ProgramRun],
        programsByID: [UUID: TrainingProgram],
        analysesByID: [UUID: WeeklyTrainingAnalysis],
        context: ModelContext
    ) -> [UUID: AdaptationProposal] {
        var proposalsByID: [UUID: AdaptationProposal] = [:]

        for proposalDTO in proposals {
            let proposal = AdaptationProposal(
                id: proposalDTO.id,
                syncStableID: proposalDTO.sync.stableID,
                syncVersion: proposalDTO.sync.version,
                syncLastModifiedAt: proposalDTO.sync.lastModifiedAt,
                createdAt: proposalDTO.createdAt,
                decidedAt: proposalDTO.decidedAt,
                programRun: proposalDTO.programRunID.flatMap { programRunsByID[$0] },
                trainingProgram: proposalDTO.trainingProgramID.flatMap { programsByID[$0] },
                sourceAnalysis: proposalDTO.sourceAnalysisID.flatMap { analysesByID[$0] },
                proposalType: proposalDTO.proposalType,
                proposalStatus: proposalDTO.proposalStatus,
                requiresUserConfirmation: proposalDTO.requiresUserConfirmation,
                autoApplyEligible: proposalDTO.autoApplyEligible,
                confidenceScore: proposalDTO.confidenceScore,
                priority: proposalDTO.priority,
                targetWeekStart: proposalDTO.targetWeekStart,
                targetWeekEnd: proposalDTO.targetWeekEnd,
                targetSessionNumber: proposalDTO.targetSessionNumber,
                targetProgramSessionExerciseID: proposalDTO.targetProgramSessionExerciseID,
                targetLiftKey: proposalDTO.targetLiftKey,
                proposedLoadPercentDelta: proposalDTO.proposedLoadPercentDelta,
                proposedSetDelta: proposalDTO.proposedSetDelta,
                proposedRepDelta: proposalDTO.proposedRepDelta,
                proposedDeloadFactor: proposalDTO.proposedDeloadFactor,
                swapFromExerciseName: proposalDTO.swapFromExerciseName,
                swapToExerciseName: proposalDTO.swapToExerciseName,
                adjustmentReason: proposalDTO.adjustmentReason,
                summaryText: proposalDTO.summaryText,
                detailText: proposalDTO.detailText,
                expiresAt: proposalDTO.expiresAt
            )
            context.insert(proposal)
            proposalsByID[proposalDTO.id] = proposal
        }

        return proposalsByID
    }

    private func importAppliedProgramOverlays(
        _ overlays: [PortableBackupAppliedProgramOverlay],
        programRunsByID: [UUID: ProgramRun],
        programsByID: [UUID: TrainingProgram],
        proposalsByID: [UUID: AdaptationProposal],
        context: ModelContext
    ) -> [UUID: AppliedProgramOverlay] {
        var overlaysByID: [UUID: AppliedProgramOverlay] = [:]

        for overlayDTO in overlays {
            let overlay = AppliedProgramOverlay(
                id: overlayDTO.id,
                syncStableID: overlayDTO.sync.stableID,
                syncVersion: overlayDTO.sync.version,
                syncLastModifiedAt: overlayDTO.sync.lastModifiedAt,
                createdAt: overlayDTO.createdAt,
                appliedAt: overlayDTO.appliedAt,
                programRun: overlayDTO.programRunID.flatMap { programRunsByID[$0] },
                trainingProgram: overlayDTO.trainingProgramID.flatMap { programsByID[$0] },
                sourceProposal: overlayDTO.sourceProposalID.flatMap { proposalsByID[$0] },
                effectiveWeekStart: overlayDTO.effectiveWeekStart,
                effectiveWeekEnd: overlayDTO.effectiveWeekEnd,
                overlayStatus: overlayDTO.overlayStatus,
                appliedByUserConfirmation: overlayDTO.appliedByUserConfirmation,
                adjustmentReason: overlayDTO.adjustmentReason,
                summaryText: overlayDTO.summaryText
            )
            context.insert(overlay)
            overlaysByID[overlayDTO.id] = overlay
            var importedAdjustments: [AppliedOverlayAdjustment] = []

            for adjustmentDTO in overlayDTO.adjustments {
                let adjustment = AppliedOverlayAdjustment(
                    id: adjustmentDTO.id,
                    syncStableID: adjustmentDTO.sync.stableID,
                    syncVersion: adjustmentDTO.sync.version,
                    syncLastModifiedAt: adjustmentDTO.sync.lastModifiedAt,
                    overlay: overlay,
                    sequence: adjustmentDTO.sequence,
                    targetProgramSessionExerciseID: adjustmentDTO.targetProgramSessionExerciseID,
                    targetWeekNumber: adjustmentDTO.targetWeekNumber,
                    targetSessionNumber: adjustmentDTO.targetSessionNumber,
                    adjustmentType: adjustmentDTO.adjustmentType,
                    loadPercentDelta: adjustmentDTO.loadPercentDelta,
                    absolutePrescribedWeight: adjustmentDTO.absolutePrescribedWeight,
                    setDelta: adjustmentDTO.setDelta,
                    absoluteTargetSets: adjustmentDTO.absoluteTargetSets,
                    repDelta: adjustmentDTO.repDelta,
                    absoluteTargetReps: adjustmentDTO.absoluteTargetReps,
                    replacementExerciseName: adjustmentDTO.replacementExerciseName,
                    adjustmentReason: adjustmentDTO.adjustmentReason,
                    isAutoApplied: adjustmentDTO.isAutoApplied
                )
                context.insert(adjustment)
                importedAdjustments.append(adjustment)
            }

            overlay.adjustments = importedAdjustments
        }

        return overlaysByID
    }

    private func importAdaptationEventHistory(
        _ rows: [PortableBackupAdaptationEventHistory],
        programRunsByID: [UUID: ProgramRun],
        programsByID: [UUID: TrainingProgram],
        analysesByID: [UUID: WeeklyTrainingAnalysis],
        proposalsByID: [UUID: AdaptationProposal],
        overlaysByID: [UUID: AppliedProgramOverlay],
        context: ModelContext
    ) {
        for rowDTO in rows {
            let row = AdaptationEventHistory(
                id: rowDTO.id,
                timestamp: rowDTO.timestamp,
                programRun: rowDTO.programRunID.flatMap { programRunsByID[$0] },
                trainingProgram: rowDTO.trainingProgramID.flatMap { programsByID[$0] },
                analysis: rowDTO.analysisID.flatMap { analysesByID[$0] },
                proposal: rowDTO.proposalID.flatMap { proposalsByID[$0] },
                overlay: rowDTO.overlayID.flatMap { overlaysByID[$0] },
                eventType: rowDTO.eventType,
                analysisWeekNumber: rowDTO.analysisWeekNumber,
                targetLiftKey: rowDTO.targetLiftKey,
                message: rowDTO.message,
                explanation: rowDTO.explanation,
                adjustmentReason: rowDTO.adjustmentReason,
                performanceScoreSnapshot: rowDTO.performanceScoreSnapshot,
                fatigueStatusSnapshot: rowDTO.fatigueStatusSnapshot,
                liftTrendStatusSnapshot: rowDTO.liftTrendStatusSnapshot,
                confidenceSnapshot: rowDTO.confidenceSnapshot,
                requiresUserAction: rowDTO.requiresUserAction,
                userActionTaken: rowDTO.userActionTaken
            )
            context.insert(row)
        }
    }

    private func importHealthKitDailySummaries(
        _ rows: [PortableBackupHealthKitDailySummary],
        context: ModelContext
    ) {
        for rowDTO in rows {
            let row = HealthKitDailySummary(
                id: rowDTO.id,
                syncStableID: rowDTO.sync.stableID,
                syncVersion: rowDTO.sync.version,
                syncLastModifiedAt: rowDTO.sync.lastModifiedAt,
                dayStart: rowDTO.dayStart,
                sleepDurationSeconds: rowDTO.sleepDurationSeconds,
                timeInBedSeconds: rowDTO.timeInBedSeconds,
                restingHeartRateBPM: rowDTO.restingHeartRateBPM,
                heartRateVariabilityMS: rowDTO.heartRateVariabilityMS,
                activeEnergyKilocalories: rowDTO.activeEnergyKilocalories,
                stepCount: rowDTO.stepCount,
                bodyMassKilograms: rowDTO.bodyMassKilograms,
                sourceUpdatedAt: rowDTO.sourceUpdatedAt,
                createdAt: rowDTO.createdAt,
                updatedAt: rowDTO.updatedAt
            )
            context.insert(row)
        }
    }
}
