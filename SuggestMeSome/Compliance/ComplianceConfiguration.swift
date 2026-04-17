//
//  ComplianceConfiguration.swift
//  SuggestMeSome
//
//  Feature 14 - Paid app compliance configuration, legal documents, and
//  release-gate placeholders.
//

import Foundation

enum LegalDocumentKind: String, CaseIterable, Codable, Identifiable {
    case privacyPolicy
    case termsOfUse
    case consumerHealthNotice
    case automationDisclosure
    case wellnessDisclaimer
    case support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy:
            return "Privacy Policy"
        case .termsOfUse:
            return "Terms of Use"
        case .consumerHealthNotice:
            return "Consumer Health Data Notice"
        case .automationDisclosure:
            return "Smart Guidance Disclosure"
        case .wellnessDisclaimer:
            return "Wellness Disclaimer"
        case .support:
            return "Support"
        }
    }
}

struct LegalDocumentVersion: Codable, Equatable, Identifiable {
    let kind: LegalDocumentKind
    let version: String
    let title: String
    let summary: String
    let bodyMarkdown: String
    let hostedURL: URL?
    let requiresOnboardingAcceptance: Bool
    let containsPlaceholders: Bool

    var id: String {
        "\(kind.rawValue)::\(version)"
    }
}

struct LegalDocumentRecord: Codable, Equatable {
    let documentID: String
    let acceptedAt: Date
}

enum ComplianceConfiguration {
    static let appName = "SuggestMeSome"
    static let premiumUnlockProductID = "premium_unlock"
    static let placeholderSellerName = "Your Legal Name"
    static let placeholderSupportEmail = "support@suggestmesome.example"
    static let placeholderPrivacyEmail = "privacy@suggestmesome.example"
    static let placeholderWebsiteURL = URL(string: "https://suggestmesome.example")!
    static let placeholderPrivacyPolicyURL = URL(string: "https://suggestmesome.example/privacy")!
    static let placeholderTermsURL = URL(string: "https://suggestmesome.example/terms")!
    static let placeholderConsumerHealthNoticeURL = URL(string: "https://suggestmesome.example/consumer-health")!
    static let requiresOrganizationAccountBeforeRelease = false

    static let adultsOnlyLegalDisclosure = "SuggestMeSome is intended for adults age 18 and older."
    static let onboardingEligibilityTitle = "Training eligibility"
    static let onboardingEligibilityDisclosure = "SuggestMeSome is designed for independent adult training use. By continuing, you confirm that you're 18 or older."
    static let wellnessDisclaimerDisclosure = "SuggestMeSome provides fitness and wellness guidance only. It is not medical advice, diagnosis, or treatment, and it should not be used for emergency or medical decisions."
    static let smartGuidanceDisclosure = "Some workouts, programs, and coaching explanations are generated from your logged training data and app logic. Review recommendations before acting on them."
    static let consumerHealthDataDisclosure = "Your workouts, readiness check-ins, recovery data, and coaching outputs can reveal health information. SuggestMeSome uses this data to provide the features you request and does not use Apple Health data for advertising."
    static let freeWorkoutLoggingDisclosure = "Manual workout logging, history, editing, export, and deletion remain available without Premium Unlock."
    static let premiumUnlockDisclosure = "Premium Unlock is a one-time purchase. It unlocks coaching, analytics, smart generation, Apple Health integration, and Apple Watch features. Manual workout logging remains free."

    static let appleHealthDisclosure = "If you choose to connect Apple Health, SuggestMeSome may read sleep, resting heart rate, heart rate variability, active energy, step count, body mass, and workouts, and may write workout summaries you save in SuggestMeSome. Apple Health access is optional and can be changed anytime."

    static let dailyCoachGuidanceDisclosure = "Recovery and readiness outputs are estimates based on your logged workouts, check-ins, and optional Apple Health data. They are not diagnostic measurements or medical advice."

