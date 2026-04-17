//
//  WatchUIComponents.swift
//  SuggestMeSomeWatch
//
//  Feature 12 Prompt 3 — Shared watch UI primitives.
//
//  Small, reusable SwiftUI pieces used across the root flow and Today Plan
//  screen. Kept intentionally presentational — no store coupling, no data
//  fetching, no navigation. Views compose these into premium execution-first
//  surfaces while keeping typography and spacing consistent.
//

import SwiftUI

// MARK: - Palette

enum WatchPalette {
    static let primary = Color.indigo
    static let surface = Color.white.opacity(0.08)
    static let surfaceStrong = Color.indigo.opacity(0.18)
    static let strokeFaint = Color.white.opacity(0.12)
    static let positive = Color.green
    static let warning = Color.orange
    static let danger = Color.red
}

// MARK: - Card Modifier

struct WatchCardStyle: ViewModifier {
    var emphasized: Bool = false
    var tint: Color = WatchPalette.primary

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                emphasized ? tint.opacity(0.18) : WatchPalette.surface,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(emphasized ? tint.opacity(0.4) : WatchPalette.strokeFaint, lineWidth: 0.5)
            )
    }
}

extension View {
    func watchCard(emphasized: Bool = false, tint: Color = WatchPalette.primary) -> some View {
        modifier(WatchCardStyle(emphasized: emphasized, tint: tint))
    }
}

// MARK: - Pill Badge

struct WatchPillBadge: View {
    enum Size {
        case small
        case regular
    }

    let label: String
    var detail: String? = nil
    var tint: Color = WatchPalette.primary
    var size: Size = .regular

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: size == .small ? 5 : 6, height: size == .small ? 5 : 6)
            Text(label)
                .font((size == .small ? Font.caption2 : Font.caption).weight(.semibold))
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font((size == .small ? Font.caption2 : Font.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, size == .small ? 6 : 8)
        .padding(.vertical, size == .small ? 3 : 4)
        .background(tint.opacity(0.22), in: Capsule())
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(label), \($0)" } ?? label)
    }
}

// MARK: - Readiness Badge

struct WatchReadinessBadge: View {
    let tierLabel: String
    var size: WatchPillBadge.Size = .regular

    private var tint: Color {
        switch tierLabel.lowercased() {
        case "strong":  return WatchPalette.positive
        case "neutral": return WatchPalette.primary
        case "low":     return WatchPalette.warning
        default:        return .secondary
        }
    }

    var body: some View {
        WatchPillBadge(
            label: tierLabel,
            detail: "Readiness",
            tint: tint,
            size: size
        )
    }
}

// MARK: - Confidence Badge

struct WatchConfidenceBadge: View {
    let confidenceLabel: String
    var size: WatchPillBadge.Size = .regular

    private var tint: Color {
        switch confidenceLabel.lowercased() {
        case "high":   return WatchPalette.positive
        case "medium": return WatchPalette.primary
        case "low":    return WatchPalette.warning
        default:       return .secondary
        }
    }

    var body: some View {
        WatchPillBadge(
            label: confidenceLabel,
            detail: "Confidence",
            tint: tint,
            size: size
        )
    }
}

// MARK: - Pain Flag Badge

struct WatchPainFlagBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
            Text("Pain flagged")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(WatchPalette.warning)
        .background(WatchPalette.warning.opacity(0.18), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Adherence Block

struct WatchAdherenceBlock: View {
    let headline: String
    let guidanceType: String?
    let sessionsBehind: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.left.circle.fill")
                    .font(.caption.weight(.semibold))
                Text("Rescue")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(WatchPalette.warning)

            Text(headline)
                .font(.caption.weight(.semibold))
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            if sessionsBehind > 0 || guidanceType != nil {
                HStack(spacing: 4) {
                    if sessionsBehind > 0 {
                        Text("\(sessionsBehind) behind")
                            .font(.caption2)
                    }
                    if sessionsBehind > 0, guidanceType != nil {
                        Text("·")
                            .font(.caption2)
                    }
                    if let guidanceType {
                        Text(guidanceType)
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .watchCard(emphasized: true, tint: WatchPalette.warning)
    }
}

// MARK: - What Changed Block

struct WatchWhatChangedBlock: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.semibold))
                Text("What changed")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(WatchPalette.primary)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
        .watchCard()
    }
}

// MARK: - Source Labels

struct WatchSourceLabelsStrip: View {
    let labels: [String]

    var body: some View {
        if labels.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sources")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text(labels.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Empty / Reconnect / Loading States

struct WatchEmptyStatePanel: View {
    var systemImage: String = "applewatch.radiowaves.left.and.right"
    var title: String
    var message: String
    var subMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(WatchPalette.primary)
            Text(title)
                .font(.headline)
                .lineLimit(2)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let subMessage {
                Text(subMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .watchCard()
    }
}

// MARK: - Connection Dot

struct WatchConnectionDot: View {
    let status: WatchCompanionSessionStatus

    private var color: Color {
        if !status.isSupported || !status.isCompanionAppInstalled {
            return .secondary
        }
        if status.isReachable {
            return WatchPalette.positive
        }
        if status.hasContentPending || status.activationState == .activated {
            return WatchPalette.primary
        }
        return .secondary
    }

    /// Only surface the dot when it's actionable — disconnected, unsupported,
    /// or content pending. When the iPhone is reachable and idle, stay silent
    /// so vertical space goes to the primary execution surface.
    private var shouldSurface: Bool {
        if !status.isSupported || !status.isCompanionAppInstalled { return true }
        if status.isReachable && !status.hasContentPending { return false }
        return true
    }

    var body: some View {
        if shouldSurface {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(status.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("iPhone connection")
            .accessibilityValue(status.message)
        }
    }
}

// MARK: - Elapsed Time Formatter

enum WatchDurationFormatter {
    static func format(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
