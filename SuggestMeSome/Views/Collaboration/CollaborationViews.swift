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

