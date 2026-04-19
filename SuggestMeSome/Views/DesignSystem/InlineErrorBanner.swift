//
//  InlineErrorBanner.swift
//  SuggestMeSome
//
//  Compact, tinted banner for surfacing recoverable errors in-place above
//  the affected form or list. Accepts either a sync or async retry
//  closure — async retries show a ProgressView in place of the retry
//  label while running.
//

import SwiftUI

struct InlineErrorBanner: View {
    let message: String
    private let retry: (() async -> Void)?
    private let retryTitle: String

    @State private var isRetrying = false

    init(
        message: String,
        retryTitle: String = "Try Again",
        retry: (() async -> Void)? = nil
    ) {
        self.message = message
        self.retryTitle = retryTitle
        self.retry = retry
    }

    /// Sync-retry convenience that wraps the closure in a Task so the
    /// shared async-capable body can run it.
    init(
        message: String,
        retryTitle: String = "Try Again",
        syncRetry: @escaping () -> Void
    ) {
        self.message = message
        self.retryTitle = retryTitle
        self.retry = { syncRetry() }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DSColor.signalCaution)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.primary)

                if let retry {
                    Button {
                        Task {
                            isRetrying = true
                            await retry()
                            isRetrying = false
                        }
                    } label: {
                        if isRetrying {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(retryTitle)
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRetrying)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DSSpacing.m)
        .background(DSColor.signalCaution.opacity(0.10), in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Issue: \(message)")
    }
}
