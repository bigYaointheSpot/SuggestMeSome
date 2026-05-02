//
//  DSCard.swift
//  SuggestMeSome
//
//  Unified card primitive introduced in Feature 22 Prompt 2. Replaces the
//  ad-hoc `DSCardStyle` modifier (kept as a deprecation shim) plus the
//  several ad-hoc card implementations across the app. One file, five
//  visual variants, optional header / expansion / press feedback.
//

import SwiftUI

// MARK: - Variant

enum DSCardVariant {
    case flat
    case elevated
    case outlined
    case tinted(Color)
    case gradient(LinearGradient)
}

// MARK: - DSCard

/// A neutral container with consistent padding, corner radius, and optional
/// header + expansion. Variants control fill/stroke. Always uses DSTokens.
struct DSCard<Content: View>: View {
    private let variant: DSCardVariant
    private let header: AnyView?
    private let expandable: Bool
    private let isExpanded: Binding<Bool>?
    private let onTap: (() -> Void)?
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ variant: DSCardVariant = .flat,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.header = nil
        self.expandable = false
        self.isExpanded = nil
        self.onTap = nil
        self.content = content()
    }

    init<Header: View>(
        _ variant: DSCardVariant = .flat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.header = AnyView(header())
        self.expandable = false
        self.isExpanded = nil
        self.onTap = nil
        self.content = content()
    }

    init(
        _ variant: DSCardVariant = .flat,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.header = nil
        self.expandable = true
        self.isExpanded = isExpanded
        self.onTap = nil
        self.content = content()
    }

    init(
        _ variant: DSCardVariant = .flat,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.header = nil
        self.expandable = false
        self.isExpanded = nil
        self.onTap = onTap
        self.content = content()
    }

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: DSSpacing.m) {
            if let header { header }
            if expandable, let isExpanded {
                if isExpanded.wrappedValue {
                    content
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                content
            }
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(strokeOverlay)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .shadow(
            color: shadowColor,
            radius: shadowRadius,
            x: 0,
            y: shadowYOffset
        )

        if let onTap {
            Button(action: onTap) { inner }
                .buttonStyle(DSCardPressStyle())
        } else if expandable, let isExpanded {
            Button {
                withAnimation(reduceMotion ? .linear(duration: 0.001) : DSMotion.standard) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                inner
            }
            .buttonStyle(DSCardPressStyle())
        } else {
            inner
        }
    }

    @ViewBuilder
    private var background: some View {
        switch variant {
        case .flat:
            DSColor.surface
        case .elevated:
            DSColor.surfaceElevated
        case .outlined:
            DSColor.surface
        case .tinted(let tint):
            tint.opacity(0.12)
        case .gradient(let g):
            g
        }
    }

    @ViewBuilder
    private var strokeOverlay: some View {
        switch variant {
        case .outlined:
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .stroke(Color.primary.opacity(DSOpacity.divider), lineWidth: DSHairline.width)
        case .tinted(let tint):
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        default:
            EmptyView()
        }
    }

    private var shadowColor: Color {
        switch variant {
        case .elevated: return DSElevation.level1.shadowColor
        case .gradient: return DSElevation.level1.shadowColor
        default:        return .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch variant {
        case .elevated, .gradient: return DSElevation.level1.shadowRadius
        default:                   return 0
        }
    }

    private var shadowYOffset: CGFloat {
        switch variant {
        case .elevated, .gradient: return DSElevation.level1.shadowYOffset
        default:                   return 0
        }
    }
}

// MARK: - Press style

private struct DSCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

// Note: the existing `.dsCardStyle()` modifier in DSTokens.swift produces
// the same visual output as `DSCard(.flat)` / `DSCard(.tinted(tint))` because
// both consume identical DSSpacing/DSRadius/DSColor tokens. It stays in place
// as a soft deprecation: call sites work unchanged through P5/P6 and migrate
// to `DSCard` opportunistically.
