import Foundation
import SwiftData

@MainActor
struct LocalProgramSyncStore {
    let context: LocalSyncStoreContext

    func fetchTrainingProgramPayloads(since: Date?) throws -> [TrainingProgramSyncDTO] {
        try context.measureSyncExport(named: "TrainingProgram", since: since) {
            try context.fetchRows(trainingProgramFetchDescriptor(since: since))
                .map { $0.toSyncDTO() }
        }
    }

    func upsertTrainingProgramPayloads(_ payloads: [TrainingProgramSyncDTO]) throws {
        guard !payloads.isEmpty else { return }

        var existing = try context.stableIDMap(for: TrainingProgram.self)
        for payload in payloads {
            if payload.metadata.deletedAt != nil {
                if let model = existing[payload.metadata.stableID] {
                    context.modelContext.delete(model)
                    existing[payload.metadata.stableID] = nil
                }
                continue
            }

            if let model = existing[payload.metadata.stableID] {
                model.apply(syncDTO: payload)
                rebuildProgramStructure(for: model, prescriptions: payload.prescriptions)
            } else {
                let model = TrainingProgram(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    syncDeletedAt: payload.metadata.deletedAt,
                    name: payload.name,
                    lengthInWeeks: payload.lengthInWeeks,
                    sessionsPerWeek: payload.sessionsPerWeek,
                    createdDate: payload.createdDate,
                    source: ProgramSource(rawValue: payload.sourceRawValue) ?? .userCreated,
                    descriptionText: payload.descriptionText,
                    progressionModel: payload.progressionModelRawValue.flatMap(ProgramProgressionModel.init(rawValue:)),
                    usedLiftMapping: payload.usedLiftMapping,
                    usedVolumeBalancing: payload.usedVolumeBalancing,
                    usedFatigueBalancing: payload.usedFatigueBalancing,
                    usedTopSetBackoff: payload.usedTopSetBackoff
                )
                context.modelContext.insert(model)
                rebuildProgramStructure(for: model, prescriptions: payload.prescriptions)
                existing[payload.metadata.stableID] = model
            }
        }

        try context.save()
    }

    func fetchProgramRunPayloads(since: Date?) throws -> [ProgramRunSyncDTO] {
        try context.measureSyncExport(named: "ProgramRun", since: since) {
            try context.fetchRows(programRunFetchDescriptor(since: since))
                .map { $0.toSyncDTO() }
        }
    }

    func upsertProgramRunPayloads(_ payloads: [ProgramRunSyncDTO]) throws {
        guard !payloads.isEmpty else { return }

        var runs = try context.stableIDMap(for: ProgramRun.self)
        let programs = try context.stableIDMap(for: TrainingProgram.self)

        for payload in payloads {
            if payload.metadata.deletedAt != nil {
                if let existing = runs[payload.metadata.stableID] {
                    context.modelContext.delete(existing)
                    runs[payload.metadata.stableID] = nil
                }
                continue
            }

            let program = payload.trainingProgramStableID.flatMap { programs[$0] }
            if let existing = runs[payload.metadata.stableID] {
                existing.apply(syncDTO: payload, program: program)
            } else {
                let run = ProgramRun(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
                    syncDeletedAt: payload.metadata.deletedAt,
                    startDate: payload.startDate,
                    endDate: payload.endDate,
                    isCompleted: payload.isCompleted,
                    previousProgramRunStableID: payload.previousProgramRunStableID,
                    recommendationDecisionHistoryJSON: payload.recommendationDecisionHistoryJSON,
                    continuitySnapshotJSON: payload.continuitySnapshotJSON
                )
                run.program = program
                context.modelContext.insert(run)
                runs[payload.metadata.stableID] = run
            }
        }

        try context.save()
    }

    private func trainingProgramFetchDescriptor(since: Date?) -> FetchDescriptor<TrainingProgram> {
        let sortBy = [SortDescriptor(\TrainingProgram.createdDate, order: .reverse)]
        guard let sinceDate = since else {
            return FetchDescriptor<TrainingProgram>(
                predicate: #Predicate<TrainingProgram> { program in
                    program.syncDeletedAt == nil
                },
                sortBy: sortBy
            )
        }
        return FetchDescriptor<TrainingProgram>(
            predicate: #Predicate<TrainingProgram> { program in
                program.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }

