import SwiftData
import SwiftUI

struct CollaborationHubView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var showingInviteComposer = false

    var body: some View {
        List {
            CollaborationSummarySection()

            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else {
                Section("Relationships") {
                    NavigationLink {
                        MyCoachView()
                    } label: {
                        hubRow(
                            title: "My Coach",
                            subtitle: "\(collaborationCoordinator.athleteRelationships.count) active coach relationship(s)",
                            systemImage: "person.crop.circle.badge.checkmark"
                        )
                    }

                    if FeatureAccessPolicy.isAccessible(.coachCollaboration, entitlementState: purchaseManager.entitlementState) {
                        NavigationLink {
                            CoachRosterView()
                        } label: {
                            hubRow(
                                title: "Coach Roster",
                                subtitle: "\(collaborationCoordinator.coachRosterSnapshots.count) athlete snapshot(s)",
                                systemImage: "person.3.sequence.fill"
                            )
                        }
                    } else {
                        NavigationLink {
                            PaywallView(feature: .coachCollaboration)
                        } label: {
                            hubRow(
                                title: "Coach Roster",
                                subtitle: "Premium unlock required for coach-facing tools",
                                systemImage: "lock.circle"
                            )
                        }
                    }

                    Button {
                        showingInviteComposer = true
                    } label: {
                        Label("Send Coach Invite", systemImage: "envelope.badge")
                    }
                    .disabled(!FeatureAccessPolicy.isAccessible(.coachCollaboration, entitlementState: purchaseManager.entitlementState))
                }

                if collaborationCoordinator.outgoingPendingInvites.isEmpty == false {
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
                            title: "Assignment Inbox",
                            subtitle: "\(collaborationCoordinator.inboxAssignments.count) pending assignment(s)",
                            systemImage: "tray.full"
                        )
                    }

                    NavigationLink {
                        BlueprintLibraryView()
                    } label: {
                        hubRow(
                            title: "Blueprint Library",
                            subtitle: "\(collaborationCoordinator.blueprints.count) saved blueprint(s)",
                            systemImage: "square.stack.3d.up.fill"
                        )
                    }

                    NavigationLink {
                        PrivateSharingCenterView()
                    } label: {
                        hubRow(
                            title: "Private Sharing",
                            subtitle: "\(collaborationCoordinator.programShares.count + collaborationCoordinator.progressShares.count) active share(s)",
                            systemImage: "person.crop.circle.badge.arrow.forward"
                        )
                    }
                }

                Section("Coach Notes & Digests") {
                    NavigationLink {
                        CoachNotesInboxView()
                    } label: {
                        hubRow(
                            title: "Coach Notes",
                            subtitle: "\(collaborationCoordinator.unreadCoachNotes.count) unread note(s), \(collaborationCoordinator.unreadDigests.count) unread digest(s)",
                            systemImage: "text.bubble.fill"
                        )
                    }
                }

                if let statusMessage = collaborationCoordinator.statusMessage {
                    Section("Status") {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastErrorMessage = collaborationCoordinator.lastErrorMessage {
                    Section("Issue") {
                        Text(lastErrorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if collaborationCoordinator.recentActivity.isEmpty == false {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await collaborationCoordinator.refreshAll(reason: "Manual collaboration refresh")
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(accountManager.currentUser == nil)
            }
        }
        .sheet(isPresented: $showingInviteComposer) {
            NavigationStack {
                if FeatureAccessPolicy.isAccessible(.coachCollaboration, entitlementState: purchaseManager.entitlementState) {
                    CreateCoachInviteView()
                } else {
                    PaywallView(feature: .coachCollaboration)
                }
            }
        }
    }

    private func hubRow(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct NotificationPreferencesView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(PushNotificationManager.self) private var pushNotificationManager

    @State private var draft = NotificationPreferenceDraft()

    var body: some View {
        List {
            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else {
                Section {
                    LabeledContent("Status", value: pushNotificationManager.authorizationState.title)
                    if let deviceToken = pushNotificationManager.deviceTokenHex {
                        LabeledContent("Device Token", value: String(deviceToken.prefix(12)) + "…")
                    }
                    Button("Enable Push Notifications") {
                        Task {
                            await collaborationCoordinator.requestPushAuthorization()
                        }
                    }
                    .disabled(pushNotificationManager.authorizationState == .authorized || pushNotificationManager.authorizationState == .provisional)
                } header: {
                    Text("Push Access")
                } footer: {
                    Text("Push is the only outbound delivery channel in Feature 19. Notifications deep-link into the existing iPhone surfaces.")
                }

                Section {
                    preferenceToggle(.coachInvites)
                    preferenceToggle(.assignmentUpdates)
                    preferenceToggle(.coachNotes)
                    preferenceToggle(.missedSessionNudges)
                    preferenceToggle(.checkInReminders)
                    preferenceToggle(.pendingProposalReminders)
                    preferenceToggle(.weeklyDigests)
                } header: {
                    Text("Coach Collaboration Alerts")
                }

                Section {
                    Button("Save Preferences") {
                        Task {
                            await collaborationCoordinator.updateNotificationPreferences(draft.asRequest())
                        }
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draft = NotificationPreferenceDraft(
                preference: collaborationCoordinator.notificationPreference
            )
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MyCoachView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    var body: some View {
        List {
            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else if collaborationCoordinator.shouldShowMyCoachEmptyState {
                ContentUnavailableView(
                    "No Coach Yet",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Accept an invite or ask your coach to send one to connect training, assignments, notes, and deterministic insights.")
                )
            } else {
                if collaborationCoordinator.incomingPendingInvites.isEmpty == false {
                    Section("Pending Invites") {
                        ForEach(collaborationCoordinator.incomingPendingInvites) { invite in
                            InviteRow(invite: invite)
                        }
                    }
                }

                if collaborationCoordinator.athleteRelationships.isEmpty == false {
                    Section("Active Coach Relationships") {
                        ForEach(collaborationCoordinator.athleteRelationships) { relationship in
                            NavigationLink {
                                RelationshipDetailView(relationship: relationship)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(relationship.participantDisplayName(for: collaborationCoordinator.currentAccountID))
                                        .font(.headline)
                                    Text("\(relationship.unreadCoachNoteCount) unread notes • \(relationship.pendingAssignmentCount) pending assignments")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("My Coach")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CoachRosterView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(PurchaseManager.self) private var purchaseManager

    var body: some View {
        Group {
            if !FeatureAccessPolicy.isAccessible(.coachCollaboration, entitlementState: purchaseManager.entitlementState) {
                PaywallView(feature: .coachCollaboration)
            } else {
                List {
                    if accountManager.currentUser == nil {
                        CollaborationSignedOutSection()
                    } else if collaborationCoordinator.coachRosterSnapshots.isEmpty {
                        ContentUnavailableView(
                            "No Athlete Snapshots Yet",
                            systemImage: "person.3.sequence",
                            description: Text("As invite-only relationships go live, deterministic athlete snapshots will appear here with sync freshness, adherence, fatigue, and review priorities.")
                        )
                    } else {
                        ForEach(collaborationCoordinator.coachRosterSnapshots) { snapshot in
                            NavigationLink {
                                InsightSnapshotDetailView(snapshot: snapshot)
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
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Coach Roster")
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
                Section("Saved Blueprints") {
                    if collaborationCoordinator.blueprints.isEmpty {
                        Text("Save an existing program into your account-backed blueprint library to reuse, assign, and privately share it later.")
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

                Section("Save Existing Program") {
                    if programs.isEmpty {
                        Text("Build or generate a program first, then save it into your immutable blueprint library.")
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
        .navigationTitle("Blueprint Library")
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
            Section("Blueprint") {
                LabeledContent("Name", value: blueprint.name)
                if let focusText = blueprint.focusText, !focusText.isEmpty {
                    LabeledContent("Focus", value: focusText)
                }
                LabeledContent("Duration", value: "\(blueprint.durationWeeks) weeks")
                LabeledContent("Sessions / Week", value: "\(blueprint.sessionsPerWeek)")
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
                Button("Assign to Athlete") {
                    showingAssignmentComposer = true
                }
                .disabled(!FeatureAccessPolicy.isAccessible(.coachCollaboration, entitlementState: purchaseManager.entitlementState))

                Button("Share Privately") {
                    showingProgramShareComposer = true
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

struct AssignmentInboxView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    var body: some View {
        List {
            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else if collaborationCoordinator.inboxAssignments.isEmpty {
                ContentUnavailableView(
                    "No Assignments Yet",
                    systemImage: "tray",
                    description: Text("Assignments from a coach will appear here. Accepted assignments clone a blueprint into your personal training graph and then pull through Cloud Sync.")
                )
            } else {
                ForEach(collaborationCoordinator.inboxAssignments) { assignment in
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(assignment.athleteAccountID == collaborationCoordinator.currentAccountID ? assignment.coachDisplayName : assignment.athleteDisplayName)
                                .font(.headline)
                            Text(assignment.status.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.indigo.opacity(0.12))
                                .foregroundStyle(.indigo)
                                .clipShape(Capsule())
                            if let notesText = assignment.notesText, !notesText.isEmpty {
                                Text(notesText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if let startGuidance = assignment.startGuidance, !startGuidance.isEmpty {
                                Text(startGuidance)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if collaborationCoordinator.canActOnAssignment(assignment) {
                                HStack {
                                    Button("Accept") {
                                        Task {
                                            await collaborationCoordinator.updateAssignmentStatus(assignment, status: .accepted)
                                        }
                                    }
                                    Button("Decline", role: .destructive) {
                                        Task {
                                            await collaborationCoordinator.updateAssignmentStatus(assignment, status: .declined)
                                        }
                                    }
                                    Button("Archive") {
                                        Task {
                                            await collaborationCoordinator.updateAssignmentStatus(assignment, status: .archived)
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Assignments")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CoachNotesInboxView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    var body: some View {
        List {
            if accountManager.currentUser == nil {
                CollaborationSignedOutSection()
            } else {
                if collaborationCoordinator.notes.isEmpty == false {
                    Section("Coach Notes") {
                        ForEach(collaborationCoordinator.notes) { note in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(note.authorDisplayName)
                                        .font(.headline)
                                    Spacer()
                                    if note.isUnread {
                                        Text("Unread")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.indigo)
                                    }
                                }
                                Text(note.bodyText)
                                if let summary = note.eventSummaryText {
                                    Text(summary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Button("Mark Read") {
                                    Task {
                                        await collaborationCoordinator.markNoteRead(note)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!note.isUnread)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if collaborationCoordinator.weeklyDigests.isEmpty == false {
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
                    ContentUnavailableView(
                        "No Notes Yet",
                        systemImage: "text.bubble",
                        description: Text("Coach notes, deterministic nudges, and weekly digests will surface here.")
                    )
                }
            }
        }
        .navigationTitle("Coach Notes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RelationshipDetailView: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(PurchaseManager.self) private var purchaseManager

    let relationship: CoachRelationship

    @State private var scopeSelection: Set<CollaborationVisibilityScope> = []
    @State private var showingNoteComposer = false

    var body: some View {
        List {
            Section("Relationship") {
                LabeledContent("Coach", value: relationship.coachDisplayName)
                LabeledContent("Athlete", value: relationship.athleteDisplayName)
                LabeledContent("Status", value: relationship.status.title)
                LabeledContent("Unread Notes", value: "\(relationship.unreadCoachNoteCount)")
                LabeledContent("Pending Assignments", value: "\(relationship.pendingAssignmentCount)")
            }

            Section("Visibility Scopes") {
                ForEach(CollaborationVisibilityScope.allCases) { scope in
                    Toggle(
                        scope.title,
                        isOn: Binding(
                            get: { scopeSelection.contains(scope) },
                            set: { isEnabled in
                                if isEnabled {
                                    scopeSelection.insert(scope)
                                } else {
                                    scopeSelection.remove(scope)
                                }
                            }
                        )
                    )
                }

                Button("Save Scope Changes") {
                    Task {
                        await collaborationCoordinator.updateRelationshipScopes(
                            relationship,
                            scopes: Array(scopeSelection).sorted { $0.rawValue < $1.rawValue }
                        )
                    }
                }
            }

            if FeatureAccessPolicy.isAccessible(.coachCollaboration, entitlementState: purchaseManager.entitlementState)
                && collaborationCoordinator.canWriteCoachNote(for: relationship) {
                Section("Coach Actions") {
                    Button("Write Coach Note") {
                        showingNoteComposer = true
                    }
                }
            }
        }
        .navigationTitle(relationship.participantDisplayName(for: collaborationCoordinator.currentAccountID))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            scopeSelection = Set(relationship.visibilityScopes)
        }
        .sheet(isPresented: $showingNoteComposer) {
            NavigationStack {
                CoachNoteComposerView(relationship: relationship)
            }
        }
    }
}

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
                        Text("Saved blueprints and editable programs can be shared privately with specific accounts. There is no public feed or discovery layer.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(collaborationCoordinator.programShares) { share in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(share.shareKind.title) → \(share.grantedToDisplayName)")
                                    .font(.headline)
                                Text(share.status.rawValue.capitalized)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button("Revoke") {
                                    Task {
                                        await collaborationCoordinator.revokeProgramShare(share)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Progress Shares") {
                    if collaborationCoordinator.progressShares.isEmpty {
                        Text("PR highlights, lift trends, adherence streaks, and completed-block summaries can be shared as invite-scoped, read-only cards.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(collaborationCoordinator.progressShares) { share in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(share.shareKind.title) → \(share.grantedToDisplayName)")
                                    .font(.headline)
                                Text(share.summaryText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button("Revoke") {
                                    Task {
                                        await collaborationCoordinator.revokeProgressShare(share)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Private Sharing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
                Button("Share This Snapshot") {
                    showingProgressShareComposer = true
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
                List {
                    InviteRow(invite: invite)
                }
                .navigationTitle("Invite")
            } else {
                routeUnavailableView("Invite")
            }
        case .relationship(let stableID):
            if let relationship = collaborationCoordinator.relationships.first(where: { $0.stableID == stableID }) {
                RelationshipDetailView(relationship: relationship)
            } else {
                routeUnavailableView("Relationship")
            }
        case .assignment(let stableID):
            if let assignment = collaborationCoordinator.assignments.first(where: { $0.stableID == stableID }) {
                List {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(assignment.status.title)
                            .font(.headline)
                        if let notesText = assignment.notesText {
                            Text(notesText)
                        }
                    }
                }
                .navigationTitle("Assignment")
            } else {
                routeUnavailableView("Assignment")
            }
        case .coachNote(let stableID):
            if let note = collaborationCoordinator.notes.first(where: { $0.stableID == stableID }) {
                List {
                    Text(note.bodyText)
                }
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
                routeUnavailableView("Blueprint")
            }
        case .programShare:
            PrivateSharingCenterView()
        case .progressShare:
            PrivateSharingCenterView()
        case .coachRoster:
            CoachRosterView()
        case .notificationPreferences:
            NotificationPreferencesView()
        }
    }

    private func routeUnavailableView(_ title: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "questionmark.circle",
            description: Text("This route is no longer available on this device. Pull to refresh collaboration data and try again.")
        )
    }
}

struct CollaborationInsightSummaryCard: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    var body: some View {
        if let snapshot = collaborationCoordinator.athleteFacingSnapshots.first {
            VStack(alignment: .leading, spacing: 10) {
                Label("Cloud Insight", systemImage: "icloud.fill")
                    .font(.headline)
                    .foregroundStyle(.indigo)
                Text(snapshot.headline)
                    .font(.title3.weight(.semibold))
                Text(snapshot.summaryText)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let adherence = snapshot.recentAdherenceScore {
                        Label("\(Int(adherence.rounded()))% adherence", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if snapshot.unreadCoachNoteCount > 0 {
                        Label("\(snapshot.unreadCoachNoteCount) unread notes", systemImage: "text.bubble.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.indigo.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct DailyCoachCloudUpdatesCard: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator
    @Environment(PushNotificationManager.self) private var pushNotificationManager

    var body: some View {
        if collaborationCoordinator.unreadCoachNotes.isEmpty == false ||
            collaborationCoordinator.unreadDigests.isEmpty == false ||
            pushNotificationManager.lastNudgeExplanation != nil {
            VStack(alignment: .leading, spacing: 10) {
                Label("Coach Updates", systemImage: "bell.badge.fill")
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
                        Text("Latest note from \(note.authorDisplayName)")
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
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct CollaborationSummarySection: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    var body: some View {
        Section("Cloud Collaboration") {
            LabeledContent("Status", value: collaborationCoordinator.phase.title)
            if let currentUser = accountManager.currentUser {
                LabeledContent("Account", value: currentUser.email)
            }
            Text(collaborationCoordinator.statusSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Invite-only coach workflows, deterministic cloud insights, and private sharing stay separate from the personal Feature 18 sync batch and never include Apple Health-derived recovery data in this release.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CollaborationSignedOutSection: View {
    var body: some View {
        Section("Connect Account") {
            Text("Sign in with Apple from Account & Cloud to use invite-only coach collaboration, private sharing, assignment inboxes, and deterministic cloud insights.")
                .foregroundStyle(.secondary)
            NavigationLink {
                AccountSettingsView()
            } label: {
                Label("Open Account Settings", systemImage: "person.crop.circle.badge.plus")
            }
        }
    }
}

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
                Text(invite.status.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.12))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())
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
                HStack {
                    Button("Accept") {
                        Task {
                            await collaborationCoordinator.respondToInvite(invite, action: .accepted)
                        }
                    }
                    Button("Decline", role: .destructive) {
                        Task {
                            await collaborationCoordinator.respondToInvite(invite, action: .declined)
                        }
                    }
                }
                .buttonStyle(.bordered)
            } else if presentationMode == .outgoingPending {
                Button("Revoke", role: .destructive) {
                    Task {
                        await collaborationCoordinator.revokeInvite(invite)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CreateCoachInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    @State private var inviteeEmail = ""
    @State private var noteText = ""
    @State private var inviterRole: CollaborationRole = .coach
    @State private var selectedScopes = Set(CollaborationVisibilityScope.defaultInviteScopes)

    var body: some View {
        Form {
            Section("Invitee") {
                TextField("Email", text: $inviteeEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                Picker("You Are Inviting As", selection: $inviterRole) {
                    ForEach(CollaborationRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
            }

            Section("Visibility Scopes") {
                ForEach(CollaborationVisibilityScope.allCases) { scope in
                    Toggle(
                        scope.title,
                        isOn: Binding(
                            get: { selectedScopes.contains(scope) },
                            set: { isEnabled in
                                if isEnabled {
                                    selectedScopes.insert(scope)
                                } else {
                                    selectedScopes.remove(scope)
                                }
                            }
                        )
                    )
                }
            }

            Section("Note") {
                TextField("Optional note", text: $noteText, axis: .vertical)
            }
        }
        .navigationTitle("Send Invite")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Send") {
                    Task {
                        await collaborationCoordinator.createCoachInvite(
                            inviteeEmail: inviteeEmail,
                            noteText: noteText.nilIfEmpty,
                            inviterRole: inviterRole,
                            scopes: Array(selectedScopes).sorted { $0.rawValue < $1.rawValue }
                        )
                        dismiss()
                    }
                }
                .disabled(inviteeEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct BlueprintComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let program: TrainingProgram

    @State private var focusText = ""
    @State private var notesText = ""
    @State private var tagsText = ""

    var body: some View {
        Form {
            Section("Program") {
                Text(program.name)
                Text("\(program.lengthInWeeks) weeks • \(program.sessionsPerWeek) sessions/week")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Blueprint Metadata") {
                TextField("Focus", text: $focusText)
                TextField("Notes", text: $notesText, axis: .vertical)
                TextField("Tags (comma separated)", text: $tagsText)
            }
        }
        .navigationTitle("Save Blueprint")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await collaborationCoordinator.saveBlueprint(
                            from: program,
                            focusText: focusText.nilIfEmpty,
                            notesText: notesText.nilIfEmpty,
                            tags: CSVListCodec.decode(tagsText)
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AssignmentComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let blueprint: SavedProgramBlueprint

    @State private var selectedRelationshipID = ""
    @State private var notesText = ""
    @State private var startGuidance = ""

    private var coachRelationships: [CoachRelationship] {
        collaborationCoordinator.coachRelationships.filter { $0.status == .active }
    }

    var body: some View {
        Form {
            Section("Blueprint") {
                Text(blueprint.name)
            }

            Section("Athlete") {
                Picker("Relationship", selection: $selectedRelationshipID) {
                    ForEach(coachRelationships) { relationship in
                        Text(relationship.athleteDisplayName).tag(relationship.stableID)
                    }
                }
            }

            Section("Delivery") {
                TextField("Notes", text: $notesText, axis: .vertical)
                TextField("Start guidance", text: $startGuidance, axis: .vertical)
            }
        }
        .navigationTitle("Assign Blueprint")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedRelationshipID = coachRelationships.first?.stableID ?? ""
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Send") {
                    guard let relationship = coachRelationships.first(where: { $0.stableID == selectedRelationshipID }) else {
                        return
                    }
                    Task {
                        await collaborationCoordinator.createAssignment(
                            relationship: relationship,
                            blueprint: blueprint,
                            notesText: notesText.nilIfEmpty,
                            startGuidance: startGuidance.nilIfEmpty
                        )
                        dismiss()
                    }
                }
                .disabled(selectedRelationshipID.isEmpty)
            }
        }
    }
}

private struct CoachNoteComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let relationship: CoachRelationship

    @State private var noteText = ""
    @State private var eventSummary = ""
    @State private var priority: CollaborationInsightPriority = .medium
    @State private var requiresReview = false

    var body: some View {
        Form {
            Section("Note") {
                TextField("Coach note", text: $noteText, axis: .vertical)
                TextField("Optional event summary", text: $eventSummary)
                Picker("Priority", selection: $priority) {
                    ForEach(CollaborationInsightPriority.allCases) { option in
                        Text(option.rawValue.capitalized).tag(option)
                    }
                }
                Toggle("Requires review", isOn: $requiresReview)
            }
        }
        .navigationTitle("Coach Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Send") {
                    Task {
                        await collaborationCoordinator.createCoachNote(
                            relationship: relationship,
                            bodyText: noteText,
                            anchorKind: .general,
                            eventSummaryText: eventSummary.nilIfEmpty,
                            priority: priority,
                            requiresReview: requiresReview
                        )
                        dismiss()
                    }
                }
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct ProgramShareComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let blueprint: SavedProgramBlueprint

    @State private var selectedRelationshipID = ""
    @State private var messageText = ""
    @State private var shareKind: ProgramShareKind = .blueprint

    private var relationships: [CoachRelationship] {
        collaborationCoordinator.relationships.filter { $0.status == .active }
    }

    var body: some View {
        Form {
            Section("Recipient") {
                Picker("Relationship", selection: $selectedRelationshipID) {
                    ForEach(relationships) { relationship in
                        Text(relationship.participantDisplayName(for: collaborationCoordinator.currentAccountID))
                            .tag(relationship.stableID)
                    }
                }
                Picker("Share Type", selection: $shareKind) {
                    ForEach(ProgramShareKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }

            Section("Message") {
                TextField("Optional message", text: $messageText, axis: .vertical)
            }
        }
        .navigationTitle("Share Blueprint")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedRelationshipID = relationships.first?.stableID ?? ""
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Share") {
                    guard let relationship = relationships.first(where: { $0.stableID == selectedRelationshipID }) else {
                        return
                    }
                    let recipientID = relationship.coachAccountID == collaborationCoordinator.currentAccountID
                        ? relationship.athleteAccountID
                        : relationship.coachAccountID
                    Task {
                        await collaborationCoordinator.createProgramShare(
                            relationshipStableID: relationship.stableID,
                            shareKind: shareKind,
                            blueprintStableID: blueprint.stableID,
                            sourceProgramStableID: nil,
                            grantedToAccountID: recipientID,
                            messageText: messageText.nilIfEmpty
                        )
                        dismiss()
                    }
                }
                .disabled(selectedRelationshipID.isEmpty)
            }
        }
    }
}

private struct ProgressShareComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let snapshot: InsightSnapshot

    @State private var selectedRelationshipID = ""
    @State private var kind: ProgressShareKind = .completedBlockSummary

    private var relationships: [CoachRelationship] {
        collaborationCoordinator.relationships.filter { $0.status == .active }
    }

    var body: some View {
        Form {
            Section("Snapshot") {
                Text(snapshot.headline)
                Text(snapshot.summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Recipient") {
                Picker("Relationship", selection: $selectedRelationshipID) {
                    ForEach(relationships) { relationship in
                        Text(relationship.participantDisplayName(for: collaborationCoordinator.currentAccountID))
                            .tag(relationship.stableID)
                    }
                }
                Picker("Card Type", selection: $kind) {
                    ForEach(ProgressShareKind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
        }
        .navigationTitle("Share Progress")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedRelationshipID = relationships.first?.stableID ?? ""
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Share") {
                    guard let relationship = relationships.first(where: { $0.stableID == selectedRelationshipID }) else {
                        return
                    }
                    let recipientID = relationship.coachAccountID == collaborationCoordinator.currentAccountID
                        ? relationship.athleteAccountID
                        : relationship.coachAccountID
                    let payload = ProgressSharePayload(
                        snapshotStableID: snapshot.stableID,
                        headline: snapshot.headline,
                        summaryText: snapshot.summaryText
                    )
                    Task {
                        await collaborationCoordinator.createProgressShare(
                            relationshipStableID: relationship.stableID,
                            shareKind: kind,
                            grantedToAccountID: recipientID,
                            titleText: snapshot.headline,
                            subtitleText: snapshot.activeProgramName,
                            summaryText: snapshot.summaryText,
                            payloadJSON: payload.encodedJSON
                        )
                        dismiss()
                    }
                }
                .disabled(selectedRelationshipID.isEmpty)
            }
        }
    }
}

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
        case .coachInvites:
            coachInvitesEnabled = isEnabled
        case .assignmentUpdates:
            assignmentUpdatesEnabled = isEnabled
        case .coachNotes:
            coachNotesEnabled = isEnabled
        case .missedSessionNudges:
            missedSessionNudgesEnabled = isEnabled
        case .checkInReminders:
            checkInRemindersEnabled = isEnabled
        case .pendingProposalReminders:
            pendingProposalRemindersEnabled = isEnabled
        case .weeklyDigests:
            weeklyDigestsEnabled = isEnabled
        }
    }

    func value(for category: CollaborationNotificationCategory) -> Bool {
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

private struct ProgressSharePayload: Codable {
    let snapshotStableID: String
    let headline: String
    let summaryText: String

    var encodedJSON: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let self, self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return self
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
