import Foundation

private enum SyncMapperUtilities {
    static func metadata(for model: any SyncTrackableModel, deletedAt: Date? = nil) -> SyncRecordMetadataDTO {
        SyncRecordMetadataDTO(
            stableID: model.resolvedSyncStableID,
            version: model.syncVersion,
            lastModifiedAt: model.syncLastModifiedAt,
            deletedAt: deletedAt
        )
    }

    static func nestedMetadata(
        stableID: String,
        lastModifiedAt: Date,
        deletedAt: Date? = nil
    ) -> SyncRecordMetadataDTO {
        SyncRecordMetadataDTO(
            stableID: stableID,
            version: 1,
            lastModifiedAt: lastModifiedAt,
            deletedAt: deletedAt
        )
    }
}

extension SetEntry {
    func toSyncDTO() -> SetEntrySyncDTO {
        initializeSyncMetadataIfNeeded()
        return SetEntrySyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self),
            setNumber: setNumber,
            reps: reps,
            weight: weight,
            isPR: isPR
        )
    }

    static func fromSyncDTO(_ dto: SetEntrySyncDTO) -> SetEntry {
        SetEntry(
            id: UUID(uuidString: dto.metadata.stableID) ?? UUID(),
            syncStableID: dto.metadata.stableID,
            syncVersion: dto.metadata.version,
            syncLastModifiedAt: dto.metadata.lastModifiedAt,
            setNumber: dto.setNumber,
            reps: dto.reps,
            weight: dto.weight,
            isPR: dto.isPR
        )
    }

    func apply(syncDTO dto: SetEntrySyncDTO) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        setNumber = dto.setNumber
        reps = dto.reps
        weight = dto.weight
        isPR = dto.isPR
    }
}

extension ExerciseEntry {
    func toSyncDTO() -> ExerciseEntrySyncDTO {
        initializeSyncMetadataIfNeeded()
        return ExerciseEntrySyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self),
            exerciseName: exerciseName,
            unitRawValue: unit.rawValue,
            orderIndex: orderIndex,
            isCardio: isCardio,
            cardioDurationSeconds: cardioDurationSeconds,
            sourceProgramSessionExerciseStableID: sourceProgramSessionExerciseID?.uuidString,
            prescribedTargetSets: prescribedTargetSets,
            prescribedTargetReps: prescribedTargetReps,
            prescribedTargetPercentage1RM: prescribedTargetPercentage1RM,
            prescribedTargetRPE: prescribedTargetRPE,
            prescribedTargetRIR: prescribedTargetRIR,
            prescribedWeight: prescribedWeight,
            prescribedWeightUnit: prescribedWeightUnit,
            prescribedWorkingSetStyleRawValue: prescribedWorkingSetStyle?.rawValue,
            prescribedTargetEffortTypeRawValue: prescribedTargetEffortType?.rawValue,
            effortFeedbackRawValue: effortFeedback?.rawValue,
            topSetRPE: topSetRPE,
            sets: sets.sorted { $0.setNumber < $1.setNumber }.map { $0.toSyncDTO() }
        )
    }

    static func fromSyncDTO(_ dto: ExerciseEntrySyncDTO) -> ExerciseEntry {
        let entry = ExerciseEntry(
            id: UUID(uuidString: dto.metadata.stableID) ?? UUID(),
            syncStableID: dto.metadata.stableID,
            syncVersion: dto.metadata.version,
            syncLastModifiedAt: dto.metadata.lastModifiedAt,
            exerciseName: dto.exerciseName,
            unit: WeightUnit(rawValue: dto.unitRawValue) ?? .lbs,
            orderIndex: dto.orderIndex,
            isCardio: dto.isCardio,
            cardioDurationSeconds: dto.cardioDurationSeconds,
            sourceProgramSessionExerciseID: dto.sourceProgramSessionExerciseStableID.flatMap(UUID.init(uuidString:)),
            prescribedTargetSets: dto.prescribedTargetSets,
            prescribedTargetReps: dto.prescribedTargetReps,
            prescribedTargetPercentage1RM: dto.prescribedTargetPercentage1RM,
            prescribedTargetRPE: dto.prescribedTargetRPE,
            prescribedTargetRIR: dto.prescribedTargetRIR,
            prescribedWeight: dto.prescribedWeight,
            prescribedWeightUnit: dto.prescribedWeightUnit,
            prescribedWorkingSetStyle: dto.prescribedWorkingSetStyleRawValue.flatMap(ProgramWorkingSetStyle.init(rawValue:)),
            prescribedTargetEffortType: dto.prescribedTargetEffortTypeRawValue.flatMap(ProgramTargetEffortType.init(rawValue:))
        )
        entry.effortFeedback = dto.effortFeedbackRawValue.flatMap(WorkoutEffortFeedback.init(rawValue:))
        entry.topSetRPE = dto.topSetRPE
        entry.sets = dto.sets.map(SetEntry.fromSyncDTO)
        return entry
    }

    func apply(syncDTO dto: ExerciseEntrySyncDTO) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        exerciseName = dto.exerciseName
        unit = WeightUnit(rawValue: dto.unitRawValue) ?? .lbs
        orderIndex = dto.orderIndex
        isCardio = dto.isCardio
        cardioDurationSeconds = dto.cardioDurationSeconds
        sourceProgramSessionExerciseID = dto.sourceProgramSessionExerciseStableID.flatMap(UUID.init(uuidString:))
        prescribedTargetSets = dto.prescribedTargetSets
        prescribedTargetReps = dto.prescribedTargetReps
        prescribedTargetPercentage1RM = dto.prescribedTargetPercentage1RM
        prescribedTargetRPE = dto.prescribedTargetRPE
        prescribedTargetRIR = dto.prescribedTargetRIR
        prescribedWeight = dto.prescribedWeight
        prescribedWeightUnit = dto.prescribedWeightUnit
        prescribedWorkingSetStyle = dto.prescribedWorkingSetStyleRawValue.flatMap(ProgramWorkingSetStyle.init(rawValue:))
        prescribedTargetEffortType = dto.prescribedTargetEffortTypeRawValue.flatMap(ProgramTargetEffortType.init(rawValue:))
        effortFeedback = dto.effortFeedbackRawValue.flatMap(WorkoutEffortFeedback.init(rawValue:))
        topSetRPE = dto.topSetRPE
    }
}

