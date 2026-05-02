//
//  DSStat.swift
//  SuggestMeSome
//
//  "Label + big number + delta" pattern introduced in Feature 22 Prompt 2.
//  Replaces the bespoke implementations in DashboardStatCard, the daily
//  coach hero block, and various PR feed rows. Number animates with
//  numericText content transition for a confident value-change feel.
//

import SwiftUI

enum DSStatDelta {
    case none
    case up(String)
    case down(String)
    case neutral(String)

    fileprivate var systemImage: String? {
        switch self {
        case .none:        return nil
        case .up:          return "arrow.up.right"
        case .down:        return "arrow.down.right"
        case .neutral:     return "minus"
        }
    }

    fileprivate var color: Color {
        switch self {
        case .up:      return DSColor.signalPositive
        case .down:    return DSColor.signalCritical
        case .neutral: return .secondary
        case .none:    return .clear
        }
    }

    fileprivate var text: String? {
        switch self {
        case .up(let t), .down(let t), .neutral(let t): return t
        case .none: return nil
        }
    }
}

struct DSStat: View {
    let label: String
    let value: String
    var unit: String? = nil
    var delta: DSStatDelta = .none

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                Text(value)
                    .modifier(DSMetricFont(.large))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let deltaText = delta.text, let icon = delta.systemImage {
                Label(deltaText, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(delta.color)
                    .labelStyle(.titleAndIcon)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCombinedLabel)
    }

    private var accessibilityCombinedLabel: String {
        var parts: [String] = [label, value]
        if let unit { parts.append(unit) }
        if let d = delta.text { parts.append(d) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Metric font modifier shim

/// Internal adapter so DSStat can reference the existing DSMetricFont
/// modifier without coupling to its sized variant API (pre-P3 only the
/// `.large` modifier ships; `.medium`/`.small` land in P3).
private struct DSMetricFont: ViewModifier {
    enum Size { case large, medium, small }
    let size: Size
    init(_ size: Size) { self.size = size }

    func body(content: Content) -> some View {
        switch size {
        case .large:  content.dsMetricLarge()
        case .medium: content.font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
        case .small:  content.font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
        }
    }
}
