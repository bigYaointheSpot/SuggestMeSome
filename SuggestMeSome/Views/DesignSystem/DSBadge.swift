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
    var systemImage: String? = nil

    init(_ text: String, tone: Tone = .accent, systemImage: String? = nil) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, 4)
        .background(tone.background)
        .foregroundStyle(tone.foreground)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }
}
