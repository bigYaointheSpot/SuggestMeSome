import Foundation
import SwiftData

enum CollaborationRole: String, Codable, CaseIterable, Identifiable {
    case coach
    case athlete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coach:
            return "Coach"
        case .athlete:
            return "Athlete"
        }
    }
}

enum CoachRelationshipStatus: String, Codable, CaseIterable, Identifiable {
    case invited
    case active
    case paused
    case revoked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invited:
            return "Invited"
        case .active:
            return "Active"
        case .paused:
            return "Paused"
        case .revoked:
            return "Revoked"
        }
    }
}

enum CoachInviteStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case accepted
    case declined
    case revoked
    case expired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending:
            return "Pending"
        case .accepted:
            return "Accepted"
        case .declined:
            return "Declined"
        case .revoked:
            return "Revoked"
        case .expired:
            return "Expired"
        }
    }
}

enum ProgramAssignmentStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case accepted
    case declined
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending:
            return "Pending"
        case .accepted:
            return "Accepted"
        case .declined:
            return "Declined"
        case .archived:
            return "Archived"
        }
    }
}

enum CoachNoteAnchorKind: String, Codable, CaseIterable, Identifiable {
    case general
    case workout
    case programRun
    case weekWindow

    var id: String { rawValue }
}

enum WeeklyDigestAudience: String, Codable, CaseIterable, Identifiable {
    case coach
    case athlete

    var id: String { rawValue }
}

enum CollaborationInsightPriority: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var tintName: String {
        switch self {
        case .low:
            return "green"
        case .medium:
            return "orange"
        case .high:
            return "red"
        }
    }
}

enum CollaborationNotificationCategory: String, Codable, CaseIterable, Identifiable {
    case coachInvites
    case assignmentUpdates
    case coachNotes
    case missedSessionNudges
    case checkInReminders
    case pendingProposalReminders
    case weeklyDigests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coachInvites:
            return "Coach Invites"
        case .assignmentUpdates:
            return "Assignment Updates"
        case .coachNotes:
            return "Coach Notes"
        case .missedSessionNudges:
            return "Missed Session Nudges"
        case .checkInReminders:
            return "Check-In Reminders"
        case .pendingProposalReminders:
            return "Pending Proposal Reminders"
        case .weeklyDigests:
            return "Weekly Digests"
        }
    }

    var subtitle: String {
        switch self {
        case .coachInvites:
            return "Invite-only relationship requests."
        case .assignmentUpdates:
            return "New plans, acceptance, archive, and decline state changes."
        case .coachNotes:
            return "Read-only coach feedback and review comments."
        case .missedSessionNudges:
            return "Reminders when planned training falls behind."
        case .checkInReminders:
            return "Prompts to log readiness and daily context."
        case .pendingProposalReminders:
            return "Heads-up before a scheduled session when a proposal is still waiting."
        case .weeklyDigests:
            return "Deterministic weekly summary cards."
        }
    }
}

enum CollaborationPushAuthorizationState: String, Codable, CaseIterable, Identifiable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notDetermined:
            return "Not Requested"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        }
    }
}

enum ProgramShareKind: String, Codable, CaseIterable, Identifiable {
    case blueprint
    case editableProgram

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blueprint:
            return "Blueprint"
        case .editableProgram:
            return "Editable Program"
        }
    }
}

enum ShareGrantStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case revoked
    case expired

    var id: String { rawValue }
}

enum ProgressShareKind: String, Codable, CaseIterable, Identifiable {
    case prHighlight
    case liftTrend
    case adherenceStreak
    case completedBlockSummary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prHighlight:
            return "PR Highlight"
        case .liftTrend:
            return "Lift Trend"
        case .adherenceStreak:
            return "Adherence Streak"
        case .completedBlockSummary:
            return "Completed Block"
        }
    }
}

