import Foundation

enum PortableBackupVersion {
    static let v1 = 1
    static let current = v1
}

struct PortableBackupSourceMetadata: Codable, Equatable {
    var appName: String
    var bundleIdentifier: String
    var appVersion: String
    var buildNumber: String
}

struct PortableBackupEnvelope: Codable, Equatable {
    var backupVersion: Int
    var generatedAt: Date
    var source: PortableBackupSourceMetadata
    var manifest: PortableBackupManifest
    var payload: PortableBackupPayload
}

struct PortableBackupPayload: Codable, Equatable {
    var muscleGroups: [PortableBackupMuscleGroup]
    var workouts: [PortableBackupWorkout]
    var personalRecords: [PortableBackupPersonalRecord]
    var trainingPrograms: [PortableBackupTrainingProgram]
    var programRuns: [PortableBackupProgramRun]
    var dailyCoachCheckIns: [PortableBackupDailyCoachCheckIn]
    var dailyCoachWeeklyReviews: [PortableBackupDailyCoachWeeklyReview]
    var weeklyTrainingAnalyses: [PortableBackupWeeklyTrainingAnalysis]
    var liftPerformanceTrends: [PortableBackupLiftPerformanceTrend]
    var adaptationProposals: [PortableBackupAdaptationProposal]
    var appliedProgramOverlays: [PortableBackupAppliedProgramOverlay]
    var adaptationEventHistory: [PortableBackupAdaptationEventHistory]
    var healthKitDailySummaries: [PortableBackupHealthKitDailySummary]
    var localState: PortableBackupLocalState

    func computedManifest() -> PortableBackupManifest {
        PortableBackupManifest(payload: self)
    }
}

struct PortableBackupManifest: Codable, Equatable {
    var muscleGroupCount: Int
    var exerciseLibraryCount: Int
    var workoutCount: Int
    var workoutExerciseEntryCount: Int
    var workoutSetCount: Int
    var personalRecordCount: Int
    var trainingProgramCount: Int
    var programWeekCount: Int
    var programSessionCount: Int
    var programSessionExerciseCount: Int
    var programRunCount: Int
    var dailyCoachCheckInCount: Int
    var dailyCoachWeeklyReviewCount: Int
    var weeklyTrainingAnalysisCount: Int
    var exercisePerformanceOutcomeCount: Int
    var weeklyVolumeMetricCount: Int
    var liftPerformanceTrendCount: Int
    var liftTrendSnapshotCount: Int
    var adaptationProposalCount: Int
    var appliedProgramOverlayCount: Int
    var appliedOverlayAdjustmentCount: Int
    var adaptationEventHistoryCount: Int
    var healthKitDailySummaryCount: Int
    var knownAccountCount: Int
    var privacyRequestCount: Int
    var consumerHealthConsentCount: Int
    var totalSwiftDataRecordCount: Int

