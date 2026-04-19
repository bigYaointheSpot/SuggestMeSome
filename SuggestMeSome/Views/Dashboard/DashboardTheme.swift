//
//  DashboardTheme.swift
//  SuggestMeSome
//
//  Dashboard-specific color/label extensions on domain enums. The shared
//  DSSpacing/DSRadius/DSColor tokens, DSCardStyle, and DSSectionHeader live
//  in Views/DesignSystem/DSTokens.swift so every surface can reach them.
//

import SwiftUI

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
