//
//  CloudFeaturePreviewView.swift
//  SuggestMeSome
//
//  Feature 21 - Public, read-only preview mode for cloud, collaboration,
//  and premium account surfaces used by signed-out users and App Review.
//

import SwiftUI

struct CloudFeaturePreviewView: View {
    private let snapshot = CloudFeaturePreviewSnapshot.sample

    var body: some View {
        List {
            Section("Preview Mode") {
                Text(ComplianceConfiguration.cloudFeaturePreviewDisclosure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Label("Read-only sample data", systemImage: "eye")
                    .foregroundStyle(.secondary)
            }

            Section("Premium Unlock") {
                NavigationLink {
                    PaywallView(feature: .coachCollaboration)
                } label: {
                    Label("Open Premium Unlock Preview", systemImage: "star.circle.fill")
                }

                Text("Premium Unlock remains a one-time purchase. Manual workout logging stays free while cloud collaboration, coaching, and Apple Health features stay behind the premium gate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Sign In & Cloud Sync") {
                AccountSignInNoticeView()
                previewCard(
                    title: "Sample account snapshot",
                    systemImage: "person.crop.circle.badge.checkmark",
                    lines: [
                        "Name: \(snapshot.accountDisplayName)",
                        "Email: \(snapshot.accountEmail)",
                        "Preview sync status: \(snapshot.syncStatus)",
                        "Local logging remains available while signed out."
                    ]
                )
            }

            Section("Coach Collaboration") {
                previewCard(
                    title: "Sample coach roster",
                    systemImage: "person.2.wave.2.fill",
                    lines: snapshot.relationshipSummaries
                )

                previewCard(
                    title: "Sample assignment inbox",
                    systemImage: "tray.full.fill",
                    lines: snapshot.assignmentSummaries
                )

                previewCard(
                    title: "Sample coach notes",
                    systemImage: "text.bubble.fill",
                    lines: snapshot.noteSummaries
                )
            }

            Section("Private Sharing") {
                previewCard(
                    title: "Shared programs",
                    systemImage: "square.stack.3d.up.fill",
                    lines: snapshot.programShareSummaries
                )

                previewCard(
                    title: "Shared progress",
                    systemImage: "chart.line.uptrend.xyaxis.circle.fill",
                    lines: snapshot.progressShareSummaries
                )

                CollaborationSharingConsentView(context: .programShare)
                PrivacyRevocationExplainerView()
            }

            Section("Push Notifications") {
                PushNotificationNoticeView()
                previewCard(
                    title: "Sample notification mix",
                    systemImage: "bell.badge.fill",
                    lines: snapshot.notificationSummaries
                )
            }

            Section("Privacy Controls") {
                NavigationLink {
                    PrivacyChoicesView()
                } label: {
                    Label("Open Privacy Choices", systemImage: "slider.horizontal.3")
                }

                NavigationLink {
                    AboutThisGuidanceView()
                } label: {
                    Label("About This Guidance", systemImage: "heart.text.square.fill")
                }
            }
        }
        .navigationTitle("Preview Cloud Features")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func previewCard(
        title: String,
        systemImage: String,
        lines: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct CloudFeaturePreviewSnapshot: Equatable {
    let accountDisplayName: String
    let accountEmail: String
    let syncStatus: String
    let relationshipSummaries: [String]
    let assignmentSummaries: [String]
    let noteSummaries: [String]
    let programShareSummaries: [String]
    let progressShareSummaries: [String]
    let notificationSummaries: [String]

    static let sample = CloudFeaturePreviewSnapshot(
        accountDisplayName: "Preview Athlete",
        accountEmail: "preview-athlete@suggestmesome.app",
        syncStatus: "sample only, no backend connection",
        relationshipSummaries: [
            "Coach Jordan — readiness, workouts, and program visibility enabled",
            "Training partner Maya — private progress sharing only"
        ],
        assignmentSummaries: [
            "Lower Body Strength Week 3 — assigned yesterday",
            "Travel Deload Microcycle — starts Monday"
        ],
        noteSummaries: [
            "Coach note: Keep Tuesday's squat volume steady and flag any knee pain.",
            "Weekly digest: Training load held steady while recovery improved."
        ],
        programShareSummaries: [
            "Shared blueprint: Four-Day Strength Base — read-only access",
            "Editable block: Summer Push/Pull Cycle — coach can revise"
        ],
        progressShareSummaries: [
            "Progress card: Deadlift trend up 12 lb over 6 weeks",
            "Progress card: Recovery pressure moderate after two high-load sessions"
        ],
        notificationSummaries: [
            "Coach invites and acceptance updates",
            "Program assignments and note replies",
            "Digest summaries and missed-session nudges"
        ]
    )
}
