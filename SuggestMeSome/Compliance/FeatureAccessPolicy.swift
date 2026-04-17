//
//  FeatureAccessPolicy.swift
//  SuggestMeSome
//
//  Feature 14 - Shared premium feature gating policy.
//

enum PremiumFeature: String, CaseIterable, Identifiable {
    case dailyCoach
    case dashboardAnalytics
    case smartWorkoutGeneration
    case trainingPrograms
    case healthData
    case watchCompanion
    case nextBlockPlanning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyCoach:
            return "Daily Coach"
        case .dashboardAnalytics:
            return "Dashboard"
        case .smartWorkoutGeneration:
            return "Smart Workout Generation"
        case .trainingPrograms:
            return "Training Programs"
        case .healthData:
            return "Apple Health"
        case .watchCompanion:
            return "Apple Watch"
        case .nextBlockPlanning:
            return "Next Block Planning"
        }
    }

    var systemImage: String {
        switch self {
        case .dailyCoach:
            return "brain.head.profile"
        case .dashboardAnalytics:
            return "chart.xyaxis.line"
        case .smartWorkoutGeneration:
            return "wand.and.stars"
        case .trainingPrograms:
            return "list.clipboard"
        case .healthData:
            return "heart.text.square.fill"
        case .watchCompanion:
            return "applewatch"
        case .nextBlockPlanning:
            return "arrow.triangle.branch"
        }
    }

    var headline: String {
        switch self {
        case .dailyCoach:
            return "Unlock daily coaching and readiness guidance."
        case .dashboardAnalytics:
            return "Unlock progress analytics and coaching insights."
        case .smartWorkoutGeneration:
            return "Unlock smart workout generation and adaptive suggestions."
        case .trainingPrograms:
            return "Unlock smart program building and adaptive program tools."
        case .healthData:
            return "Unlock Apple Health integration for recovery and workout context."
        case .watchCompanion:
            return "Unlock Apple Watch sync and workout continuity."
        case .nextBlockPlanning:
            return "Unlock next-block recommendations and progression planning."
        }
    }

    var detail: String {
        switch self {
        case .dailyCoach:
            return "Daily Coach combines training history, readiness check-ins, and optional Apple Health context into explainable guidance."
        case .dashboardAnalytics:
            return "Dashboard analytics surface trends, fatigue context, and long-horizon progress snapshots."
        case .smartWorkoutGeneration:
            return "Smart workout generation builds session suggestions from your saved training context and preferences."
        case .trainingPrograms:
            return "Training Programs includes smart generation, templates, active program tracking, and adaptive overlays."
        case .healthData:
            return "Apple Health access is optional and premium-gated. The free workout logger remains fully usable without it."
        case .watchCompanion:
            return "Apple Watch features mirror premium coaching and workout continuity from the iPhone experience."
        case .nextBlockPlanning:
            return "Next-block planning turns completed block outcomes into editable carry-forward guidance."
        }
    }

    var valueBullets: [String] {
        switch self {
        case .dailyCoach:
            return [
                "Readiness and recovery summaries",
                "Explainable Today Plan guidance",
                "Premium coaching disclosure and source attribution"
            ]
        case .dashboardAnalytics:
            return [
                "Trend cards and analytics",
                "Coaching summaries",
                "Adaptive history visibility"
            ]
        case .smartWorkoutGeneration:
            return [
                "Smart workout suggestions",
                "Context-aware generation flows",
                "Editable generated sessions"
            ]
        case .trainingPrograms:
            return [
                "Program templates and smart generation",
                "Adaptive overlays and review surfaces",
                "Multi-week training planning"
            ]
        case .healthData:
            return [
                "Optional Apple Health read access",
                "Workout import and writeback controls",
                "Recovery-aware premium guidance"
            ]
        case .watchCompanion:
            return [
                "Apple Watch launch continuity",
                "Live workout context syncing",
                "Watch-facing Today Plan support"
            ]
        case .nextBlockPlanning:
            return [
                "Post-block review flows",
                "Carry-forward next block suggestions",
                "Editable progression handoff"
            ]
        }
    }
}

enum EntitlementState: String, Codable, Equatable {
    case free
    case premiumUnlocked

    var hasPremiumAccess: Bool {
        self == .premiumUnlocked
    }
}

enum FeatureAccessDecision: Equatable {
    case granted
    case premiumRequired(PremiumFeature)
}

struct FeatureAccessPolicy {
    static func decision(
        for feature: PremiumFeature,
        entitlementState: EntitlementState
    ) -> FeatureAccessDecision {
        entitlementState.hasPremiumAccess ? .granted : .premiumRequired(feature)
    }

    static func isAccessible(
        _ feature: PremiumFeature,
        entitlementState: EntitlementState
    ) -> Bool {
        decision(for: feature, entitlementState: entitlementState) == .granted
    }
}