    init(payload: PortableBackupPayload) {
        muscleGroupCount = payload.muscleGroups.count
        exerciseLibraryCount = payload.muscleGroups.flatMap(\.exercises).count
        workoutCount = payload.workouts.count
        workoutExerciseEntryCount = payload.workouts.flatMap(\.exerciseEntries).count
        workoutSetCount = payload.workouts.flatMap(\.exerciseEntries).flatMap(\.sets).count
        personalRecordCount = payload.personalRecords.count
        trainingProgramCount = payload.trainingPrograms.count
        programWeekCount = payload.trainingPrograms.flatMap(\.weeks).count
        programSessionCount = payload.trainingPrograms.flatMap(\.weeks).flatMap(\.sessions).count
        programSessionExerciseCount = payload.trainingPrograms
            .flatMap(\.weeks)
            .flatMap(\.sessions)
            .flatMap(\.exercises)
            .count
        programRunCount = payload.programRuns.count
        dailyCoachCheckInCount = payload.dailyCoachCheckIns.count
        dailyCoachWeeklyReviewCount = payload.dailyCoachWeeklyReviews.count
        weeklyTrainingAnalysisCount = payload.weeklyTrainingAnalyses.count
        exercisePerformanceOutcomeCount = payload.weeklyTrainingAnalyses.flatMap(\.outcomes).count
        weeklyVolumeMetricCount = payload.weeklyTrainingAnalyses.flatMap(\.volumeMetrics).count
        liftPerformanceTrendCount = payload.liftPerformanceTrends.count
        liftTrendSnapshotCount = payload.liftPerformanceTrends.flatMap(\.snapshots).count
        adaptationProposalCount = payload.adaptationProposals.count
        appliedProgramOverlayCount = payload.appliedProgramOverlays.count
        appliedOverlayAdjustmentCount = payload.appliedProgramOverlays.flatMap(\.adjustments).count
        adaptationEventHistoryCount = payload.adaptationEventHistory.count
        healthKitDailySummaryCount = payload.healthKitDailySummaries.count
        knownAccountCount = payload.localState.accountState.knownAccounts.count
        privacyRequestCount = payload.localState.accountState.privacyRequests.count
        consumerHealthConsentCount = payload.localState.accountState.consumerHealthConsents.count
        totalSwiftDataRecordCount =
            muscleGroupCount +
            exerciseLibraryCount +
            workoutCount +
            workoutExerciseEntryCount +
            workoutSetCount +
            personalRecordCount +
            trainingProgramCount +
            programWeekCount +
            programSessionCount +
            programSessionExerciseCount +
            programRunCount +
            dailyCoachCheckInCount +
            dailyCoachWeeklyReviewCount +
            weeklyTrainingAnalysisCount +
            exercisePerformanceOutcomeCount +
            weeklyVolumeMetricCount +
            liftPerformanceTrendCount +
            liftTrendSnapshotCount +
            adaptationProposalCount +
            appliedProgramOverlayCount +
            appliedOverlayAdjustmentCount +
            adaptationEventHistoryCount +
            healthKitDailySummaryCount
    }
}

struct PortableBackupLocalState: Codable, Equatable {
    var preferences: PortableBackupPreferences
    var complianceState: ComplianceOnboardingState
    var accountState: AccountBackendContractState
}

struct PortableBackupPreferences: Codable, Equatable {
    var defaultWeightUnit: WeightUnit
    var appColorScheme: String
    var defaultRestTimerSeconds: Int
    var coachPreferredDays: Int
    var healthKitEnabled: Bool
    var useHealthKitInDailyCoach: Bool
    var importHealthKitWorkouts: Bool
    var writeAppWorkoutsToHealthKit: Bool
    var recoveryLastSyncAt: Date?
    var workoutImportLastSyncAt: Date?
    var generatorAIFocus: ProgramFocus?
    var generatorAILevel: ProgramLevel?
    var generatorAIDurationWeeks: Int?
    var generatorAIFrequency: Int?
    var generatorFlowMode: SuggestMeSomeSessionMode?
    var generatorFlowGoal: SuggestMeSomeGenerationGoal?
    var generatorFlowEquipment: SuggestMeSomeEquipmentProfile?
    var generatorFlowDurationMinutes: Int?
    var generatorFlowIntensity: Int?

    private enum Keys {
        static let defaultWeightUnit = "globalWeightUnit"
        static let appColorScheme = "appColorScheme"
        static let defaultRestTimerSeconds = "defaultRestTimerSeconds"
        static let coachPreferredDays = "coachPreferredDays"
        static let importHealthKitWorkouts = "healthkit.importWorkouts"
        static let writeAppWorkoutsToHealthKit = "healthkit.writeWorkouts"
        static let generatorAIFocus = "generator.ai.focus"
        static let generatorAILevel = "generator.ai.level"
        static let generatorAIDuration = "generator.ai.duration"
        static let generatorAIFrequency = "generator.ai.frequency"
        static let generatorFlowMode = "generator.flow.mode"
        static let generatorFlowGoal = "generator.flow.goal"
        static let generatorFlowEquipment = "generator.flow.equipment"
        static let generatorFlowDuration = "generator.flow.duration"
        static let generatorFlowIntensity = "generator.flow.intensity"
    }