    static let deleteLocalDataDisclosure = "Delete Local Data removes SuggestMeSome data from this device. It does not delete records stored in Apple Health."

    static var releaseGateChecklist: [String] {
        [
            "Replace the placeholder seller name, support email, privacy email, and hosted legal URLs.",
            "Confirm you are comfortable publishing with your legal personal seller name visible on the App Store.",
            "If you distribute in the EU, complete the DSA trader-status review and be ready for Apple to display required contact information.",
            "Publish hosted Privacy Policy, Terms of Use, and Consumer Health Data Notice pages.",
            "Complete the App Store Connect privacy questionnaire and paid IAP metadata.",
            "Review final legal text with counsel before release."
        ]
    }

    static let legalDocuments: [LegalDocumentVersion] = [
        LegalDocumentVersion(
            kind: .privacyPolicy,
            version: "1.0",
            title: "Privacy Policy",
            summary: "How SuggestMeSome collects, uses, and protects local workout and wellness data.",
            bodyMarkdown: """
            **Pre-launch placeholder**

            This policy uses placeholder seller and contact details. Replace them before public release.

            ## Overview

            \(appName) is published by **\(placeholderSellerName)**. The app is designed as a local-first fitness and wellness product. It stores your workout history, exercise library, personal records, readiness check-ins, and premium entitlement state on your device. Optional Apple Health access can add wellness and workout data to the features you request.

            ## Data categories

            \(appName) may process:

            - manual workout logs, exercise entries, sets, notes, and calories
            - exercise library and personal records
            - readiness check-ins and coaching outputs
            - optional Apple Health data such as sleep, resting heart rate, heart rate variability, active energy, step count, body mass, and workouts
            - device-side premium purchase entitlement status

            ## How data is used

            \(appName) uses this data to:

            - provide workout logging, history, export, and deletion tools
            - generate smart workout, program, and coaching guidance
            - calculate progress, trend, recovery, and readiness summaries
            - support optional Apple Health read and write flows you request
            - verify Premium Unlock entitlement on this device

            ## Data sharing

            At this stage, \(appName) is built to operate without accounts, ads, analytics SDKs, or off-device AI processing. Apple Health data is not used for advertising. If remote sync, accounts, third-party analytics, or external AI processing are added later, this policy and the in-app consent flow must be updated before release.

            ## Your controls

            You can:

            - use the free workout logger without purchasing Premium Unlock
            - choose whether to connect Apple Health
            - export workout data from the app
            - delete local workout data from the app
            - change Apple Health permissions in Apple Health or iOS Settings

            ## Contact

            Support: \(placeholderSupportEmail)

            Privacy: \(placeholderPrivacyEmail)

            Website: \(placeholderWebsiteURL.absoluteString)
            """,
            hostedURL: placeholderPrivacyPolicyURL,
            requiresOnboardingAcceptance: true,
            containsPlaceholders: true
        ),
        LegalDocumentVersion(
            kind: .termsOfUse,
            version: "1.0",
            title: "Terms of Use",
            summary: "Core use terms, purchase terms, and wellness limitations for SuggestMeSome.",
            bodyMarkdown: """
            **Pre-launch placeholder**

            Replace the seller and contact details before public release.

            ## Product scope

            \(adultsOnlyLegalDisclosure)

            \(appName) provides workout logging, smart workout and program suggestions, analytics, and wellness-oriented coaching support.

            ## No medical use

            \(wellnessDisclaimerDisclosure)

            ## User responsibility

            You are responsible for reviewing and deciding whether to act on any workout, program, readiness, recovery, or coaching recommendation shown in the app.

            ## Premium Unlock

            Premium Unlock is a one-time in-app purchase. It unlocks premium coaching, analytics, smart generation, Apple Health integration, and Apple Watch features. Manual workout logging remains free. Restore Purchases is available in the app for eligible prior purchases.

            ## Availability

            Features may change over time as the product evolves. Pre-release placeholder legal content must be finalized before public launch.

            ## Contact

            \(placeholderSupportEmail)
            """,
            hostedURL: placeholderTermsURL,
            requiresOnboardingAcceptance: true,
            containsPlaceholders: true
        ),
        LegalDocumentVersion(
            kind: .consumerHealthNotice,
            version: "1.0",
            title: "Consumer Health Data Notice",
            summary: "Notice for workout, readiness, recovery, and Apple Health-derived wellness data.",
            bodyMarkdown: """
            **Pre-launch placeholder**

            Replace placeholder details before public release and confirm jurisdiction-specific requirements with counsel.

            ## Consumer health data categories

            \(appName) may process consumer health data such as:

            - workout history and exercise performance
            - readiness check-ins and recovery summaries
            - coaching, fatigue, and progress outputs that may reveal health-related inferences
            - optional Apple Health data you authorize

            ## Sources

            Consumer health data may come from:

            - data you manually enter in \(appName)
            - workouts you log in \(appName)
            - optional Apple Health data you authorize the app to read

            ## Purposes

            \(appName) uses this information to provide the fitness and wellness features you request, including coaching, recovery context, progress views, and Apple Watch continuity.

            ## Sharing and advertising

            \(appName) does not use Apple Health data for advertising. The current product plan does not include ads, analytics SDKs, or off-device AI processing. If that changes, the app must add updated notices and consent flows before release.

            ## Controls

            You can export workout data, delete local app data, and change Apple Health permissions at any time.

            ## Contact

            Privacy contact: \(placeholderPrivacyEmail)
            """,
            hostedURL: placeholderConsumerHealthNoticeURL,
            requiresOnboardingAcceptance: true,
            containsPlaceholders: true
        ),
        LegalDocumentVersion(
            kind: .automationDisclosure,
            version: "1.0",
            title: "Smart Guidance Disclosure",
            summary: "How smart generation and coaching outputs are produced and how to use them.",
            bodyMarkdown: """
            \(smartGuidanceDisclosure)

            \(appName) is currently designed as a local-first product. Smart guidance reflects your logged workouts, optional Apple Health data, saved program state, and deterministic app logic. It should be reviewed as a training suggestion, not treated as a guaranteed or authoritative instruction.
            """,
            hostedURL: nil,
            requiresOnboardingAcceptance: false,
            containsPlaceholders: false
        ),
        LegalDocumentVersion(
            kind: .wellnessDisclaimer,
            version: "1.0",
            title: "Wellness Disclaimer",
            summary: "Important non-medical framing for workout, readiness, and recovery outputs.",
            bodyMarkdown: """
            \(wellnessDisclaimerDisclosure)

            Recovery and readiness outputs are estimates based on your logged workouts, check-ins, and optional Apple Health data. They are not diagnostic measurements or medical advice.
            """,
            hostedURL: nil,
            requiresOnboardingAcceptance: false,
            containsPlaceholders: false
        ),
        LegalDocumentVersion(
            kind: .support,
            version: "1.0",
            title: "Support",
            summary: "Support and privacy contact details, plus pre-release release gates.",
            bodyMarkdown: """
            **Support**

            Seller: \(placeholderSellerName)

            Support: \(placeholderSupportEmail)

            Privacy: \(placeholderPrivacyEmail)

            Website: \(placeholderWebsiteURL.absoluteString)

            ## Pre-release release gates

            \(releaseGateChecklist.map { "- \($0)" }.joined(separator: "\n"))
            """,
            hostedURL: nil,
            requiresOnboardingAcceptance: false,
            containsPlaceholders: true
        )
    ]

    static let requiredOnboardingDocumentIDs: Set<String> = Set(
        legalDocuments
            .filter(\.requiresOnboardingAcceptance)
            .map(\.id)
    )

    static func document(for kind: LegalDocumentKind) -> LegalDocumentVersion {
        legalDocuments.first(where: { $0.kind == kind })!
    }
}