extension Workout {
    func toSyncDTO() -> WorkoutSyncDTO {
        initializeSyncMetadataIfNeeded()
        return WorkoutSyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self, deletedAt: syncDeletedAt),
            date: date,
            startTime: startTime,
            durationSeconds: durationSeconds,
            caloriesBurned: caloriesBurned,
            comments: comments,
            sourceTypeRawValue: sourceType.rawValue,
            sourceExternalIdentifier: sourceExternalIdentifier,
            sourceDisplayName: sourceDisplayName,
            sourceWorkoutTypeIdentifier: sourceWorkoutTypeIdentifier,
            sourceWorkoutTypeDisplayName: sourceWorkoutTypeDisplayName,
            sourceImportedAt: sourceImportedAt,
            healthKitExportedAt: healthKitExportedAt,
            healthKitWritebackIdentifier: healthKitWritebackIdentifier,
            programRunStableID: programRun?.resolvedSyncStableID,
            programWeekNumber: programWeekNumber,
            programSessionNumber: programSessionNumber,
            exerciseEntries: exerciseEntries.sorted { $0.orderIndex < $1.orderIndex }.map { $0.toSyncDTO() }
        )
    }

    static func fromSyncDTO(_ dto: WorkoutSyncDTO, programRun: ProgramRun? = nil) -> Workout {
        let workout = Workout(
            id: UUID(uuidString: dto.metadata.stableID) ?? UUID(),
            syncStableID: dto.metadata.stableID,
            syncVersion: dto.metadata.version,
            syncLastModifiedAt: dto.metadata.lastModifiedAt,
            syncDeletedAt: dto.metadata.deletedAt,
            date: dto.date,
            startTime: dto.startTime,
            durationSeconds: dto.durationSeconds,
            caloriesBurned: dto.caloriesBurned,
            comments: dto.comments,
            programRun: programRun,
            programWeekNumber: dto.programWeekNumber,
            programSessionNumber: dto.programSessionNumber,
            sourceType: WorkoutSourceType(rawValue: dto.sourceTypeRawValue) ?? .loggedInApp,
            sourceExternalIdentifier: dto.sourceExternalIdentifier,
            sourceDisplayName: dto.sourceDisplayName,
            sourceWorkoutTypeIdentifier: dto.sourceWorkoutTypeIdentifier,
            sourceWorkoutTypeDisplayName: dto.sourceWorkoutTypeDisplayName,
            sourceImportedAt: dto.sourceImportedAt,
            healthKitExportedAt: dto.healthKitExportedAt,
            healthKitWritebackIdentifier: dto.healthKitWritebackIdentifier
        )
        workout.exerciseEntries = dto.exerciseEntries.map(ExerciseEntry.fromSyncDTO)
        return workout
    }

    func apply(syncDTO dto: WorkoutSyncDTO, programRun: ProgramRun? = nil) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        syncDeletedAt = dto.metadata.deletedAt
        date = dto.date
        startTime = dto.startTime
        durationSeconds = dto.durationSeconds
        caloriesBurned = dto.caloriesBurned
        comments = dto.comments
        self.programRun = programRun
        programWeekNumber = dto.programWeekNumber
        programSessionNumber = dto.programSessionNumber
        sourceType = WorkoutSourceType(rawValue: dto.sourceTypeRawValue) ?? .loggedInApp
        sourceExternalIdentifier = dto.sourceExternalIdentifier
        sourceDisplayName = dto.sourceDisplayName
        sourceWorkoutTypeIdentifier = dto.sourceWorkoutTypeIdentifier
        sourceWorkoutTypeDisplayName = dto.sourceWorkoutTypeDisplayName
        sourceImportedAt = dto.sourceImportedAt
        healthKitExportedAt = dto.healthKitExportedAt
        healthKitWritebackIdentifier = dto.healthKitWritebackIdentifier
    }
}

extension PersonalRecord {
    func toSyncDTO() -> PersonalRecordSyncDTO {
        initializeSyncMetadataIfNeeded()
        return PersonalRecordSyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self),
            exerciseName: exerciseName,
            repCount: repCount,
            weight: weight,
            unitRawValue: unit.rawValue,
            dateAchieved: dateAchieved
        )
    }
}

extension ProgramSessionExercise {
    func toPrescriptionSyncDTO() -> ProgramPrescriptionExerciseSyncDTO {
        initializeSyncMetadataIfNeeded()
        return ProgramPrescriptionExerciseSyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self),
            trainingProgramStableID: session?.week?.program?.resolvedSyncStableID,
            weekNumber: session?.week?.weekNumber ?? 0,
            sessionNumber: session?.sessionNumber ?? 0,
            exerciseName: exerciseName,
            orderIndex: orderIndex,
            targetSets: targetSets,
            targetReps: targetReps,
            targetPercentage1RM: targetPercentage1RM,
            targetRPE: targetRPE,
            targetRIR: targetRIR,
            isWarmup: isWarmup,
            prescribedWeight: prescribedWeight,
            prescribedWeightUnit: prescribedWeightUnit,
            workingSetStyleRawValue: workingSetStyle?.rawValue,
            backoffPercentageDrop: backoffPercentageDrop,
            targetEffortTypeRawValue: targetEffortType?.rawValue,
            baseLiftUsed: baseLiftUsed,
            effectiveOneRepMax: effectiveOneRepMax,
            effectiveOneRepMaxUnit: effectiveOneRepMaxUnit,
            usedMappedSourceLift: usedMappedSourceLift,
            progressionPhaseRawValue: progressionPhase?.rawValue,
            estimatedFatigueScore: estimatedFatigueScore,
            topBackoffGroupID: topBackoffGroupID,
            explainabilityPurposeRawValue: explainabilityPurpose?.rawValue,
            explainabilitySelectionReasonRawValue: explainabilitySelectionReason?.rawValue
        )
    }
}

