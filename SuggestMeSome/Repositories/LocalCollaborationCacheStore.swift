import Foundation
import SwiftData

struct CollaborationCacheSnapshot {
    var relationships: [CoachRelationship]
    var invites: [CoachInvite]
    var assignments: [ProgramAssignment]
    var notes: [CoachNote]
    var notificationPreference: NotificationPreference?
    var deviceRegistration: DevicePushRegistration?
    var insightSnapshots: [InsightSnapshot]
    var weeklyDigests: [WeeklyDigest]
    var blueprints: [SavedProgramBlueprint]
    var programShares: [ProgramShareGrant]
    var progressShares: [ProgressShareCard]
}

struct CollaborationFullRefreshPayload {
    var relationships: [CoachRelationshipDTO]
    var invites: [CoachInviteDTO]
    var assignments: [ProgramAssignmentDTO]
    var notes: [CoachNoteDTO]
    var notificationPreference: NotificationPreferenceDTO?
    var insightSnapshots: [InsightSnapshotDTO]
    var weeklyDigests: [WeeklyDigestDTO]
    var blueprints: [SavedProgramBlueprintDTO]
    var programShares: [ProgramShareGrantDTO]
    var progressShares: [ProgressShareCardDTO]
}

@MainActor
struct LocalCollaborationCacheStore {
    let modelContext: ModelContext
    private let saveHandler: @MainActor () throws -> Void