    private func programRunFetchDescriptor(since: Date?) -> FetchDescriptor<ProgramRun> {
        let sortBy = [SortDescriptor(\ProgramRun.startDate, order: .reverse)]
        guard let sinceDate = since else {
            return FetchDescriptor<ProgramRun>(
                predicate: #Predicate<ProgramRun> { run in
                    run.syncDeletedAt == nil
                },
                sortBy: sortBy
            )
        }
        return FetchDescriptor<ProgramRun>(
            predicate: #Predicate<ProgramRun> { run in
                run.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }

    private func rebuildProgramStructure(
        for program: TrainingProgram,
        prescriptions: [ProgramPrescriptionExerciseSyncDTO]
    ) {
        for week in program.weeks {
            context.modelContext.delete(week)
        }
        program.weeks.removeAll()

        let exercisesByWeek = Dictionary(grouping: prescriptions, by: \.weekNumber)

        for weekNumber in 1...max(1, program.lengthInWeeks) {
            let week = ProgramWeekTemplate(weekNumber: weekNumber)
            week.program = program
            context.modelContext.insert(week)

            let exercisesBySession = Dictionary(
                grouping: exercisesByWeek[weekNumber] ?? [],
                by: \.sessionNumber
            )

            for sessionNumber in 1...max(1, program.sessionsPerWeek) {
                let session = ProgramSessionTemplate(sessionNumber: sessionNumber)
                session.week = week
                context.modelContext.insert(session)

                let sessionExercises = (exercisesBySession[sessionNumber] ?? [])
                    .sorted { $0.orderIndex < $1.orderIndex }

                for exercisePayload in sessionExercises {
                    let exercise = ProgramSessionExercise(
                        id: UUID(uuidString: exercisePayload.metadata.stableID) ?? UUID(),
                        syncStableID: exercisePayload.metadata.stableID,
                        syncVersion: exercisePayload.metadata.version,
                        syncLastModifiedAt: exercisePayload.metadata.lastModifiedAt,
                        exerciseName: exercisePayload.exerciseName,
                        orderIndex: exercisePayload.orderIndex,
                        targetSets: exercisePayload.targetSets,
                        targetReps: exercisePayload.targetReps,
                        targetPercentage1RM: exercisePayload.targetPercentage1RM,
                        targetRPE: exercisePayload.targetRPE,
                        targetRIR: exercisePayload.targetRIR,
                        isWarmup: exercisePayload.isWarmup,
                        prescribedWeight: exercisePayload.prescribedWeight,
                        prescribedWeightUnit: exercisePayload.prescribedWeightUnit,
                        workingSetStyle: exercisePayload.workingSetStyleRawValue.flatMap(ProgramWorkingSetStyle.init(rawValue:)),
                        backoffPercentageDrop: exercisePayload.backoffPercentageDrop,
                        targetEffortType: exercisePayload.targetEffortTypeRawValue.flatMap(ProgramTargetEffortType.init(rawValue:)),
                        baseLiftUsed: exercisePayload.baseLiftUsed,
                        effectiveOneRepMax: exercisePayload.effectiveOneRepMax,
                        effectiveOneRepMaxUnit: exercisePayload.effectiveOneRepMaxUnit,
                        usedMappedSourceLift: exercisePayload.usedMappedSourceLift,
                        progressionPhase: exercisePayload.progressionPhaseRawValue.flatMap(ProgramProgressionPhase.init(rawValue:)),
                        estimatedFatigueScore: exercisePayload.estimatedFatigueScore,
                        topBackoffGroupID: exercisePayload.topBackoffGroupID,
                        explainabilityPurpose: exercisePayload.explainabilityPurposeRawValue.flatMap(ProgramExercisePurposeCode.init(rawValue:)),
                        explainabilitySelectionReason: exercisePayload.explainabilitySelectionReasonRawValue.flatMap(ProgramAccessorySelectionReason.init(rawValue:))
                    )
                    exercise.session = session
                    context.modelContext.insert(exercise)
                }
            }
        }
    }
}
