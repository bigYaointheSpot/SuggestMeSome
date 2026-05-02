//
//  AccountPrivacyViews.swift
//  SuggestMeSome
//
//  Feature 15 - Account, privacy-rights, and consent views for U.S. launch
//  readiness and future cloud-account rollout.
//

import AuthenticationServices
import SwiftUI

struct AccountSettingsView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CloudSyncManager.self) private var cloudSyncManager

    @State private var email = ""
    @State private var displayName = ""

    var body: some View {
        List {
            accountModeSection
            if let currentUser = accountManager.currentUser {
                signedInSection(currentUser)
                consumerHealthConsentSection
                privacyHistorySection(accountManager.currentAccountPrivacyRequests)
            } else {
                signedOutSection
                consumerHealthConsentSection
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
            Text(ComplianceConfiguration.consumerHealthConsentRequiredCopy)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let lastSuccessfulSyncAt = cloudSyncManager.lastSuccessfulSyncAt {
                LabeledContent(
                    "Last Sync",
                    value: lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
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
            Text("Your local training data remains available while signed out. Cloud sync resumes when you reconnect this account.")
        }
    }

    private var signedOutSection: some View {
        Section {
            if accountManager.launchMode == .productionBackend {
                AccountSignInNoticeView()

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)

                NavigationLink {
                    CloudFeaturePreviewView()
                } label: {
                    Label("Preview Cloud Features", systemImage: "sparkles.rectangle.stack")
                }
            } else {
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
            Text(accountManager.launchMode == .productionBackend ? "Connect Account or Preview" : "Create or Sign In")
        } footer: {
            Text(accountManager.launchMode == .productionBackend
                 ? "Sign in is optional. The app remains fully usable while signed out, and Preview Cloud Features shows sample collaboration surfaces without creating an account or contacting the backend."
                 : "This build does not transmit account data off device. Replace the local contract service with your production backend before public cloud launch.")
        }
    }

    private var consumerHealthConsentSection: some View {
        Section {
            ConsumerHealthConsentControlsView()
        } header: {
            Text("Consumer Health Consent")
        } footer: {
            Text("Consent controls apply to backend sync and collaboration transmissions. Local workout logging remains available while signed out or after withdrawal.")
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
                                .background(DSColor.primaryAction.opacity(0.12))
                                .foregroundStyle(DSColor.primaryAction)
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

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                accountManager.recordExternalError("Apple sign-in did not return an Apple ID credential.")
                return
            }

            guard let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8),
                  !identityToken.isEmpty else {
                accountManager.recordExternalError(AuthServiceError.missingAppleIdentityToken.localizedDescription)
                return
            }

            let authorizationCode = credential.authorizationCode.flatMap {
                String(data: $0, encoding: .utf8)
            }
            let formatter = PersonNameComponentsFormatter()
            let displayName = credential.fullName.map(formatter.string)?.trimmingCharacters(in: .whitespacesAndNewlines)

            Task {
                await accountManager.signInWithApple(
                    AppleSignInIdentity(
                        appleUserID: credential.user,
                        identityToken: identityToken,
                        authorizationCode: authorizationCode,
                        email: credential.email,
                        displayName: displayName?.isEmpty == false ? displayName : nil
                    )
                )
            }
        case .failure(let error):
            accountManager.recordExternalError(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
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
                Text("Use these controls to submit access and export requests for backend-held account, collaboration, notification-preference, and synced training data. Apple Health-derived recovery data is not sent off device in this release.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(ComplianceConfiguration.privacyRightsDisclosure)
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
                    Task {
                        await generateExport()
                    }
                } label: {
                    if isGeneratingExport {
                        ProgressView("Generating Export…")
                    } else {
                        Label("Download Cloud Account Export", systemImage: "doc.badge.gearshape")
                    }
                }
                .disabled(accountManager.currentUser == nil || isGeneratingExport)

                if let exportURL {
                    ShareLink(
                        item: exportURL,
                        subject: Text("SuggestMeSome Account Export"),
                        message: Text("Cloud account export from SuggestMeSome.")
                    ) {
                        Label("Share Export File", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Cloud Export")
            } footer: {
                Text("This export comes from the account backend and contains synced account, collaboration, privacy, notification-preference, and training records available to your connected account. Where required by law, export responses may identify categories of recipients or processors.")
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

            Section("Appeals & Revocation") {
                PrivacyRevocationExplainerView()
            }
        }
        .navigationTitle("Access & Export")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func generateExport() async {
        guard accountManager.currentUser != nil else { return }
        isGeneratingExport = true
        defer { isGeneratingExport = false }

        do {
            let response = try await accountManager.requestAccountExport()
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(response.fileName)
            try response.data.write(to: destination, options: .atomic)
            exportURL = destination
        } catch {
            accountManager.recordExternalError(
                (error as? LocalizedError)?.errorDescription ?? "Export failed."
            )
        }
    }
}

struct PrivacyChoicesView: View {
    @Environment(AccountManager.self) private var accountManager

    var body: some View {
        List {
            Section("Account and Sync") {
                AccountSignInNoticeView()
                Text(ComplianceConfiguration.cloudSyncStorageDisclosure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(ComplianceConfiguration.collaborationDataDisclosure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Consumer Health Sync and Sharing") {
                ConsumerHealthConsentControlsView()

                Label("Apple Health-derived recovery data stays on this device", systemImage: "iphone")
                    .foregroundStyle(.secondary)

                Text(ComplianceConfiguration.consumerHealthDataDisclosure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(ComplianceConfiguration.collaborationSharingDisclosure)
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
                Text("These categories describe sensitive training and wellness context. Synced cloud data covers account, collaboration, notification-preference, and training records, while Apple Health-derived recovery inputs do not leave the device in this release.")
            }

            Section("Revocation, Deletion, and Appeals") {
                PrivacyRevocationExplainerView()
            }
        }
        .navigationTitle("Privacy Choices")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConsumerHealthConsentControlsView: View {
    @Environment(AccountManager.self) private var accountManager

    private var currentConsent: ConsumerHealthConsentRecord? {
        accountManager.currentConsumerHealthConsent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if accountManager.currentUser == nil {
                Label("Sign in required for cloud consent", systemImage: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                Text(ComplianceConfiguration.consumerHealthConsentRequiredCopy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let currentConsent {
                Label("Active for cloud sync and collaboration", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Recorded \(currentConsent.acceptedAt.formatted(date: .abbreviated, time: .shortened)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let legalVersion = currentConsent.legalVersion,
                   let legalEffectiveDate = currentConsent.legalEffectiveDate {
                    Text("Legal version \(legalVersion), effective \(legalEffectiveDate).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Withdraw Consumer Health Consent", role: .destructive) {
                    Task {
                        await accountManager.setConsumerHealthConsent(granted: false)
                    }
                }
                .buttonStyle(.bordered)
            } else {
                Label("Consent not recorded", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(ComplianceConfiguration.consumerHealthConsentRequiredCopy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        await accountManager.setConsumerHealthConsent(granted: true)
                    }
                } label: {
                    Label("Grant Consumer Health Sync Consent", systemImage: "checkmark.shield.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Text(ComplianceConfiguration.consumerHealthConsentPurpose)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("Delete-data and delete-account requests are sent to the account backend for synced training, collaboration, privacy, and notification-preference records. Apple Health-derived recovery data stays on device in this release.")
            }

            Section("Delete This Cloud Account") {
                Button("Delete Cloud Account", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(accountManager.currentUser == nil)

                Text("Deleting the cloud account removes backend-held account and synced training data, then signs this device out. Local training history on this device is not deleted automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(ComplianceConfiguration.privacyRightsDisclosure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(ComplianceConfiguration.privacyAppealDisclosure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Revocation and Separate Data Stores") {
                PrivacyRevocationExplainerView()
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete Cloud Account?",
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
            Text("This deletes your backend-held account records and signs this device out. Local training history remains on device unless you delete it separately.")
        }
    }
}

struct CloudSyncSettingsView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(CloudSyncManager.self) private var cloudSyncManager

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("State", value: cloudSyncManager.phase.title)
                if let email = cloudSyncManager.currentAccountEmail {
                    LabeledContent("Account", value: email)
                } else {
                    LabeledContent("Account", value: "Not connected")
                }
                if let lastSuccessfulSyncAt = cloudSyncManager.lastSuccessfulSyncAt {
                    LabeledContent(
                        "Last Successful Sync",
                        value: lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                Text(cloudSyncManager.statusSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task {
                        await cloudSyncManager.retryNow()
                    }
                } label: {
                    Label("Retry Sync", systemImage: "arrow.clockwise")
                }
                .disabled(accountManager.currentUser == nil || !accountManager.hasActiveConsumerHealthConsent)
            } footer: {
                Text("Cloud sync covers workouts, programs, program runs, daily coaching records, adaptive history, collaboration records, privacy requests, and key training preferences. Apple Health-derived recovery data stays on device in this release.")
            }

            Section("Recent Activity") {
                if cloudSyncManager.recentActivity.isEmpty {
                    Text("No sync activity yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cloudSyncManager.recentActivity) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.message)
                                    .font(.subheadline)
                                Spacer()
                                Text(record.level.rawValue.capitalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(levelColor(record.level))
                            }
                            Text(record.date, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Cloud Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func levelColor(_ level: CloudSyncActivityLevel) -> Color {
        switch level {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
