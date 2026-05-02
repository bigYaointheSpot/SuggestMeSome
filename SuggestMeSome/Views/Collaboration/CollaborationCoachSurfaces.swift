//
//  CollaborationCoachSurfaces.swift
//  SuggestMeSome
//
//  Coach-facing destinations from CollaborationHubView (notification prefs,
//  my coach, roster, blueprint library, assignments, notes, relationship,
//  visibility presets). Extracted in Feature 22 Prompt 1.
//

import SwiftUI
import SwiftData

// MARK: - Notification Preferences

struct NotificationPreferencesView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(PushNotificationManager.self) private var pushNotificationManager

    @State private var draft = NotificationPreferenceDraft()
    @State private var isSaving = false
    @State private var didSaveTrigger = 0

    var body: some View {
        List {
            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else {
                Section("Before You Enable Notifications") {
                    PushNotificationNoticeView()
                }

                Section {
                    LabeledContent("Status", value: pushNotificationManager.authorizationState.title)
                    if let deviceToken = pushNotificationManager.deviceTokenHex {
                        LabeledContent("Device Token", value: String(deviceToken.prefix(12)) + "…")
                            .font(.footnote.monospaced())
                    }
                    if pushNotificationManager.authorizationState != .authorized
                        && pushNotificationManager.authorizationState != .provisional {
                        Button {
                            Task { await collaborationCoordinator.requestPushAuthorization() }
                        } label: {
                            Label("Turn On Notifications", systemImage: "bell.badge")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("We only use push notifications — no email or SMS. Tapping a notification opens the relevant tab in this app, and you can change notification permissions later in iOS Settings.")
                }

                Section("What you'll be notified about") {
                    preferenceToggle(.coachInvites)
                    preferenceToggle(.assignmentUpdates)
                    preferenceToggle(.coachNotes)
                    preferenceToggle(.missedSessionNudges)
                    preferenceToggle(.checkInReminders)
                    preferenceToggle(.pendingProposalReminders)
                    preferenceToggle(.weeklyDigests)
                }

                Section {
                    AsyncActionButton(title: "Save Preferences") {
                        await collaborationCoordinator.updateNotificationPreferences(draft.asRequest())
                        if collaborationCoordinator.lastErrorMessage == nil {
                            didSaveTrigger &+= 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: didSaveTrigger)
        .onAppear {
            draft = NotificationPreferenceDraft(preference: collaborationCoordinator.notificationPreference)
        }
    }

    private func preferenceToggle(_ category: CollaborationNotificationCategory) -> some View {
        Toggle(
            isOn: Binding(
                get: { draft.value(for: category) },
                set: { draft.set(category, to: $0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                Text(category.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - My Coach

struct MyCoachView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    @State private var showingInviteComposer = false

    var body: some View {
        List {
            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else if collaborationCoordinator.shouldShowMyCoachEmptyState {
                DSEmptyState(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "No Coach Yet",
                    message: "Invite a coach to share programs, get assignments, and exchange notes.",
                    cta: .init(title: "Send a Coach Invite") {
                        showingInviteComposer = true
                    }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                if !collaborationCoordinator.incomingPendingInvites.isEmpty {
                    Section("Incoming Invites") {
                        ForEach(collaborationCoordinator.incomingPendingInvites) { invite in
                            InviteRow(invite: invite)
                        }
                    }
                }

                if !collaborationCoordinator.athleteRelationships.isEmpty {
                    Section("Connected Coaches") {
                        ForEach(collaborationCoordinator.athleteRelationships) { relationship in
                            NavigationLink {
                                RelationshipDetailView(relationship: relationship)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(relationship.participantDisplayName(for: collaborationCoordinator.currentAccountID))
                                        .font(.headline)
                                    Text(relationshipSubtitle(relationship))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("My Coach")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingInviteComposer) {
            NavigationStack {
                CreateCoachInviteView()
            }
        }
    }

    private func relationshipSubtitle(_ relationship: CoachRelationship) -> String {
        var parts: [String] = []
        if relationship.unreadCoachNoteCount > 0 {
            parts.append("\(relationship.unreadCoachNoteCount) unread \(relationship.unreadCoachNoteCount == 1 ? "note" : "notes")")
        }
        if relationship.pendingAssignmentCount > 0 {
            parts.append("\(relationship.pendingAssignmentCount) pending")
        }
        return parts.isEmpty ? "Up to date" : parts.joined(separator: " • ")
    }
}

// MARK: - Coach Roster

struct CoachRosterView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(PurchaseManager.self) private var purchaseManager

    /// iOS 18 zoom-transition namespace tying each roster row to its
    /// pushed InsightSnapshotDetailView.
    @Namespace private var rosterTransitionNamespace

    var body: some View {
        Group {
            if !FeatureAccessPolicy.isAccessible(.coachCollaboration, entitlementState: purchaseManager.entitlementState) {
                PaywallView(feature: .coachCollaboration)
            } else {
                List {
                    if accountManager.currentUser == nil {
                        CollaborationSignedOutSection()
                    } else if collaborationCoordinator.coachRosterSnapshots.isEmpty {
                        DSEmptyState(
                            systemImage: "person.3.sequence",
                            title: "No Athletes Yet",
                            message: "Once an athlete accepts your invite, you'll see their training snapshots here — adherence, fatigue, and what to review next."
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(collaborationCoordinator.coachRosterSnapshots) { snapshot in
                            NavigationLink {
                                InsightSnapshotDetailView(snapshot: snapshot)
                                    .navigationTransition(.zoom(sourceID: snapshot.stableID, in: rosterTransitionNamespace))
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(snapshot.accountDisplayName)
                                        .font(.headline)
                                    Text(snapshot.headline)
                                        .font(.subheadline)
                                    Text(snapshot.summaryText)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            .matchedTransitionSource(id: snapshot.stableID, in: rosterTransitionNamespace)
                        }
                    }
                }
            }
        }
        .navigationTitle("Athlete Roster")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Saved Programs (Blueprints)

struct BlueprintLibraryView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Query(sort: \TrainingProgram.createdDate, order: .reverse) private var programs: [TrainingProgram]

    @State private var selectedProgram: TrainingProgram?

    var body: some View {
        List {
            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else {
                Section("Your Saved Programs") {
                    if collaborationCoordinator.blueprints.isEmpty {
                        Text("Save a program to reuse it later, assign it to an athlete, or share it privately.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(collaborationCoordinator.blueprints) { blueprint in
                            NavigationLink {
                                BlueprintDetailView(blueprint: blueprint)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(blueprint.name)
                                        .font(.headline)
                                    Text("\(blueprint.durationWeeks) weeks • \(blueprint.sessionsPerWeek) sessions/week")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if !blueprint.tags.isEmpty {
                                        Text(blueprint.tags.joined(separator: " • "))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Save a Program") {
                    if programs.isEmpty {
                        Text("Build or generate a program first, then save it here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(programs) { program in
                            Button {
                                selectedProgram = program
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(program.name)
                                    Text("\(program.lengthInWeeks) weeks • \(program.sessionsPerWeek) sessions/week")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved Programs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedProgram) { program in
            NavigationStack {
                BlueprintComposerView(program: program)
            }
        }
    }
}

struct BlueprintDetailView: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(PurchaseManager.self) private var purchaseManager

    let blueprint: SavedProgramBlueprint

    @State private var showingAssignmentComposer = false
    @State private var showingProgramShareComposer = false

    var body: some View {
        List {
            Section("Saved Program") {
                LabeledContent("Name", value: blueprint.name)
                if let focusText = blueprint.focusText, !focusText.isEmpty {
                    LabeledContent("Focus", value: focusText)
                }
                LabeledContent("Duration", value: "\(blueprint.durationWeeks) weeks")
                LabeledContent("Sessions / week", value: "\(blueprint.sessionsPerWeek)")
                if let notesText = blueprint.notesText, !notesText.isEmpty {
                    Text(notesText)
                        .foregroundStyle(.secondary)
                }
            }

            if !blueprint.tags.isEmpty {
                Section("Tags") {
                    Text(blueprint.tags.joined(separator: " • "))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Actions") {
                Button {
                    showingAssignmentComposer = true
                } label: {
                    Label("Assign to an Athlete", systemImage: "paperplane.fill")
                }
                .disabled(!FeatureAccessPolicy.isAccessible(.coachCollaboration, entitlementState: purchaseManager.entitlementState))

                Button {
                    showingProgramShareComposer = true
                } label: {
                    Label("Share Privately", systemImage: "lock.shield")
                }
                .disabled(collaborationCoordinator.relationships.isEmpty)
            }
        }
        .navigationTitle(blueprint.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAssignmentComposer) {
            NavigationStack {
                if FeatureAccessPolicy.isAccessible(.coachCollaboration, entitlementState: purchaseManager.entitlementState) {
                    AssignmentComposerView(blueprint: blueprint)
                } else {
                    PaywallView(feature: .coachCollaboration)
                }
            }
        }
        .sheet(isPresented: $showingProgramShareComposer) {
            NavigationStack {
                ProgramShareComposerView(blueprint: blueprint)
            }
        }
    }
}

// MARK: - Assignments (From Your Coach)

struct AssignmentInboxView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    @State private var showingInviteComposer = false

    var body: some View {
        List {
            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else if collaborationCoordinator.inboxAssignments.isEmpty {
                let ctaTitle = collaborationCoordinator.athleteRelationships.isEmpty ? "Invite a Coach" : nil
                DSEmptyState(
                    systemImage: "tray",
                    title: "Nothing From Your Coach",
                    message: "When a coach sends you a program, it'll show up here. Accepting one drops it into your training.",
                    cta: ctaTitle.map { title in
                        DSEmptyState.CTA(title: title) { showingInviteComposer = true }
                    }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                ForEach(collaborationCoordinator.inboxAssignments) { assignment in
                    Section {
                        AssignmentCard(assignment: assignment)
                    }
                }
            }
        }
        .navigationTitle("From Your Coach")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingInviteComposer) {
            NavigationStack {
                CreateCoachInviteView()
            }
        }
    }
}

struct AssignmentCard: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let assignment: ProgramAssignment

    private var counterpartName: String {
        assignment.athleteAccountID == collaborationCoordinator.currentAccountID
            ? assignment.coachDisplayName
            : assignment.athleteDisplayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(counterpartName)
                    .font(.headline)
                Spacer()
                DSBadge(assignment.status.title)
            }

            if let notesText = assignment.notesText, !notesText.isEmpty {
                Text(notesText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let startGuidance = assignment.startGuidance, !startGuidance.isEmpty {
                Text(startGuidance)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if collaborationCoordinator.canActOnAssignment(assignment) {
                HStack(spacing: 12) {
                    AsyncActionButton(title: "Accept") {
                        await collaborationCoordinator.updateAssignmentStatus(assignment, status: .accepted)
                    }
                    .buttonStyle(.borderedProminent)

                    AsyncActionButton(title: "Decline", role: .destructive) {
                        await collaborationCoordinator.updateAssignmentStatus(assignment, status: .declined)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 2)

                AsyncActionButton(title: "Archive") {
                    await collaborationCoordinator.updateAssignmentStatus(assignment, status: .archived)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Coach Notes & Digests

struct CoachNotesInboxView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    var body: some View {
        List {
            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else {
                if !collaborationCoordinator.notes.isEmpty {
                    Section("Coach Notes") {
                        ForEach(collaborationCoordinator.notes) { note in
                            CoachNoteRow(note: note)
                        }
                    }
                }

                if !collaborationCoordinator.weeklyDigests.isEmpty {
                    Section("Weekly Digests") {
                        ForEach(collaborationCoordinator.weeklyDigests) { digest in
                            NavigationLink {
                                WeeklyDigestDetailView(digest: digest)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(digest.titleText)
                                        .font(.headline)
                                    Text(digest.summaryText)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if collaborationCoordinator.notes.isEmpty && collaborationCoordinator.weeklyDigests.isEmpty {
                    DSEmptyState(
                        systemImage: "text.bubble",
                        title: "No Notes Yet",
                        message: "Coach notes, smart coaching nudges, and weekly digests will land here."
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Coach Notes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CoachNoteRow: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    let note: CoachNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.authorDisplayName)
                    .font(.headline)
                Spacer()
                if note.isUnread {
                    DSBadge("New")
                }
            }
            Text(note.bodyText)
            if let summary = note.eventSummaryText {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if note.isUnread {
                AsyncActionButton(title: "Mark as Read") {
                    await collaborationCoordinator.markNoteRead(note)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Relationship Detail (with privacy presets)

struct RelationshipDetailView: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(PurchaseManager.self) private var purchaseManager

    let relationship: CoachRelationship

    @State private var scopeSelection: Set<CollaborationVisibilityScope> = []
    @State private var showingNoteComposer = false
    @State private var showingScopeDetails = false
    @State private var didSaveScopesTrigger = 0
    @State private var hasAcceptedVisibilityDisclosure = false
    @State private var acknowledgedVisibilityDisclosure = false

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("Coach", value: relationship.coachDisplayName)
                LabeledContent("Athlete", value: relationship.athleteDisplayName)
                LabeledContent("Status", value: relationship.status.title)
                LabeledContent("Unread Notes", value: "\(relationship.unreadCoachNoteCount)")
                LabeledContent("Pending Programs", value: "\(relationship.pendingAssignmentCount)")
            }

            Section {
                CollaborationSharingConsentView(
                    context: .visibilityScopes,
                    requiresAcknowledgement: !hasAcceptedVisibilityDisclosure,
                    isAcknowledged: $acknowledgedVisibilityDisclosure
                )

                ForEach(VisibilityPreset.allCases) { preset in
                    Button {
                        scopeSelection = Set(preset.scopes)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .foregroundStyle(.primary)
                                Text(preset.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if scopeSelection == Set(preset.scopes) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }

                Button {
                    showingScopeDetails = true
                } label: {
                    Label("What does each preset share?", systemImage: "info.circle")
                        .font(.footnote)
                }
            } header: {
                Text("What this coach can see")
            } footer: {
                Text("You can change this any time. Apple Health–derived recovery data stays on your device.")
            }

            Section {
                AsyncActionButton(title: "Save Privacy Settings") {
                    await collaborationCoordinator.updateRelationshipScopes(
                        relationship,
                        scopes: Array(scopeSelection).sorted { $0.rawValue < $1.rawValue }
                    )
                    if collaborationCoordinator.lastErrorMessage == nil {
                        recordVisibilityDisclosureAcknowledgement()
                        didSaveScopesTrigger &+= 1
                    }
                }
                .disabled(!hasAcceptedVisibilityDisclosure && !acknowledgedVisibilityDisclosure)
                .buttonStyle(.borderedProminent)
            }

            if FeatureAccessPolicy.isAccessible(.coachCollaboration, entitlementState: purchaseManager.entitlementState)
                && collaborationCoordinator.canWriteCoachNote(for: relationship) {
                Section("Coach Tools") {
                    Button {
                        showingNoteComposer = true
                    } label: {
                        Label("Write a Note", systemImage: "square.and.pencil")
                    }
                }
            }
        }
        .navigationTitle(relationship.participantDisplayName(for: collaborationCoordinator.currentAccountID))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: didSaveScopesTrigger)
        .onAppear {
            scopeSelection = Set(relationship.visibilityScopes)
            hasAcceptedVisibilityDisclosure = CollaborationDisclosureAcknowledgementStore.isAcknowledged(
                .visibilityScopes,
                accountID: collaborationCoordinator.currentAccountID
            )
            acknowledgedVisibilityDisclosure = hasAcceptedVisibilityDisclosure
        }
        .sheet(isPresented: $showingNoteComposer) {
            NavigationStack {
                CoachNoteComposerView(relationship: relationship)
            }
        }
        .sheet(isPresented: $showingScopeDetails) {
            NavigationStack {
                VisibilityScopeDetailsView()
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func recordVisibilityDisclosureAcknowledgement() {
        CollaborationDisclosureAcknowledgementStore.recordAcknowledgement(
            .visibilityScopes,
            accountID: collaborationCoordinator.currentAccountID
        )
        hasAcceptedVisibilityDisclosure = true
        acknowledgedVisibilityDisclosure = true
    }
}

enum VisibilityPreset: String, CaseIterable, Identifiable {
    case full
    case coachingOnly
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Full Access"
        case .coachingOnly: return "Coaching Only"
        case .minimal: return "Minimal"
        }
    }

    var subtitle: String {
        switch self {
        case .full: return "Programs, workouts, daily coach, insights, and notes"
        case .coachingOnly: return "Programs and notes — no day-to-day workout data"
        case .minimal: return "Notes only"
        }
    }

    var scopes: [CollaborationVisibilityScope] {
        switch self {
        case .full:
            return CollaborationVisibilityScope.allCases
        case .coachingOnly:
            return [.programsAndRuns, .coachNotes]
        case .minimal:
            return [.coachNotes]
        }
    }
}

struct VisibilityScopeDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(VisibilityPreset.allCases) { preset in
                Section(preset.title) {
                    Text(preset.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(preset.scopes) { scope in
                        Label(scope.title, systemImage: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Privacy Presets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

// MARK: - Private Sharing

struct PrivateSharingCenterView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    var body: some View {
        List {
            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else {
                Section("Program Shares") {
                    if collaborationCoordinator.programShares.isEmpty {
                        Text("Share a saved program privately with someone you've connected to. Nothing is public.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(collaborationCoordinator.programShares) { share in
                            ShareRow(
                                title: "\(share.shareKind.title) → \(share.grantedToDisplayName)",
                                subtitle: share.status.rawValue.capitalized,
                                revoke: { await collaborationCoordinator.revokeProgramShare(share) }
                            )
                        }
                    }
                }

                Section("Progress Shares") {
                    if collaborationCoordinator.progressShares.isEmpty {
                        Text("Send a read-only card — a PR, a trend, an adherence streak — to a connected coach or training partner.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(collaborationCoordinator.progressShares) { share in
                            ShareRow(
                                title: "\(share.shareKind.title) → \(share.grantedToDisplayName)",
                                subtitle: share.summaryText,
                                revoke: { await collaborationCoordinator.revokeProgressShare(share) }
                            )
                        }
                    }
                }

                Section("Revocation") {
                    PrivacyRevocationExplainerView()
                }
            }
        }
        .navigationTitle("Private Sharing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ShareRow: View {
    let title: String
    let subtitle: String
    let revoke: () async -> Void

    @State private var showingConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(role: .destructive) {
                showingConfirm = true
            } label: {
                Label("Revoke Access", systemImage: "xmark.shield")
            }
            .buttonStyle(.borderless)
            .confirmationDialog(
                "Revoke this share?",
                isPresented: $showingConfirm,
                titleVisibility: .visible
            ) {
                Button("Revoke", role: .destructive) {
                    Task { await revoke() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They'll lose access immediately. You can share again later.")
            }
        }
        .padding(.vertical, 2)
    }
}

