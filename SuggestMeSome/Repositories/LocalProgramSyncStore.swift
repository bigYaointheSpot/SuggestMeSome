import Foundation
import SwiftData

@MainActor
struct LocalProgramSyncStore {
    let context: LocalSyncStoreContext

    func fetchTrainingProgramPayloads(since: Date?) throws -> [TrainingProgramSyncDTO] {
        let programs = try context.fetchRows(TrainingProgram.self)
        return context.filteredBySince(programs, since: since)
            .sorted { $0.createdDate > $1.createdDate }
            .map { $0.toSyncDTO() }
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
        let runs = try context.fetchRows(ProgramRun.self)
        return context.filteredBySince(runs, since: since)
            .sorted { $0.startDate > $1.startDate }
            .map { $0.toSyncDTO() }
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
}
