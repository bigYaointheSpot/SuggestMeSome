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

    /// Process-wide cache so SwiftUI body re-evals don't pay a UserDefaults
    /// read on every flag check. The cache is populated on first read for a
    /// given key, and the setter writes through to both UserDefaults and the
    /// cache so tests / debug menus / runtime toggles take effect immediately.
    /// Reads from a different thread than writes are serialized via `lock`.
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [String: Bool] = [:]

    var isEnabled: Bool {
        get {
            Self.lock.lock()
            defer { Self.lock.unlock() }
            if let cached = Self.cache[defaultsKey] { return cached }
            let defaults = UserDefaults.standard
            let resolved: Bool
            if defaults.object(forKey: defaultsKey) == nil {
                resolved = compiledDefault
            } else {
                resolved = defaults.bool(forKey: defaultsKey)
            }
            Self.cache[defaultsKey] = resolved
            return resolved
        }
        nonmutating set {
            Self.lock.lock()
            defer { Self.lock.unlock() }
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            Self.cache[defaultsKey] = newValue
        }
    }

    /// Test-only: drop the cached value for this flag so the next read goes
    /// through UserDefaults again. Useful when seeding UserDefaults directly
    /// in test fixtures.
    func resetCache() {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        Self.cache.removeValue(forKey: defaultsKey)
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