enum CollaborationVisibilityScope: String, Codable, CaseIterable, Identifiable {
    case programsAndRuns
    case workoutsAndAdherence
    case dailyCoachRecords
    case insightSnapshots
    case coachNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .programsAndRuns:
            return "Programs & Runs"
        case .workoutsAndAdherence:
            return "Workouts & Adherence"
        case .dailyCoachRecords:
            return "Daily Coach Records"
        case .insightSnapshots:
            return "Insight Snapshots"
        case .coachNotes:
            return "Coach Notes"
        }
    }

    var bitmaskValue: Int {
        switch self {
        case .programsAndRuns:
            return 1 << 0
        case .workoutsAndAdherence:
            return 1 << 1
        case .dailyCoachRecords:
            return 1 << 2
        case .insightSnapshots:
            return 1 << 3
        case .coachNotes:
            return 1 << 4
        }
    }

    static let defaultInviteScopes: [CollaborationVisibilityScope] = [
        .programsAndRuns,
        .workoutsAndAdherence,
        .dailyCoachRecords,
        .insightSnapshots,
        .coachNotes
    ]

    static func bitmask(for scopes: [CollaborationVisibilityScope]) -> Int {
        scopes.reduce(0) { partialResult, scope in
            partialResult | scope.bitmaskValue
        }
    }

    static func scopes(from bitmask: Int) -> [CollaborationVisibilityScope] {
        allCases.filter { scope in
            (bitmask & scope.bitmaskValue) != 0
        }
    }
}

@Model
final class CoachRelationship {
    var id: UUID
    var stableID: String
    var createdAt: Date
    var updatedAt: Date
    var statusRawValue: String
    var coachAccountID: UUID
    var coachDisplayName: String
    var athleteAccountID: UUID
    var athleteDisplayName: String
    var invitedByAccountID: UUID?
    var visibilityScopeBitmask: Int
    var unreadCoachNoteCount: Int
    var pendingAssignmentCount: Int
    var latestInsightSnapshotAt: Date?

    init(
        id: UUID = UUID(),
        stableID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        statusRawValue: String,
        coachAccountID: UUID,
        coachDisplayName: String,
        athleteAccountID: UUID,
        athleteDisplayName: String,
        invitedByAccountID: UUID? = nil,
        visibilityScopeBitmask: Int,
        unreadCoachNoteCount: Int = 0,
        pendingAssignmentCount: Int = 0,
        latestInsightSnapshotAt: Date? = nil
    ) {
        self.id = id
        self.stableID = stableID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.statusRawValue = statusRawValue
        self.coachAccountID = coachAccountID
        self.coachDisplayName = coachDisplayName
        self.athleteAccountID = athleteAccountID
        self.athleteDisplayName = athleteDisplayName
        self.invitedByAccountID = invitedByAccountID
        self.visibilityScopeBitmask = visibilityScopeBitmask
        self.unreadCoachNoteCount = unreadCoachNoteCount
        self.pendingAssignmentCount = pendingAssignmentCount
        self.latestInsightSnapshotAt = latestInsightSnapshotAt
    }

    var status: CoachRelationshipStatus {
        CoachRelationshipStatus(rawValue: statusRawValue) ?? .invited
    }

    var visibilityScopes: [CollaborationVisibilityScope] {
        CollaborationVisibilityScope.scopes(from: visibilityScopeBitmask)
    }

    func participantDisplayName(for currentAccountID: UUID?) -> String {
        guard let currentAccountID else {
            return athleteDisplayName
        }
        if currentAccountID == coachAccountID {
            return athleteDisplayName
        }
        if currentAccountID == athleteAccountID {
            return coachDisplayName
        }
        return athleteDisplayName
    }

    func currentRole(for currentAccountID: UUID?) -> CollaborationRole? {
        guard let currentAccountID else { return nil }
        if currentAccountID == coachAccountID {
            return .coach
        }
        if currentAccountID == athleteAccountID {
            return .athlete
        }
        return nil
    }
}

@Model
final class CoachInvite {
    var id: UUID
    var stableID: String
    var createdAt: Date
    var updatedAt: Date
    var expiresAt: Date?
    var statusRawValue: String
    var inviterAccountID: UUID
    var inviterDisplayName: String
    var inviterRoleRawValue: String
    var inviteeAccountID: UUID?
    var inviteeEmail: String
    var inviteeDisplayName: String?
    var relationshipStableID: String?
    var visibilityScopeBitmask: Int
    var noteText: String?

