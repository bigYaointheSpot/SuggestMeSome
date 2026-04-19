//
//  OnboardingFlowView.swift
//  SuggestMeSome
//
//  Three-card first-launch flow that introduces strength progression,
//  recovery-aware coaching, and private sharing, then offers to connect
//  Apple Health before handing off to the tab shell. Presented as a
//  fullScreenCover from ContentView until hasCompletedOnboarding flips.
//

import SwiftUI

private struct OnboardingPage: Identifiable {
    let id: Int
    let systemImage: String
    let tint: Color
    let title: String
    let body: String
}

struct OnboardingFlowView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("healthkit.permissionsRequested") private var healthKitPermissionsRequested = false

    @State private var currentPage: Int = 0
    @State private var isRequestingHealthKit = false

    private let healthKitService = HealthKitAuthorizationService()

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            systemImage: "chart.line.uptrend.xyaxis",
            tint: .indigo,
            title: "Progress that adapts",
            body: "Your training programs evolve as you hit new bests. Every logged rep feeds the next session's prescription."
        ),
        OnboardingPage(
            id: 1,
            systemImage: "brain.head.profile",
            tint: .teal,
            title: "Coaching built on readiness",
            body: "Daily Coach reads your recovery signals and suggests when to push, hold, or back off — before you're in the gym."
        ),
        OnboardingPage(
            id: 2,
            systemImage: "lock.shield.fill",
            tint: .green,
            title: "Private by default",
            body: "Your workouts stay on your device. Connect Apple Health to layer in recovery signals, or keep things local — your call."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(pages) { page in
                    pageCard(page)
                        .tag(page.id)
                        .padding(.horizontal, DSSpacing.l)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            controls
                .padding(.horizontal, DSSpacing.l)
                .padding(.bottom, DSSpacing.xl)
                .padding(.top, DSSpacing.m)
        }
        .background(DSColor.surface.opacity(0.4))
    }

    private func pageCard(_ page: OnboardingPage) -> some View {
        VStack(spacing: DSSpacing.xl) {
            Spacer(minLength: DSSpacing.xl)

            Image(systemName: page.systemImage)
                .font(.system(size: 84, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(page.tint)
                .frame(width: 160, height: 160)
                .background(page.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))

            VStack(spacing: DSSpacing.m) {
                Text(page.title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var controls: some View {
        if currentPage == pages.count - 1 {
            VStack(spacing: DSSpacing.s) {
                Button {
                    Task { await requestHealthKit() }
                } label: {
                    HStack(spacing: DSSpacing.s) {
                        if isRequestingHealthKit {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "heart.text.square.fill")
                        }
                        Text(isRequestingHealthKit ? "Connecting…" : "Connect Apple Health")
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(isRequestingHealthKit)

                Button("Maybe later") {
                    finishOnboarding()
                }
                .buttonStyle(DSSecondaryButtonStyle())
                .disabled(isRequestingHealthKit)
            }
        } else {
            Button("Continue") {
                withAnimation { currentPage += 1 }
            }
            .buttonStyle(DSPrimaryButtonStyle())
        }
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
    }

    private func requestHealthKit() async {
        isRequestingHealthKit = true
        healthKitPermissionsRequested = true
        _ = await healthKitService.requestAuthorization(hasRequestedAuthorization: true)
        isRequestingHealthKit = false
        finishOnboarding()
    }
}
