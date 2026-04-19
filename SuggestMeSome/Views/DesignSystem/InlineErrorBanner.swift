//
//  InlineErrorBanner.swift
//  SuggestMeSome
//
//  Compact, tinted banner for surfacing recoverable errors in-place above
//  the affected form or list. Shared between this UI pass and Feature 19
//  Phase 1 collaboration polish.
//

import SwiftUI

struct InlineErrorBanner: View {
    let title: String
    let message: String?
    let retry: (() -> Void)?

    init(title: String, message: String? = nil, retry: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.retry = retry
    }

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DSColor.signalCritical)
                .font(.subheadline.weight(.semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: DSSpacing.s)

            if let retry {
                Button("Retry", action: retry)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DSColor.signalCritical)
            }
        }
        .padding(DSSpacing.m)
        .background(DSColor.signalCritical.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