    init(
        id: UUID = UUID(),
        stableID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        expiresAt: Date? = nil,
        statusRawValue: String,
        inviterAccountID: UUID,
        inviterDisplayName: String,
        inviterRoleRawValue: String,
        inviteeAccountID: UUID? = nil,
        inviteeEmail: String,
        inviteeDisplayName: String? = nil,
        relationshipStableID: String? = nil,
        visibilityScopeBitmask: Int,
        noteText: String? = nil
    ) {
        self.id = id
        self.stableID = stableID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.statusRawValue = statusRawValue
        self.inviterAccountID = inviterAccountID
        self.inviterDisplayName = inviterDisplayName
        self.inviterRoleRawValue = inviterRoleRawValue
        self.inviteeAccountID = inviteeAccountID
        self.inviteeEmail = inviteeEmail
        self.inviteeDisplayName = inviteeDisplayName
        self.relationshipStableID = relationshipStableID
        self.visibilityScopeBitmask = visibilityScopeBitmask
        self.noteText = noteText
    }

    var status: CoachInviteStatus {
        CoachInviteStatus(rawValue: statusRawValue) ?? .pending
    }

    var inviterRole: CollaborationRole {
        CollaborationRole(rawValue: inviterRoleRawValue) ?? .coach
    }

    var visibilityScopes: [CollaborationVisibilityScope] {
        CollaborationVisibilityScope.scopes(from: visibilityScopeBitmask)
    }
}

@Model
final class ProgramAssignment {
    var id: UUID
    var stableID: String
    var createdAt: Date
    var updatedAt: Date
    var relationshipStableID: String
    var blueprintStableID: String
    var coachAccountID: UUID
    var coachDisplayName: String
    var athleteAccountID: UUID
    var athleteDisplayName: String
    var statusRawValue: String
    var notesText: String?
    var startGuidance: String?
    var importedTrainingProgramStableID: String?
    var importedProgramRunStableID: String?
    var respondedAt: Date?
    var archivedAt: Date?

    init(
        id: UUID = UUID(),
        stableID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        relationshipStableID: String,
        blueprintStableID: String,
        coachAccountID: UUID,
        coachDisplayName: String,
        athleteAccountID: UUID,
        athleteDisplayName: String,
        statusRawValue: String,
        notesText: String? = nil,
        startGuidance: String? = nil,
        importedTrainingProgramStableID: String? = nil,
        importedProgramRunStableID: String? = nil,
        respondedAt: Date? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.stableID = stableID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.relationshipStableID = relationshipStableID
        self.blueprintStableID = blueprintStableID
        self.coachAccountID = coachAccountID
        self.coachDisplayName = coachDisplayName
        self.athleteAccountID = athleteAccountID
        self.athleteDisplayName = athleteDisplayName
        self.statusRawValue = statusRawValue
        self.notesText = notesText
        self.startGuidance = startGuidance
        self.importedTrainingProgramStableID = importedTrainingProgramStableID
        self.importedProgramRunStableID = importedProgramRunStableID
        self.respondedAt = respondedAt
        self.archivedAt = archivedAt
    }

    var status: ProgramAssignmentStatus {
        ProgramAssignmentStatus(rawValue: statusRawValue) ?? .pending
    }
}

@Model
final class CoachNote {
    var id: UUID
    var stableID: String
    var createdAt: Date
    var updatedAt: Date
    var relationshipStableID: String
    var authorAccountID: UUID
    var authorDisplayName: String
    var recipientAccountID: UUID
    var recipientDisplayName: String
    var bodyText: String
    var anchorKindRawValue: String
    var anchoredWorkoutStableID: String?
    var anchoredProgramRunStableID: String?
    var anchoredWeekStart: Date?
    var anchoredWeekEnd: Date?
    var eventSummaryText: String?
    var priorityRawValue: String
    var isUnread: Bool
    var requiresReview: Bool

    init(
        id: UUID = UUID(),
        stableID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        relationshipStableID: String,
        authorAccountID: UUID,
        authorDisplayName: String,
        recipientAccountID: UUID,
        recipientDisplayName: String,
        bodyText: String,
        anchorKindRawValue: String,
        anchoredWorkoutStableID: String? = nil,
        anchoredProgramRunStableID: String? = nil,
        anchoredWeekStart: Date? = nil,
        anchoredWeekEnd: Date? = nil,
        eventSummaryText: String? = nil,
        priorityRawValue: String = CollaborationInsightPriority.medium.rawValue,
        isUnread: Bool = true,
        requiresReview: Bool = false
    ) {
        self.id = id
        self.stableID = stableID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.relationshipStableID = relationshipStableID
        self.authorAccountID = authorAccountID
        self.authorDisplayName = authorDisplayName
        self.recipientAccountID = recipientAccountID
        self.recipientDisplayName = recipientDisplayName
        self.bodyText = bodyText
        self.anchorKindRawValue = anchorKindRawValue
        self.anchoredWorkoutStableID = anchoredWorkoutStableID
        self.anchoredProgramRunStableID = anchoredProgramRunStableID
        self.anchoredWeekStart = anchoredWeekStart
        self.anchoredWeekEnd = anchoredWeekEnd
        self.eventSummaryText = eventSummaryText
        self.priorityRawValue = priorityRawValue
        self.isUnread = isUnread
        self.requiresReview = requiresReview
    }

