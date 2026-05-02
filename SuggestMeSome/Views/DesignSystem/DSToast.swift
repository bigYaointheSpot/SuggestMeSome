//
//  DSToast.swift
//  SuggestMeSome
//
//  Transient confirmation overlay — a material-backed capsule with an
//  icon and message that auto-dismisses after a short interval. Replaces
//  the bespoke confirmation overlay in CheckInFormView and keeps the
//  same pattern available for future "saved", "shared", "copied" micro-
//  confirmations without each surface rolling its own.
//
//  Usage:
//      .overlay(alignment: .top) {
//          DSToast(isPresented: $showingToast,
//                  text: "Check-in saved",
//                  systemImage: "checkmark.circle.fill")
//      }
//

import SwiftUI

struct DSToast: View {
    @Binding var isPresented: Bool
    let text: String
    var systemImage: String = "checkmark.circle.fill"
    var tint: Color = DSColor.signalPositive
    /// Seconds before the toast fades back out. The timer starts when
    /// `isPresented` flips to true.
    var autoDismissAfter: Double = 2.2

    var body: some View {
        Group {
            if isPresented {
                HStack(spacing: DSSpacing.s) {
                    Image(systemName: systemImage)
                        .dsHeadline()
                        .foregroundStyle(tint)
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, DSSpacing.l)
                .padding(.vertical, DSSpacing.m)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(tint.opacity(0.2), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(text)
                .padding(.top, DSSpacing.m)
                .task(id: isPresented) {
                    guard isPresented else { return }
                    try? await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
                    if !Task.isCancelled {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPresented = false
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
    }
}
