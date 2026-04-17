//
//  ComplianceViews.swift
//  SuggestMeSome
//
//  Feature 14 - Reusable onboarding, legal, paywall, and premium gate views.
//

import SwiftUI

#if canImport(StoreKit)
import StoreKit
#endif

struct LegalDocumentView: View {
    let document: LegalDocumentVersion

    init(kind: LegalDocumentKind) {
        self.document = ComplianceConfiguration.document(for: kind)
    }

    init(document: LegalDocumentVersion) {
        self.document = document
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(document.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(.init(document.bodyMarkdown))
                    .font(.body)
                    .textSelection(.enabled)

                if let hostedURL = document.hostedURL {
                    Link("Open Hosted Version", destination: hostedURL)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SupportInfoView: View {
    private let supportDocument = ComplianceConfiguration.document(for: .support)

    var body: some View {
        List {
            Section("Contact") {
                Link(ComplianceConfiguration.supportEmail, destination: URL(string: "mailto:\(ComplianceConfiguration.supportEmail)")!)
                Link(ComplianceConfiguration.privacyEmail, destination: URL(string: "mailto:\(ComplianceConfiguration.privacyEmail)")!)
                Link("Support Center", destination: ComplianceConfiguration.supportURL)
                Link(ComplianceConfiguration.websiteURL.absoluteString, destination: ComplianceConfiguration.websiteURL)
            }

            Section {
                ForEach(ComplianceConfiguration.releaseGateChecklist, id: \.self) { item in
                    Text(item)
                }
            } header: {
                Text("U.S. Launch Checklist")
            } footer: {
                Text("Hosted legal pages, App Store metadata, and the production account backend still need to be finished before a public cloud-backed launch.")
            }

            Section("Document Preview") {
                NavigationLink {
                    LegalDocumentView(document: supportDocument)
                } label: {
                    Label("Open Support Document", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutThisGuidanceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                guidanceCallout(
                    title: "Wellness, not medical care",
                    text: ComplianceConfiguration.wellnessDisclaimerDisclosure
                )
                guidanceCallout(
                    title: "Check with a doctor when health questions are involved",
                    text: ComplianceConfiguration.doctorCheckDisclosure
                )
                guidanceCallout(
                    title: "Recovery and readiness are estimates",
                    text: ComplianceConfiguration.dailyCoachGuidanceDisclosure
                )
                guidanceCallout(
                    title: "Smart guidance should be reviewed",
                    text: ComplianceConfiguration.smartGuidanceDisclosure
                )
                guidanceCallout(
                    title: "Apple Health is optional",
                    text: ComplianceConfiguration.appleHealthDisclosure
                )
                guidanceCallout(
                    title: "Cloud storage limits",
                    text: ComplianceConfiguration.cloudSyncStorageDisclosure
                )
            }
            .padding()
        }
        .navigationTitle("About This Guidance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func guidanceCallout(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct LocalDataInfoView: View {
    var body: some View {
        List {
            Section("Delete Local Data") {
                Text(ComplianceConfiguration.deleteLocalDataDisclosure)
            }

            Section("Apple Health and Cloud Storage") {
                Text(ComplianceConfiguration.cloudSyncStorageDisclosure)
            }

            Section("What stays available for free") {
                Text(ComplianceConfiguration.freeWorkoutLoggingDisclosure)
            }

            Section("Where to manage it") {
                Text("Use the Data Management section in Settings to delete workouts by date range or delete all local workout data.")
            }
        }
        .navigationTitle("Delete Local Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LegalPrivacyCenterView: View {
    var body: some View {
        List {
            Section("Legal Documents") {
                ForEach(LegalDocumentKind.allCases.filter { $0 != .support }) { kind in
                    NavigationLink {
                        LegalDocumentView(kind: kind)
                    } label: {
                        Label(kind.title, systemImage: icon(for: kind))
                    }
                }
            }

            Section("Support") {
                NavigationLink {
                    SupportInfoView()
                } label: {
                    Label("Support", systemImage: "questionmark.circle")
                }
            }
        }
        .navigationTitle("Legal & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func icon(for kind: LegalDocumentKind) -> String {
        switch kind {
        case .privacyPolicy:
            return "lock.doc"
        case .termsOfUse:
            return "doc.text"
        case .consumerHealthNotice:
            return "heart.text.square.fill"
        case .automationDisclosure:
            return "wand.and.stars"
        case .wellnessDisclaimer:
            return "cross.case"
        case .support:
            return "questionmark.circle"
        }
    }
}

struct PaywallView: View {
    let feature: PremiumFeature?

    @Environment(PurchaseManager.self) private var purchaseManager
    @State private var showingDocumentKind: LegalDocumentKind?
    @State private var showingSupport = false
    @State private var showingAboutGuidance = false

    init(feature: PremiumFeature? = nil) {
        self.feature = feature
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                benefitsCard
                disclosureCard
                actionsCard
            }
            .padding()
        }
        .navigationTitle(feature?.title ?? "Premium Unlock")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await purchaseManager.refreshProducts()
            await purchaseManager.refreshEntitlements()
        }
        .sheet(item: $showingDocumentKind) { kind in
            NavigationStack {
                LegalDocumentView(kind: kind)
            }
        }
        .sheet(isPresented: $showingSupport) {
            NavigationStack {
                SupportInfoView()
            }
        }
        .sheet(isPresented: $showingAboutGuidance) {
            NavigationStack {
                AboutThisGuidanceView()
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Premium Unlock", systemImage: "star.circle.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.indigo)

            Text(feature?.headline ?? "Unlock coaching, analytics, smart generation, Apple Health integration, and Apple Watch features.")
                .font(.title3.weight(.semibold))

            Text(feature?.detail ?? "Premium keeps the manual workout logger free while unlocking the advanced training system.")
                .foregroundStyle(.secondary)

            Text("\(purchaseManager.premiumDisplayPrice) one-time purchase")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What Premium Unlock includes")
                .font(.headline)

            ForEach(feature?.valueBullets ?? [
                "Daily Coach and explainable premium guidance",
                "Dashboard analytics and adaptive history",
                "Smart workout and program generation",
                "Apple Health and Apple Watch features"
            ], id: \.self) { bullet in
                Label(bullet, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.primary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var disclosureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Disclosures")
                .font(.headline)
            Text(ComplianceConfiguration.premiumUnlockDisclosure)
                .foregroundStyle(.secondary)
            Text(ComplianceConfiguration.freeWorkoutLoggingDisclosure)
                .foregroundStyle(.secondary)
            Text(ComplianceConfiguration.doctorCheckDisclosure)
                .foregroundStyle(.secondary)
            Button("About This Guidance") {
                showingAboutGuidance = true
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task {
                    _ = await purchaseManager.purchasePremiumUnlock()
                }
            } label: {
                HStack {
                    if purchaseManager.isProcessingPurchase {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text(purchaseManager.isPremiumUnlocked ? "Premium Unlock Active" : "Unlock Premium")
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(purchaseManager.isPremiumUnlocked ? Color.green : Color.indigo)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(purchaseManager.isProcessingPurchase || purchaseManager.isPremiumUnlocked)

            Button("Restore Purchases") {
                Task {
                    _ = await purchaseManager.restorePurchases()
                }
            }
            .font(.subheadline.weight(.semibold))

#if canImport(StoreKit)
            OfferCodeRedemptionButton(
                title: "Redeem Offer Code",
                systemImage: "ticket"
            )
            .font(.subheadline.weight(.semibold))
#endif

            if let statusMessage = purchaseManager.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = purchaseManager.lastErrorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 12) {
                Button("Privacy Policy") {
                    showingDocumentKind = .privacyPolicy
                }
                Button("Terms") {
                    showingDocumentKind = .termsOfUse
                }
                Button("Consumer Health") {
                    showingDocumentKind = .consumerHealthNotice
                }
                Button("Support") {
                    showingSupport = true
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct PremiumGateView: View {
    let feature: PremiumFeature

    var body: some View {
        PaywallView(feature: feature)
    }
}

#if canImport(StoreKit)
struct OfferCodeRedemptionButton: View {
    let title: String
    let systemImage: String

    @Environment(PurchaseManager.self) private var purchaseManager
    @State private var isShowingOfferCodeRedemption = false

    var body: some View {
        Button {
            isShowingOfferCodeRedemption = true
        } label: {
            Label(title, systemImage: systemImage)
        }
        .offerCodeRedemption(isPresented: $isShowingOfferCodeRedemption) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    purchaseManager.statusMessage = "Offer code redemption finished. If the code was valid, Premium Unlock will activate shortly."
                    purchaseManager.lastErrorMessage = nil
                    await purchaseManager.refreshEntitlements()
                case .failure:
                    purchaseManager.lastErrorMessage = "Offer code redemption could not be opened right now."
                }
            }
        }
    }
}
#endif

private struct FeatureGateContainer<Content: View>: View {
    let feature: PremiumFeature
    let wrapLockedStateInNavigationStack: Bool
    @ViewBuilder let content: () -> Content

    @Environment(PurchaseManager.self) private var purchaseManager

    private var isAccessible: Bool {
        FeatureAccessPolicy.isAccessible(
            feature,
            entitlementState: purchaseManager.entitlementState
        )
    }

    var body: some View {
        if isAccessible {
            content()
        } else if wrapLockedStateInNavigationStack {
            NavigationStack {
                PremiumGateView(feature: feature)
            }
        } else {
            PremiumGateView(feature: feature)
        }
    }
}

struct PremiumFeatureGate<Content: View>: View {
    let feature: PremiumFeature
    @ViewBuilder let content: () -> Content

    var body: some View {
        FeatureGateContainer(
            feature: feature,
            wrapLockedStateInNavigationStack: true,
            content: content
        )
    }
}

struct HealthDataPreflightView: View {
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDocumentKind: LegalDocumentKind?
    @State private var showingAboutGuidance = false

    var body: some View {
        List {
            Section("Before You Connect Apple Health") {
                Text(ComplianceConfiguration.appleHealthDisclosure)
                Text(ComplianceConfiguration.consumerHealthDataDisclosure)
                    .foregroundStyle(.secondary)
                Text(ComplianceConfiguration.doctorCheckDisclosure)
                    .foregroundStyle(.secondary)
                Text(ComplianceConfiguration.cloudSyncStorageDisclosure)
                    .foregroundStyle(.secondary)
            }

            Section("Data Apple Health May Provide") {
                Text("Sleep")
                Text("Resting heart rate")
                Text("Heart rate variability")
                Text("Active energy")
                Text("Step count")
                Text("Body mass")
                Text("Workouts")
            }

            Section("Learn More") {
                Button("About This Guidance") {
                    showingAboutGuidance = true
                }
                Button("Privacy Policy") {
                    showingDocumentKind = .privacyPolicy
                }
                Button("Consumer Health Data Notice") {
                    showingDocumentKind = .consumerHealthNotice
                }
            }

            Section {
                Button("Continue to Apple Health Permissions") {
                    dismiss()
                    onContinue()
                }
                .font(.headline.weight(.semibold))

                Button("Not Now", role: .cancel) {
                    dismiss()
                }
            }
        }
        .navigationTitle("Apple Health Access")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showingDocumentKind) { kind in
            NavigationStack {
                LegalDocumentView(kind: kind)
            }
        }
        .sheet(isPresented: $showingAboutGuidance) {
            NavigationStack {
                AboutThisGuidanceView()
            }
        }
    }
}

struct ComplianceOnboardingFlow: View {
    @Environment(ComplianceStateStore.self) private var complianceStateStore
    @State private var stepIndex = 0
    @State private var showingDocumentKind: LegalDocumentKind?
    @State private var showingLegalCenter = false

    private let orderedSteps: [ComplianceOnboardingStep] = [
        .welcome,
        .ageGate,
        .wellness,
        .automation,
        .documents
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                stepProgress

                Spacer(minLength: 0)

                switch orderedSteps[stepIndex] {
                case .welcome:
                    welcomeStep
                case .ageGate:
                    copyStep(
                        title: ComplianceConfiguration.onboardingEligibilityTitle,
                        body: ComplianceConfiguration.onboardingEligibilityDisclosure
                    )
                case .wellness:
                    copyStep(
                        title: "Wellness, not medical care",
                        body: "\(ComplianceConfiguration.wellnessDisclaimerDisclosure)\n\n\(ComplianceConfiguration.doctorCheckDisclosure)"
                    )
                case .automation:
                    copyStep(
                        title: "Smart guidance disclosure",
                        body: ComplianceConfiguration.smartGuidanceDisclosure
                    )
                case .documents:
                    documentStep
                }

                Spacer(minLength: 0)

                onboardingFooter
            }
            .padding()
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $showingDocumentKind) { kind in
            NavigationStack {
                LegalDocumentView(kind: kind)
            }
        }
        .sheet(isPresented: $showingLegalCenter) {
            NavigationStack {
                LegalPrivacyCenterView()
            }
        }
    }

    private var stepProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before you start")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(stepIndex + 1), total: Double(orderedSteps.count))
            Text("Step \(stepIndex + 1) of \(orderedSteps.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SuggestMeSome helps you log workouts for free and unlock premium coaching when you are ready.")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Label("Manual workout logging stays free", systemImage: "checkmark.circle.fill")
                Label("Premium Unlock is a one-time purchase", systemImage: "star.circle.fill")
                Label("Apple Health and Apple Watch support are optional premium features", systemImage: "heart.text.square.fill")
            }
            .foregroundStyle(.secondary)
        }
    }

    private func copyStep(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(body)
                .foregroundStyle(.secondary)
        }
    }

    private var documentStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review key documents")
                .font(.title3.weight(.semibold))
            Text("These documents are available anytime from Settings.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Button("Privacy Policy") {
                    showingDocumentKind = .privacyPolicy
                }
                Button("Terms of Use") {
                    showingDocumentKind = .termsOfUse
                }
                Button("Consumer Health Data Notice") {
                    showingDocumentKind = .consumerHealthNotice
                }
                Button("Open Legal & Privacy Center") {
                    showingLegalCenter = true
                }
            }
            .font(.headline)
        }
    }

    private var onboardingFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if stepIndex > 0 {
                Button("Back") {
                    stepIndex = max(0, stepIndex - 1)
                }
                .font(.subheadline.weight(.semibold))
            }

            Button(stepIndex == orderedSteps.count - 1 ? "Continue into the app" : "Continue") {
                advance()
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.indigo)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func advance() {
        switch orderedSteps[stepIndex] {
        case .welcome:
            break
        case .ageGate:
            complianceStateStore.confirmAdult()
        case .wellness:
            complianceStateStore.acknowledgeWellnessDisclaimer()
        case .automation:
            complianceStateStore.acknowledgeAutomationDisclosure()
        case .documents:
            complianceStateStore.acceptRequiredDocuments()
            complianceStateStore.markCompleted()
        }

        if stepIndex < orderedSteps.count - 1 {
            stepIndex += 1
        }
    }
}

private enum ComplianceOnboardingStep {
    case welcome
    case ageGate
    case wellness
    case automation
    case documents
}