    var anchorKind: CoachNoteAnchorKind {
        CoachNoteAnchorKind(rawValue: anchorKindRawValue) ?? .general
    }

    var priority: CollaborationInsightPriority {
        CollaborationInsightPriority(rawValue: priorityRawValue) ?? .medium
    }
}

@Model
final class NotificationPreference {
    var id: UUID
    var stableID: String
    var updatedAt: Date
    var coachInvitesEnabled: Bool
    var assignmentUpdatesEnabled: Bool
    var coachNotesEnabled: Bool
    var missedSessionNudgesEnabled: Bool
    var checkInRemindersEnabled: Bool
    var pendingProposalRemindersEnabled: Bool
    var weeklyDigestsEnabled: Bool

    init(
        id: UUID = UUID(),
        stableID: String,
        updatedAt: Date = .now,
        coachInvitesEnabled: Bool = true,
        assignmentUpdatesEnabled: Bool = true,
        coachNotesEnabled: Bool = true,
        missedSessionNudgesEnabled: Bool = true,
        checkInRemindersEnabled: Bool = true,
        pendingProposalRemindersEnabled: Bool = true,
        weeklyDigestsEnabled: Bool = true
    ) {
        self.id = id
        self.stableID = stableID
        self.updatedAt = updatedAt
        self.coachInvitesEnabled = coachInvitesEnabled
        self.assignmentUpdatesEnabled = assignmentUpdatesEnabled
        self.coachNotesEnabled = coachNotesEnabled
        self.missedSessionNudgesEnabled = missedSessionNudgesEnabled
        self.checkInRemindersEnabled = checkInRemindersEnabled
        self.pendingProposalRemindersEnabled = pendingProposalRemindersEnabled
        self.weeklyDigestsEnabled = weeklyDigestsEnabled
    }

    func isEnabled(_ category: CollaborationNotificationCategory) -> Bool {
        switch category {
        case .coachInvites:
            return coachInvitesEnabled
        case .assignmentUpdates:
            return assignmentUpdatesEnabled
        case .coachNotes:
            return coachNotesEnabled
        case .missedSessionNudges:
            return missedSessionNudgesEnabled
        case .checkInReminders:
            return checkInRemindersEnabled
        case .pendingProposalReminders:
            return pendingProposalRemindersEnabled
        case .weeklyDigests:
            return weeklyDigestsEnabled
        }
    }
}

@Model
final class DevicePushRegistration {
    var id: UUID
    var stableID: String
    var updatedAt: Date
    var deviceID: String
    var pushToken: String?
    var authorizationStatusRawValue: String
    var lastRegisteredAt: Date?
    var lastErrorMessage: String?

    init(
        id: UUID = UUID(),
        stableID: String,
        updatedAt: Date = .now,
        deviceID: String,
        pushToken: String? = nil,
        authorizationStatusRawValue: String,
        lastRegisteredAt: Date? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.stableID = stableID
        self.updatedAt = updatedAt
        self.deviceID = deviceID
        self.pushToken = pushToken
        self.authorizationStatusRawValue = authorizationStatusRawValue
        self.lastRegisteredAt = lastRegisteredAt
        self.lastErrorMessage = lastErrorMessage
    }

    var authorizationStatus: CollaborationPushAuthorizationState {
        CollaborationPushAuthorizationState(rawValue: authorizationStatusRawValue) ?? .notDetermined
    }
}

@Model
final class InsightSnapshot {
    var id: UUID
    var stableID: String
    var createdAt: Date
    var updatedAt: Date
    var relationshipStableID: String?
    var accountID: UUID
    var accountDisplayName: String
    var activeProgramName: String?
    var syncFreshnessAt: Date?
    var lastWorkoutAt: Date?
    var recentAdherenceScore: Double?
    var fatigueStatusRawValue: String?
    var pendingProposalCount: Int
    var unreadCoachNoteCount: Int
    var prMomentumSummary: String?
    var liftTrendSummary: String?
    var fatigueRunwaySummary: String?
    var completionRiskSummary: String?
    var reviewPriorityText: String?
    var headline: String
    var summaryText: String
    var detailText: String?
    var priorityRawValue: String