    init(defaults: UserDefaults = .standard) {
        defaultWeightUnit = WeightUnit(
            rawValue: defaults.string(forKey: Keys.defaultWeightUnit) ?? WeightUnit.lbs.rawValue
        ) ?? .lbs
        appColorScheme = defaults.string(forKey: Keys.appColorScheme) ?? "system"
        defaultRestTimerSeconds = defaults.object(forKey: Keys.defaultRestTimerSeconds) as? Int ?? 90
        coachPreferredDays = defaults.object(forKey: Keys.coachPreferredDays) as? Int ?? 42
        healthKitEnabled = defaults.bool(forKey: HealthKitSettingsStorage.healthKitEnabledKey)
        useHealthKitInDailyCoach = defaults.bool(forKey: HealthKitSettingsStorage.dailyCoachEnabledKey)
        importHealthKitWorkouts = defaults.bool(forKey: Keys.importHealthKitWorkouts)
        writeAppWorkoutsToHealthKit = defaults.bool(forKey: Keys.writeAppWorkoutsToHealthKit)
        recoveryLastSyncAt = HealthKitSettingsStorage.date(
            forKey: HealthKitSettingsStorage.recoveryLastSyncTimestampKey,
            defaults: defaults
        )
        workoutImportLastSyncAt = HealthKitSettingsStorage.date(
            forKey: HealthKitSettingsStorage.workoutImportLastSyncTimestampKey,
            defaults: defaults
        )
        generatorAIFocus = ProgramFocus(
            rawValue: defaults.string(forKey: Keys.generatorAIFocus) ?? ""
        )
        generatorAILevel = ProgramLevel(
            rawValue: defaults.string(forKey: Keys.generatorAILevel) ?? ""
        )
        if defaults.object(forKey: Keys.generatorAIDuration) != nil {
            generatorAIDurationWeeks = defaults.integer(forKey: Keys.generatorAIDuration)
        } else {
            generatorAIDurationWeeks = nil
        }
        if defaults.object(forKey: Keys.generatorAIFrequency) != nil {
            generatorAIFrequency = defaults.integer(forKey: Keys.generatorAIFrequency)
        } else {
            generatorAIFrequency = nil
        }
        generatorFlowMode = SuggestMeSomeSessionMode(
            rawValue: defaults.string(forKey: Keys.generatorFlowMode) ?? ""
        )
        generatorFlowGoal = SuggestMeSomeGenerationGoal(
            rawValue: defaults.string(forKey: Keys.generatorFlowGoal) ?? ""
        )
        generatorFlowEquipment = SuggestMeSomeEquipmentProfile(
            rawValue: defaults.string(forKey: Keys.generatorFlowEquipment) ?? ""
        )
        if defaults.object(forKey: Keys.generatorFlowDuration) != nil {
            generatorFlowDurationMinutes = defaults.integer(forKey: Keys.generatorFlowDuration)
        } else {
            generatorFlowDurationMinutes = nil
        }
        if defaults.object(forKey: Keys.generatorFlowIntensity) != nil {
            generatorFlowIntensity = defaults.integer(forKey: Keys.generatorFlowIntensity)
        } else {
            generatorFlowIntensity = nil
        }
    }

