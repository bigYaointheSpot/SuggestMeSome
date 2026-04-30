import SwiftData
import SwiftUI

// MARK: - Hub

struct CollaborationHubView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var showingInviteComposer = false

    private var isCoachCollaborationUnlocked: Bool {
        FeatureAccessPolicy.isAccessible(.coachCollaboration, entitlementState: purchaseManager.entitlementState)
    }

    var body: some View {
        List {
            CollaborationSummarySection()

            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else {
                if let errorMessage = collaborationCoordinator.lastErrorMessage {
                    Section {
                        InlineErrorBanner(message: errorMessage) {
                            await collaborationCoordinator.refreshAll(reason: "Retry from collaboration hub", force: true)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                Section("Your Coaches") {
                    NavigationLink {
                        MyCoachView()
                    } label: {
                        hubRow(
                            title: "My Coach",
                            subtitle: subtitle(for: collaborationCoordinator.athleteRelationships.count, singular: "active connection", plural: "active connections"),
                            systemImage: "person.crop.circle.badge.checkmark"
                        )
                    }

                    if isCoachCollaborationUnlocked {
                        NavigationLink {
                            CoachRosterView()
                        } label: {
                            hubRow(
                                title: "Athlete Roster",
                                subtitle: subtitle(for: collaborationCoordinator.coachRosterSnapshots.count, singular: "athlete snapshot", plural: "athlete snapshots"),
                                systemImage: "person.3.sequence.fill"
                            )
                        }
                    } else {
                        NavigationLink {
                            PaywallView(feature: .coachCollaboration)
                        } label: {
                            hubRow(
                                title: "Athlete Roster",
                                subtitle: "Premium — coach-side tools",
                                systemImage: "lock.circle"
                            )
                        }
                    }

                    Button {
                        showingInviteComposer = true
                    } label: {
                        Label("Send a Coach Invite", systemImage: "envelope.badge")
                    }
                    .disabled(!isCoachCollaborationUnlocked)
                }

                if !collaborationCoordinator.outgoingPendingInvites.isEmpty {
                    Section("Sent Invites") {
                        ForEach(collaborationCoordinator.outgoingPendingInvites) { invite in
                            InviteRow(invite: invite)
                        }
                    }
                }

                Section("Programs & Sharing") {
                    NavigationLink {
                        AssignmentInboxView()
                    } label: {
                        hubRow(
                            title: "From Your Coach",
                            subtitle: subtitle(for: collaborationCoordinator.inboxAssignments.count, singular: "pending program", plural: "pending programs"),
                            systemImage: "tray.full"
                        )
                    }

                    NavigationLink {
                        BlueprintLibraryView()
                    } label: {
                        hubRow(
                            title: "Saved Programs",
                            subtitle: subtitle(for: collaborationCoordinator.blueprints.count, singular: "saved program", plural: "saved programs"),
                            systemImage: "square.stack.3d.up.fill"
                        )
                    }

                    NavigationLink {
                        PrivateSharingCenterView()
                    } label: {
                        hubRow(
                            title: "Private Sharing",
                            subtitle: subtitle(for: collaborationCoordinator.programShares.count + collaborationCoordinator.progressShares.count, singular: "active share", plural: "active shares"),
                            systemImage: "person.crop.circle.badge.arrow.forward"
                        )
                    }
                }

                Section("Notes & Updates") {
                    NavigationLink {
                        CoachNotesInboxView()
                    } label: {
                        hubRow(
                            title: "Coach Notes",
                            subtitle: notesSubtitle,
                            systemImage: "text.bubble.fill"
                        )
                    }
                }

                if !collaborationCoordinator.recentActivity.isEmpty {
                    Section("Recent Activity") {
                        ForEach(collaborationCoordinator.recentActivity.prefix(6)) { activity in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(activity.message)
                                Text(activity.date, format: .dateTime.hour().minute().month(.abbreviated).day())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Collaboration")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await collaborationCoordinator.refreshAll(reason: "Pull-to-refresh", force: true)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if collaborationCoordinator.phase == .loading {
                    ProgressView()
                } else {
                    Button {
                        Task {
                            await collaborationCoordinator.refreshAll(reason: "Manual collaboration refresh", force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh collaboration")
                    .disabled(accountManager.currentUser == nil)
                }
            }
        }
        .sheet(isPresented: $showingInviteComposer) {
            NavigationStack {
                if isCoachCollaborationUnlocked {
                    CreateCoachInviteView()
                } else {
                    PaywallView(feature: .coachCollaboration)
                }
            }
        }
    }

    private var notesSubtitle: String {
        let unreadNotes = collaborationCoordinator.unreadCoachNotes.count
        let unreadDigests = collaborationCoordinator.unreadDigests.count
        if unreadNotes == 0 && unreadDigests == 0 {
            return "All caught up"
        }
        var parts: [String] = []
        if unreadNotes > 0 {
            parts.append("\(unreadNotes) new \(unreadNotes == 1 ? "note" : "notes")")
        }
        if unreadDigests > 0 {
            parts.append("\(unreadDigests) new \(unreadDigests == 1 ? "digest" : "digests")")
        }
        return parts.joined(separator: " • ")
    }

    private func subtitle(for count: Int, singular: String, plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }

    private func hubRow(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle).")
    }
}

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

private struct AssignmentCard: View {
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

private struct CoachNoteRow: View {
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

private struct VisibilityScopeDetailsView: View {
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

private struct ShareRow: View {
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

private struct CollaborationSummarySection: View {
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

private struct CollaborationSignedOutSection: View {
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

private struct InviteRow: View {
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

private struct NotificationPreferenceDraft {
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