    init(
        id: UUID = UUID(),
        stableID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        relationshipStableID: String? = nil,
        accountID: UUID,
        accountDisplayName: String,
        activeProgramName: String? = nil,
        syncFreshnessAt: Date? = nil,
        lastWorkoutAt: Date? = nil,
        recentAdherenceScore: Double? = nil,
        fatigueStatusRawValue: String? = nil,
        pendingProposalCount: Int = 0,
        unreadCoachNoteCount: Int = 0,
        prMomentumSummary: String? = nil,
        liftTrendSummary: String? = nil,
        fatigueRunwaySummary: String? = nil,
        completionRiskSummary: String? = nil,
        reviewPriorityText: String? = nil,
        headline: String,
        summaryText: String,
        detailText: String? = nil,
        priorityRawValue: String = CollaborationInsightPriority.medium.rawValue
    ) {
        self.id = id
        self.stableID = stableID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.relationshipStableID = relationshipStableID
        self.accountID = accountID
        self.accountDisplayName = accountDisplayName
        self.activeProgramName = activeProgramName
        self.syncFreshnessAt = syncFreshnessAt
        self.lastWorkoutAt = lastWorkoutAt
        self.recentAdherenceScore = recentAdherenceScore
        self.fatigueStatusRawValue = fatigueStatusRawValue
        self.pendingProposalCount = pendingProposalCount
        self.unreadCoachNoteCount = unreadCoachNoteCount
        self.prMomentumSummary = prMomentumSummary
        self.liftTrendSummary = liftTrendSummary
        self.fatigueRunwaySummary = fatigueRunwaySummary
        self.completionRiskSummary = completionRiskSummary
        self.reviewPriorityText = reviewPriorityText
        self.headline = headline
        self.summaryText = summaryText
        self.detailText = detailText
        self.priorityRawValue = priorityRawValue
    }

    var priority: CollaborationInsightPriority {
        CollaborationInsightPriority(rawValue: priorityRawValue) ?? .medium
    }
}

@Model
final class WeeklyDigest {
    var id: UUID
    var stableID: String
    var createdAt: Date
    var updatedAt: Date
    var weekStart: Date
    var weekEnd: Date
    var audienceRawValue: String
    var relationshipStableID: String?
    var accountID: UUID
    var titleText: String
    var summaryText: String
    var highlightsText: String?
    var reviewPrioritiesText: String?
    var isUnread: Bool

    init(
        id: UUID = UUID(),
        stableID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        weekStart: Date,
        weekEnd: Date,
        audienceRawValue: String,
        relationshipStableID: String? = nil,
        accountID: UUID,
        titleText: String,
        summaryText: String,
        highlightsText: String? = nil,
        reviewPrioritiesText: String? = nil,
        isUnread: Bool = true
    ) {
        self.id = id
        self.stableID = stableID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.audienceRawValue = audienceRawValue
        self.relationshipStableID = relationshipStableID
        self.accountID = accountID
        self.titleText = titleText
        self.summaryText = summaryText
        self.highlightsText = highlightsText
        self.reviewPrioritiesText = reviewPrioritiesText
        self.isUnread = isUnread
    }

    var audience: WeeklyDigestAudience {
        WeeklyDigestAudience(rawValue: audienceRawValue) ?? .athlete
    }
}

@Model
final class SavedProgramBlueprint {
    var id: UUID
    var stableID: String
    var createdAt: Date
    var updatedAt: Date
    var name: String
    var focusText: String?
    var notesText: String?
    var tagsCSV: String
    var durationWeeks: Int
    var sessionsPerWeek: Int
    var sourceProgramStableID: String?
    var createdByAccountID: UUID?
    var createdByDisplayName: String?
    var trainingProgramSnapshotJSON: String
    var lastSharedAt: Date?

