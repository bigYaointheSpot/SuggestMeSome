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
            if let model = existing[payload.metadata.stableID] {
                model.apply(syncDTO: payload)
            } else {
                let model = TrainingProgram(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
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
            let program = payload.trainingProgramStableID.flatMap { programs[$0] }
            if let existing = runs[payload.metadata.stableID] {
                existing.apply(syncDTO: payload, program: program)
            } else {
                let run = ProgramRun(
                    id: UUID(uuidString: payload.metadata.stableID) ?? UUID(),
                    syncStableID: payload.metadata.stableID,
                    syncVersion: payload.metadata.version,
                    syncLastModifiedAt: payload.metadata.lastModifiedAt,
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
            return FetchDescriptor<TrainingProgram>(sortBy: sortBy)
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
            return FetchDescriptor<ProgramRun>(sortBy: sortBy)
        }
        return FetchDescriptor<ProgramRun>(
            predicate: #Predicate<ProgramRun> { run in
                run.syncLastModifiedAt >= sinceDate
            },
            sortBy: sortBy
        )
    }
}
