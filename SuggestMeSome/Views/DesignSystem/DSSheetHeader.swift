//
//  DSSheetHeader.swift
//  SuggestMeSome
//
//  Standardized modal/sheet header introduced in Feature 22 Prompt 2.
//  Replaces the 8+ ad-hoc sheet headers across Generator, Programs,
//  Collaboration, and Settings.
//

import SwiftUI

struct DSSheetHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let onClose: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.m) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: DSIcon.s, weight: .semibold))
                    .frame(width: DSIcon.l, height: DSIcon.l)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Circle())
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.top, DSSpacing.m)
        .padding(.bottom, DSSpacing.s)
    }
}

extension DSSheetHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, onClose: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, onClose: onClose) { EmptyView() }
    }
}
