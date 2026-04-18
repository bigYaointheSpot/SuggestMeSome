//
//  DashboardEmptyState.swift
//  SuggestMeSome
//
//  Consistent empty-state block for dashboard cards.
//

import SwiftUI

struct DashboardEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var iconColor: Color = DSColor.primaryAction
    var cta: (label: String, action: () -> Void)? = nil

    var body: some View {
        VStack(spacing: DSSpacing.s) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor.opacity(0.75))
                .padding(.bottom, 2)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let cta {
                Button(cta.label, action: cta.action)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.vertical, DSSpacing.s)
                    .background(iconColor.opacity(0.15))
                    .foregroundStyle(iconColor)
                    .clipShape(Capsule())
                    .padding(.top, DSSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.l)
    }
}