    func apply(to defaults: UserDefaults = .standard) {
        defaults.set(defaultWeightUnit.rawValue, forKey: Keys.defaultWeightUnit)
        defaults.set(appColorScheme, forKey: Keys.appColorScheme)
        defaults.set(defaultRestTimerSeconds, forKey: Keys.defaultRestTimerSeconds)
        defaults.set(coachPreferredDays, forKey: Keys.coachPreferredDays)
        defaults.set(healthKitEnabled, forKey: HealthKitSettingsStorage.healthKitEnabledKey)
        defaults.set(useHealthKitInDailyCoach, forKey: HealthKitSettingsStorage.dailyCoachEnabledKey)
        defaults.set(importHealthKitWorkouts, forKey: Keys.importHealthKitWorkouts)
        defaults.set(writeAppWorkoutsToHealthKit, forKey: Keys.writeAppWorkoutsToHealthKit)
        HealthKitSettingsStorage.setDate(
            recoveryLastSyncAt,
            forKey: HealthKitSettingsStorage.recoveryLastSyncTimestampKey,
            defaults: defaults
        )
        HealthKitSettingsStorage.setDate(
            workoutImportLastSyncAt,
            forKey: HealthKitSettingsStorage.workoutImportLastSyncTimestampKey,
            defaults: defaults
        )

        Self.setOptionalRawValue(generatorAIFocus?.rawValue, forKey: Keys.generatorAIFocus, defaults: defaults)
        Self.setOptionalRawValue(generatorAILevel?.rawValue, forKey: Keys.generatorAILevel, defaults: defaults)
        Self.setOptionalInt(generatorAIDurationWeeks, forKey: Keys.generatorAIDuration, defaults: defaults)
        Self.setOptionalInt(generatorAIFrequency, forKey: Keys.generatorAIFrequency, defaults: defaults)
        Self.setOptionalRawValue(generatorFlowMode?.rawValue, forKey: Keys.generatorFlowMode, defaults: defaults)
        Self.setOptionalRawValue(generatorFlowGoal?.rawValue, forKey: Keys.generatorFlowGoal, defaults: defaults)
        Self.setOptionalRawValue(generatorFlowEquipment?.rawValue, forKey: Keys.generatorFlowEquipment, defaults: defaults)
        Self.setOptionalInt(generatorFlowDurationMinutes, forKey: Keys.generatorFlowDuration, defaults: defaults)
        Self.setOptionalInt(generatorFlowIntensity, forKey: Keys.generatorFlowIntensity, defaults: defaults)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        let keys = [
            Keys.defaultWeightUnit,
            Keys.appColorScheme,
            Keys.defaultRestTimerSeconds,
            Keys.coachPreferredDays,
            HealthKitSettingsStorage.healthKitEnabledKey,
            HealthKitSettingsStorage.dailyCoachEnabledKey,
            Keys.importHealthKitWorkouts,
            Keys.writeAppWorkoutsToHealthKit,
            HealthKitSettingsStorage.recoveryLastSyncTimestampKey,
            HealthKitSettingsStorage.workoutImportLastSyncTimestampKey,
            Keys.generatorAIFocus,
            Keys.generatorAILevel,
            Keys.generatorAIDuration,
            Keys.generatorAIFrequency,
            Keys.generatorFlowMode,
            Keys.generatorFlowGoal,
            Keys.generatorFlowEquipment,
            Keys.generatorFlowDuration,
            Keys.generatorFlowIntensity,
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    private static func setOptionalRawValue(
        _ value: String?,
        forKey key: String,
        defaults: UserDefaults
    ) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func setOptionalInt(
        _ value: Int?,
        forKey key: String,
        defaults: UserDefaults
    ) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

struct PortableBackupSyncMetadata: Codable, Equatable {
    var stableID: String?
    var version: Int
    var lastModifiedAt: Date
    var deletedAt: Date?
}

struct PortableBackupMuscleGroup: Codable, Equatable {
    var name: String
    var exercises: [PortableBackupExerciseLibraryItem]
}

struct PortableBackupExerciseLibraryItem: Codable, Equatable {
    var name: String
    var exerciseType: ExerciseType
}

struct PortableBackupWorkout: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var date: Date
    var startTime: Date
    var durationSeconds: Int
    var caloriesBurned: Int?
    var comments: String?
    var programRunID: UUID?
    var programWeekNumber: Int?
    var programSessionNumber: Int?
    var sourceType: WorkoutSourceType
    var sourceExternalIdentifier: String?
    var sourceDisplayName: String?
    var sourceWorkoutTypeIdentifier: String?
    var sourceWorkoutTypeDisplayName: String?
    var sourceImportedAt: Date?
    var healthKitExportedAt: Date?
    var healthKitWritebackIdentifier: String?
    var exerciseEntries: [PortableBackupExerciseEntry]
}

struct PortableBackupExerciseEntry: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var exerciseName: String
    var unit: WeightUnit
    var orderIndex: Int
    var isCardio: Bool
    var cardioDurationSeconds: Int?
    var sourceProgramSessionExerciseID: UUID?
    var prescribedTargetSets: Int?
    var prescribedTargetReps: Int?
    var prescribedTargetPercentage1RM: Double?
    var prescribedTargetRPE: Double?
    var prescribedTargetRIR: Double?
    var prescribedWeight: Double?
    var prescribedWeightUnit: String?
    var prescribedWorkingSetStyle: ProgramWorkingSetStyle?
    var prescribedTargetEffortType: ProgramTargetEffortType?
    var effortFeedback: WorkoutEffortFeedback?
    var topSetRPE: Double?
    var sets: [PortableBackupSetEntry]
}

struct PortableBackupSetEntry: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var setNumber: Int
    var reps: Int
    var weight: Double
    var isPR: Bool
}

