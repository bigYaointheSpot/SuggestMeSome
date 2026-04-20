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
    static let accountBackendLaunchMode: AccountBackendLaunchMode = .productionBackend
    static let accountBackendBaseURL = URL(string: "https://api.suggestmesome.app/v1")!

    static let adultsOnlyLegalDisclosure = "SuggestMeSome is intended for adults age 18 and older."
    static let onboardingEligibilityTitle = "Training eligibility"
    static let onboardingEligibilityDisclosure = "SuggestMeSome is designed for independent adult training use. By continuing, you confirm that you're 18 or older."
    static let onboardingPrivacyDisclosure = "Keep logging workouts on this device, or choose Sign in with Apple to sync training across your devices and collaborate privately with people you invite. Apple Health-derived recovery data stays on device in this release."
    static let wellnessDisclaimerDisclosure = "SuggestMeSome provides fitness and wellness guidance only. It is not medical advice, diagnosis, or treatment, and it should not be used for emergency or medical decisions."
    static let doctorCheckDisclosure = "Check with a doctor before making medical decisions, changing care, or relying on recovery or readiness results after illness, injury, pain, pregnancy, or other health concerns."
    static let smartGuidanceDisclosure = "Some workouts, programs, and coaching explanations are generated from your logged training data and app logic. Review recommendations before acting on them."
    static let consumerHealthDataDisclosure = "Your workouts, readiness check-ins, recovery data, and coaching outputs can reveal health information. SuggestMeSome uses this data to provide the features you request and does not use Apple Health data for advertising."
    static let cloudSyncStorageDisclosure = "SuggestMeSome syncs workouts, programs, daily coaching, adaptive history, and account privacy records through a dedicated backend. Apple Health-derived recovery data stays on device in this release and is not sent to CloudKit or the sync backend."
    static let collaborationDataDisclosure = "If you connect cloud collaboration, SuggestMeSome may sync relationship records, invitee email addresses, visibility scope settings, coach notes, assignments, private program shares, private progress shares, notification preferences, and APNs device-token registrations through the dedicated backend."
    static let accountSignInDisclosure = "If you choose Sign in with Apple, SuggestMeSome uses your Apple account identifier and the name or email you share to create your account, link backend sessions, sync workouts and programs across your devices, and fulfill privacy requests. You can stay signed out and keep using the local workout logger."
    static let collaborationSharingDisclosure = "Coach invites, visibility scopes, and private sharing only disclose the training and coaching records you choose to share with the recipient account. Apple Health-derived recovery data stays on your device in this release."
    static let collaborationRevocationDisclosure = "Revoking a relationship or private share stops future access from that point forward, but recipients may already have seen, copied, or acted on content that was shared before you revoked it."
    static let pushNotificationDisclosure = "Push notifications are optional. If you turn them on, SuggestMeSome registers this device's APNs token and your notification preferences with the backend so it can send invite, assignment, coach note, reminder, and digest notifications through Apple Push Notification service. You can turn notifications off later in iOS Settings or in this app."
    static let privacyRightsDisclosure = "Access, export, delete-data, and delete-account requests apply to backend-held account and synced training records. Local device data and Apple Health records are managed separately. Exports may identify categories of recipients or processors where required by law, and deletion requests may take time to propagate to backups or archival systems where legally permitted."
    static let privacyAppealDisclosure = "If a privacy request is denied, you can appeal through the in-app privacy request flow or by contacting \(privacyEmail)."
    static let freeWorkoutLoggingDisclosure = "Manual workout logging, history, editing, export, and deletion remain available without Premium Unlock."
    static let premiumUnlockDisclosure = "Premium Unlock is a one-time purchase. It unlocks coaching, analytics, smart generation, Apple Health integration, and Apple Watch features. Manual workout logging remains free."
    static let appleHealthDisclosure = "If you choose to connect Apple Health, SuggestMeSome may read sleep, resting heart rate, heart rate variability, active energy, step count, body mass, and workouts, and may write workout summaries you save in SuggestMeSome. Apple Health access is optional and can be changed anytime."
    static let dailyCoachGuidanceDisclosure = "Recovery and readiness outputs are estimates based on your logged workouts, check-ins, and optional Apple Health data. They are not diagnostic measurements or medical advice."
    static let deleteLocalDataDisclosure = "Delete Local Data removes SuggestMeSome data from this device. It does not delete records stored in Apple Health."
    static let accountLaunchModeDisclosure = "Account, privacy requests, and cloud sync in this build use the production backend path. Local workout logging still works while signed out, and Apple Health-derived recovery data remains on device."
    static let dataRetentionDisclosure = "Local workout and coaching data remain on this device until you delete them. Backend-held account, training, and privacy request data are retained only as long as needed to provide the service, comply with law, resolve disputes, or enforce terms."
    static let securityDisclosure = "SuggestMeSome uses encrypted network transport for backend connections and is intended to protect backend-held account and training records with role-limited access, auditable deletion, secrets management, and a documented incident-response plan."
    static let noAdvertisingDisclosure = "SuggestMeSome does not use Apple Health data for advertising and does not include ads or third-party analytics in this public launch baseline."
    static let cloudFeaturePreviewDisclosure = "Preview Cloud Features shows sample account, collaboration, sharing, and notification surfaces using local read-only data. It does not create an account, send an invite, register for push notifications, or sync anything to the backend."
    static let supportResponseDisclosure = "For support, privacy, or account questions, email us and include the device, iOS version, and app version when possible."

    static let consumerHealthConsentCategories = [
        "Workout history",
        "Readiness check-ins",
        "Recovery metrics",
        "Coaching outputs",
        "Coach notes and assignments",
        "Private sharing records",
        "Account support records"
    ]
    static let consumerHealthConsentPurpose = "Account sync, collaboration sharing, and privacy-rights fulfillment for workouts, readiness, recovery, and coaching outputs."

    static var releaseGateChecklist: [String] {
        [
            "Publish the configured support, privacy, terms, and consumer health pages at their hosted URLs before App Store submission.",
            "Publish the privacy choices page so App Store Connect can link directly to in-app and hosted data-rights controls.",
            "Complete the App Store Connect privacy questionnaire and product-page copy using the real production data flows for Premium Unlock, Sign in with Apple, cloud collaboration, private sharing, push registration, and Apple Health.",
            "Sign the Paid Apps Agreement and finish the premium_unlock in-app purchase metadata and review notes.",
            "Validate the production backend's Sign in with Apple, sync, export, deletion, and token-revocation flows against the shipped app before App Store submission.",
            "Finalize a custom U.S. Terms/EULA in App Store Connect and review the hosted legal text with counsel before release.",
            "Complete retention, breach-response, and vendor-contract work before any off-device account or consumer health sync goes live."
        ]
    }

    static let legalDocuments: [LegalDocumentVersion] = [
        LegalDocumentVersion(
            kind: .privacyPolicy,
            version: "2.1",
            title: "Privacy Policy",
            summary: "How SuggestMeSome handles workout data, cloud accounts, coach collaboration, Premium Unlock, Apple Health access, and privacy-rights workflows in the United States.",
            bodyMarkdown: """
            ## Overview

            \(appName) is published by **\(sellerName)**. This app is a fitness and wellness product. It helps you log workouts, review progress, unlock premium coaching, and optionally connect Apple Health. It is not designed for diagnosis, treatment, or emergency use.

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
            - Sign in with Apple identifiers plus the name and email you choose to share when you connect an account
            - backend account session state, sync cursors, and privacy request records tied to your connected account
            - synced programs, daily coaching records, adaptive history, relationship records, visibility scope settings, coach notes, assignments, private program shares, and private progress shares
            - invitee email addresses, notification preferences, and APNs device-token registrations used for coach collaboration and push delivery
            - device-side premium purchase entitlement state for Premium Unlock

            ## How data is used

            \(appName) uses this information to:

            - provide workout logging, history, export, and deletion tools
            - generate smart workout, program, and coaching guidance
            - calculate trend, readiness, recovery, and progress summaries
            - support optional Apple Health read and write flows that you request
            - validate Premium Unlock on your device and restore eligible purchases through Apple
            - support account sync, collaboration, private sharing, deletion, export, and privacy-rights workflows
            - register optional push notifications and store your notification preferences
            - show collaboration updates such as coach invites, assignments, notes, and digests to the people you choose to connect with

            ## Local storage and cloud sync

            The current build stores workout, coaching, Apple Health sync summaries, and purchase state on device. If you connect an account, workouts, programs, daily coaching records, adaptive history, privacy requests, relationship records, private sharing records, and key training preferences may also sync through the dedicated backend.

            \(cloudSyncStorageDisclosure)
            \(collaborationDataDisclosure)

            The production account service should continue using a dedicated backend and documented privacy-rights workflow. Any backend-held consumer health data should follow the retention, deletion, and security commitments described in this policy and the Consumer Health Data Notice.

            ## Sharing and disclosures

            \(noAdvertisingDisclosure)

            \(appName) may share data only as needed to:

            - process Apple in-app purchases and purchase restoration through Apple
            - create and restore cloud accounts through Sign in with Apple when you choose that option
            - read from or write to Apple Health when you grant permission
            - deliver optional push notifications through Apple Push Notification service
            - disclose the specific programs, progress, coach notes, assignments, and visibility-scoped records you choose to share with coaches or training partners you invite or accept
            - comply with law, respond to valid legal requests, or protect rights and safety
            - support future vendors only after this policy and in-app notices are updated before those vendors receive your data

            \(appName) does not sell personal information or consumer health data.

            ## Retention and deletion

            \(dataRetentionDisclosure)
            \(privacyRightsDisclosure)

            You can export local workout data, delete local workout data, revoke Apple Health permissions, revoke collaboration access, and use in-app account deletion and privacy request tools. Deleting local app data does not delete records stored in Apple Health.

            ## Security

            \(securityDisclosure)

            ## Your controls

            You can:

            - use the free workout logger without purchasing Premium Unlock
            - choose whether to connect Apple Health
            - export local workout data from the app
            - delete local workout data from the app
            - restore prior Premium Unlock purchases through Apple
            - manage notification preferences and revoke push permissions in iOS Settings
            - revoke coach relationships or private shares from the collaboration surfaces
            - submit access, export, deletion, and account-deletion requests from the in-app account screens

            ## Consumer health data

            Workouts, readiness check-ins, recovery signals, and coaching outputs can reveal health information. Review the Consumer Health Data Notice for more detail, including Washington-specific consumer health rights.
            """,
            hostedURL: privacyPolicyURL,
            requiresOnboardingAcceptance: true,
            containsPlaceholders: false
        ),
        LegalDocumentVersion(
            kind: .termsOfUse,
            version: "2.1",
            title: "Terms of Use",
            summary: "Use terms for SuggestMeSome, including wellness limitations, Premium Unlock terms, account sync, coach collaboration, and deletion expectations.",
            bodyMarkdown: """
            ## Eligibility

            \(adultsOnlyLegalDisclosure)

            ## Product scope

            \(appName) provides workout logging, analytics, smart workout and program suggestions, optional Apple Health integration, and wellness-oriented coaching support.

            ## No medical use

            \(wellnessDisclaimerDisclosure)

            \(doctorCheckDisclosure)

            ## Assumption of risk and user responsibility

            Physical training carries risk. You are responsible for deciding whether to perform any exercise, workout, program, recovery suggestion, or coaching recommendation shown in the app. Stop training and seek qualified medical advice if you experience pain, dizziness, illness, or other warning signs.

            ## Premium Unlock

            Premium Unlock is a one-time in-app purchase. It unlocks premium coaching, analytics, smart generation, Apple Health integration, and Apple Watch features. Manual workout logging remains free. Eligible users may restore Premium Unlock through Apple. Refunds, billing issues, and purchase restoration are handled according to Apple's payment rules and any applicable law.

            ## Accounts and privacy requests

            \(appName) provides optional account-backed cloud sync through the production backend and includes in-app account deletion and privacy-rights request tools for that service.

            ## Collaboration and sharing

            Coach collaboration and private sharing are optional account features. If you use them, you may share programs, progress, assignments, notes, invitee email addresses, and visibility settings with the specific people you choose to connect with.

            You represent that you have the right to share any content, email address, or training information you submit through collaboration features, and that you are using those tools only with intended recipients.

            You may not use collaboration features to harass, impersonate, spam, scrape, or disclose information you do not have the right to share. \(sellerName) may revoke collaboration access or suspend connected accounts that misuse these tools.

            ## Apple Health

            Apple Health access is optional. You control Apple Health permissions through Apple Health and iOS Settings. Deleting local app data does not delete records already stored in Apple Health.

            ## Revocation and deletion

            You may revoke coach relationships, private shares, or push permissions at any time. Revocation stops future access from that point forward, but recipients may already have seen content shared before you revoked it. Deleting the connected account removes backend-held account and synced training data subject to legal retention limits, but does not automatically delete local data or Apple Health records.

            ## Disclaimer of warranties

            To the fullest extent permitted by law, \(appName) is provided on an "as is" and "as available" basis without warranties of accuracy, fitness for a particular purpose, or uninterrupted availability.

            ## Limitation of liability

            To the fullest extent permitted by law, \(sellerName) will not be liable for indirect, incidental, consequential, special, exemplary, or punitive damages arising from your use of the app. The total liability for any claim relating to \(appName) will not exceed the amount you paid for Premium Unlock during the 12 months before the claim arose, or USD $25 if you paid nothing.

            ## Termination

            You may stop using the app at any time. You may also delete local data from the app and, if you connected an account, delete your account in the app. Access may be suspended or terminated if you misuse the product or violate these terms.

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
            version: "2.1",
            title: "Consumer Health Data Notice",
            summary: "Notice covering workout, readiness, recovery, coaching, account sync, collaboration, and Apple Health-derived information that may reveal health status.",
            bodyMarkdown: """
            ## Scope

            \(appName) processes workout, readiness, recovery, and coaching information that may reveal health status. This notice is written for a U.S. release that includes Washington residents and other state consumer health privacy requirements.

            ## Categories of consumer health data

            \(appName) may process:

            - workout history and exercise performance
            - readiness check-ins, daily coach records, and training-recovery summaries
            - coaching, fatigue, adaptation, and progress outputs that may reveal health-related inferences
            - coach notes, assignments, private program shares, private progress shares, and visibility settings that describe your training status or readiness
            - optional Apple Health data that you authorize
            - account identifiers, invitee email addresses, notification preferences, and support records tied to privacy requests involving consumer health data

            ## Sources

            Consumer health data may come from:

            - data you manually enter in \(appName)
            - workouts and training history you log in \(appName)
            - optional Apple Health data you authorize the app to read
            - collaboration invites, notes, assignments, private shares, and account/privacy-rights workflows you initiate

            ## Purposes

            \(appName) uses this information to provide the workout logging, coaching, recovery, analytics, collaboration, private sharing, privacy-rights, support, and optional push-notification features you request.

            ## Sharing

            \(noAdvertisingDisclosure)

            \(cloudSyncStorageDisclosure)
            \(collaborationDataDisclosure)

            If you invite or connect with a coach or training partner, the specific training and coaching records covered by your visibility settings or share action may be disclosed to that recipient.

            Apple Health-derived recovery data stays on device in this release and is not sent to the sync backend.

            Consumer health data may otherwise be disclosed only when necessary to deliver Apple-hosted push notifications, comply with law, respond to valid legal process, protect rights and safety, or support vendors that are disclosed to you in advance through an updated policy and notice.

            ## Your rights

            Depending on applicable U.S. law, you may have the right to:

            - confirm whether \(appName) is processing your consumer health data
            - request access to or export of consumer health data, including categories of recipients where required by law
            - request deletion of consumer health data
            - withdraw consent for future consumer health data collection or sharing where consent is the legal basis
            - appeal a denied privacy request where applicable law requires it

            ## How to exercise rights

            Use the in-app account and privacy request screens, or contact:

            - Privacy: \(privacyEmail)
            - Support: \(supportEmail)
            - Consumer Health Notice URL: \(consumerHealthNoticeURL.absoluteString)
            - Privacy Choices URL: \(privacyChoicesURL.absoluteString)

            \(privacyAppealDisclosure)

            ## Important limits

            Deleting local app data does not delete records stored in Apple Health. Apple Health permissions can be changed at any time through Apple Health or iOS Settings.

            Revoking collaboration access stops future sharing, but recipients may already have seen previously shared content. Deletion requests may require reasonable time to propagate to backups or archives where permitted by law.
            """,
            hostedURL: consumerHealthNoticeURL,
            requiresOnboardingAcceptance: true,
            containsPlaceholders: false
        ),
        LegalDocumentVersion(
            kind: .automationDisclosure,
            version: "2.0",
            title: "Smart Guidance Disclosure",
            summary: "How smart generation and coaching outputs are produced and how to use them safely.",
            bodyMarkdown: """
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
            version: "2.0",
            title: "Wellness Disclaimer",
            summary: "Important non-medical framing for workout, readiness, recovery, and coaching outputs.",
            bodyMarkdown: """
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
            version: "2.1",
            title: "Support",
            summary: "Support contacts, privacy choices, and help topics for SuggestMeSome accounts, Premium Unlock, Apple Health, and cloud sync.",
            bodyMarkdown: """
            ## Support Contacts

            - Seller: \(sellerName)
            - Support: \(supportEmail)
            - Privacy: \(privacyEmail)
            - Website: \(websiteURL.absoluteString)
            - Support Center: \(supportURL.absoluteString)
            - Privacy Choices: \(privacyChoicesURL.absoluteString)

            ## Getting help

            - Premium Unlock: purchase and restore are handled through Apple. Use Restore Purchases in the app if your prior unlock is missing on a device.
            - Account & Cloud: Sign in with Apple is optional. If you stay signed out, manual workout logging still works locally on this device.
            - Apple Health: Apple Health access is optional and user-controlled. Deleting local app data does not delete Apple Health records.
            - Privacy Rights: Use the in-app account and privacy request screens, or the privacy choices page, for access, export, delete-data, and delete-account requests.

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
