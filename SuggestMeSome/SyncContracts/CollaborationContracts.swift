import Foundation

struct CoachRelationshipDTO: Codable, Equatable, Identifiable {
    var id: String { stableID }
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
}

struct CoachInviteDTO: Codable, Equatable, Identifiable {
    var id: String { stableID }
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
}

struct ProgramAssignmentDTO: Codable, Equatable, Identifiable {
    var id: String { stableID }
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
}

struct CollaborationCloneReceiptDTO: Codable, Equatable {
    var createdTrainingProgramStableID: String?
    var createdProgramRunStableID: String?
}

struct ProgramAssignmentActionResponseDTO: Codable, Equatable {
    var assignment: ProgramAssignmentDTO
    var cloneReceipt: CollaborationCloneReceiptDTO?
}

struct CoachNoteDTO: Codable, Equatable, Identifiable {
    var id: String { stableID }
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
}

struct NotificationPreferenceDTO: Codable, Equatable {
    var stableID: String
    var updatedAt: Date
    var coachInvitesEnabled: Bool
    var assignmentUpdatesEnabled: Bool
    var coachNotesEnabled: Bool
    var missedSessionNudgesEnabled: Bool
    var checkInRemindersEnabled: Bool
    var pendingProposalRemindersEnabled: Bool
    var weeklyDigestsEnabled: Bool
}

struct DevicePushRegistrationDTO: Codable, Equatable {
    var stableID: String
    var updatedAt: Date
    var deviceID: String
    var pushToken: String?
    var authorizationStatusRawValue: String
    var lastRegisteredAt: Date?
    var lastErrorMessage: String?
}

struct InsightSnapshotDTO: Codable, Equatable, Identifiable {
    var id: String { stableID }
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
}

struct WeeklyDigestDTO: Codable, Equatable, Identifiable {
    var id: String { stableID }
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
}

struct SavedProgramBlueprintDTO: Codable, Equatable, Identifiable {
    var id: String { stableID }
    var stableID: String
    var createdAt: Date
    var updatedAt: Date
    var name: String
    var focusText: String?
    var notesText: String?
    var tags: [String]
    var durationWeeks: Int
    var sessionsPerWeek: Int
    var sourceProgramStableID: String?
    var createdByAccountID: UUID?
    var createdByDisplayName: String?
    var trainingProgramSnapshotJSON: String
    var lastSharedAt: Date?
}

struct ProgramShareGrantDTO: Codable, Equatable, Identifiable {
    var id: String { stableID }
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
}

struct ProgressShareCardDTO: Codable, Equatable, Identifiable {
    var id: String { stableID }
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
}

struct CollaborationNudgeExplanationDTO: Codable, Equatable {
    var categoryRawValue: String
    var title: String
    var explanation: String
    var triggeredAt: Date
    var anchorStableID: String?
}

struct CoachInviteCreateRequest: Codable, Equatable {
    var inviteeEmail: String
    var noteText: String?
    var inviterRoleRawValue: String
    var visibilityScopeBitmask: Int
}

struct CoachInviteActionRequest: Codable, Equatable {
    var actionRawValue: String
}

struct RelationshipScopeUpdateRequest: Codable, Equatable {
    var visibilityScopeBitmask: Int
}

struct ProgramAssignmentCreateRequest: Codable, Equatable {
    var relationshipStableID: String
    var blueprintStableID: String
    var notesText: String?
    var startGuidance: String?
}

struct ProgramAssignmentStatusUpdateRequest: Codable, Equatable {
    var statusRawValue: String
}

struct CoachNoteCreateRequest: Codable, Equatable {
    var relationshipStableID: String
    var bodyText: String
    var anchorKindRawValue: String
    var anchoredWorkoutStableID: String?
    var anchoredProgramRunStableID: String?
    var anchoredWeekStart: Date?
    var anchoredWeekEnd: Date?
    var eventSummaryText: String?
    var priorityRawValue: String
    var requiresReview: Bool
}

struct NotificationPreferenceUpdateRequest: Codable, Equatable {
    var coachInvitesEnabled: Bool
    var assignmentUpdatesEnabled: Bool
    var coachNotesEnabled: Bool
    var missedSessionNudgesEnabled: Bool
    var checkInRemindersEnabled: Bool
    var pendingProposalRemindersEnabled: Bool
    var weeklyDigestsEnabled: Bool
}

struct DevicePushRegistrationRequest: Codable, Equatable {
    var deviceID: String
    var pushToken: String?
    var authorizationStatusRawValue: String
}

struct SavedProgramBlueprintCreateRequest: Codable, Equatable {
    var name: String
    var focusText: String?
    var notesText: String?
    var tags: [String]
    var durationWeeks: Int
    var sessionsPerWeek: Int
    var sourceProgramStableID: String?
    var trainingProgramSnapshotJSON: String
}

struct ProgramShareGrantCreateRequest: Codable, Equatable {
    var relationshipStableID: String?
    var shareKindRawValue: String
    var blueprintStableID: String?
    var sourceProgramStableID: String?
    var grantedToAccountID: UUID
    var messageText: String?
}

struct ProgressShareCardCreateRequest: Codable, Equatable {
    var relationshipStableID: String?
    var shareKindRawValue: String
    var grantedToAccountID: UUID
    var titleText: String
    var subtitleText: String?
    var summaryText: String
    var payloadJSON: String
}
