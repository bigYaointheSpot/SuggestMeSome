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

@MainActor
struct LocalCollaborationCacheStore {
    let modelContext: ModelContext

    func loadSnapshot() throws -> CollaborationCacheSnapshot {
        CollaborationCacheSnapshot(
            relationships: try modelContext.fetch(FetchDescriptor<CoachRelationship>())
                .sorted { $0.updatedAt > $1.updatedAt },
            invites: try modelContext.fetch(FetchDescriptor<CoachInvite>())
                .sorted { $0.updatedAt > $1.updatedAt },
            assignments: try modelContext.fetch(FetchDescriptor<ProgramAssignment>())
                .sorted { $0.updatedAt > $1.updatedAt },
            notes: try modelContext.fetch(FetchDescriptor<CoachNote>())
                .sorted { lhs, rhs in
                    if lhs.isUnread != rhs.isUnread {
                        return lhs.isUnread && !rhs.isUnread
                    }
                    return lhs.updatedAt > rhs.updatedAt
                },
            notificationPreference: try modelContext.fetch(FetchDescriptor<NotificationPreference>()).first,
            deviceRegistration: try modelContext.fetch(FetchDescriptor<DevicePushRegistration>()).first,
            insightSnapshots: try modelContext.fetch(FetchDescriptor<InsightSnapshot>())
                .sorted { $0.updatedAt > $1.updatedAt },
            weeklyDigests: try modelContext.fetch(FetchDescriptor<WeeklyDigest>())
                .sorted { $0.updatedAt > $1.updatedAt },
            blueprints: try modelContext.fetch(FetchDescriptor<SavedProgramBlueprint>())
                .sorted { $0.updatedAt > $1.updatedAt },
            programShares: try modelContext.fetch(FetchDescriptor<ProgramShareGrant>())
                .sorted { $0.updatedAt > $1.updatedAt },
            progressShares: try modelContext.fetch(FetchDescriptor<ProgressShareCard>())
                .sorted { $0.updatedAt > $1.updatedAt }
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
        try modelContext.save()
    }

    func replaceRelationships(with dtos: [CoachRelationshipDTO]) throws {
        let existing = try stableIDMap(for: CoachRelationship.self)
        let keep = Set(dtos.map(\.stableID))

        for dto in dtos {
            if let relationship = existing[dto.stableID] {
                apply(dto, to: relationship)
            } else {
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
                modelContext.insert(relationship)
            }
        }

        deleteMissing(existing, keepStableIDs: keep)
        try modelContext.save()
    }

    func replaceInvites(with dtos: [CoachInviteDTO]) throws {
        let existing = try stableIDMap(for: CoachInvite.self)
        let keep = Set(dtos.map(\.stableID))

        for dto in dtos {
            if let invite = existing[dto.stableID] {
                apply(dto, to: invite)
            } else {
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
                modelContext.insert(invite)
            }
        }

        deleteMissing(existing, keepStableIDs: keep)
        try modelContext.save()
    }

    func replaceAssignments(with dtos: [ProgramAssignmentDTO]) throws {
        let existing = try stableIDMap(for: ProgramAssignment.self)
        let keep = Set(dtos.map(\.stableID))

        for dto in dtos {
            if let assignment = existing[dto.stableID] {
                apply(dto, to: assignment)
            } else {
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
                modelContext.insert(assignment)
            }
        }

        deleteMissing(existing, keepStableIDs: keep)
        try modelContext.save()
    }

    func replaceNotes(with dtos: [CoachNoteDTO]) throws {
        let existing = try stableIDMap(for: CoachNote.self)
        let keep = Set(dtos.map(\.stableID))

        for dto in dtos {
            if let note = existing[dto.stableID] {
                apply(dto, to: note)
            } else {
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
                modelContext.insert(note)
            }
        }

        deleteMissing(existing, keepStableIDs: keep)
        try modelContext.save()
    }

    func replaceNotificationPreference(with dto: NotificationPreferenceDTO?) throws {
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
        try modelContext.save()
    }

    func replaceDeviceRegistration(with dto: DevicePushRegistrationDTO?) throws {
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
        try modelContext.save()
    }

    func replaceInsightSnapshots(with dtos: [InsightSnapshotDTO]) throws {
        let existing = try stableIDMap(for: InsightSnapshot.self)
        let keep = Set(dtos.map(\.stableID))

        for dto in dtos {
            if let snapshot = existing[dto.stableID] {
                apply(dto, to: snapshot)
            } else {
                let snapshot = InsightSnapshot(
                    stableID: dto.stableID,
                    accountID: dto.accountID,
                    accountDisplayName: dto.accountDisplayName,
                    headline: dto.headline,
                    summaryText: dto.summaryText
                )
                apply(dto, to: snapshot)
                modelContext.insert(snapshot)
            }
        }

        deleteMissing(existing, keepStableIDs: keep)
        try modelContext.save()
    }

    func replaceWeeklyDigests(with dtos: [WeeklyDigestDTO]) throws {
        let existing = try stableIDMap(for: WeeklyDigest.self)
        let keep = Set(dtos.map(\.stableID))

        for dto in dtos {
            if let digest = existing[dto.stableID] {
                apply(dto, to: digest)
            } else {
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
                modelContext.insert(digest)
            }
        }

        deleteMissing(existing, keepStableIDs: keep)
        try modelContext.save()
    }

    func replaceBlueprints(with dtos: [SavedProgramBlueprintDTO]) throws {
        let existing = try stableIDMap(for: SavedProgramBlueprint.self)
        let keep = Set(dtos.map(\.stableID))

        for dto in dtos {
            if let blueprint = existing[dto.stableID] {
                apply(dto, to: blueprint)
            } else {
                let blueprint = SavedProgramBlueprint(
                    stableID: dto.stableID,
                    name: dto.name,
                    durationWeeks: dto.durationWeeks,
                    sessionsPerWeek: dto.sessionsPerWeek,
                    trainingProgramSnapshotJSON: dto.trainingProgramSnapshotJSON
                )
                apply(dto, to: blueprint)
                modelContext.insert(blueprint)
            }
        }

        deleteMissing(existing, keepStableIDs: keep)
        try modelContext.save()
    }

    func replaceProgramShares(with dtos: [ProgramShareGrantDTO]) throws {
        let existing = try stableIDMap(for: ProgramShareGrant.self)
        let keep = Set(dtos.map(\.stableID))

        for dto in dtos {
            if let share = existing[dto.stableID] {
                apply(dto, to: share)
            } else {
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
                modelContext.insert(share)
            }
        }

        deleteMissing(existing, keepStableIDs: keep)
        try modelContext.save()
    }

    func replaceProgressShares(with dtos: [ProgressShareCardDTO]) throws {
        let existing = try stableIDMap(for: ProgressShareCard.self)
        let keep = Set(dtos.map(\.stableID))

        for dto in dtos {
            if let share = existing[dto.stableID] {
                apply(dto, to: share)
            } else {
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
                modelContext.insert(share)
            }
        }

        deleteMissing(existing, keepStableIDs: keep)
        try modelContext.save()
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
