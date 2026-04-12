import Foundation

enum SyncContractVersion {
    static let v1 = 1
}

struct SyncRecordMetadataDTO: Codable, Equatable {
    var stableID: String
    var version: Int
    var lastModifiedAt: Date
    var deletedAt: Date?

    init(stableID: String, version: Int, lastModifiedAt: Date, deletedAt: Date? = nil) {
        self.stableID = stableID
        self.version = max(1, version)
        self.lastModifiedAt = lastModifiedAt
        self.deletedAt = deletedAt
    }
}

struct WorkoutSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var date: Date
    var startTime: Date
    var durationSeconds: Int
    var caloriesBurned: Int?
    var comments: String?
    var sourceTypeRawValue: String
    var sourceExternalIdentifier: String?
    var sourceDisplayName: String?
    var sourceWorkoutTypeIdentifier: String?
    var sourceWorkoutTypeDisplayName: String?
    var sourceImportedAt: Date?
    var healthKitExportedAt: Date?
    var healthKitWritebackIdentifier: String?
    var programRunStableID: String?
    var programWeekNumber: Int?
    var programSessionNumber: Int?
    var exerciseEntries: [ExerciseEntrySyncDTO]
}

struct ExerciseEntrySyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var exerciseName: String
    var unitRawValue: String
    var orderIndex: Int
    var isCardio: Bool
    var cardioDurationSeconds: Int?
    var sourceProgramSessionExerciseStableID: String?
    var prescribedTargetSets: Int?
    var prescribedTargetReps: Int?
    var prescribedTargetPercentage1RM: Double?
    var prescribedTargetRPE: Double?
    var prescribedTargetRIR: Double?
    var prescribedWeight: Double?
    var prescribedWeightUnit: String?
    var prescribedWorkingSetStyleRawValue: String?
    var prescribedTargetEffortTypeRawValue: String?
    var effortFeedbackRawValue: String?
    var topSetRPE: Double?
    var sets: [SetEntrySyncDTO]
}

struct SetEntrySyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var setNumber: Int
    var reps: Int
    var weight: Double
    var isPR: Bool
}

struct PersonalRecordSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var exerciseName: String
    var repCount: Int
    var weight: Double
    var unitRawValue: String
    var dateAchieved: Date
}

struct ProgramPrescriptionExerciseSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var trainingProgramStableID: String?
    var weekNumber: Int
    var sessionNumber: Int
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
    var workingSetStyleRawValue: String?
    var backoffPercentageDrop: Double?
    var targetEffortTypeRawValue: String?
    var baseLiftUsed: String?
    var effectiveOneRepMax: Double?
    var effectiveOneRepMaxUnit: String?
    var usedMappedSourceLift: Bool?
    var progressionPhaseRawValue: String?
    var estimatedFatigueScore: Double?
    var topBackoffGroupID: UUID?
    var explainabilityPurposeRawValue: String?
    var explainabilitySelectionReasonRawValue: String?
}

struct TrainingProgramSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var name: String
    var lengthInWeeks: Int
    var sessionsPerWeek: Int
    var createdDate: Date
    var sourceRawValue: String
    var descriptionText: String?
    var progressionModelRawValue: String?
    var usedLiftMapping: Bool?
    var usedVolumeBalancing: Bool?
    var usedFatigueBalancing: Bool?
    var usedTopSetBackoff: Bool?
    var prescriptions: [ProgramPrescriptionExerciseSyncDTO]
}

struct ProgramRunSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var startDate: Date
    var endDate: Date?
    var isCompleted: Bool
    var trainingProgramStableID: String?
}

struct DailyCoachCheckInSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var date: Date
    var dayStart: Date
    var sleepQuality: Int
    var soreness: Int
    var energy: Int
    var stress: Int
    var availableTimeMinutes: Int
    var hasPainOrDiscomfort: Bool
    var painNotes: String?
    var programRunStableID: String?
    var createdAt: Date
    var updatedAt: Date
}

struct DailyCoachWeeklyReviewSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var weekStart: Date
    var weekEnd: Date
    var isProgramWeek: Bool
    var programRunStableID: String?
    var headline: String
    var winText: String
    var watchoutText: String
    var nextActionText: String
    var sourceWeeklyAnalysisIDText: String?
    var hasBeenSeen: Bool
    var createdAt: Date
}

struct AdaptationProposalSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var createdAt: Date
    var decidedAt: Date?
    var programRunStableID: String?
    var trainingProgramStableID: String?
    var sourceAnalysisStableID: String?
    var proposalTypeRawValue: String
    var proposalStatusRawValue: String
    var requiresUserConfirmation: Bool
    var autoApplyEligible: Bool
    var confidenceScore: Double
    var priority: Int
    var targetWeekStart: Int
    var targetWeekEnd: Int?
    var targetSessionNumber: Int?
    var targetProgramSessionExerciseStableID: String?
    var targetLiftKey: String?
    var proposedLoadPercentDelta: Double?
    var proposedSetDelta: Int?
    var proposedRepDelta: Int?
    var proposedDeloadFactor: Double?
    var swapFromExerciseName: String?
    var swapToExerciseName: String?
    var adjustmentReasonRawValue: String
    var summaryText: String
    var detailText: String?
    var expiresAt: Date?
}

struct AppliedOverlayAdjustmentSyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var sequence: Int
    var targetProgramSessionExerciseStableID: String?
    var targetWeekNumber: Int?
    var targetSessionNumber: Int?
    var adjustmentTypeRawValue: String
    var loadPercentDelta: Double?
    var absolutePrescribedWeight: Double?
    var setDelta: Int?
    var absoluteTargetSets: Int?
    var repDelta: Int?
    var absoluteTargetReps: Int?
    var replacementExerciseName: String?
    var adjustmentReasonRawValue: String
    var isAutoApplied: Bool
}

struct AppliedProgramOverlaySyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
    var createdAt: Date
    var appliedAt: Date
    var programRunStableID: String?
    var trainingProgramStableID: String?
    var sourceProposalStableID: String?
    var effectiveWeekStart: Int
    var effectiveWeekEnd: Int?
    var overlayStatusRawValue: String
    var appliedByUserConfirmation: Bool
    var adjustmentReasonRawValue: String
    var summaryText: String?
    var adjustments: [AppliedOverlayAdjustmentSyncDTO]
}

struct HealthKitDailySummarySyncDTO: Codable, Equatable {
    var contractVersion: Int = SyncContractVersion.v1
    var metadata: SyncRecordMetadataDTO
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

/// Future watch transport can reuse these same contract types by wrapping in a channel envelope.
struct SyncEnvelopeDTO<Payload: Codable & Equatable>: Codable, Equatable {
    var sentAt: Date
    var payload: Payload
}
