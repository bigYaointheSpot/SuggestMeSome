//
//  ComplianceConfiguration.swift
//  SuggestMeSome
//
//  Feature 15 - U.S. individual-seller compliance configuration, legal
//  documents, and launch-readiness copy.
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
    static let currentLegalVersion = "2.3"
    static let legalEffectiveDateText = "2026-05-02"
    static let sellerName = "Alexander Yao"
    static let supportEmail = "support@suggestmesome.app"
    static let privacyEmail = "privacy@suggestmesome.app"
    static let websiteURL = URL(string: "https://www.suggestmesome.app")!
    static let supportURL = URL(string: "https://www.suggestmesome.app/support")!
    static let privacyPolicyURL = URL(string: "https://www.suggestmesome.app/privacy")!
    static let termsURL = URL(string: "https://www.suggestmesome.app/terms")!
    static let consumerHealthNoticeURL = URL(string: "https://www.suggestmesome.app/consumer-health")!
    static let privacyChoicesURL = URL(string: "https://www.suggestmesome.app/privacy-choices")!
    static let requiresOrganizationAccountBeforeRelease = false
    static var accountBackendLaunchMode: AccountBackendLaunchMode {
        AppBuildEnvironment.enablesProductionCloudFeatures ? .productionBackend : .localContractValidation
    }
    static let accountBackendBaseURL = URL(string: "https://api.suggestmesome.app/v1")!

    static let adultsOnlyLegalDisclosure = "SuggestMeSome is intended for adults age 18 and older."
    static let onboardingEligibilityTitle = "Training eligibility"
    static let onboardingEligibilityDisclosure = "SuggestMeSome is designed for independent adult training use. By continuing, you confirm that you're 18 or older."
    static let onboardingPrivacyDisclosure = "Keep logging workouts on this device. This v1 App Store release does not include production cloud accounts, Sign in with Apple, coach collaboration, private sharing, backend sync, or push notifications."
    static let wellnessDisclaimerDisclosure = "SuggestMeSome provides fitness and wellness guidance only. It is not medical advice, diagnosis, or treatment, and it should not be used for emergency or medical decisions."
    static let doctorCheckDisclosure = "Check with a doctor before making medical decisions, changing care, or relying on recovery or readiness results after illness, injury, pain, pregnancy, or other health concerns."
    static let smartGuidanceDisclosure = "Some workouts, programs, and coaching explanations are generated from your logged training data and app logic. Review recommendations before acting on them."
    static let consumerHealthDataDisclosure = "Your workouts, readiness check-ins, recovery data, and coaching outputs can reveal health information. SuggestMeSome uses this data to provide the features you request and does not use Apple Health data for advertising."
    static let v1LocalReleaseDisclosure = "This v1 App Store release stores workout, coaching, analytics, Apple Health-derived recovery summaries, and Premium Unlock entitlement state locally on this device. Production cloud accounts, Sign in with Apple, backend sync, coach collaboration, private sharing, and push notifications are not included in this release."
    static let cloudSyncStorageDisclosure = v1LocalReleaseDisclosure
    static let collaborationDataDisclosure = "Coach collaboration, private sharing, invite workflows, notification-preference sync, APNs backend registration, and backend account records are not included in this v1 App Store release."
    static let accountSignInDisclosure = "This v1 App Store release does not create production cloud accounts or use Sign in with Apple. Manual workout logging remains available locally without an account."
    static let collaborationSharingDisclosure = "Coach invites, visibility scopes, private program sharing, coach notes, assignments, and progress sharing are not available in this v1 App Store release."
    static let collaborationRevocationDisclosure = "Because production collaboration is not included in v1, there are no coach relationships or private shares to revoke in this release."
    static let pushNotificationDisclosure = "Push notifications are not included in this v1 App Store release. SuggestMeSome does not register an APNs token with a backend in v1."
    static let privacyRightsDisclosure = "This v1 App Store release does not operate a production backend account system. Use the in-app local export, backup, and delete controls for device data, manage Apple Health records in Apple Health, and contact \(privacyEmail) for privacy questions."
    static let privacyAppealDisclosure = "If you contact us about a privacy question and disagree with the response, you can appeal by replying to that email or contacting \(privacyEmail)."
    static let freeWorkoutLoggingDisclosure = "Manual workout logging, history, editing, export, and deletion remain available without Premium Unlock."
    static let premiumUnlockDisclosure = "Premium Unlock is a one-time purchase. It unlocks coaching, analytics, smart generation, Apple Health integration, and Apple Watch features. Manual workout logging remains free."
    static let appleHealthDisclosure = "If you choose to connect Apple Health, SuggestMeSome may read sleep, resting heart rate, heart rate variability, active energy, step count, body mass, and workouts, and may write workout summaries you save in SuggestMeSome. Apple Health access is optional and can be changed anytime."
    static let dailyCoachGuidanceDisclosure = "Recovery and readiness outputs are estimates based on your logged workouts, check-ins, and optional Apple Health data. They are not diagnostic measurements or medical advice."
    static let deleteLocalDataDisclosure = "Delete Local Data removes SuggestMeSome data from this device. It does not delete records stored in Apple Health."
    static let accountLaunchModeDisclosure = "Account and cloud sync features are not available in this v1 App Store release. Local workout logging, export, deletion, Premium Unlock, optional Apple Health, Apple Watch, widgets, and Live Activity are the v1 focus."
    static let dataRetentionDisclosure = "Local workout and coaching data remain on this device until you delete them. SuggestMeSome v1 does not retain production backend account, sync, collaboration, or push-notification records."
    static let securityDisclosure = "SuggestMeSome v1 keeps app data local by default. Any support emails you send are handled through the support inboxes listed here."
    static let noAdvertisingDisclosure = "SuggestMeSome does not use Apple Health data for advertising and does not include ads or third-party analytics in this public launch baseline."
    static let cloudFeaturePreviewDisclosure = "Cloud feature previews, where visible in development builds, use local sample data only. They do not create an account, send invites, register for push notifications, or sync anything to the backend."
    static let supportResponseDisclosure = "For support or privacy questions, email us and include the device, iOS version, and app version when possible."

    static let consumerHealthConsentCategories = [
        "Workout history",
        "Readiness check-ins",
        "Recovery metrics",
        "Coaching outputs",
        "Apple Health-derived recovery summaries stored in the app",
        "Premium entitlement state",
        "Support messages you choose to send"
    ]
    static let consumerHealthConsentPurpose = "Local workout logging, coaching, recovery, analytics, optional Apple Health features, and support you request."
    static let consumerHealthConsentRequiredDocumentIDs: [String] = [
        "privacyPolicy::\(currentLegalVersion)",
        "termsOfUse::\(currentLegalVersion)",
        "consumerHealthNotice::\(currentLegalVersion)"
    ]
    static let consumerHealthConsentRequiredCopy = "This v1 release keeps consumer health data local by default and does not enable production cloud sync or collaboration sharing."
    static let consumerHealthConsentMissingMessage = "Consumer health data stays local in this v1 release; production cloud sync and collaboration are not enabled."

    static var releaseGateChecklist: [String] {
        [
            "Publish the configured support, privacy, terms, and consumer health pages at their hosted URLs before App Store submission.",
            "Publish the privacy choices page so App Store Connect can link directly to in-app and hosted data-rights controls.",
            "Complete the App Store Connect privacy questionnaire and product-page copy using only the v1 data flows: local workout logging, Premium Unlock, optional Apple Health, Apple Watch, widgets, and Live Activity.",
            "Sign the Paid Apps Agreement and finish the premium_unlock in-app purchase metadata and review notes.",
            "Confirm the v1 App Store build hides production backend, Sign in with Apple, cloud sync, coach collaboration, private sharing, and push-notification surfaces.",
            "Document in App Review notes that the app is free, Premium Unlock is a one-time IAP, Apple Health is optional, and v1 has no production account or cloud features.",
            "Finalize a custom U.S. Terms/EULA in App Store Connect and review the hosted legal text with counsel before release.",
            "Confirm the hosted legal pages match in-app version \(currentLegalVersion), effective date \(legalEffectiveDateText), contact, consent, appeal, retention, and Apple Health off-backend claims.",
            "Keep production backend, account, collaboration, push, and backend privacy workflows out of v1 until they are fully operated and reviewed for a later launch."
        ]
    }

    static let legalDocuments: [LegalDocumentVersion] = [
        LegalDocumentVersion(
            kind: .privacyPolicy,
            version: currentLegalVersion,
            title: "Privacy Policy",
            summary: "How SuggestMeSome v1 handles local workout data, Premium Unlock, optional Apple Health access, and privacy choices in the United States.",
            bodyMarkdown: """
            **Version \(currentLegalVersion). Effective \(legalEffectiveDateText).**

            ## Overview

            \(appName) is published by **\(sellerName)**. This v1 App Store release is a local-first fitness and wellness product. It helps you log workouts, review progress, unlock premium coaching features with a one-time Apple in-app purchase, and optionally connect Apple Health. It is not designed for diagnosis, treatment, or emergency use.

            Contact:

            - Support: \(supportEmail)
            - Privacy: \(privacyEmail)
            - Website: \(websiteURL.absoluteString)
            - Support Center: \(supportURL.absoluteString)
            - Privacy Choices: \(privacyChoicesURL.absoluteString)

            ## Data categories

            \(appName) may process:

            - workout logs, exercise entries, sets, notes, and workout timing
            - exercise library data and personal records
            - readiness check-ins, coaching outputs, trend summaries, and recovery estimates
            - optional Apple Health data that you authorize, including sleep, resting heart rate, heart rate variability, active energy, step count, body mass, and workouts
            - device-side premium purchase entitlement state for Premium Unlock
            - local backup or export files you choose to create
            - support or privacy emails you choose to send to us

            ## How data is used

            \(appName) uses this information to:

            - provide workout logging, history, export, and deletion tools
            - generate smart workout, program, and coaching guidance
            - calculate trend, readiness, recovery, and progress summaries
            - support optional Apple Health read and write flows that you request
            - validate Premium Unlock on your device and restore eligible purchases through Apple
            - respond to support or privacy messages you send

            ## Local storage

            \(cloudSyncStorageDisclosure)

            ## Sharing and disclosures

            \(noAdvertisingDisclosure)

            \(appName) may share data only as needed to:

            - process Apple in-app purchases and purchase restoration through Apple
            - read from or write to Apple Health when you grant permission
            - comply with law, respond to valid legal requests, or protect rights and safety
            - support future vendors only after this policy and in-app notices are updated before those vendors receive your data

            \(appName) does not sell personal information or consumer health data.

            ## Retention and deletion

            \(dataRetentionDisclosure)
            \(privacyRightsDisclosure)

            You can export local workout data, create a local backup, delete local workout data, and revoke Apple Health permissions. Deleting local app data does not delete records stored in Apple Health.

            ## Security

            \(securityDisclosure)

            ## Your controls

            You can:

            - use the free workout logger without purchasing Premium Unlock
            - choose whether to connect Apple Health
            - export local workout data from the app
            - create a local backup file for device-to-device migration
            - delete local workout data from the app
            - restore prior Premium Unlock purchases through Apple
            - email \(privacyEmail) with privacy questions

            ## Consumer health data

            Workouts, readiness check-ins, recovery signals, and coaching outputs can reveal health information. Review the Consumer Health Data Notice for more detail, including Washington-specific consumer health rights.
            """,
            hostedURL: privacyPolicyURL,
            requiresOnboardingAcceptance: true,
            containsPlaceholders: false
        ),
        LegalDocumentVersion(
            kind: .termsOfUse,
            version: currentLegalVersion,
            title: "Terms of Use",
            summary: "Use terms for SuggestMeSome v1, including wellness limitations, Premium Unlock terms, Apple Health, and local data expectations.",
            bodyMarkdown: """
            **Version \(currentLegalVersion). Effective \(legalEffectiveDateText).**

            ## Eligibility

            \(adultsOnlyLegalDisclosure)

            ## Product scope

            \(appName) v1 provides workout logging, analytics, smart workout and program suggestions, optional Apple Health integration, Apple Watch support, widgets, Live Activity support, and wellness-oriented coaching support. Production cloud accounts, Sign in with Apple, backend sync, coach collaboration, private sharing, and push notifications are not included in this v1 App Store release.

            ## No medical use

            \(wellnessDisclaimerDisclosure)

            \(doctorCheckDisclosure)

            ## Assumption of risk and user responsibility

            Physical training carries risk. You are responsible for deciding whether to perform any exercise, workout, program, recovery suggestion, or coaching recommendation shown in the app. Stop training and seek qualified medical advice if you experience pain, dizziness, illness, or other warning signs.

            ## Premium Unlock

            Premium Unlock is a one-time in-app purchase. It unlocks premium coaching, analytics, smart generation, Apple Health integration, and Apple Watch features. Manual workout logging remains free. Eligible users may restore Premium Unlock through Apple. Refunds, billing issues, and purchase restoration are handled according to Apple's payment rules and any applicable law.

            ## Accounts and privacy requests

            \(appName) v1 does not create a production cloud account and does not include Sign in with Apple. Use the local export, local backup, and local delete controls for data stored on this device. Contact \(privacyEmail) for privacy questions.

            ## Collaboration and sharing

            Coach collaboration, private sharing, invites, coach notes, assignments, visibility scopes, and push notifications are not available in this v1 App Store release. If those features return in a later release, the app and legal documents should be updated before they are enabled.

            ## Apple Health

            Apple Health access is optional. You control Apple Health permissions through Apple Health and iOS Settings. Deleting local app data does not delete records already stored in Apple Health.

            ## Revocation and deletion

            You may delete local app data from the app. Local deletion does not automatically delete Apple Health records, local files you exported, or messages you sent to support. Since v1 has no production account or collaboration service, there is no backend account, coach relationship, private share, or APNs backend registration to revoke.

            ## Disclaimer of warranties

            To the fullest extent permitted by law, \(appName) is provided on an "as is" and "as available" basis without warranties of accuracy, fitness for a particular purpose, or uninterrupted availability.

            ## Limitation of liability

            To the fullest extent permitted by law, \(sellerName) will not be liable for indirect, incidental, consequential, special, exemplary, or punitive damages arising from your use of the app. The total liability for any claim relating to \(appName) will not exceed the amount you paid for Premium Unlock during the 12 months before the claim arose, or USD $25 if you paid nothing.

            ## Termination

            You may stop using the app at any time. You may also delete local data from the app. Access may be suspended or terminated if you misuse the product or violate these terms.

            ## Governing law

            These terms are governed by the laws of the State of California and applicable United States law, without regard to conflict-of-law rules. Any dispute arising out of or relating to these terms or \(appName) will be brought exclusively in the state or federal courts located in Santa Clara County, California, unless non-waivable law requires another forum. You and \(sellerName) consent to personal jurisdiction and venue in those courts.

            ## Contact

            - Support: \(supportEmail)
            - Privacy: \(privacyEmail)
            - Terms URL: \(termsURL.absoluteString)
            """,
            hostedURL: termsURL,
            requiresOnboardingAcceptance: true,
            containsPlaceholders: false
        ),
        LegalDocumentVersion(
            kind: .consumerHealthNotice,
            version: currentLegalVersion,
            title: "Consumer Health Data Notice",
            summary: "Notice covering local workout, readiness, recovery, coaching, Premium Unlock, support, and optional Apple Health-derived information that may reveal health status.",
            bodyMarkdown: """
            **Version \(currentLegalVersion). Effective \(legalEffectiveDateText).**

            ## Scope

            \(appName) processes workout, readiness, recovery, and coaching information that may reveal health status. This notice is written for a U.S. release that includes Washington residents and other state consumer health privacy requirements.

            ## Categories of consumer health data

            \(appName) may process:

            - workout history and exercise performance
            - readiness check-ins, daily coach records, and training-recovery summaries
            - coaching, fatigue, adaptation, and progress outputs that may reveal health-related inferences
            - optional Apple Health data that you authorize
            - local backup or export files you choose to create
            - support records you choose to send that involve consumer health data

            ## Sources

            Consumer health data may come from:

            - data you manually enter in \(appName)
            - workouts and training history you log in \(appName)
            - optional Apple Health data you authorize the app to read
            - support or privacy messages you choose to send

            ## Purposes

            \(appName) uses this information to provide the workout logging, coaching, recovery, analytics, optional Apple Health, Apple Watch, widgets, Live Activity, Premium Unlock, and support features you request.

            \(consumerHealthConsentRequiredCopy)

            ## Sharing

            \(noAdvertisingDisclosure)

            \(cloudSyncStorageDisclosure)
            \(collaborationDataDisclosure)

            Apple Health-derived recovery data stays on device in this release and is not sent to a sync backend.

            Consumer health data may otherwise be disclosed only when necessary to process Apple-hosted purchases, comply with law, respond to valid legal process, protect rights and safety, or support vendors that are disclosed to you in advance through an updated policy and notice.

            ## Your rights

            Depending on applicable U.S. law, you may have the right to:

            - confirm whether \(appName) is processing your consumer health data
            - request access to or export of consumer health data, including categories of recipients where required by law
            - request deletion of consumer health data
            - withdraw consent for future consumer health data collection or sharing where consent is the legal basis
            - appeal a denied privacy request where applicable law requires it

            ## How to exercise rights

            Use the in-app local export, backup, and delete controls, or contact:

            - Privacy: \(privacyEmail)
            - Support: \(supportEmail)
            - Consumer Health Notice URL: \(consumerHealthNoticeURL.absoluteString)
            - Privacy Choices URL: \(privacyChoicesURL.absoluteString)

            \(privacyAppealDisclosure)

            ## Important limits

            Deleting local app data does not delete records stored in Apple Health. Apple Health permissions can be changed at any time through Apple Health or iOS Settings.

            Production cloud sync, coach collaboration, private sharing, and push notifications are not included in this v1 App Store release.
            """,
            hostedURL: consumerHealthNoticeURL,
            requiresOnboardingAcceptance: true,
            containsPlaceholders: false
        ),
        LegalDocumentVersion(
            kind: .automationDisclosure,
            version: currentLegalVersion,
            title: "Smart Guidance Disclosure",
            summary: "How smart generation and coaching outputs are produced and how to use them safely.",
            bodyMarkdown: """
            **Version \(currentLegalVersion). Effective \(legalEffectiveDateText).**

            \(smartGuidanceDisclosure)

            \(appName) currently uses on-device training history, saved program context, optional Apple Health summaries, and deterministic app logic to generate training guidance. Review every recommendation before acting on it.

            \(dailyCoachGuidanceDisclosure)

            \(doctorCheckDisclosure)
            """,
            hostedURL: nil,
            requiresOnboardingAcceptance: false,
            containsPlaceholders: false
        ),
        LegalDocumentVersion(
            kind: .wellnessDisclaimer,
            version: currentLegalVersion,
            title: "Wellness Disclaimer",
            summary: "Important non-medical framing for workout, readiness, recovery, and coaching outputs.",
            bodyMarkdown: """
            **Version \(currentLegalVersion). Effective \(legalEffectiveDateText).**

            \(wellnessDisclaimerDisclosure)

            \(dailyCoachGuidanceDisclosure)

            \(doctorCheckDisclosure)
            """,
            hostedURL: nil,
            requiresOnboardingAcceptance: false,
            containsPlaceholders: false
        ),
        LegalDocumentVersion(
            kind: .support,
            version: currentLegalVersion,
            title: "Support",
            summary: "Support contacts, privacy choices, and help topics for SuggestMeSome v1, Premium Unlock, Apple Health, and local data controls.",
            bodyMarkdown: """
            **Version \(currentLegalVersion). Effective \(legalEffectiveDateText).**

            ## Support Contacts

            - Seller: \(sellerName)
            - Support: \(supportEmail)
            - Privacy: \(privacyEmail)
            - Website: \(websiteURL.absoluteString)
            - Support Center: \(supportURL.absoluteString)
            - Privacy Choices: \(privacyChoicesURL.absoluteString)

            ## Getting help

            - Premium Unlock: Premium Unlock is a one-time in-app purchase. Purchases and restores are handled through Apple. Use Restore Purchases in the app if your prior unlock is missing on a device.
            - Redeem Offer Code: Use the in-app Redeem Offer Code button or the App Store redemption flow for Apple offer codes tied to Premium Unlock.
            - Local Data: Manual workout logging, workout history, local backup, CSV export, and local deletion work without an account.
            - Account & Cloud: Production cloud accounts, Sign in with Apple, backend sync, coach collaboration, private sharing, and push notifications are not included in this v1 App Store release.
            - Apple Health: Apple Health access is optional and user-controlled. Apple Health-derived recovery data stays on device in this release and is not sent to CloudKit or a sync backend. Deleting local app data does not delete Apple Health records.
            - Privacy Questions: Use in-app local export, backup, and delete controls for device data. Contact \(privacyEmail) for privacy questions.

            ## Privacy and security commitments

            \(noAdvertisingDisclosure)
            \(dataRetentionDisclosure)
            \(securityDisclosure)

            ## Privacy and data controls

            - Privacy Choices: \(privacyChoicesURL.absoluteString)
            - Privacy Policy: \(privacyPolicyURL.absoluteString)
            - Terms of Use: \(termsURL.absoluteString)
            - Consumer Health Notice: \(consumerHealthNoticeURL.absoluteString)

            ## Response expectations

            \(supportResponseDisclosure)
        """,
            hostedURL: supportURL,
            requiresOnboardingAcceptance: false,
            containsPlaceholders: false
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