struct PortableBackupPersonalRecord: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var exerciseName: String
    var repCount: Int
    var weight: Double
    var unit: WeightUnit
    var dateAchieved: Date
}

struct PortableBackupTrainingProgram: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var name: String
    var lengthInWeeks: Int
    var sessionsPerWeek: Int
    var createdDate: Date
    var source: ProgramSource
    var descriptionText: String?
    var progressionModel: ProgramProgressionModel?
    var usedLiftMapping: Bool?
    var usedVolumeBalancing: Bool?
    var usedFatigueBalancing: Bool?
    var usedTopSetBackoff: Bool?
    var weeks: [PortableBackupProgramWeek]
}

struct PortableBackupProgramWeek: Codable, Equatable {
    var id: UUID
    var weekNumber: Int
    var isDeloadWeek: Bool
    var progressionPhase: ProgramProgressionPhase?
    var plannedFatigueScore: Double?
    var sessions: [PortableBackupProgramSession]
}

struct PortableBackupProgramSession: Codable, Equatable {
    var id: UUID
    var sessionNumber: Int
    var sessionName: String?
    var plannedFatigueScore: Double?
    var explainabilityReason: ProgramSessionReasonCode?
    var exercises: [PortableBackupProgramSessionExercise]
}

struct PortableBackupProgramSessionExercise: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var exerciseName: String
    var orderIndex: Int
    var targetSets: Int?
    var targetReps: Int?
    var targetPercentage1RM: Double?
    var targetRPE: Double?
    var targetRIR: Double?
    var isWarmup: Bool
    var prescribedWeight: Double?
    var prescribedWeightUnit: String?
    var workingSetStyle: ProgramWorkingSetStyle?
    var backoffPercentageDrop: Double?
    var targetEffortType: ProgramTargetEffortType?
    var baseLiftUsed: String?
    var effectiveOneRepMax: Double?
    var effectiveOneRepMaxUnit: String?
    var usedMappedSourceLift: Bool?
    var progressionPhase: ProgramProgressionPhase?
    var estimatedFatigueScore: Double?
    var topBackoffGroupID: UUID?
    var explainabilityPurpose: ProgramExercisePurposeCode?
    var explainabilitySelectionReason: ProgramAccessorySelectionReason?
}

struct PortableBackupProgramRun: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var startDate: Date
    var endDate: Date?
    var isCompleted: Bool
    var previousProgramRunStableID: String?
    var recommendationDecisionHistoryJSON: String?
    var continuitySnapshotJSON: String?
    var trainingProgramID: UUID?
}

struct PortableBackupDailyCoachCheckIn: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var date: Date
    var dayStart: Date
    var sleepQuality: Int
    var soreness: Int
    var energy: Int
    var stress: Int
    var availableTimeMinutes: Int
    var hasPainOrDiscomfort: Bool
    var painNotes: String?
    var programRunID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

struct PortableBackupDailyCoachWeeklyReview: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var weekStart: Date
    var weekEnd: Date
    var isProgramWeek: Bool
    var programRunID: UUID?
    var headline: String
    var winText: String
    var watchoutText: String
    var nextActionText: String
    var sourceWeeklyAnalysisIDText: String?
    var hasBeenSeen: Bool
    var createdAt: Date
}

