//
//  CollaborationComposers.swift
//  SuggestMeSome
//
//  The six collaboration mutation composers (invite, blueprint save,
//  assignment, coach note, program share, progress share) plus the
//  FormComposerScaffold and small internal helpers (ProgressSharePayload,
//  nilIfEmpty extensions) they all share.
//
//  Split out of CollaborationViews.swift as part of the Feature 20 Phase 2
//  view-file fragmentation: every composer opens from a sheet in one of
//  the other surfaces, so grouping them here keeps the composer surface
//  discoverable without scrolling through 1,900 LOC of hub + detail code.
//

import SwiftUI
import SwiftData

// MARK: - Composers

struct CreateCoachInviteView: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    @AppStorage("collaboration.disclosure.invite.v1") private var hasAcceptedInviteDisclosure = false

    @State private var inviteeEmail = ""
    @State private var noteText = ""
    @State private var inviterRole: CollaborationRole = .coach
    @State private var preset: VisibilityPreset = .full
    @State private var acknowledgedInviteDisclosure = false

    var body: some View {
        FormComposerScaffold(
            title: "Send Invite",
            sendLabel: "Send",
            isSendDisabled: inviteeEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (!hasAcceptedInviteDisclosure && !acknowledgedInviteDisclosure),
            send: {
                await collaborationCoordinator.createCoachInvite(
                    inviteeEmail: inviteeEmail,
                    noteText: noteText.nilIfEmpty,
                    inviterRole: inviterRole,
                    scopes: preset.scopes.sorted { $0.rawValue < $1.rawValue }
                )
                if collaborationCoordinator.lastErrorMessage == nil {
                    hasAcceptedInviteDisclosure = true
                }
            }
        ) {
            Section("Sharing disclosure") {
                CollaborationSharingConsentView(
                    context: .coachInvite,
                    requiresAcknowledgement: !hasAcceptedInviteDisclosure,
                    isAcknowledged: $acknowledgedInviteDisclosure
                )
            }

            Section("Who") {
                TextField("Email", text: $inviteeEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                Picker("You're inviting them as your", selection: $inviterRole) {
                    ForEach(CollaborationRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
            }

            Section {
                Picker("Privacy", selection: $preset) {
                    ForEach(VisibilityPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Text(preset.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("What they'll see")
            } footer: {
                Text("You can change this any time after they accept.")
            }

            Section("Personal note") {
                TextField("Optional", text: $noteText, axis: .vertical)
            }
        }
        .onAppear {
            acknowledgedInviteDisclosure = hasAcceptedInviteDisclosure
        }
    }
}

struct BlueprintComposerView: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let program: TrainingProgram

    @State private var focusText = ""
    @State private var notesText = ""
    @State private var tagsText = ""

    var body: some View {
        FormComposerScaffold(
            title: "Save Program",
            sendLabel: "Save",
            isSendDisabled: false,
            send: {
                await collaborationCoordinator.saveBlueprint(
                    from: program,
                    focusText: focusText.nilIfEmpty,
                    notesText: notesText.nilIfEmpty,
                    tags: CSVListCodec.decode(tagsText)
                )
            }
        ) {
            Section("Program") {
                Text(program.name)
                Text("\(program.lengthInWeeks) weeks • \(program.sessionsPerWeek) sessions/week")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Details") {
                TextField("Focus (e.g. hypertrophy)", text: $focusText)
                TextField("Notes", text: $notesText, axis: .vertical)
                TextField("Tags (comma separated)", text: $tagsText)
            }
        }
    }
}

struct AssignmentComposerView: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let blueprint: SavedProgramBlueprint

    @State private var selectedRelationshipID = ""
    @State private var notesText = ""
    @State private var startGuidance = ""

    private var coachRelationships: [CoachRelationship] {
        collaborationCoordinator.coachRelationships.filter { $0.status == .active }
    }

    var body: some View {
        FormComposerScaffold(
            title: "Assign Program",
            sendLabel: "Send",
            isSendDisabled: selectedRelationshipID.isEmpty,
            send: {
                guard let relationship = coachRelationships.first(where: { $0.stableID == selectedRelationshipID }) else { return }
                await collaborationCoordinator.createAssignment(
                    relationship: relationship,
                    blueprint: blueprint,
                    notesText: notesText.nilIfEmpty,
                    startGuidance: startGuidance.nilIfEmpty
                )
            }
        ) {
            Section("Program") {
                Text(blueprint.name)
            }
            Section("Athlete") {
                if coachRelationships.isEmpty {
                    Text("No active athletes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Send to", selection: $selectedRelationshipID) {
                        ForEach(coachRelationships) { relationship in
                            Text(relationship.athleteDisplayName).tag(relationship.stableID)
                        }
                    }
                }
            }
            Section("Message") {
                TextField("Notes for the athlete", text: $notesText, axis: .vertical)
                TextField("How to start", text: $startGuidance, axis: .vertical)
            }
        }
        .onAppear {
            selectedRelationshipID = coachRelationships.first?.stableID ?? ""
        }
    }
}

struct CoachNoteComposerView: View {
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let relationship: CoachRelationship

    @State private var noteText = ""
    @State private var eventSummary = ""
    @State private var priority: CollaborationInsightPriority = .medium
    @State private var requiresReview = false

    var body: some View {
        FormComposerScaffold(
            title: "New Note",
            sendLabel: "Send",
            isSendDisabled: noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            send: {
                await collaborationCoordinator.createCoachNote(
                    relationship: relationship,
                    bodyText: noteText,
                    anchorKind: .general,
                    eventSummaryText: eventSummary.nilIfEmpty,
                    priority: priority,
                    requiresReview: requiresReview
                )
            }
        ) {
            Section("Note") {
                TextField("What do you want to say?", text: $noteText, axis: .vertical)
                TextField("Event summary (optional)", text: $eventSummary)
                Picker("Priority", selection: $priority) {
                    ForEach(CollaborationInsightPriority.allCases) { option in
                        Text(option.rawValue.capitalized).tag(option)
                    }
                }
                Toggle("Needs a follow-up", isOn: $requiresReview)
            }
        }
    }
}

struct ProgramShareComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let blueprint: SavedProgramBlueprint

    @AppStorage("collaboration.disclosure.privateShare.v1") private var hasAcceptedPrivateShareDisclosure = false

    @State private var selectedRelationshipID = ""
    @State private var messageText = ""
    @State private var shareKind: ProgramShareKind = .blueprint
    @State private var showingConfirm = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var acknowledgedPrivateShareDisclosure = false

    private var relationships: [CoachRelationship] {
        collaborationCoordinator.relationships.filter { $0.status == .active }
    }

    private var recipientName: String {
        relationships.first(where: { $0.stableID == selectedRelationshipID })?
            .participantDisplayName(for: collaborationCoordinator.currentAccountID) ?? ""
    }

    var body: some View {
        Form {
            if let errorMessage {
                InlineErrorBanner(message: errorMessage)
            }
            Section("Send to") {
                Picker("Recipient", selection: $selectedRelationshipID) {
                    ForEach(relationships) { relationship in
                        Text(relationship.participantDisplayName(for: collaborationCoordinator.currentAccountID))
                            .tag(relationship.stableID)
                    }
                }
                Picker("Share as", selection: $shareKind) {
                    ForEach(ProgramShareKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }
            Section("Sharing disclosure") {
                CollaborationSharingConsentView(
                    context: .programShare,
                    requiresAcknowledgement: !hasAcceptedPrivateShareDisclosure,
                    isAcknowledged: $acknowledgedPrivateShareDisclosure
                )
            }
            Section("Message") {
                TextField("Optional", text: $messageText, axis: .vertical)
            }
        }
        .navigationTitle("Share Program")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedRelationshipID = relationships.first?.stableID ?? ""
            acknowledgedPrivateShareDisclosure = hasAcceptedPrivateShareDisclosure
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                } else {
                    Button("Share") { showingConfirm = true }
                        .disabled(selectedRelationshipID.isEmpty || (!hasAcceptedPrivateShareDisclosure && !acknowledgedPrivateShareDisclosure))
                }
            }
        }
        .confirmationDialog(
            "Share with \(recipientName)?",
            isPresented: $showingConfirm,
            titleVisibility: .visible
        ) {
            Button("Share") { Task { await performShare() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll have read-only access to this program.")
        }
    }

    private func performShare() async {
        guard let relationship = relationships.first(where: { $0.stableID == selectedRelationshipID }) else { return }
        let recipientID = relationship.coachAccountID == collaborationCoordinator.currentAccountID
            ? relationship.athleteAccountID
            : relationship.coachAccountID
        isSending = true
        await collaborationCoordinator.createProgramShare(
            relationshipStableID: relationship.stableID,
            shareKind: shareKind,
            blueprintStableID: blueprint.stableID,
            sourceProgramStableID: nil,
            grantedToAccountID: recipientID,
            messageText: messageText.nilIfEmpty
        )
        isSending = false
        if let pending = collaborationCoordinator.lastErrorMessage {
            errorMessage = pending
        } else {
            hasAcceptedPrivateShareDisclosure = true
            dismiss()
        }
    }
}

struct ProgressShareComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let snapshot: InsightSnapshot

    @AppStorage("collaboration.disclosure.privateShare.v1") private var hasAcceptedPrivateShareDisclosure = false

    @State private var selectedRelationshipID = ""
    @State private var kind: ProgressShareKind = .completedBlockSummary
    @State private var showingConfirm = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var acknowledgedPrivateShareDisclosure = false

    private var relationships: [CoachRelationship] {
        collaborationCoordinator.relationships.filter { $0.status == .active }
    }

    private var recipientName: String {
        relationships.first(where: { $0.stableID == selectedRelationshipID })?
            .participantDisplayName(for: collaborationCoordinator.currentAccountID) ?? ""
    }

    var body: some View {
        Form {
            if let errorMessage {
                InlineErrorBanner(message: errorMessage)
            }
            Section("Snapshot") {
                Text(snapshot.headline)
                Text(snapshot.summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Send to") {
                Picker("Recipient", selection: $selectedRelationshipID) {
                    ForEach(relationships) { relationship in
                        Text(relationship.participantDisplayName(for: collaborationCoordinator.currentAccountID))
                            .tag(relationship.stableID)
                    }
                }
                Picker("Card type", selection: $kind) {
                    ForEach(ProgressShareKind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
            Section("Sharing disclosure") {
                CollaborationSharingConsentView(
                    context: .progressShare,
                    requiresAcknowledgement: !hasAcceptedPrivateShareDisclosure,
                    isAcknowledged: $acknowledgedPrivateShareDisclosure
                )
            }
        }
        .navigationTitle("Share Progress")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedRelationshipID = relationships.first?.stableID ?? ""
            acknowledgedPrivateShareDisclosure = hasAcceptedPrivateShareDisclosure
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                } else {
                    Button("Share") { showingConfirm = true }
                        .disabled(selectedRelationshipID.isEmpty || (!hasAcceptedPrivateShareDisclosure && !acknowledgedPrivateShareDisclosure))
                }
            }
        }
        .confirmationDialog(
            "Share with \(recipientName)?",
            isPresented: $showingConfirm,
            titleVisibility: .visible
        ) {
            Button("Share") { Task { await performShare() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll see a read-only card with this progress.")
        }
    }

    private func performShare() async {
        guard let relationship = relationships.first(where: { $0.stableID == selectedRelationshipID }) else { return }
        let recipientID = relationship.coachAccountID == collaborationCoordinator.currentAccountID
            ? relationship.athleteAccountID
            : relationship.coachAccountID
        let payload = ProgressSharePayload(
            snapshotStableID: snapshot.stableID,
            headline: snapshot.headline,
            summaryText: snapshot.summaryText
        )
        isSending = true
        await collaborationCoordinator.createProgressShare(
            relationshipStableID: relationship.stableID,
            shareKind: kind,
            grantedToAccountID: recipientID,
            titleText: snapshot.headline,
            subtitleText: snapshot.activeProgramName,
            summaryText: snapshot.summaryText,
            payloadJSON: payload.encodedJSON
        )
        isSending = false
        if let pending = collaborationCoordinator.lastErrorMessage {
            errorMessage = pending
        } else {
            hasAcceptedPrivateShareDisclosure = true
            dismiss()
        }
    }
}

// MARK: - Shared scaffold

private struct FormComposerScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollaborationCoordinator.self) private var collaborationCoordinator

    let title: String
    let sendLabel: String
    let isSendDisabled: Bool
    let send: () async -> Void
    @ViewBuilder let content: () -> Content

    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSendTrigger = 0

    var body: some View {
        Form {
            if let errorMessage {
                InlineErrorBanner(message: errorMessage)
            }
            content()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: didSendTrigger)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSending)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                } else {
                    Button(sendLabel) {
                        Task { await performSend() }
                    }
                    .disabled(isSendDisabled)
                }
            }
        }
    }

    private func performSend() async {
        isSending = true
        errorMessage = nil
        await send()
        isSending = false
        if let pending = collaborationCoordinator.lastErrorMessage {
            errorMessage = pending
        } else {
            didSendTrigger &+= 1
            dismiss()
        }
    }
}

// MARK: - Progress share payload

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

// MARK: - String trim helpers

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let self, !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return self
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