extension TrainingProgram {
    func toSyncDTO() -> TrainingProgramSyncDTO {
        initializeSyncMetadataIfNeeded()
        let prescriptions = weeks
            .sorted { $0.weekNumber < $1.weekNumber }
            .flatMap { week in
                week.sessions.sorted { $0.sessionNumber < $1.sessionNumber }
            }
            .flatMap { session in
                session.exercises.sorted { $0.orderIndex < $1.orderIndex }.map { $0.toPrescriptionSyncDTO() }
            }

        return TrainingProgramSyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self, deletedAt: syncDeletedAt),
            name: name,
            lengthInWeeks: lengthInWeeks,
            sessionsPerWeek: sessionsPerWeek,
            createdDate: createdDate,
            sourceRawValue: source.rawValue,
            descriptionText: descriptionText,
            progressionModelRawValue: progressionModel?.rawValue,
            usedLiftMapping: usedLiftMapping,
            usedVolumeBalancing: usedVolumeBalancing,
            usedFatigueBalancing: usedFatigueBalancing,
            usedTopSetBackoff: usedTopSetBackoff,
            prescriptions: prescriptions
        )
    }

    func apply(syncDTO dto: TrainingProgramSyncDTO) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        syncDeletedAt = dto.metadata.deletedAt
        name = dto.name
        lengthInWeeks = dto.lengthInWeeks
        sessionsPerWeek = dto.sessionsPerWeek
        createdDate = dto.createdDate
        source = ProgramSource(rawValue: dto.sourceRawValue) ?? .userCreated
        descriptionText = dto.descriptionText
        progressionModel = dto.progressionModelRawValue.flatMap(ProgramProgressionModel.init(rawValue:))
        usedLiftMapping = dto.usedLiftMapping
        usedVolumeBalancing = dto.usedVolumeBalancing
        usedFatigueBalancing = dto.usedFatigueBalancing
        usedTopSetBackoff = dto.usedTopSetBackoff
    }
}

extension ProgramRun {
    func toSyncDTO() -> ProgramRunSyncDTO {
        initializeSyncMetadataIfNeeded()
        return ProgramRunSyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self, deletedAt: syncDeletedAt),
            startDate: startDate,
            endDate: endDate,
            isCompleted: isCompleted,
            trainingProgramStableID: program?.resolvedSyncStableID,
            previousProgramRunStableID: previousProgramRunStableID,
            recommendationDecisionHistoryJSON: recommendationDecisionHistoryJSON,
            continuitySnapshotJSON: continuitySnapshotJSON
        )
    }

    func apply(syncDTO dto: ProgramRunSyncDTO, program: TrainingProgram? = nil) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        syncDeletedAt = dto.metadata.deletedAt
        startDate = dto.startDate
        endDate = dto.endDate
        isCompleted = dto.isCompleted
        previousProgramRunStableID = dto.previousProgramRunStableID
        recommendationDecisionHistoryJSON = dto.recommendationDecisionHistoryJSON
        continuitySnapshotJSON = dto.continuitySnapshotJSON
        self.program = program
    }
}

extension DailyCoachCheckIn {
    func toSyncDTO() -> DailyCoachCheckInSyncDTO {
        initializeSyncMetadataIfNeeded()
        return DailyCoachCheckInSyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self, deletedAt: syncDeletedAt),
            date: date,
            dayStart: dayStart,
            sleepQuality: sleepQuality,
            soreness: soreness,
            energy: energy,
            stress: stress,
            availableTimeMinutes: availableTimeMinutes,
            hasPainOrDiscomfort: hasPainOrDiscomfort,
            painNotes: painNotes,
            programRunStableID: programRun?.resolvedSyncStableID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func apply(syncDTO dto: DailyCoachCheckInSyncDTO, programRun: ProgramRun? = nil) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        syncDeletedAt = dto.metadata.deletedAt
        date = dto.date
        dayStart = dto.dayStart
        sleepQuality = dto.sleepQuality
        soreness = dto.soreness
        energy = dto.energy
        stress = dto.stress
        availableTimeMinutes = dto.availableTimeMinutes
        hasPainOrDiscomfort = dto.hasPainOrDiscomfort
        painNotes = dto.painNotes
        self.programRun = programRun
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
    }
}

extension DailyCoachWeeklyReview {
    func toSyncDTO() -> DailyCoachWeeklyReviewSyncDTO {
        initializeSyncMetadataIfNeeded()
        return DailyCoachWeeklyReviewSyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self, deletedAt: syncDeletedAt),
            weekStart: weekStart,
            weekEnd: weekEnd,
            isProgramWeek: isProgramWeek,
            programRunStableID: programRun?.resolvedSyncStableID,
            headline: headline,
            winText: winText,
            watchoutText: watchoutText,
            nextActionText: nextActionText,
            sourceWeeklyAnalysisIDText: sourceWeeklyAnalysisIDText,
            hasBeenSeen: hasBeenSeen,
            createdAt: createdAt
        )
    }

    func apply(syncDTO dto: DailyCoachWeeklyReviewSyncDTO, programRun: ProgramRun? = nil) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        syncDeletedAt = dto.metadata.deletedAt
        weekStart = dto.weekStart
        weekEnd = dto.weekEnd
        isProgramWeek = dto.isProgramWeek
        self.programRun = programRun
        headline = dto.headline
        winText = dto.winText
        watchoutText = dto.watchoutText
        nextActionText = dto.nextActionText
        sourceWeeklyAnalysisIDText = dto.sourceWeeklyAnalysisIDText
        hasBeenSeen = dto.hasBeenSeen
        createdAt = dto.createdAt
    }
}