    init(
        modelContext: ModelContext,
        saveHandler: (@MainActor () throws -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.saveHandler = saveHandler ?? { try modelContext.save() }
    }

    func loadSnapshot() throws -> CollaborationCacheSnapshot {
        let notes = try modelContext.fetch(
            FetchDescriptor(sortBy: [SortDescriptor(\CoachNote.updatedAt, order: .reverse)])
        )

        return CollaborationCacheSnapshot(
            relationships: try modelContext.fetch(
                FetchDescriptor(sortBy: [SortDescriptor(\CoachRelationship.updatedAt, order: .reverse)])
            ),
            invites: try modelContext.fetch(
                FetchDescriptor(sortBy: [SortDescriptor(\CoachInvite.updatedAt, order: .reverse)])
            ),
            assignments: try modelContext.fetch(
                FetchDescriptor(sortBy: [SortDescriptor(\ProgramAssignment.updatedAt, order: .reverse)])
            ),
            notes: notes.sorted { lhs, rhs in
                if lhs.isUnread != rhs.isUnread {
                    return lhs.isUnread && !rhs.isUnread
                }
                return lhs.updatedAt > rhs.updatedAt
            },
            notificationPreference: try modelContext.fetch(FetchDescriptor<NotificationPreference>()).first,
            deviceRegistration: try modelContext.fetch(FetchDescriptor<DevicePushRegistration>()).first,
            insightSnapshots: try modelContext.fetch(
                FetchDescriptor(sortBy: [SortDescriptor(\InsightSnapshot.updatedAt, order: .reverse)])
            ),
            weeklyDigests: try modelContext.fetch(
                FetchDescriptor(sortBy: [SortDescriptor(\WeeklyDigest.updatedAt, order: .reverse)])
            ),
            blueprints: try modelContext.fetch(
                FetchDescriptor(sortBy: [SortDescriptor(\SavedProgramBlueprint.updatedAt, order: .reverse)])
            ),
            programShares: try modelContext.fetch(
                FetchDescriptor(sortBy: [SortDescriptor(\ProgramShareGrant.updatedAt, order: .reverse)])
            ),
            progressShares: try modelContext.fetch(
                FetchDescriptor(sortBy: [SortDescriptor(\ProgressShareCard.updatedAt, order: .reverse)])
            )
        )
    }

    func clearAll() throws {
        try deleteAll(CoachRelationship.self)
        try deleteAll(CoachInvite.self)
        try deleteAll(ProgramAssignment.self)
        try deleteAll(CoachNote.self)
        try deleteAll(NotificationPreference.self)
        try deleteAll(DevicePushRegistration.self)
        try deleteAll(InsightSnapshot.self)
        try deleteAll(WeeklyDigest.self)
        try deleteAll(SavedProgramBlueprint.self)
        try deleteAll(ProgramShareGrant.self)
        try deleteAll(ProgressShareCard.self)
        try persist()
    }

    func replaceAll(with payload: CollaborationFullRefreshPayload) throws {
        try replaceRelationships(
            with: payload.relationships,
            existing: stableIDMap(for: CoachRelationship.self),
            save: false
        )
        try replaceInvites(
            with: payload.invites,
            existing: stableIDMap(for: CoachInvite.self),
            save: false
        )
        try replaceAssignments(
            with: payload.assignments,
            existing: stableIDMap(for: ProgramAssignment.self),
            save: false
        )
        try replaceNotes(
            with: payload.notes,
            existing: stableIDMap(for: CoachNote.self),
            save: false
        )
        try replaceNotificationPreference(with: payload.notificationPreference, save: false)
        try replaceInsightSnapshots(
            with: payload.insightSnapshots,
            existing: stableIDMap(for: InsightSnapshot.self),
            save: false
        )
        try replaceWeeklyDigests(
            with: payload.weeklyDigests,
            existing: stableIDMap(for: WeeklyDigest.self),
            save: false
        )
        try replaceBlueprints(
            with: payload.blueprints,
            existing: stableIDMap(for: SavedProgramBlueprint.self),
            save: false
        )
        try replaceProgramShares(
            with: payload.programShares,
            existing: stableIDMap(for: ProgramShareGrant.self),
            save: false
        )
        try replaceProgressShares(
            with: payload.progressShares,
            existing: stableIDMap(for: ProgressShareCard.self),
            save: false
        )
        try sweepOrphanedDependents(
            livingRelationshipStableIDs: Set(payload.relationships.map(\.stableID))
        )
        try persist()
    }

    /// Delete a relationship and every cached row that referenced it by
    /// string FK, inside one transaction. Used when the coordinator
    /// learns a relationship was removed (revoked invite, account teardown,
    /// remote deletion). Mirrors the cascade behavior we'd get from a full
    /// @Relationship(deleteRule: .cascade) conversion without the schema
    /// reshape.
    func deleteRelationshipCascade(stableID: String) throws {
        let relationshipPredicate = #Predicate<CoachRelationship> { $0.stableID == stableID }
        let relationships = try modelContext.fetch(FetchDescriptor<CoachRelationship>(predicate: relationshipPredicate))
        for relationship in relationships {
            modelContext.delete(relationship)
        }

        try deleteDependents(relationshipStableID: stableID)
        try persist()
    }

    /// After a full refresh, delete dependent rows whose relationshipStableID
    /// is not in the fresh relationship set. Guards against server-side
    /// deletions that don't surface through an explicit revoke path.
    private func sweepOrphanedDependents(livingRelationshipStableIDs: Set<String>) throws {
        try sweepOrphans(
            fetch: FetchDescriptor<CoachInvite>(),
            relationshipStableID: { $0.relationshipStableID },
            living: livingRelationshipStableIDs
        )
        try sweepOrphans(
            fetch: FetchDescriptor<ProgramAssignment>(),
            relationshipStableID: { $0.relationshipStableID },
            living: livingRelationshipStableIDs
        )
        try sweepOrphans(
            fetch: FetchDescriptor<CoachNote>(),
            relationshipStableID: { $0.relationshipStableID },
            living: livingRelationshipStableIDs
        )
        try sweepOrphans(
            fetch: FetchDescriptor<InsightSnapshot>(),
            relationshipStableID: { $0.relationshipStableID },
            living: livingRelationshipStableIDs
        )
        try sweepOrphans(
            fetch: FetchDescriptor<WeeklyDigest>(),
            relationshipStableID: { $0.relationshipStableID },
            living: livingRelationshipStableIDs
        )
        try sweepOrphans(
            fetch: FetchDescriptor<ProgramShareGrant>(),
            relationshipStableID: { $0.relationshipStableID },
            living: livingRelationshipStableIDs
        )
        try sweepOrphans(
            fetch: FetchDescriptor<ProgressShareCard>(),
            relationshipStableID: { $0.relationshipStableID },
            living: livingRelationshipStableIDs
        )
    }

    private func deleteDependents(relationshipStableID: String) throws {
        let invites = try modelContext.fetch(FetchDescriptor<CoachInvite>(
            predicate: #Predicate { $0.relationshipStableID == relationshipStableID }
        ))
        for invite in invites { modelContext.delete(invite) }

        let assignments = try modelContext.fetch(FetchDescriptor<ProgramAssignment>(
            predicate: #Predicate { $0.relationshipStableID == relationshipStableID }
        ))
        for assignment in assignments { modelContext.delete(assignment) }

        let notes = try modelContext.fetch(FetchDescriptor<CoachNote>(
            predicate: #Predicate { $0.relationshipStableID == relationshipStableID }
        ))
        for note in notes { modelContext.delete(note) }

        let insights = try modelContext.fetch(FetchDescriptor<InsightSnapshot>(
            predicate: #Predicate { $0.relationshipStableID == relationshipStableID }
        ))
        for insight in insights { modelContext.delete(insight) }

        let digests = try modelContext.fetch(FetchDescriptor<WeeklyDigest>(
            predicate: #Predicate { $0.relationshipStableID == relationshipStableID }
        ))
        for digest in digests { modelContext.delete(digest) }

        let programShares = try modelContext.fetch(FetchDescriptor<ProgramShareGrant>(
            predicate: #Predicate { $0.relationshipStableID == relationshipStableID }
        ))
        for share in programShares { modelContext.delete(share) }

        let progressShares = try modelContext.fetch(FetchDescriptor<ProgressShareCard>(
            predicate: #Predicate { $0.relationshipStableID == relationshipStableID }
        ))
        for share in progressShares { modelContext.delete(share) }
    }

    private func sweepOrphans<Model: PersistentModel>(
        fetch: FetchDescriptor<Model>,
        relationshipStableID: (Model) -> String?,
        living: Set<String>
    ) throws {
        let rows = try modelContext.fetch(fetch)
        for row in rows {
            guard let parentStableID = relationshipStableID(row) else { continue }
            if !living.contains(parentStableID) {
                modelContext.delete(row)
            }
        }
    }

    func replaceRelationships(with dtos: [CoachRelationshipDTO]) throws {
        try replaceRelationships(
            with: dtos,
            existing: stableIDMap(for: CoachRelationship.self),
            save: true
        )
    }

    func replaceInvites(with dtos: [CoachInviteDTO]) throws {
        try replaceInvites(
            with: dtos,
            existing: stableIDMap(for: CoachInvite.self),
            save: true
        )
    }

    func replaceAssignments(with dtos: [ProgramAssignmentDTO]) throws {
        try replaceAssignments(
            with: dtos,
            existing: stableIDMap(for: ProgramAssignment.self),
            save: true
        )
    }

    func replaceNotes(with dtos: [CoachNoteDTO]) throws {
        try replaceNotes(
            with: dtos,
            existing: stableIDMap(for: CoachNote.self),
            save: true
        )
    }

    func replaceNotificationPreference(with dto: NotificationPreferenceDTO?) throws {
        try replaceNotificationPreference(with: dto, save: true)
    }

    func replaceDeviceRegistration(with dto: DevicePushRegistrationDTO?) throws {
        try replaceDeviceRegistration(with: dto, save: true)
    }

    func replaceInsightSnapshots(with dtos: [InsightSnapshotDTO]) throws {
        try replaceInsightSnapshots(
            with: dtos,
            existing: stableIDMap(for: InsightSnapshot.self),
            save: true
        )
    }

    func replaceWeeklyDigests(with dtos: [WeeklyDigestDTO]) throws {
        try replaceWeeklyDigests(
            with: dtos,
            existing: stableIDMap(for: WeeklyDigest.self),
            save: true
        )
    }

    func replaceBlueprints(with dtos: [SavedProgramBlueprintDTO]) throws {
        try replaceBlueprints(
            with: dtos,
            existing: stableIDMap(for: SavedProgramBlueprint.self),
            save: true
        )
    }

    func replaceProgramShares(with dtos: [ProgramShareGrantDTO]) throws {
        try replaceProgramShares(
            with: dtos,
            existing: stableIDMap(for: ProgramShareGrant.self),
            save: true
        )
    }

    func replaceProgressShares(with dtos: [ProgressShareCardDTO]) throws {
        try replaceProgressShares(
            with: dtos,
            existing: stableIDMap(for: ProgressShareCard.self),
            save: true
        )
    }

    private func replaceRelationships(
        with dtos: [CoachRelationshipDTO],
        existing: [String: CoachRelationship],
        save: Bool
    ) throws {
        try replaceCachedModels(
            dtos,
            existing: existing,
            stableID: \.stableID,
            create: { dto in
                let relationship = CoachRelationship(
                    stableID: dto.stableID,
                    statusRawValue: dto.statusRawValue,
                    coachAccountID: dto.coachAccountID,
                    coachDisplayName: dto.coachDisplayName,
                    athleteAccountID: dto.athleteAccountID,
                    athleteDisplayName: dto.athleteDisplayName,
                    visibilityScopeBitmask: dto.visibilityScopeBitmask
                )
                apply(dto, to: relationship)
                return relationship
            },
            applyDTO: apply,
            save: save
        )
    }

    private func replaceInvites(
        with dtos: [CoachInviteDTO],
        existing: [String: CoachInvite],
        save: Bool
    ) throws {
        try replaceCachedModels(
            dtos,
            existing: existing,
            stableID: \.stableID,
            create: { dto in
                let invite = CoachInvite(
                    stableID: dto.stableID,
                    statusRawValue: dto.statusRawValue,
                    inviterAccountID: dto.inviterAccountID,
                    inviterDisplayName: dto.inviterDisplayName,
                    inviterRoleRawValue: dto.inviterRoleRawValue,
                    inviteeEmail: dto.inviteeEmail,
                    visibilityScopeBitmask: dto.visibilityScopeBitmask
                )
                apply(dto, to: invite)
                return invite
            },
            applyDTO: apply,
            save: save
        )
    }

    private func replaceAssignments(
        with dtos: [ProgramAssignmentDTO],
        existing: [String: ProgramAssignment],
        save: Bool
    ) throws {
        try replaceCachedModels(
            dtos,
            existing: existing,
            stableID: \.stableID,
            create: { dto in
                let assignment = ProgramAssignment(
                    stableID: dto.stableID,
                    relationshipStableID: dto.relationshipStableID,
                    blueprintStableID: dto.blueprintStableID,
                    coachAccountID: dto.coachAccountID,
                    coachDisplayName: dto.coachDisplayName,
                    athleteAccountID: dto.athleteAccountID,
                    athleteDisplayName: dto.athleteDisplayName,
                    statusRawValue: dto.statusRawValue
                )
                apply(dto, to: assignment)
                return assignment
            },
            applyDTO: apply,
            save: save
        )
    }

    private func replaceNotes(
        with dtos: [CoachNoteDTO],
        existing: [String: CoachNote],
        save: Bool
    ) throws {
        try replaceCachedModels(
            dtos,
            existing: existing,
            stableID: \.stableID,
            create: { dto in
                let note = CoachNote(
                    stableID: dto.stableID,
                    relationshipStableID: dto.relationshipStableID,
                    authorAccountID: dto.authorAccountID,
                    authorDisplayName: dto.authorDisplayName,
                    recipientAccountID: dto.recipientAccountID,
                    recipientDisplayName: dto.recipientDisplayName,
                    bodyText: dto.bodyText,
                    anchorKindRawValue: dto.anchorKindRawValue
                )
                apply(dto, to: note)
                return note
            },
            applyDTO: apply,
            save: save
        )
    }

    private func replaceNotificationPreference(
        with dto: NotificationPreferenceDTO?,
        save: Bool
    ) throws {
        let existing = try modelContext.fetch(FetchDescriptor<NotificationPreference>())
        if let dto {
            let preference = existing.first ?? NotificationPreference(stableID: dto.stableID)
            apply(dto, to: preference)
            if existing.isEmpty {
                modelContext.insert(preference)
            }
        } else {
            for preference in existing {
                modelContext.delete(preference)
            }
        }
        if save {
            try persist()
        }
    }

    private func replaceDeviceRegistration(
        with dto: DevicePushRegistrationDTO?,
        save: Bool
    ) throws {
        let existing = try modelContext.fetch(FetchDescriptor<DevicePushRegistration>())
        if let dto {
            let registration = existing.first ?? DevicePushRegistration(
                stableID: dto.stableID,
                deviceID: dto.deviceID,
                authorizationStatusRawValue: dto.authorizationStatusRawValue
            )
            apply(dto, to: registration)
            if existing.isEmpty {
                modelContext.insert(registration)
            }
        } else {
            for registration in existing {
                modelContext.delete(registration)
            }
        }
        if save {
            try persist()
        }
    }

    private func replaceInsightSnapshots(
        with dtos: [InsightSnapshotDTO],
        existing: [String: InsightSnapshot],
        save: Bool
    ) throws {
        try replaceCachedModels(
            dtos,
            existing: existing,
            stableID: \.stableID,
            create: { dto in
                let snapshot = InsightSnapshot(
                    stableID: dto.stableID,
                    accountID: dto.accountID,
                    accountDisplayName: dto.accountDisplayName,
                    headline: dto.headline,
                    summaryText: dto.summaryText
                )
                apply(dto, to: snapshot)
                return snapshot
            },
            applyDTO: apply,
            save: save
        )
    }

    private func replaceWeeklyDigests(
        with dtos: [WeeklyDigestDTO],
        existing: [String: WeeklyDigest],
        save: Bool
    ) throws {
        try replaceCachedModels(
            dtos,
            existing: existing,
            stableID: \.stableID,
            create: { dto in
                let digest = WeeklyDigest(
                    stableID: dto.stableID,
                    weekStart: dto.weekStart,
                    weekEnd: dto.weekEnd,
                    audienceRawValue: dto.audienceRawValue,
                    accountID: dto.accountID,
                    titleText: dto.titleText,
                    summaryText: dto.summaryText
                )
                apply(dto, to: digest)
                return digest
            },
            applyDTO: apply,
            save: save
        )
    }

    private func replaceBlueprints(
        with dtos: [SavedProgramBlueprintDTO],
        existing: [String: SavedProgramBlueprint],
        save: Bool
    ) throws {
        try replaceCachedModels(
            dtos,
            existing: existing,
            stableID: \.stableID,
            create: { dto in
                let blueprint = SavedProgramBlueprint(
                    stableID: dto.stableID,
                    name: dto.name,
                    durationWeeks: dto.durationWeeks,
                    sessionsPerWeek: dto.sessionsPerWeek,
                    trainingProgramSnapshotJSON: dto.trainingProgramSnapshotJSON
                )
                apply(dto, to: blueprint)
                return blueprint
            },
            applyDTO: apply,
            save: save
        )
    }

    private func replaceProgramShares(
        with dtos: [ProgramShareGrantDTO],
        existing: [String: ProgramShareGrant],
        save: Bool
    ) throws {
        try replaceCachedModels(
            dtos,
            existing: existing,
            stableID: \.stableID,
            create: { dto in
                let share = ProgramShareGrant(
                    stableID: dto.stableID,
                    shareKindRawValue: dto.shareKindRawValue,
                    statusRawValue: dto.statusRawValue,
                    grantedByAccountID: dto.grantedByAccountID,
                    grantedByDisplayName: dto.grantedByDisplayName,
                    grantedToAccountID: dto.grantedToAccountID,
                    grantedToDisplayName: dto.grantedToDisplayName
                )
                apply(dto, to: share)
                return share
            },
            applyDTO: apply,
            save: save
        )
    }

    private func replaceProgressShares(
        with dtos: [ProgressShareCardDTO],
        existing: [String: ProgressShareCard],
        save: Bool
    ) throws {
        try replaceCachedModels(
            dtos,
            existing: existing,
            stableID: \.stableID,
            create: { dto in
                let share = ProgressShareCard(
                    stableID: dto.stableID,
                    shareKindRawValue: dto.shareKindRawValue,
                    statusRawValue: dto.statusRawValue,
                    grantedByAccountID: dto.grantedByAccountID,
                    grantedByDisplayName: dto.grantedByDisplayName,
                    grantedToAccountID: dto.grantedToAccountID,
                    grantedToDisplayName: dto.grantedToDisplayName,
                    titleText: dto.titleText,
                    summaryText: dto.summaryText,
                    payloadJSON: dto.payloadJSON
                )
                apply(dto, to: share)
                return share
            },
            applyDTO: apply,
            save: save
        )
    }

    private func deleteAll<Model: PersistentModel>(_ type: Model.Type) throws {
        let models = try modelContext.fetch(FetchDescriptor<Model>())
        for model in models {
            modelContext.delete(model)
        }
    }

    private func stableIDMap<Model: CollaborationCachedModel>(
        for type: Model.Type
    ) throws -> [String: Model] {
        Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<Model>()).map {
            ($0.stableID, $0)
        })
    }

    private func deleteMissing<Model: CollaborationCachedModel>(
        _ existing: [String: Model],
        keepStableIDs: Set<String>
    ) {
        for (stableID, model) in existing where !keepStableIDs.contains(stableID) {
            modelContext.delete(model)
        }
    }

    private func replaceCachedModels<Model: CollaborationCachedModel, DTO>(
        _ dtos: [DTO],
        existing: [String: Model],
        stableID: (DTO) -> String,
        create: (DTO) -> Model,
        applyDTO: (DTO, Model) -> Void,
        save: Bool
    ) throws {
        let keep = Set(dtos.map(stableID))

        for dto in dtos {
            if let model = existing[stableID(dto)] {
                applyDTO(dto, model)
            } else {
                let model = create(dto)
                modelContext.insert(model)
            }
        }

        deleteMissing(existing, keepStableIDs: keep)
        if save {
            try persist()
        }
    }

    private func persist() throws {
        try saveHandler()
    }

    private func apply(_ dto: CoachRelationshipDTO, to model: CoachRelationship) {
        model.stableID = dto.stableID
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
        model.statusRawValue = dto.statusRawValue
        model.coachAccountID = dto.coachAccountID
        model.coachDisplayName = dto.coachDisplayName
        model.athleteAccountID = dto.athleteAccountID
        model.athleteDisplayName = dto.athleteDisplayName
        model.invitedByAccountID = dto.invitedByAccountID
        model.visibilityScopeBitmask = dto.visibilityScopeBitmask
        model.unreadCoachNoteCount = dto.unreadCoachNoteCount
        model.pendingAssignmentCount = dto.pendingAssignmentCount
        model.latestInsightSnapshotAt = dto.latestInsightSnapshotAt
    }

    private func apply(_ dto: CoachInviteDTO, to model: CoachInvite) {
        model.stableID = dto.stableID
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
        model.expiresAt = dto.expiresAt
        model.statusRawValue = dto.statusRawValue
        model.inviterAccountID = dto.inviterAccountID
        model.inviterDisplayName = dto.inviterDisplayName
        model.inviterRoleRawValue = dto.inviterRoleRawValue
        model.inviteeAccountID = dto.inviteeAccountID
        model.inviteeEmail = dto.inviteeEmail
        model.inviteeDisplayName = dto.inviteeDisplayName
        model.relationshipStableID = dto.relationshipStableID
        model.visibilityScopeBitmask = dto.visibilityScopeBitmask
        model.noteText = dto.noteText
    }

    private func apply(_ dto: ProgramAssignmentDTO, to model: ProgramAssignment) {
        model.stableID = dto.stableID
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
        model.relationshipStableID = dto.relationshipStableID
        model.blueprintStableID = dto.blueprintStableID
        model.coachAccountID = dto.coachAccountID
        model.coachDisplayName = dto.coachDisplayName
        model.athleteAccountID = dto.athleteAccountID
        model.athleteDisplayName = dto.athleteDisplayName
        model.statusRawValue = dto.statusRawValue
        model.notesText = dto.notesText
        model.startGuidance = dto.startGuidance
        model.importedTrainingProgramStableID = dto.importedTrainingProgramStableID
        model.importedProgramRunStableID = dto.importedProgramRunStableID
        model.respondedAt = dto.respondedAt
        model.archivedAt = dto.archivedAt
    }

    private func apply(_ dto: CoachNoteDTO, to model: CoachNote) {
        model.stableID = dto.stableID
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
        model.relationshipStableID = dto.relationshipStableID
        model.authorAccountID = dto.authorAccountID
        model.authorDisplayName = dto.authorDisplayName
        model.recipientAccountID = dto.recipientAccountID
        model.recipientDisplayName = dto.recipientDisplayName
        model.bodyText = dto.bodyText
        model.anchorKindRawValue = dto.anchorKindRawValue
        model.anchoredWorkoutStableID = dto.anchoredWorkoutStableID
        model.anchoredProgramRunStableID = dto.anchoredProgramRunStableID
        model.anchoredWeekStart = dto.anchoredWeekStart
        model.anchoredWeekEnd = dto.anchoredWeekEnd
        model.eventSummaryText = dto.eventSummaryText
        model.priorityRawValue = dto.priorityRawValue
        model.isUnread = dto.isUnread
        model.requiresReview = dto.requiresReview
    }

    private func apply(_ dto: NotificationPreferenceDTO, to model: NotificationPreference) {
        model.stableID = dto.stableID
        model.updatedAt = dto.updatedAt
        model.coachInvitesEnabled = dto.coachInvitesEnabled
        model.assignmentUpdatesEnabled = dto.assignmentUpdatesEnabled
        model.coachNotesEnabled = dto.coachNotesEnabled
        model.missedSessionNudgesEnabled = dto.missedSessionNudgesEnabled
        model.checkInRemindersEnabled = dto.checkInRemindersEnabled
        model.pendingProposalRemindersEnabled = dto.pendingProposalRemindersEnabled
        model.weeklyDigestsEnabled = dto.weeklyDigestsEnabled
    }

    private func apply(_ dto: DevicePushRegistrationDTO, to model: DevicePushRegistration) {
        model.stableID = dto.stableID
        model.updatedAt = dto.updatedAt
        model.deviceID = dto.deviceID
        model.pushToken = dto.pushToken
        model.authorizationStatusRawValue = dto.authorizationStatusRawValue
        model.lastRegisteredAt = dto.lastRegisteredAt
        model.lastErrorMessage = dto.lastErrorMessage
    }

    private func apply(_ dto: InsightSnapshotDTO, to model: InsightSnapshot) {
        model.stableID = dto.stableID
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
        model.relationshipStableID = dto.relationshipStableID
        model.accountID = dto.accountID
        model.accountDisplayName = dto.accountDisplayName
        model.activeProgramName = dto.activeProgramName
        model.syncFreshnessAt = dto.syncFreshnessAt
        model.lastWorkoutAt = dto.lastWorkoutAt
        model.recentAdherenceScore = dto.recentAdherenceScore
        model.fatigueStatusRawValue = dto.fatigueStatusRawValue
        model.pendingProposalCount = dto.pendingProposalCount
        model.unreadCoachNoteCount = dto.unreadCoachNoteCount
        model.prMomentumSummary = dto.prMomentumSummary
        model.liftTrendSummary = dto.liftTrendSummary
        model.fatigueRunwaySummary = dto.fatigueRunwaySummary
        model.completionRiskSummary = dto.completionRiskSummary
        model.reviewPriorityText = dto.reviewPriorityText
        model.headline = dto.headline
        model.summaryText = dto.summaryText
        model.detailText = dto.detailText
        model.priorityRawValue = dto.priorityRawValue
    }

    private func apply(_ dto: WeeklyDigestDTO, to model: WeeklyDigest) {
        model.stableID = dto.stableID
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
        model.weekStart = dto.weekStart
        model.weekEnd = dto.weekEnd
        model.audienceRawValue = dto.audienceRawValue
        model.relationshipStableID = dto.relationshipStableID
        model.accountID = dto.accountID
        model.titleText = dto.titleText
        model.summaryText = dto.summaryText
        model.highlightsText = dto.highlightsText
        model.reviewPrioritiesText = dto.reviewPrioritiesText
        model.isUnread = dto.isUnread
    }

    private func apply(_ dto: SavedProgramBlueprintDTO, to model: SavedProgramBlueprint) {
        model.stableID = dto.stableID
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
        model.name = dto.name
        model.focusText = dto.focusText
        model.notesText = dto.notesText
        model.tagsCSV = CSVListCodec.encode(dto.tags)
        model.durationWeeks = dto.durationWeeks
        model.sessionsPerWeek = dto.sessionsPerWeek
        model.sourceProgramStableID = dto.sourceProgramStableID
        model.createdByAccountID = dto.createdByAccountID
        model.createdByDisplayName = dto.createdByDisplayName
        model.trainingProgramSnapshotJSON = dto.trainingProgramSnapshotJSON
        model.lastSharedAt = dto.lastSharedAt
    }

    private func apply(_ dto: ProgramShareGrantDTO, to model: ProgramShareGrant) {
        model.stableID = dto.stableID
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
        model.relationshipStableID = dto.relationshipStableID
        model.shareKindRawValue = dto.shareKindRawValue
        model.statusRawValue = dto.statusRawValue
        model.blueprintStableID = dto.blueprintStableID
        model.sourceProgramStableID = dto.sourceProgramStableID
        model.grantedByAccountID = dto.grantedByAccountID
        model.grantedByDisplayName = dto.grantedByDisplayName
        model.grantedToAccountID = dto.grantedToAccountID
        model.grantedToDisplayName = dto.grantedToDisplayName
        model.messageText = dto.messageText
    }

    private func apply(_ dto: ProgressShareCardDTO, to model: ProgressShareCard) {
        model.stableID = dto.stableID
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
        model.relationshipStableID = dto.relationshipStableID
        model.shareKindRawValue = dto.shareKindRawValue
        model.statusRawValue = dto.statusRawValue
        model.grantedByAccountID = dto.grantedByAccountID
        model.grantedByDisplayName = dto.grantedByDisplayName
        model.grantedToAccountID = dto.grantedToAccountID
        model.grantedToDisplayName = dto.grantedToDisplayName
        model.titleText = dto.titleText
        model.subtitleText = dto.subtitleText
        model.summaryText = dto.summaryText
        model.payloadJSON = dto.payloadJSON
    }
}

private protocol CollaborationCachedModel: PersistentModel {
    var stableID: String { get set }
}

extension CoachRelationship: CollaborationCachedModel {}
extension CoachInvite: CollaborationCachedModel {}
extension ProgramAssignment: CollaborationCachedModel {}
extension CoachNote: CollaborationCachedModel {}
extension InsightSnapshot: CollaborationCachedModel {}
extension WeeklyDigest: CollaborationCachedModel {}
extension SavedProgramBlueprint: CollaborationCachedModel {}
extension ProgramShareGrant: CollaborationCachedModel {}
extension ProgressShareCard: CollaborationCachedModel {}
