//
//  DSButtonStyles.swift
//  SuggestMeSome
//
//  Named button styles for consistent tint, padding, and tactile feedback.
//  Prefer these over inline `.buttonStyle(.borderedProminent)` modifiers so
//  the visual language stays uniform across surfaces.
//

import SwiftUI

struct DSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.vertical, DSSpacing.m)
            .padding(.horizontal, DSSpacing.l)
            .frame(maxWidth: .infinity)
            .background(DSColor.primaryAction.opacity(configuration.isPressed ? 0.75 : 1.0))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed)
    }
}

struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.vertical, DSSpacing.m)
            .padding(.horizontal, DSSpacing.l)
            .frame(maxWidth: .infinity)
            .background(DSColor.primaryAction.opacity(configuration.isPressed ? 0.18 : 0.12))
            .foregroundStyle(DSColor.primaryAction)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed)
    }
}