extension AdaptationProposal {
    func toSyncDTO() -> AdaptationProposalSyncDTO {
        initializeSyncMetadataIfNeeded()
        return AdaptationProposalSyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self, deletedAt: syncDeletedAt),
            createdAt: createdAt,
            decidedAt: decidedAt,
            programRunStableID: programRun?.resolvedSyncStableID,
            trainingProgramStableID: trainingProgram?.resolvedSyncStableID,
            sourceAnalysisStableID: sourceAnalysis?.id.uuidString,
            proposalTypeRawValue: proposalType.rawValue,
            proposalStatusRawValue: proposalStatus.rawValue,
            requiresUserConfirmation: requiresUserConfirmation,
            autoApplyEligible: autoApplyEligible,
            confidenceScore: confidenceScore,
            priority: priority,
            targetWeekStart: targetWeekStart,
            targetWeekEnd: targetWeekEnd,
            targetSessionNumber: targetSessionNumber,
            targetProgramSessionExerciseStableID: targetProgramSessionExerciseID?.uuidString,
            targetLiftKey: targetLiftKey,
            proposedLoadPercentDelta: proposedLoadPercentDelta,
            proposedSetDelta: proposedSetDelta,
            proposedRepDelta: proposedRepDelta,
            proposedDeloadFactor: proposedDeloadFactor,
            swapFromExerciseName: swapFromExerciseName,
            swapToExerciseName: swapToExerciseName,
            adjustmentReasonRawValue: adjustmentReason.rawValue,
            summaryText: summaryText,
            detailText: detailText,
            expiresAt: expiresAt
        )
    }

    func apply(syncDTO dto: AdaptationProposalSyncDTO) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        syncDeletedAt = dto.metadata.deletedAt
        createdAt = dto.createdAt
        decidedAt = dto.decidedAt
        proposalType = ProposalType(rawValue: dto.proposalTypeRawValue) ?? .increaseLoad
        proposalStatus = ProposalStatus(rawValue: dto.proposalStatusRawValue) ?? .draft
        requiresUserConfirmation = dto.requiresUserConfirmation
        autoApplyEligible = dto.autoApplyEligible
        confidenceScore = dto.confidenceScore
        priority = dto.priority
        targetWeekStart = dto.targetWeekStart
        targetWeekEnd = dto.targetWeekEnd
        targetSessionNumber = dto.targetSessionNumber
        targetProgramSessionExerciseID = dto.targetProgramSessionExerciseStableID.flatMap(UUID.init(uuidString:))
        targetLiftKey = dto.targetLiftKey
        proposedLoadPercentDelta = dto.proposedLoadPercentDelta
        proposedSetDelta = dto.proposedSetDelta
        proposedRepDelta = dto.proposedRepDelta
        proposedDeloadFactor = dto.proposedDeloadFactor
        swapFromExerciseName = dto.swapFromExerciseName
        swapToExerciseName = dto.swapToExerciseName
        adjustmentReason = AdjustmentReason(rawValue: dto.adjustmentReasonRawValue) ?? .programSignalPriority
        summaryText = dto.summaryText
        detailText = dto.detailText
        expiresAt = dto.expiresAt
    }
}

extension AppliedOverlayAdjustment {
    func toSyncDTO() -> AppliedOverlayAdjustmentSyncDTO {
        initializeSyncMetadataIfNeeded()
        return AppliedOverlayAdjustmentSyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self),
            sequence: sequence,
            targetProgramSessionExerciseStableID: targetProgramSessionExerciseID?.uuidString,
            targetWeekNumber: targetWeekNumber,
            targetSessionNumber: targetSessionNumber,
            adjustmentTypeRawValue: adjustmentType.rawValue,
            loadPercentDelta: loadPercentDelta,
            absolutePrescribedWeight: absolutePrescribedWeight,
            setDelta: setDelta,
            absoluteTargetSets: absoluteTargetSets,
            repDelta: repDelta,
            absoluteTargetReps: absoluteTargetReps,
            replacementExerciseName: replacementExerciseName,
            adjustmentReasonRawValue: adjustmentReason.rawValue,
            isAutoApplied: isAutoApplied
        )
    }

    static func fromSyncDTO(_ dto: AppliedOverlayAdjustmentSyncDTO) -> AppliedOverlayAdjustment {
        AppliedOverlayAdjustment(
            id: UUID(uuidString: dto.metadata.stableID) ?? UUID(),
            syncStableID: dto.metadata.stableID,
            syncVersion: dto.metadata.version,
            syncLastModifiedAt: dto.metadata.lastModifiedAt,
            sequence: dto.sequence,
            targetProgramSessionExerciseID: dto.targetProgramSessionExerciseStableID.flatMap(UUID.init(uuidString:)),
            targetWeekNumber: dto.targetWeekNumber,
            targetSessionNumber: dto.targetSessionNumber,
            adjustmentType: OverlayAdjustmentType(rawValue: dto.adjustmentTypeRawValue) ?? .load,
            loadPercentDelta: dto.loadPercentDelta,
            absolutePrescribedWeight: dto.absolutePrescribedWeight,
            setDelta: dto.setDelta,
            absoluteTargetSets: dto.absoluteTargetSets,
            repDelta: dto.repDelta,
            absoluteTargetReps: dto.absoluteTargetReps,
            replacementExerciseName: dto.replacementExerciseName,
            adjustmentReason: AdjustmentReason(rawValue: dto.adjustmentReasonRawValue) ?? .programSignalPriority,
            isAutoApplied: dto.isAutoApplied
        )
    }
}