struct PortableBackupWeeklyTrainingAnalysis: Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var weekStartDate: Date
    var weekEndDate: Date
    var programRunID: UUID?
    var trainingProgramID: UUID?
    var programWeekNumber: Int?
    var focusSnapshot: ProgramFocus?
    var programWorkoutCount: Int
    var standaloneWorkoutCount: Int
    var totalOutcomeCount: Int
    var totalSignalWeight: Double
    var programSignalWeight: Double
    var standaloneSignalWeight: Double
    var weightedPerformanceScore: Double
    var adherenceScore: Double
    var plannedFatigueScore: Double?
    var observedFatigueScore: Double
    var fatigueStatus: FatigueStatus
    var totalCompletedHardSets: Double
    var totalCompletedTonnage: Double?
    var isFinalized: Bool
    var finalizedAt: Date?
    var outcomes: [PortableBackupExercisePerformanceOutcome]
    var volumeMetrics: [PortableBackupWeeklyVolumeMetric]
}

struct PortableBackupExercisePerformanceOutcome: Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var programRunID: UUID?
    var workoutID: UUID?
    var exerciseEntryID: UUID?
    var workoutDate: Date
    var programWeekNumber: Int?
    var programSessionNumber: Int?
    var sourceProgramSessionExerciseID: UUID?
    var exerciseName: String
    var canonicalLiftKey: String?
    var signalSource: WorkoutSignalSource
    var signalConfidence: WorkoutSignalConfidence
    var signalWeight: Double
    var prescribedSets: Int?
    var prescribedReps: Int?
    var prescribedWeight: Double?
    var prescribedWeightUnit: String?
    var prescribedTargetPercentage1RM: Double?
    var prescribedTargetRPE: Double?
    var prescribedTargetRIR: Double?
    var prescribedWorkingSetStyle: ProgramWorkingSetStyle?
    var prescribedTargetEffortType: ProgramTargetEffortType?
    var actualSetCount: Int
    var actualAverageReps: Double?
    var actualAverageWeight: Double?
    var actualTopSetReps: Int?
    var actualTopSetWeight: Double?
    var actualTopSetEstimated1RM: Double?
    var completionRatio: Double?
    var loadDeltaPercent: Double?
    var repsDelta: Double?
    var performanceScoreValue: Double
    var performanceScore: PerformanceScore
    var inferredFatigueStatus: FatigueStatus
    var isTopSetSignal: Bool
    var notes: String?
}

struct PortableBackupWeeklyVolumeMetric: Codable, Equatable {
    var id: UUID
    var muscle: ProgramVolumeMuscle
    var plannedHardSets: Double?
    var completedHardSets: Double
    var weightedCompletedHardSets: Double
    var deltaHardSets: Double
}

struct PortableBackupLiftPerformanceTrend: Codable, Equatable {
    var id: UUID
    var updatedAt: Date
    var programRunID: UUID?
    var trainingProgramID: UUID?
    var canonicalLiftKey: String
    var liftDisplayName: String
    var totalDataPoints: Int
    var programLinkedDataPoints: Int
    var standaloneDataPoints: Int
    var weightedSignalCount: Double
    var confidenceScore: Double
    var firstObservationDate: Date
    var lastObservationDate: Date
    var currentEstimated1RM: Double?
    var previousEstimated1RM: Double?
    var rollingBestEstimated1RM: Double?
    var fourWeekChangePercent: Double?
    var trendStatus: LiftTrendStatus
    var fatigueStatus: FatigueStatus
    var latestTopSetWeight: Double?
    var latestTopSetReps: Int?
    var latestPerformanceScoreValue: Double?
    var lastPerformanceScore: PerformanceScore?
    var snapshots: [PortableBackupLiftTrendSnapshot]
}

struct PortableBackupLiftTrendSnapshot: Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var analysisID: UUID?
    var programRunID: UUID?
    var trainingProgramID: UUID?
    var canonicalLiftKey: String
    var liftDisplayName: String
    var weekStartDate: Date
    var weekEndDate: Date
    var programWeekNumber: Int?
    var totalDataPoints: Int
    var programLinkedDataPoints: Int
    var standaloneDataPoints: Int
    var weightedSignalCount: Double
    var weightedProgramSignal: Double
    var weightedStandaloneSignal: Double
    var confidenceScore: Double
    var currentEstimated1RM: Double?
    var baselineEstimated1RM: Double?
    var rollingBestEstimated1RM: Double?
    var changePercent: Double?
    var trendStatus: LiftTrendStatus
    var fatigueStatus: FatigueStatus
    var latestTopSetWeight: Double?
    var latestTopSetReps: Int?
    var latestPerformanceScoreValue: Double?
    var note: String?
}

