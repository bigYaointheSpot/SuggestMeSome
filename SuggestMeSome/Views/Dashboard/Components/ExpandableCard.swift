//
//  ExpandableCard.swift
//  SuggestMeSome
//
//  Generic tap-to-expand wrapper for dashboard signal cards.
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
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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
                Divider()
                    .opacity(0.5)
                expanded()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .dsCardStyle(tint: tint)
    }
}