extension AppliedProgramOverlay {
    func toSyncDTO() -> AppliedProgramOverlaySyncDTO {
        initializeSyncMetadataIfNeeded()
        return AppliedProgramOverlaySyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self, deletedAt: syncDeletedAt),
            createdAt: createdAt,
            appliedAt: appliedAt,
            programRunStableID: programRun?.resolvedSyncStableID,
            trainingProgramStableID: trainingProgram?.resolvedSyncStableID,
            sourceProposalStableID: sourceProposal?.resolvedSyncStableID,
            effectiveWeekStart: effectiveWeekStart,
            effectiveWeekEnd: effectiveWeekEnd,
            overlayStatusRawValue: overlayStatus.rawValue,
            appliedByUserConfirmation: appliedByUserConfirmation,
            adjustmentReasonRawValue: adjustmentReason.rawValue,
            summaryText: summaryText,
            adjustments: adjustments.sorted { $0.sequence < $1.sequence }.map { $0.toSyncDTO() }
        )
    }

    func apply(syncDTO dto: AppliedProgramOverlaySyncDTO) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        syncDeletedAt = dto.metadata.deletedAt
        createdAt = dto.createdAt
        appliedAt = dto.appliedAt
        effectiveWeekStart = dto.effectiveWeekStart
        effectiveWeekEnd = dto.effectiveWeekEnd
        overlayStatus = OverlayStatus(rawValue: dto.overlayStatusRawValue) ?? .active
        appliedByUserConfirmation = dto.appliedByUserConfirmation
        adjustmentReason = AdjustmentReason(rawValue: dto.adjustmentReasonRawValue) ?? .programSignalPriority
        summaryText = dto.summaryText
    }
}

extension ExercisePerformanceOutcome {
    func toSyncDTO() -> ExercisePerformanceOutcomeSyncDTO {
        ExercisePerformanceOutcomeSyncDTO(
            metadata: SyncMapperUtilities.nestedMetadata(
                stableID: id.uuidString,
                lastModifiedAt: analysis?.syncLastModifiedAt ?? createdAt
            ),
            createdAt: createdAt,
            programRunStableID: programRun?.resolvedSyncStableID,
            workoutStableID: workout?.resolvedSyncStableID,
            exerciseEntryStableID: exerciseEntry?.resolvedSyncStableID,
            workoutDate: workoutDate,
            programWeekNumber: programWeekNumber,
            programSessionNumber: programSessionNumber,
            sourceProgramSessionExerciseID: sourceProgramSessionExerciseID?.uuidString,
            exerciseName: exerciseName,
            canonicalLiftKey: canonicalLiftKey,
            signalSourceRawValue: signalSource.rawValue,
            signalConfidenceRawValue: signalConfidence.rawValue,
            signalWeight: signalWeight,
            prescribedSets: prescribedSets,
            prescribedReps: prescribedReps,
            prescribedWeight: prescribedWeight,
            prescribedWeightUnit: prescribedWeightUnit,
            prescribedTargetPercentage1RM: prescribedTargetPercentage1RM,
            prescribedTargetRPE: prescribedTargetRPE,
            prescribedTargetRIR: prescribedTargetRIR,
            prescribedWorkingSetStyleRawValue: prescribedWorkingSetStyle?.rawValue,
            prescribedTargetEffortTypeRawValue: prescribedTargetEffortType?.rawValue,
            actualSetCount: actualSetCount,
            actualAverageReps: actualAverageReps,
            actualAverageWeight: actualAverageWeight,
            actualTopSetReps: actualTopSetReps,
            actualTopSetWeight: actualTopSetWeight,
            actualTopSetEstimated1RM: actualTopSetEstimated1RM,
            completionRatio: completionRatio,
            loadDeltaPercent: loadDeltaPercent,
            repsDelta: repsDelta,
            performanceScoreValue: performanceScoreValue,
            performanceScoreRawValue: performanceScore.rawValue,
            inferredFatigueStatusRawValue: inferredFatigueStatus.rawValue,
            isTopSetSignal: isTopSetSignal,
            notes: notes
        )
    }

    static func fromSyncDTO(
        _ dto: ExercisePerformanceOutcomeSyncDTO,
        analysis: WeeklyTrainingAnalysis?,
        programRun: ProgramRun?,
        workout: Workout?,
        exerciseEntry: ExerciseEntry?
    ) -> ExercisePerformanceOutcome {
        ExercisePerformanceOutcome(
            id: UUID(uuidString: dto.metadata.stableID) ?? UUID(),
            createdAt: dto.createdAt,
            analysis: analysis,
            programRun: programRun,
            workout: workout,
            exerciseEntry: exerciseEntry,
            workoutDate: dto.workoutDate,
            programWeekNumber: dto.programWeekNumber,
            programSessionNumber: dto.programSessionNumber,
            sourceProgramSessionExerciseID: dto.sourceProgramSessionExerciseID.flatMap(UUID.init(uuidString:)),
            exerciseName: dto.exerciseName,
            canonicalLiftKey: dto.canonicalLiftKey,
            signalSource: WorkoutSignalSource(rawValue: dto.signalSourceRawValue) ?? .standalone,
            signalConfidence: WorkoutSignalConfidence(rawValue: dto.signalConfidenceRawValue) ?? .low,
            signalWeight: dto.signalWeight,
            prescribedSets: dto.prescribedSets,
            prescribedReps: dto.prescribedReps,
            prescribedWeight: dto.prescribedWeight,
            prescribedWeightUnit: dto.prescribedWeightUnit,
            prescribedTargetPercentage1RM: dto.prescribedTargetPercentage1RM,
            prescribedTargetRPE: dto.prescribedTargetRPE,
            prescribedTargetRIR: dto.prescribedTargetRIR,
            prescribedWorkingSetStyle: dto.prescribedWorkingSetStyleRawValue.flatMap(ProgramWorkingSetStyle.init(rawValue:)),
            prescribedTargetEffortType: dto.prescribedTargetEffortTypeRawValue.flatMap(ProgramTargetEffortType.init(rawValue:)),
            actualSetCount: dto.actualSetCount,
            actualAverageReps: dto.actualAverageReps,
            actualAverageWeight: dto.actualAverageWeight,
            actualTopSetReps: dto.actualTopSetReps,
            actualTopSetWeight: dto.actualTopSetWeight,
            actualTopSetEstimated1RM: dto.actualTopSetEstimated1RM,
            completionRatio: dto.completionRatio,
            loadDeltaPercent: dto.loadDeltaPercent,
            repsDelta: dto.repsDelta,
            performanceScoreValue: dto.performanceScoreValue,
            performanceScore: PerformanceScore(rawValue: dto.performanceScoreRawValue) ?? .insufficientData,
            inferredFatigueStatus: FatigueStatus(rawValue: dto.inferredFatigueStatusRawValue) ?? .manageable,
            isTopSetSignal: dto.isTopSetSignal,
            notes: dto.notes
        )
    }
}

