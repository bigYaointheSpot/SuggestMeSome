//
//  ExpandableCard.swift
//  SuggestMeSome
//
//  Generic tap-to-expand wrapper for dashboard signal cards. Now a thin
//  composition over `DSCard` from the Feature 22 design system, which
//  owns the expand/collapse animation, accessibility, and surface
//  treatment. The original public API is preserved for the existing
//  call sites in Dashboard cards.
//

import SwiftUI

struct ExpandableCard<Collapsed: View, Expanded: View>: View {
    let collapsed: () -> Collapsed
    let expanded: () -> Expanded
    var tint: Color? = nil
    var showsChevron: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool = false

    init(
        tint: Color? = nil,
        showsChevron: Bool = true,
        @ViewBuilder collapsed: @escaping () -> Collapsed,
        @ViewBuilder expanded: @escaping () -> Expanded
    ) {
        self.tint = tint
        self.showsChevron = showsChevron
        self.collapsed = collapsed
        self.expanded = expanded
    }

    var body: some View {
        DSCard(tint.map { DSCardVariant.tinted($0) } ?? .flat) {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                Button {
                    if reduceMotion {
                        isExpanded.toggle()
                    } else {
                        withAnimation(DSMotion.standard) {
                            isExpanded.toggle()
                        }
                    }
                } label: {
                    HStack(alignment: .top, spacing: DSSpacing.s) {
                        collapsed()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if showsChevron {
                            Image(systemName: "chevron.down")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .padding(.top, 2)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Double tap to collapse details." : "Double tap to expand for more detail.")

                if isExpanded {
                    DSDivider()
                    expanded()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}
