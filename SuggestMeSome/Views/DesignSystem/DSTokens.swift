//
//  DSTokens.swift
//  SuggestMeSome
//
//  Shared design tokens and primitive style modifiers used across every
//  surface in the app. Promoted out of DashboardTheme so non-Dashboard
//  features can consume the system without importing a Dashboard module.
//

import SwiftUI

enum DSSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat  = 8
    static let m: CGFloat  = 12
    static let l: CGFloat  = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

enum DSRadius {
    static let s: CGFloat  = 8
    static let m: CGFloat  = 12
    static let l: CGFloat  = 16
    static let xl: CGFloat = 20
}

enum DSColor {
    static let primaryAction: Color     = .indigo
    static let surface: Color           = Color(.secondarySystemBackground)
    static let surfaceElevated: Color   = Color(.tertiarySystemBackground)
    static let signalPositive: Color    = .green
    static let signalNeutral: Color     = .blue
    static let signalCaution: Color     = .orange
    static let signalCritical: Color    = .red
}

// MARK: - Elevation

enum DSElevation {
    case none
    case level1
    case level2

    var shadowColor: Color {
        switch self {
        case .none: return .clear
        case .level1: return Color.black.opacity(0.06)
        case .level2: return Color.black.opacity(0.10)
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .none: return 0
        case .level1: return 4
        case .level2: return 12
        }
    }

    var shadowYOffset: CGFloat {
        switch self {
        case .none: return 0
        case .level1: return 1
        case .level2: return 4
        }
    }
}

// MARK: - Icon sizes

enum DSIcon {
    static let xs: CGFloat = 14
    static let s: CGFloat  = 18
    static let m: CGFloat  = 22
    static let l: CGFloat  = 28
    static let xl: CGFloat = 36
}

// MARK: - Motion

/// Named motion tokens. Resolves to plain springs in P1 — values become
/// canonical in P4 (Motion language). Always respect reduce-motion.
enum DSMotion {
    static var snap: Animation       { .spring(response: 0.25, dampingFraction: 0.85) }
    static var standard: Animation   { .spring(response: 0.35, dampingFraction: 0.85) }
    static var expressive: Animation { .spring(response: 0.45, dampingFraction: 0.75) }
}

// MARK: - Hairline

enum DSHairline {
    static var width: CGFloat {
        1 / max(UIScreen.main.scale, 1)
    }
}

// MARK: - Opacity

enum DSOpacity {
    static let disabled: Double = 0.4
    static let subdued: Double  = 0.6
    static let divider: Double  = 0.12
}

// MARK: - Gradients (stubs — real values land in P3)

enum DSGradient {
    static var heroAccent: LinearGradient {
        LinearGradient(
            colors: [DSColor.primaryAction, DSColor.primaryAction],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var surfaceGlow: RadialGradient {
        RadialGradient(
            colors: [DSColor.primaryAction.opacity(0.08), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 200
        )
    }

    static var prCelebration: LinearGradient {
        LinearGradient(
            colors: [DSColor.signalPositive, DSColor.primaryAction],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Card style

struct DSCardStyle: ViewModifier {
    var tint: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(DSSpacing.l)
            .background(DSColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .stroke((tint ?? .clear).opacity(tint == nil ? 0 : 0.35), lineWidth: tint == nil ? 0 : 1)
            )
    }
}

extension View {
    func dsCardStyle(tint: Color? = nil) -> some View {
        modifier(DSCardStyle(tint: tint))
    }
}

// MARK: - Section header

struct DSSectionHeader: View {
    let icon: String
    let title: String
    var iconColor: Color = DSColor.primaryAction
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22, height: 22)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.headline.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer()
            if let trailing { trailing }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