extension WeeklyVolumeMetric {
    func toSyncDTO() -> WeeklyVolumeMetricSyncDTO {
        WeeklyVolumeMetricSyncDTO(
            metadata: SyncMapperUtilities.nestedMetadata(
                stableID: id.uuidString,
                lastModifiedAt: analysis?.syncLastModifiedAt ?? .now
            ),
            muscleRawValue: muscle.rawValue,
            plannedHardSets: plannedHardSets,
            completedHardSets: completedHardSets,
            weightedCompletedHardSets: weightedCompletedHardSets,
            deltaHardSets: deltaHardSets
        )
    }

    static func fromSyncDTO(
        _ dto: WeeklyVolumeMetricSyncDTO,
        analysis: WeeklyTrainingAnalysis?
    ) -> WeeklyVolumeMetric {
        WeeklyVolumeMetric(
            id: UUID(uuidString: dto.metadata.stableID) ?? UUID(),
            analysis: analysis,
            muscle: ProgramVolumeMuscle(rawValue: dto.muscleRawValue) ?? .chest,
            plannedHardSets: dto.plannedHardSets,
            completedHardSets: dto.completedHardSets,
            weightedCompletedHardSets: dto.weightedCompletedHardSets,
            deltaHardSets: dto.deltaHardSets
        )
    }
}

extension WeeklyTrainingAnalysis {
    func toSyncDTO() -> WeeklyTrainingAnalysisSyncDTO {
        initializeSyncMetadataIfNeeded()
        return WeeklyTrainingAnalysisSyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self, deletedAt: syncDeletedAt),
            createdAt: createdAt,
            weekStartDate: weekStartDate,
            weekEndDate: weekEndDate,
            programRunStableID: programRun?.resolvedSyncStableID,
            trainingProgramStableID: trainingProgram?.resolvedSyncStableID,
            programWeekNumber: programWeekNumber,
            focusSnapshotRawValue: focusSnapshot?.rawValue,
            programWorkoutCount: programWorkoutCount,
            standaloneWorkoutCount: standaloneWorkoutCount,
            totalOutcomeCount: totalOutcomeCount,
            totalSignalWeight: totalSignalWeight,
            programSignalWeight: programSignalWeight,
            standaloneSignalWeight: standaloneSignalWeight,
            weightedPerformanceScore: weightedPerformanceScore,
            adherenceScore: adherenceScore,
            plannedFatigueScore: plannedFatigueScore,
            observedFatigueScore: observedFatigueScore,
            fatigueStatusRawValue: fatigueStatus.rawValue,
            totalCompletedHardSets: totalCompletedHardSets,
            totalCompletedTonnage: totalCompletedTonnage,
            isFinalized: isFinalized,
            finalizedAt: finalizedAt,
            outcomes: outcomes
                .sorted { lhs, rhs in
                    if lhs.workoutDate == rhs.workoutDate {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.workoutDate < rhs.workoutDate
                }
                .map { $0.toSyncDTO() },
            volumeMetrics: volumeMetrics
                .sorted { $0.muscle.rawValue < $1.muscle.rawValue }
                .map { $0.toSyncDTO() }
        )
    }

    func apply(syncDTO dto: WeeklyTrainingAnalysisSyncDTO, programRun: ProgramRun?, trainingProgram: TrainingProgram?) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        syncDeletedAt = dto.metadata.deletedAt
        createdAt = dto.createdAt
        weekStartDate = dto.weekStartDate
        weekEndDate = dto.weekEndDate
        self.programRun = programRun
        self.trainingProgram = trainingProgram
        programWeekNumber = dto.programWeekNumber
        focusSnapshot = dto.focusSnapshotRawValue.flatMap(ProgramFocus.init(rawValue:))
        programWorkoutCount = dto.programWorkoutCount
        standaloneWorkoutCount = dto.standaloneWorkoutCount
        totalOutcomeCount = dto.totalOutcomeCount
        totalSignalWeight = dto.totalSignalWeight
        programSignalWeight = dto.programSignalWeight
        standaloneSignalWeight = dto.standaloneSignalWeight
        weightedPerformanceScore = dto.weightedPerformanceScore
        adherenceScore = dto.adherenceScore
        plannedFatigueScore = dto.plannedFatigueScore
        observedFatigueScore = dto.observedFatigueScore
        fatigueStatus = FatigueStatus(rawValue: dto.fatigueStatusRawValue) ?? .manageable
        totalCompletedHardSets = dto.totalCompletedHardSets
        totalCompletedTonnage = dto.totalCompletedTonnage
        isFinalized = dto.isFinalized
        finalizedAt = dto.finalizedAt
    }
}

