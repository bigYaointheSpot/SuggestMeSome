//
//  AccountPrivacyViews.swift
//  SuggestMeSome
//
//  Feature 15 - Account, privacy-rights, and consent views for U.S. launch
//  readiness and future cloud-account rollout.
//

import SwiftUI

struct AccountSettingsView: View {
    @Environment(AccountManager.self) private var accountManager

    @State private var email = ""
    @State private var displayName = ""

    var body: some View {
        List {
            accountModeSection
            if let currentUser = accountManager.currentUser {
                signedInSection(currentUser)
                privacyHistorySection(accountManager.currentAccountPrivacyRequests)
            } else {
                signedOutSection
            }
            messageSection
        }
        .navigationTitle("Account & Cloud")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if email.isEmpty {
                email = accountManager.currentUser?.email ?? ""
            }
            if displayName.isEmpty {
                displayName = accountManager.currentUser?.displayName ?? ""
            }
        }
    }

    private var accountModeSection: some View {
        Section("Launch Mode") {
            LabeledContent("Mode", value: accountManager.launchMode.title)
            Text(accountManager.launchMode.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(ComplianceConfiguration.cloudSyncStorageDisclosure)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func signedInSection(_ account: UserAccount) -> some View {
        Section {
            LabeledContent("Name", value: account.displayName)
            LabeledContent("Email", value: account.email)
            LabeledContent(
                "Created",
                value: account.createdAt.formatted(date: .abbreviated, time: .shortened)
            )
            LabeledContent(
                "Last Sign-In",
                value: account.lastSignedInAt.formatted(date: .abbreviated, time: .shortened)
            )

            NavigationLink {
                DataExportRequestView()
            } label: {
                Label("Access & Export Requests", systemImage: "square.and.arrow.up.on.square")
            }

            NavigationLink {
                PrivacyChoicesView()
            } label: {
                Label("Privacy Choices", systemImage: "slider.horizontal.3")
            }

            NavigationLink {
                DeleteAccountView()
            } label: {
                Label("Delete Account", systemImage: "trash")
                    .foregroundStyle(.red)
            }

            Button("Sign Out") {
                Task {
                    await accountManager.signOut()
                }
            }
        } header: {
            Text("Current Account")
        } footer: {
            Text("Use this screen to validate account, consent, and privacy-rights flows before enabling a production backend.")
        }
    }

    private var signedOutSection: some View {
        Section {
            Text("Create a local contract-validation account to exercise privacy-rights and deletion flows before your production backend is live.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("Display Name", text: $displayName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()

            Button("Create Account on This Device") {
                Task {
                    await accountManager.createAccount(
                        displayName: displayName,
                        email: email
                    )
                }
            }

            Button("Sign In to Existing Local Account") {
                Task {
                    await accountManager.signIn(email: email)
                }
            }

            if accountManager.knownAccounts.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Known Local Accounts")
                        .font(.footnote.weight(.semibold))
                    ForEach(accountManager.knownAccounts) { account in
                        Text("\(account.displayName) • \(account.email)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        } header: {
            Text("Create or Sign In")
        } footer: {
            Text("This build does not transmit account data off device. Replace the local contract service with your production backend before public cloud launch.")
        }
    }

    private func privacyHistorySection(_ requests: [PrivacyRequestRecord]) -> some View {
        Section("Recent Privacy Requests") {
            if requests.isEmpty {
                Text("No privacy requests submitted from this account yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(requests.prefix(5)) { request in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(request.type.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(request.status.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.indigo.opacity(0.12))
                                .foregroundStyle(.indigo)
                                .clipShape(Capsule())
                        }
                        Text(request.requestedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(request.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if let statusMessage = accountManager.statusMessage {
            Section("Status") {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
            }
        }

        if let errorMessage = accountManager.lastErrorMessage {
            Section("Issue") {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct DataExportRequestView: View {
    @Environment(AccountManager.self) private var accountManager

    @State private var exportURL: URL?
    @State private var isGeneratingExport = false

    var body: some View {
        List {
            Section("Cloud Rights Requests") {
                Text("Use these controls to record access and export requests for backend-held account and consumer health data once your production backend is connected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Submit Access Request") {
                    Task {
                        await accountManager.submitPrivacyRequest(.access)
                    }
                }
                .disabled(accountManager.currentUser == nil)

                Button("Submit Export Request") {
                    Task {
                        await accountManager.submitPrivacyRequest(.export)
                    }
                }
                .disabled(accountManager.currentUser == nil)
            }

            Section {
                Button {
                    generateExport()
                } label: {
                    if isGeneratingExport {
                        ProgressView("Generating Export…")
                    } else {
                        Label("Generate Local Account Export", systemImage: "doc.badge.gearshape")
                    }
                }
                .disabled(accountManager.currentUser == nil || isGeneratingExport)

                if let exportURL {
                    ShareLink(
                        item: exportURL,
                        subject: Text("SuggestMeSome Account Export"),
                        message: Text("Local account and privacy export from SuggestMeSome.")
                    ) {
                        Label("Share Export File", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Local Contract Export")
            } footer: {
                Text("This JSON export contains the current local account profile, privacy request history, and consumer health consent records stored on this device.")
            }

            if accountManager.currentAccountPrivacyRequests.isEmpty == false {
                Section("Request History") {
                    ForEach(accountManager.currentAccountPrivacyRequests) { request in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.type.title)
                                .font(.subheadline.weight(.semibold))
                            Text(request.status.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(request.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Access & Export")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func generateExport() {
        guard let account = accountManager.currentUser else { return }
        isGeneratingExport = true
        defer { isGeneratingExport = false }

        struct ExportPayload: Codable {
            let account: UserAccount
            let privacyRequests: [PrivacyRequestRecord]
            let consumerHealthConsents: [ConsumerHealthConsentRecord]
            let generatedAt: Date
            let launchMode: AccountBackendLaunchMode
        }

        let payload = ExportPayload(
            account: account,
            privacyRequests: accountManager.currentAccountPrivacyRequests,
            consumerHealthConsents: accountManager.consumerHealthConsents.filter { $0.accountID == account.id },
            generatedAt: Date(),
            launchMode: accountManager.launchMode
        )

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuggestMeSome_Account_Export.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: destination, options: .atomic)
        exportURL = destination
    }
}

struct PrivacyChoicesView: View {
    @Environment(AccountManager.self) private var accountManager

    @State private var consumerHealthSyncEnabled = false

    var body: some View {
        List {
            Section("Consumer Health Sync Consent") {
                Toggle("Allow future account sync for consumer health data", isOn: $consumerHealthSyncEnabled)
                    .disabled(accountManager.currentUser == nil)

                Text(ComplianceConfiguration.consumerHealthDataDisclosure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(ComplianceConfiguration.cloudSyncStorageDisclosure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(ComplianceConfiguration.doctorCheckDisclosure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ComplianceConfiguration.consumerHealthConsentCategories, id: \.self) { category in
                    Text(category)
                }
            } header: {
                Text("Categories Covered")
            } footer: {
                Text("Withdrawing consent stops future off-device syncing for these categories once a production backend is connected.")
            }

            if let consent = accountManager.currentConsumerHealthConsent {
                Section("Current Consent Record") {
                    LabeledContent(
                        "Accepted",
                        value: consent.acceptedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    LabeledContent("Purpose", value: consent.purpose)
                }
            }
        }
        .navigationTitle("Privacy Choices")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            consumerHealthSyncEnabled = accountManager.currentConsumerHealthConsent != nil
        }
        .onChange(of: consumerHealthSyncEnabled) { _, newValue in
            Task {
                await accountManager.setConsumerHealthConsent(granted: newValue)
            }
        }
    }
}

struct DeleteAccountView: View {
    @Environment(AccountManager.self) private var accountManager

    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            Section {
                Button("Submit Delete Data Request") {
                    Task {
                        await accountManager.submitPrivacyRequest(.deleteData)
                    }
                }
                .disabled(accountManager.currentUser == nil)

                Button("Submit Delete Account Request") {
                    Task {
                        await accountManager.submitPrivacyRequest(.deleteAccount)
                    }
                }
                .disabled(accountManager.currentUser == nil)
            } header: {
                Text("Delete Requests")
            } footer: {
                Text("These requests are recorded locally in this validation build. Connect your production backend before relying on them for public cloud accounts.")
            }

            Section("Delete This Local Account") {
                Button("Delete Account From This Build", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(accountManager.currentUser == nil)

                Text("Deleting the local account removes the stored account profile, local privacy request history, and consumer health consent records from this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete Account From This Build?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task {
                    await accountManager.deleteCurrentAccount()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local account profile and its associated validation records from this device.")
        }
    }
}
