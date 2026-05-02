//
//  CollaborationSharingAndCards.swift
//  SuggestMeSome
//
//  Sharing surfaces (private sharing center, insight detail, weekly digest,
//  route sheet) plus dashboard cards and signed-out / summary helpers.
//  Extracted from CollaborationViews in Feature 22 Prompt 1.
//

import SwiftUI
import SwiftData

// MARK: - Insight Snapshot Detail

struct InsightSnapshotDetailView: View {
    let snapshot: InsightSnapshot

    @State private var showingProgressShareComposer = false

    var body: some View {
        List {
            Section("Overview") {
                Text(snapshot.headline)
                    .font(.headline)
                Text(snapshot.summaryText)
                    .foregroundStyle(.secondary)
                if let detailText = snapshot.detailText, !detailText.isEmpty {
                    Text(detailText)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Signals") {
                if let activeProgramName = snapshot.activeProgramName {
                    LabeledContent("Active Program", value: activeProgramName)
                }
                if let lastWorkoutAt = snapshot.lastWorkoutAt {
                    LabeledContent("Last Workout", value: lastWorkoutAt.formatted(date: .abbreviated, time: .omitted))
                }
                if let adherence = snapshot.recentAdherenceScore {
                    LabeledContent("Adherence", value: "\(Int(adherence.rounded()))%")
                }
                if let fatigueStatus = snapshot.fatigueStatusRawValue {
                    LabeledContent("Fatigue", value: fatigueStatus.capitalized)
                }
                if let prMomentumSummary = snapshot.prMomentumSummary {
                    LabeledContent("PR Momentum", value: prMomentumSummary)
                }
                if let liftTrendSummary = snapshot.liftTrendSummary {
                    LabeledContent("Lift Trend", value: liftTrendSummary)
                }
                if let completionRiskSummary = snapshot.completionRiskSummary {
                    LabeledContent("Completion Risk", value: completionRiskSummary)
                }
            }

            Section("Sharing") {
                Button {
                    showingProgressShareComposer = true
                } label: {
                    Label("Share This Snapshot", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(snapshot.accountDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingProgressShareComposer) {
            NavigationStack {
                ProgressShareComposerView(snapshot: snapshot)
            }
        }
    }
}

struct WeeklyDigestDetailView: View {
    let digest: WeeklyDigest

    var body: some View {
        List {
            Section("Digest") {
                Text(digest.summaryText)
                if let highlightsText = digest.highlightsText {
                    Text(highlightsText)
                        .foregroundStyle(.secondary)
                }
                if let priorities = digest.reviewPrioritiesText {
                    Text(priorities)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(digest.titleText)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Deep-link Sheet Router

struct CollaborationRouteSheetView: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    let route: AppDeepLinkRoute

    var body: some View {
        NavigationStack {
            routeContent
        }
    }

    @ViewBuilder
    private var routeContent: some View {
        switch route {
        case .collaborationHub:
            CollaborationHubView()
        case .coachInvite(let stableID):
            if let invite = collaborationCoordinator.invites.first(where: { $0.stableID == stableID }) {
                List { InviteRow(invite: invite) }
                    .navigationTitle("Invite")
            } else {
                routeUnavailableView("Invite")
            }
        case .relationship(let stableID):
            if let relationship = collaborationCoordinator.relationships.first(where: { $0.stableID == stableID }) {
                RelationshipDetailView(relationship: relationship)
            } else {
                routeUnavailableView("Connection")
            }
        case .assignment(let stableID):
            if let assignment = collaborationCoordinator.assignments.first(where: { $0.stableID == stableID }) {
                List {
                    Section {
                        AssignmentCard(assignment: assignment)
                    }
                }
                .navigationTitle("Assignment")
            } else {
                routeUnavailableView("Assignment")
            }
        case .coachNote(let stableID):
            if let note = collaborationCoordinator.notes.first(where: { $0.stableID == stableID }) {
                List { CoachNoteRow(note: note) }
                    .navigationTitle("Coach Note")
            } else {
                routeUnavailableView("Coach Note")
            }
        case .weeklyDigest(let stableID):
            if let digest = collaborationCoordinator.weeklyDigests.first(where: { $0.stableID == stableID }) {
                WeeklyDigestDetailView(digest: digest)
            } else {
                routeUnavailableView("Weekly Digest")
            }
        case .insightSnapshot(let stableID):
            if let snapshot = collaborationCoordinator.insightSnapshots.first(where: { $0.stableID == stableID }) {
                InsightSnapshotDetailView(snapshot: snapshot)
            } else {
                routeUnavailableView("Insight")
            }
        case .blueprint(let stableID):
            if let blueprint = collaborationCoordinator.blueprints.first(where: { $0.stableID == stableID }) {
                BlueprintDetailView(blueprint: blueprint)
            } else {
                routeUnavailableView("Saved Program")
            }
        case .programShare:
            PrivateSharingCenterView()
        case .progressShare:
            PrivateSharingCenterView()
        case .coachRoster:
            CoachRosterView()
        case .notificationPreferences:
            NotificationPreferencesView()
        case .activeWorkout:
            // Live Activity taps are handled by ContentView (it flips the
            // Workouts tab and opens the active-workout sheet directly).
            // This sheet — the collaboration route sheet — never presents
            // an active workout, so fall through to an empty view.
            EmptyView()
        }
    }

    private func routeUnavailableView(_ title: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "questionmark.circle",
            description: Text("Pull to refresh and try again.")
        )
    }
}

// MARK: - Cards used by core tabs

struct CollaborationInsightSummaryCard: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    var body: some View {
        if let snapshot = collaborationCoordinator.athleteFacingSnapshots.first {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                DSSectionHeader(icon: "sparkles", title: "Smart Coaching", iconColor: .indigo)
                Text(snapshot.headline)
                    .font(.title3.weight(.semibold))
                Text(snapshot.summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: DSSpacing.m) {
                    if let adherence = snapshot.recentAdherenceScore {
                        Label("\(Int(adherence.rounded()))% adherence", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if snapshot.unreadCoachNoteCount > 0 {
                        Label("\(snapshot.unreadCoachNoteCount) unread \(snapshot.unreadCoachNoteCount == 1 ? "note" : "notes")", systemImage: "text.bubble.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCardStyle()
        }
    }
}

struct DailyCoachCloudUpdatesCard: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(PushNotificationManager.self) private var pushNotificationManager

    private var hasContent: Bool {
        !collaborationCoordinator.unreadCoachNotes.isEmpty
            || !collaborationCoordinator.unreadDigests.isEmpty
            || pushNotificationManager.lastNudgeExplanation != nil
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 10) {
                Label("From Your Coach", systemImage: "bell.badge.fill")
                    .font(.headline)
                    .foregroundStyle(.indigo)

                if let nudge = pushNotificationManager.lastNudgeExplanation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(nudge.title)
                            .font(.subheadline.weight(.semibold))
                        Text(nudge.explanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let note = collaborationCoordinator.unreadCoachNotes.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("New note from \(note.authorDisplayName)")
                            .font(.subheadline.weight(.semibold))
                        Text(note.bodyText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let digest = collaborationCoordinator.unreadDigests.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(digest.titleText)
                            .font(.subheadline.weight(.semibold))
                        Text(digest.summaryText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

// MARK: - Reusable Hub Sections

struct CollaborationSummarySection: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    var body: some View {
        Section {
            LabeledContent("Status", value: collaborationCoordinator.phase.title)
            if let currentUser = accountManager.currentUser {
                LabeledContent("Account", value: currentUser.email)
            }
            Text(collaborationCoordinator.statusSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Collaboration")
        } footer: {
            Text("Coaches and training partners only see what you share. Apple Health–derived recovery data stays on your device.")
        }
    }
}

struct CollaborationSignedOutSection: View {
    var body: some View {
        Section {
            AccountSignInNoticeView()
            Text("Sign in to invite a coach, swap programs privately, and sync the collaboration tools tied to your account.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            NavigationLink {
                AccountSettingsView()
            } label: {
                Label("Sign In", systemImage: "person.crop.circle.badge.plus")
            }
        } header: {
            Text("Sign In Required")
        }
    }
}

// MARK: - Invite Row

struct InviteRow: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    let invite: CoachInvite

    private var presentationMode: InvitePresentationMode {
        collaborationCoordinator.invitePresentationMode(for: invite)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(invite.inviterDisplayName)
                    .font(.headline)
                Spacer()
                DSBadge(invite.status.title)
            }
            Text(invite.inviteeEmail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let noteText = invite.noteText, !noteText.isEmpty {
                Text(noteText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if presentationMode == .incomingPending {
                HStack(spacing: 12) {
                    AsyncActionButton(title: "Accept") {
                        await collaborationCoordinator.respondToInvite(invite, action: .accepted)
                    }
                    .buttonStyle(.borderedProminent)

                    AsyncActionButton(title: "Decline", role: .destructive) {
                        await collaborationCoordinator.respondToInvite(invite, action: .declined)
                    }
                    .buttonStyle(.bordered)
                }
            } else if presentationMode == .outgoingPending {
                AsyncActionButton(title: "Revoke Invite", role: .destructive) {
                    await collaborationCoordinator.revokeInvite(invite)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Composers
//
// The six collaboration composers (invite, blueprint save, assignment,
// coach note, program share, progress share) plus FormComposerScaffold,
// ProgressSharePayload, and the nilIfEmpty String helpers live in
// `CollaborationComposers.swift` after the Feature 20 Phase 2 view-file
// split. Composer structs were promoted from `private` to internal so
// the sheet callsites in this file can still see them. StatusBadge,
// NotificationPreferenceDraft, and the remaining scaffolding stay here
// since they're only consumed from this file.


// MARK: - Shared scaffolding

// FormComposerScaffold, ProgressSharePayload, and the nilIfEmpty helpers
// moved to CollaborationComposers.swift alongside the composers that are
// their only callers. NotificationPreferenceDraft stays here because it
// only renders inside NotificationPreferencesView; the earlier private
// StatusBadge has been folded into the shared DSBadge.

// MARK: - Models / Helpers

struct NotificationPreferenceDraft {
    var coachInvitesEnabled = true
    var assignmentUpdatesEnabled = true
    var coachNotesEnabled = true
    var missedSessionNudgesEnabled = true
    var checkInRemindersEnabled = true
    var pendingProposalRemindersEnabled = true
    var weeklyDigestsEnabled = true

    init(preference: NotificationPreference? = nil) {
        guard let preference else { return }
        coachInvitesEnabled = preference.coachInvitesEnabled
        assignmentUpdatesEnabled = preference.assignmentUpdatesEnabled
        coachNotesEnabled = preference.coachNotesEnabled
        missedSessionNudgesEnabled = preference.missedSessionNudgesEnabled
        checkInRemindersEnabled = preference.checkInRemindersEnabled
        pendingProposalRemindersEnabled = preference.pendingProposalRemindersEnabled
        weeklyDigestsEnabled = preference.weeklyDigestsEnabled
    }

    func asRequest() -> NotificationPreferenceUpdateRequest {
        NotificationPreferenceUpdateRequest(
            coachInvitesEnabled: coachInvitesEnabled,
            assignmentUpdatesEnabled: assignmentUpdatesEnabled,
            coachNotesEnabled: coachNotesEnabled,
            missedSessionNudgesEnabled: missedSessionNudgesEnabled,
            checkInRemindersEnabled: checkInRemindersEnabled,
            pendingProposalRemindersEnabled: pendingProposalRemindersEnabled,
            weeklyDigestsEnabled: weeklyDigestsEnabled
        )
    }

    mutating func set(_ category: CollaborationNotificationCategory, to isEnabled: Bool) {
        switch category {
        case .coachInvites: coachInvitesEnabled = isEnabled
        case .assignmentUpdates: assignmentUpdatesEnabled = isEnabled
        case .coachNotes: coachNotesEnabled = isEnabled
        case .missedSessionNudges: missedSessionNudgesEnabled = isEnabled
        case .checkInReminders: checkInRemindersEnabled = isEnabled
        case .pendingProposalReminders: pendingProposalRemindersEnabled = isEnabled
        case .weeklyDigests: weeklyDigestsEnabled = isEnabled
        }
    }

    func value(for category: CollaborationNotificationCategory) -> Bool {
        switch category {
        case .coachInvites: return coachInvitesEnabled
        case .assignmentUpdates: return assignmentUpdatesEnabled
        case .coachNotes: return coachNotesEnabled
        case .missedSessionNudges: return missedSessionNudgesEnabled
        case .checkInReminders: return checkInRemindersEnabled
        case .pendingProposalReminders: return pendingProposalRemindersEnabled
        case .weeklyDigests: return weeklyDigestsEnabled
        }
    }
}