extension LiftTrendSnapshot {
    func toSyncDTO() -> LiftTrendSnapshotSyncDTO {
        LiftTrendSnapshotSyncDTO(
            metadata: SyncMapperUtilities.nestedMetadata(
                stableID: id.uuidString,
                lastModifiedAt: trend?.syncLastModifiedAt ?? createdAt
            ),
            createdAt: createdAt,
            analysisStableID: analysis?.resolvedSyncStableID,
            canonicalLiftKey: canonicalLiftKey,
            liftDisplayName: liftDisplayName,
            weekStartDate: weekStartDate,
            weekEndDate: weekEndDate,
            programWeekNumber: programWeekNumber,
            totalDataPoints: totalDataPoints,
            programLinkedDataPoints: programLinkedDataPoints,
            standaloneDataPoints: standaloneDataPoints,
            weightedSignalCount: weightedSignalCount,
            weightedProgramSignal: weightedProgramSignal,
            weightedStandaloneSignal: weightedStandaloneSignal,
            confidenceScore: confidenceScore,
            currentEstimated1RM: currentEstimated1RM,
            baselineEstimated1RM: baselineEstimated1RM,
            rollingBestEstimated1RM: rollingBestEstimated1RM,
            changePercent: changePercent,
            trendStatusRawValue: trendStatus.rawValue,
            fatigueStatusRawValue: fatigueStatus.rawValue,
            latestTopSetWeight: latestTopSetWeight,
            latestTopSetReps: latestTopSetReps,
            latestPerformanceScoreValue: latestPerformanceScoreValue,
            note: note
        )
    }

    static func fromSyncDTO(
        _ dto: LiftTrendSnapshotSyncDTO,
        trend: LiftPerformanceTrend?,
        analysis: WeeklyTrainingAnalysis?,
        programRun: ProgramRun?,
        trainingProgram: TrainingProgram?
    ) -> LiftTrendSnapshot {
        LiftTrendSnapshot(
            id: UUID(uuidString: dto.metadata.stableID) ?? UUID(),
            createdAt: dto.createdAt,
            trend: trend,
            analysis: analysis,
            programRun: programRun,
            trainingProgram: trainingProgram,
            canonicalLiftKey: dto.canonicalLiftKey,
            liftDisplayName: dto.liftDisplayName,
            weekStartDate: dto.weekStartDate,
            weekEndDate: dto.weekEndDate,
            programWeekNumber: dto.programWeekNumber,
            totalDataPoints: dto.totalDataPoints,
            programLinkedDataPoints: dto.programLinkedDataPoints,
            standaloneDataPoints: dto.standaloneDataPoints,
            weightedSignalCount: dto.weightedSignalCount,
            weightedProgramSignal: dto.weightedProgramSignal,
            weightedStandaloneSignal: dto.weightedStandaloneSignal,
            confidenceScore: dto.confidenceScore,
            currentEstimated1RM: dto.currentEstimated1RM,
            baselineEstimated1RM: dto.baselineEstimated1RM,
            rollingBestEstimated1RM: dto.rollingBestEstimated1RM,
            changePercent: dto.changePercent,
            trendStatus: LiftTrendStatus(rawValue: dto.trendStatusRawValue) ?? .insufficientData,
            fatigueStatus: FatigueStatus(rawValue: dto.fatigueStatusRawValue) ?? .manageable,
            latestTopSetWeight: dto.latestTopSetWeight,
            latestTopSetReps: dto.latestTopSetReps,
            latestPerformanceScoreValue: dto.latestPerformanceScoreValue,
            note: dto.note
        )
    }
}

extension LiftPerformanceTrend {
    func toSyncDTO() -> LiftPerformanceTrendSyncDTO {
        initializeSyncMetadataIfNeeded()
        return LiftPerformanceTrendSyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self, deletedAt: syncDeletedAt),
            updatedAt: updatedAt,
            programRunStableID: programRun?.resolvedSyncStableID,
            trainingProgramStableID: trainingProgram?.resolvedSyncStableID,
            canonicalLiftKey: canonicalLiftKey,
            liftDisplayName: liftDisplayName,
            totalDataPoints: totalDataPoints,
            programLinkedDataPoints: programLinkedDataPoints,
            standaloneDataPoints: standaloneDataPoints,
            weightedSignalCount: weightedSignalCount,
            confidenceScore: confidenceScore,
            firstObservationDate: firstObservationDate,
            lastObservationDate: lastObservationDate,
            currentEstimated1RM: currentEstimated1RM,
            previousEstimated1RM: previousEstimated1RM,
            rollingBestEstimated1RM: rollingBestEstimated1RM,
            fourWeekChangePercent: fourWeekChangePercent,
            trendStatusRawValue: trendStatus.rawValue,
            fatigueStatusRawValue: fatigueStatus.rawValue,
            latestTopSetWeight: latestTopSetWeight,
            latestTopSetReps: latestTopSetReps,
            latestPerformanceScoreValue: latestPerformanceScoreValue,
            lastPerformanceScoreRawValue: lastPerformanceScore?.rawValue,
            snapshots: snapshots
                .sorted { lhs, rhs in
                    if lhs.weekStartDate == rhs.weekStartDate {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.weekStartDate < rhs.weekStartDate
                }
                .map { $0.toSyncDTO() }
        )
    }

    func apply(syncDTO dto: LiftPerformanceTrendSyncDTO, programRun: ProgramRun?, trainingProgram: TrainingProgram?) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        syncDeletedAt = dto.metadata.deletedAt
        updatedAt = dto.updatedAt
        self.programRun = programRun
        self.trainingProgram = trainingProgram
        canonicalLiftKey = dto.canonicalLiftKey
        liftDisplayName = dto.liftDisplayName
        totalDataPoints = dto.totalDataPoints
        programLinkedDataPoints = dto.programLinkedDataPoints
        standaloneDataPoints = dto.standaloneDataPoints
        weightedSignalCount = dto.weightedSignalCount
        confidenceScore = dto.confidenceScore
        firstObservationDate = dto.firstObservationDate
        lastObservationDate = dto.lastObservationDate
        currentEstimated1RM = dto.currentEstimated1RM
        previousEstimated1RM = dto.previousEstimated1RM
        rollingBestEstimated1RM = dto.rollingBestEstimated1RM
        fourWeekChangePercent = dto.fourWeekChangePercent
        trendStatus = LiftTrendStatus(rawValue: dto.trendStatusRawValue) ?? .insufficientData
        fatigueStatus = FatigueStatus(rawValue: dto.fatigueStatusRawValue) ?? .manageable
        latestTopSetWeight = dto.latestTopSetWeight
        latestTopSetReps = dto.latestTopSetReps
        latestPerformanceScoreValue = dto.latestPerformanceScoreValue
        lastPerformanceScore = dto.lastPerformanceScoreRawValue.flatMap(PerformanceScore.init(rawValue:))
    }
}

