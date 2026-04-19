//
//  DSEmptyState.swift
//  SuggestMeSome
//
//  Unified empty-state card wrapping ContentUnavailableView with an optional
//  primary CTA. Use everywhere the UI has no data to show so tone stays
//  consistent across tabs.
//

import SwiftUI

struct DSEmptyState: View {
    struct CTA {
        let title: String
        let systemImage: String?
        let action: () -> Void

        init(title: String, systemImage: String? = nil, action: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.action = action
        }
    }

    let systemImage: String
    let title: String
    let message: String?
    let cta: CTA?

    init(
        systemImage: String,
        title: String,
        message: String? = nil,
        cta: CTA? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.cta = cta
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DSColor.primaryAction)
            }
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let cta {
                Button {
                    cta.action()
                } label: {
                    if let systemImage = cta.systemImage {
                        Label(cta.title, systemImage: systemImage)
                    } else {
                        Text(cta.title)
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .padding(.horizontal, DSSpacing.l)
                .padding(.top, DSSpacing.s)
            }
        }
    }
}
