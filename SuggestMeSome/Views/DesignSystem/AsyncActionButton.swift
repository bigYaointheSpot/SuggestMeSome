//
//  AsyncActionButton.swift
//  SuggestMeSome
//
//  Button that awaits an async action, disables itself while running, swaps
//  the label for a ProgressView, and fires a success haptic on completion.
//  Shared between this UI pass and Feature 19 Phase 1 collaboration polish.
//

import SwiftUI

struct AsyncActionButton<Label: View>: View {
    let role: ButtonRole?
    let action: () async -> Void
    @ViewBuilder let label: () -> Label

    @State private var isRunning = false
    @State private var completionCount = 0

    init(
        role: ButtonRole? = nil,
        action: @escaping () async -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.role = role
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(role: role) {
            guard !isRunning else { return }
            isRunning = true
            Task {
                await action()
                await MainActor.run {
                    isRunning = false
                    completionCount &+= 1
                }
            }
        } label: {
            HStack(spacing: DSSpacing.s) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                label()
            }
        }
        .disabled(isRunning)
        .sensoryFeedback(.success, trigger: completionCount)
    }
}