struct PortableBackupAdaptationProposal: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var createdAt: Date
    var decidedAt: Date?
    var programRunID: UUID?
    var trainingProgramID: UUID?
    var sourceAnalysisID: UUID?
    var proposalType: ProposalType
    var proposalStatus: ProposalStatus
    var requiresUserConfirmation: Bool
    var autoApplyEligible: Bool
    var confidenceScore: Double
    var priority: Int
    var targetWeekStart: Int
    var targetWeekEnd: Int?
    var targetSessionNumber: Int?
    var targetProgramSessionExerciseID: UUID?
    var targetLiftKey: String?
    var proposedLoadPercentDelta: Double?
    var proposedSetDelta: Int?
    var proposedRepDelta: Int?
    var proposedDeloadFactor: Double?
    var swapFromExerciseName: String?
    var swapToExerciseName: String?
    var adjustmentReason: AdjustmentReason
    var summaryText: String
    var detailText: String?
    var expiresAt: Date?
}

struct PortableBackupAppliedProgramOverlay: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var createdAt: Date
    var appliedAt: Date
    var programRunID: UUID?
    var trainingProgramID: UUID?
    var sourceProposalID: UUID?
    var effectiveWeekStart: Int
    var effectiveWeekEnd: Int?
    var overlayStatus: OverlayStatus
    var appliedByUserConfirmation: Bool
    var adjustmentReason: AdjustmentReason
    var summaryText: String?
    var adjustments: [PortableBackupAppliedOverlayAdjustment]
}

struct PortableBackupAppliedOverlayAdjustment: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var sequence: Int
    var targetProgramSessionExerciseID: UUID?
    var targetWeekNumber: Int?
    var targetSessionNumber: Int?
    var adjustmentType: OverlayAdjustmentType
    var loadPercentDelta: Double?
    var absolutePrescribedWeight: Double?
    var setDelta: Int?
    var absoluteTargetSets: Int?
    var repDelta: Int?
    var absoluteTargetReps: Int?
    var replacementExerciseName: String?
    var adjustmentReason: AdjustmentReason
    var isAutoApplied: Bool
}

struct PortableBackupAdaptationEventHistory: Codable, Equatable {
    var id: UUID
    var timestamp: Date
    var programRunID: UUID?
    var trainingProgramID: UUID?
    var analysisID: UUID?
    var proposalID: UUID?
    var overlayID: UUID?
    var eventType: AdaptationEventType
    var analysisWeekNumber: Int?
    var targetLiftKey: String?
    var message: String
    var explanation: String?
    var adjustmentReason: AdjustmentReason?
    var performanceScoreSnapshot: PerformanceScore?
    var fatigueStatusSnapshot: FatigueStatus?
    var liftTrendStatusSnapshot: LiftTrendStatus?
    var confidenceSnapshot: Double?
    var requiresUserAction: Bool
    var userActionTaken: Bool
}

struct PortableBackupHealthKitDailySummary: Codable, Equatable {
    var id: UUID
    var sync: PortableBackupSyncMetadata
    var dayStart: Date
    var sleepDurationSeconds: Int?
    var timeInBedSeconds: Int?
    var restingHeartRateBPM: Double?
    var heartRateVariabilityMS: Double?
    var activeEnergyKilocalories: Double?
    var stepCount: Double?
    var bodyMassKilograms: Double?
    var sourceUpdatedAt: Date
    var createdAt: Date
    var updatedAt: Date
}

struct PortableBackupImportPreview: Identifiable, Equatable {
    let id = UUID()
    var fileName: String
    var envelope: PortableBackupEnvelope
}

struct PortableBackupRestoreResult: Equatable {
    var restoredManifest: PortableBackupManifest
}
