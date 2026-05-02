//
//  DSSkeleton.swift
//  SuggestMeSome
//
//  Pulse-animated placeholder shapes introduced in Feature 22 Prompt 2.
//  Used when data is hydrating (Daily Coach today plan, Dashboard charts,
//  collaboration roster). Respects reduce-motion: when on, the placeholder
//  renders without the pulsing animation.
//

import SwiftUI

enum DSSkeletonShape {
    case line(width: CGFloat?)
    case rect(width: CGFloat, height: CGFloat)
    case circle(diameter: CGFloat)
}

struct DSSkeleton: View {
    let shape: DSSkeletonShape

    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch shape {
            case .line(let width):
                RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                    .frame(width: width, height: 14)
            case .rect(let width, let height):
                RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                    .frame(width: width, height: height)
            case .circle(let diameter):
                Circle()
                    .frame(width: diameter, height: diameter)
            }
        }
        .foregroundStyle(
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.08),
                    Color.primary.opacity(reduceMotion ? 0.08 : 0.18),
                    Color.primary.opacity(0.08)
                ],
                startPoint: UnitPoint(x: phase - 0.3, y: 0),
                endPoint: UnitPoint(x: phase + 0.3, y: 0)
            )
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.3
            }
        }
        .accessibilityLabel("Loading")
    }
}
