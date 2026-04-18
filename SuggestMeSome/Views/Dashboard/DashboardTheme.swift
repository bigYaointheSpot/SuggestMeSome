//
//  DashboardTheme.swift
//  SuggestMeSome
//
//  Design tokens and shared styling for the Dashboard surface.
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

// MARK: - Fatigue → color

extension FatigueStatus {
    var dsAccentColor: Color {
        switch self {
        case .low:        return DSColor.signalPositive
        case .manageable: return DSColor.signalNeutral
        case .elevated:   return .yellow
        case .high:       return DSColor.signalCaution
        case .critical:   return DSColor.signalCritical
        }
    }
    var dsDisplayName: String {
        switch self {
        case .low:        return "Low"
        case .manageable: return "Manageable"
        case .elevated:   return "Elevated"
        case .high:       return "High"
        case .critical:   return "Critical"
        }
    }
}

// MARK: - Recovery pressure → color

extension TrainingStateRecoveryPressure {
    var dsDisplayName: String {
        switch self {
        case .conservative: return "Conservative"
        case .neutral:      return "Neutral"
        case .elevated:     return "Push"
        }
    }
    var dsAccentColor: Color {
        switch self {
        case .conservative: return DSColor.signalCaution
        case .neutral:      return DSColor.signalNeutral
        case .elevated:     return DSColor.signalPositive
        }
    }
    var dsGuidance: String {
        switch self {
        case .conservative: return "Back off intensity today"
        case .neutral:      return "Run the plan as written"
        case .elevated:     return "Room to push"
        }
    }
}

// MARK: - LiftTrendStatus → icon/color

extension LiftTrendStatus {
    var dsTrendIcon: String {
        switch self {
        case .improving:        return "arrow.up.right"
        case .stable:           return "equal"
        case .declining:        return "arrow.down.right"
        case .volatile:         return "waveform"
        case .insufficientData: return "minus"
        }
    }
    var dsTrendColor: Color {
        switch self {
        case .improving:        return DSColor.signalPositive
        case .stable:           return DSColor.signalNeutral
        case .declining:        return DSColor.signalCritical
        case .volatile:         return DSColor.signalCaution
        case .insufficientData: return .gray
        }
    }
}

// MARK: - ObjectiveRecoveryStatus → color

extension ObjectiveRecoveryStatus {
    var dsAccentColor: Color {
        switch self {
        case .good:    return DSColor.signalPositive
        case .neutral: return DSColor.signalNeutral
        case .caution: return DSColor.signalCaution
        }
    }
    var dsLabel: String {
        switch self {
        case .good:    return "Good"
        case .neutral: return "Neutral"
        case .caution: return "Caution"
        }
    }
}

// MARK: - ProgramVolumeMuscle color palette

extension ProgramVolumeMuscle {
    /// Base hue per muscle — saturation is then modulated by stress.
    var dsBaseColor: Color {
        switch self {
        case .chest:         return .blue
        case .upperBackLats: return .teal
        case .quads:         return .orange
        case .hamstrings:    return .brown
        case .glutes:        return .pink
        case .shoulders:     return .purple
        case .biceps:        return .red
        case .triceps:       return .red
        case .calves:        return .mint
        case .abs:           return .indigo
        }
    }
}

// MARK: - Human-named muscle groups (for the legacy volume chart)

enum DashboardMusclePalette {
    static let humanGroupColors: [String: Color] = [
        "Chest":     .blue,
        "Back":      .green,
        "Legs":      .orange,
        "Shoulders": .purple,
        "Arms":      .red,
        "Core":      .teal,
    ]

    static func color(for humanGroup: String) -> Color {
        humanGroupColors[humanGroup] ?? .gray
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
            Text(title)
                .font(.headline.weight(.bold))
            Spacer()
            if let trailing { trailing }
        }
    }
}
