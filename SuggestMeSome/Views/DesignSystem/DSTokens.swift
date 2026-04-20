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