    init(
        id: UUID = UUID(),
        stableID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        name: String,
        focusText: String? = nil,
        notesText: String? = nil,
        tagsCSV: String = "",
        durationWeeks: Int,
        sessionsPerWeek: Int,
        sourceProgramStableID: String? = nil,
        createdByAccountID: UUID? = nil,
        createdByDisplayName: String? = nil,
        trainingProgramSnapshotJSON: String,
        lastSharedAt: Date? = nil
    ) {
        self.id = id
        self.stableID = stableID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.focusText = focusText
        self.notesText = notesText
        self.tagsCSV = tagsCSV
        self.durationWeeks = durationWeeks
        self.sessionsPerWeek = sessionsPerWeek
        self.sourceProgramStableID = sourceProgramStableID
        self.createdByAccountID = createdByAccountID
        self.createdByDisplayName = createdByDisplayName
        self.trainingProgramSnapshotJSON = trainingProgramSnapshotJSON
        self.lastSharedAt = lastSharedAt
    }

    var tags: [String] {
        CSVListCodec.decode(tagsCSV)
    }
}

@Model
final class ProgramShareGrant {
    var id: UUID
    var stableID: String
    var createdAt: Date
    var updatedAt: Date
    var relationshipStableID: String?
    var shareKindRawValue: String
    var statusRawValue: String
    var blueprintStableID: String?
    var sourceProgramStableID: String?
    var grantedByAccountID: UUID
    var grantedByDisplayName: String
    var grantedToAccountID: UUID
    var grantedToDisplayName: String
    var messageText: String?

    init(
        id: UUID = UUID(),
        stableID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        relationshipStableID: String? = nil,
        shareKindRawValue: String,
        statusRawValue: String,
        blueprintStableID: String? = nil,
        sourceProgramStableID: String? = nil,
        grantedByAccountID: UUID,
        grantedByDisplayName: String,
        grantedToAccountID: UUID,
        grantedToDisplayName: String,
        messageText: String? = nil
    ) {
        self.id = id
        self.stableID = stableID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.relationshipStableID = relationshipStableID
        self.shareKindRawValue = shareKindRawValue
        self.statusRawValue = statusRawValue
        self.blueprintStableID = blueprintStableID
        self.sourceProgramStableID = sourceProgramStableID
        self.grantedByAccountID = grantedByAccountID
        self.grantedByDisplayName = grantedByDisplayName
        self.grantedToAccountID = grantedToAccountID
        self.grantedToDisplayName = grantedToDisplayName
        self.messageText = messageText
    }

    var shareKind: ProgramShareKind {
        ProgramShareKind(rawValue: shareKindRawValue) ?? .blueprint
    }

    var status: ShareGrantStatus {
        ShareGrantStatus(rawValue: statusRawValue) ?? .active
    }
}

@Model
final class ProgressShareCard {
    var id: UUID
    var stableID: String
    var createdAt: Date
    var updatedAt: Date
    var relationshipStableID: String?
    var shareKindRawValue: String
    var statusRawValue: String
    var grantedByAccountID: UUID
    var grantedByDisplayName: String
    var grantedToAccountID: UUID
    var grantedToDisplayName: String
    var titleText: String
    var subtitleText: String?
    var summaryText: String
    var payloadJSON: String

    init(
        id: UUID = UUID(),
        stableID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        relationshipStableID: String? = nil,
        shareKindRawValue: String,
        statusRawValue: String,
        grantedByAccountID: UUID,
        grantedByDisplayName: String,
        grantedToAccountID: UUID,
        grantedToDisplayName: String,
        titleText: String,
        subtitleText: String? = nil,
        summaryText: String,
        payloadJSON: String
    ) {
        self.id = id
        self.stableID = stableID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.relationshipStableID = relationshipStableID
        self.shareKindRawValue = shareKindRawValue
        self.statusRawValue = statusRawValue
        self.grantedByAccountID = grantedByAccountID
        self.grantedByDisplayName = grantedByDisplayName
        self.grantedToAccountID = grantedToAccountID
        self.grantedToDisplayName = grantedToDisplayName
        self.titleText = titleText
        self.subtitleText = subtitleText
        self.summaryText = summaryText
        self.payloadJSON = payloadJSON
    }

    var shareKind: ProgressShareKind {
        ProgressShareKind(rawValue: shareKindRawValue) ?? .prHighlight
    }

    var status: ShareGrantStatus {
        ShareGrantStatus(rawValue: statusRawValue) ?? .active
    }
}

enum CSVListCodec {
    static func decode(_ csv: String) -> [String] {
        csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func encode(_ values: [String]) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
