//
//  DSBadge.swift
//  SuggestMeSome
//
//  Pill-shaped status label used across the app for invite status,
//  assignment status, note freshness, and other short categorical
//  indicators. Replaces the file-private StatusBadge in
//  CollaborationViews.swift and the inline `Text(...).background(Capsule())`
//  variants sprinkled through Dashboard cards.
//

import SwiftUI

struct DSBadge: View {
    enum Tone {
        case accent
        case positive
        case caution
        case critical
        case neutral

        fileprivate var foreground: Color {
            switch self {
            case .accent:   return DSColor.primaryAction
            case .positive: return DSColor.signalPositive
            case .caution:  return DSColor.signalCaution
            case .critical: return DSColor.signalCritical
            case .neutral:  return .secondary
            }
        }

        fileprivate var background: Color {
            switch self {
            case .accent:   return DSColor.primaryAction.opacity(0.12)
            case .positive: return DSColor.signalPositive.opacity(0.14)
            case .caution:  return DSColor.signalCaution.opacity(0.14)
            case .critical: return DSColor.signalCritical.opacity(0.12)
            case .neutral:  return Color(.tertiarySystemFill)
            }
        }
    }

    let text: String
    var tone: Tone = .accent
    /// When set, overrides the tone enum with this color (used for
    /// dynamic semantic colors like ObjectiveRecoveryStatus.dsAccentColor
    /// that can't be expressed as a static tone case).
    var tintOverride: Color? = nil
    var systemImage: String? = nil

    init(
        _ text: String,
        tone: Tone = .accent,
        tint: Color? = nil,
        systemImage: String? = nil
    ) {
        self.text = text
        self.tone = tone
        self.tintOverride = tint
        self.systemImage = systemImage
    }

    private var foreground: Color { tintOverride ?? tone.foreground }
    private var background: Color {
        if let tintOverride { return tintOverride.opacity(0.12) }
        return tone.background
    }

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, 4)
        .background(background)
        .foregroundStyle(foreground)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }
}