extension AdaptationEventHistory {
    func toSyncDTO() -> AdaptationEventHistorySyncDTO {
        initializeSyncMetadataIfNeeded()
        return AdaptationEventHistorySyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self, deletedAt: syncDeletedAt),
            timestamp: timestamp,
            programRunStableID: programRun?.resolvedSyncStableID,
            trainingProgramStableID: trainingProgram?.resolvedSyncStableID,
            analysisStableID: analysis?.resolvedSyncStableID,
            proposalStableID: proposal?.resolvedSyncStableID,
            overlayStableID: overlay?.resolvedSyncStableID,
            eventTypeRawValue: eventType.rawValue,
            analysisWeekNumber: analysisWeekNumber,
            targetLiftKey: targetLiftKey,
            message: message,
            explanation: explanation,
            adjustmentReasonRawValue: adjustmentReason?.rawValue,
            performanceScoreSnapshotRawValue: performanceScoreSnapshot?.rawValue,
            fatigueStatusSnapshotRawValue: fatigueStatusSnapshot?.rawValue,
            liftTrendStatusSnapshotRawValue: liftTrendStatusSnapshot?.rawValue,
            confidenceSnapshot: confidenceSnapshot,
            requiresUserAction: requiresUserAction,
            userActionTaken: userActionTaken
        )
    }

    func apply(
        syncDTO dto: AdaptationEventHistorySyncDTO,
        programRun: ProgramRun?,
        trainingProgram: TrainingProgram?,
        analysis: WeeklyTrainingAnalysis?,
        proposal: AdaptationProposal?,
        overlay: AppliedProgramOverlay?
    ) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        syncDeletedAt = dto.metadata.deletedAt
        timestamp = dto.timestamp
        self.programRun = programRun
        self.trainingProgram = trainingProgram
        self.analysis = analysis
        self.proposal = proposal
        self.overlay = overlay
        eventType = AdaptationEventType(rawValue: dto.eventTypeRawValue) ?? .proposalCreated
        analysisWeekNumber = dto.analysisWeekNumber
        targetLiftKey = dto.targetLiftKey
        message = dto.message
        explanation = dto.explanation
        adjustmentReason = dto.adjustmentReasonRawValue.flatMap(AdjustmentReason.init(rawValue:))
        performanceScoreSnapshot = dto.performanceScoreSnapshotRawValue.flatMap(PerformanceScore.init(rawValue:))
        fatigueStatusSnapshot = dto.fatigueStatusSnapshotRawValue.flatMap(FatigueStatus.init(rawValue:))
        liftTrendStatusSnapshot = dto.liftTrendStatusSnapshotRawValue.flatMap(LiftTrendStatus.init(rawValue:))
        confidenceSnapshot = dto.confidenceSnapshot
        requiresUserAction = dto.requiresUserAction
        userActionTaken = dto.userActionTaken
    }
}

extension HealthKitDailySummary {
    func toSyncDTO() -> HealthKitDailySummarySyncDTO {
        initializeSyncMetadataIfNeeded()
        return HealthKitDailySummarySyncDTO(
            metadata: SyncMapperUtilities.metadata(for: self),
            dayStart: dayStart,
            sleepDurationSeconds: sleepDurationSeconds,
            timeInBedSeconds: timeInBedSeconds,
            restingHeartRateBPM: restingHeartRateBPM,
            heartRateVariabilityMS: heartRateVariabilityMS,
            activeEnergyKilocalories: activeEnergyKilocalories,
            stepCount: stepCount,
            bodyMassKilograms: bodyMassKilograms,
            sourceUpdatedAt: sourceUpdatedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func apply(syncDTO dto: HealthKitDailySummarySyncDTO) {
        syncStableID = dto.metadata.stableID
        syncVersion = dto.metadata.version
        syncLastModifiedAt = dto.metadata.lastModifiedAt
        dayStart = dto.dayStart
        sleepDurationSeconds = dto.sleepDurationSeconds
        timeInBedSeconds = dto.timeInBedSeconds
        restingHeartRateBPM = dto.restingHeartRateBPM
        heartRateVariabilityMS = dto.heartRateVariabilityMS
        activeEnergyKilocalories = dto.activeEnergyKilocalories
        stepCount = dto.stepCount
        bodyMassKilograms = dto.bodyMassKilograms
        sourceUpdatedAt = dto.sourceUpdatedAt
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
    }
}
