//
//  FeatureFlag.swift
//  SuggestMeSome
//
//  Local-only feature flags for gradual rollout. Backed by UserDefaults so
//  developers and TestFlight users can toggle without a new build. Defaults
//  are chosen so that DEBUG builds opt into new behavior automatically while
//  TestFlight remains conservative until the flag is flipped in P7.
//

import SwiftUI

enum FeatureFlag: String, CaseIterable {
    /// Whole-app visual refresh introduced in Feature 22. When OFF, design
    /// system primitives fall back to legacy colors, typography, and motion.
    case uiRefreshV2

    var defaultsKey: String { "FeatureFlag.\(rawValue)" }

    /// Compile-time default. P7 flipped this to ON across DEBUG and release
    /// after the surface uplifts shipped without regressions in P5/P6.
    /// The flag remains in code for one more release as a safety hatch — a
    /// bug report can flip a single UserDefaults key to roll back to legacy
    /// look without a new binary.
    var compiledDefault: Bool {
        true
    }

    var isEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: defaultsKey) == nil {
                return compiledDefault
            }
            return defaults.bool(forKey: defaultsKey)
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }
}

// MARK: - Environment

private struct UIRefreshV2Key: EnvironmentKey {
    static let defaultValue: Bool = FeatureFlag.uiRefreshV2.compiledDefault
}

extension EnvironmentValues {
    /// Whether the new (Feature 22) design language is active for this view tree.
    /// Resolved once at app root from `FeatureFlag.uiRefreshV2.isEnabled` and
    /// pushed down via `.environment(\.uiRefreshV2, ...)` to avoid per-read
    /// UserDefaults hits during view-body re-evaluation.
    var uiRefreshV2: Bool {
        get { self[UIRefreshV2Key.self] }
        set { self[UIRefreshV2Key.self] = newValue }
    }
}
