//
//  WatchWorkoutSessionController.swift
//  SuggestMeSomeWatch
//
//  Feature 14 — HealthKit-backed workout session controller.
//
//  Owns an `HKWorkoutSession` on the wrist so that:
//    • The display stays awake in always-on mode during a live set
//    • Heart rate and active energy flow while the workout is active
//    • Completed workouts credit the Activity rings
//
//  Phone remains source of truth for exercises/sets/reps — the HK session is
//  purely the wrist-local "we are mid-workout" anchor. Lifecycle is driven by
//  the companion bridge: `workoutLaunch` starts, `sessionCompletion` ends.
//

import Combine
import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
final class WatchWorkoutSessionController: NSObject, ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var lastError: String?

#if canImport(HealthKit) && os(watchOS)
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var activeWorkoutID: UUID?

    func start(launch: WatchWorkoutLaunchPayload) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Idempotent: if the same workout is already active, do nothing. If a
        // different workout is active (e.g. user started a new one without
        // completing the old), end the old session first.
        if let activeID = activeWorkoutID, activeID == launch.workoutID, isActive {
            return
        }
        if isActive {
            stop()
        }

        requestAuthorizationIfNeeded { [weak self] authorized in
            Task { @MainActor in
                guard let self, authorized else { return }
                self.beginSession(for: launch)
            }
        }
    }

    func stop() {
        guard let session = workoutSession else {
            isActive = false
            activeWorkoutID = nil
            return
        }
        // End collection cleanly so partial samples still land in Health.
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
        session.end()
        workoutSession = nil
        builder = nil
        activeWorkoutID = nil
        isActive = false
    }

    private func beginSession(for launch: WatchWorkoutLaunchPayload) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self

            let startDate = launch.startedAt
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { _, _ in }

            self.workoutSession = session
            self.builder = builder
            self.activeWorkoutID = launch.workoutID
            self.isActive = true
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        var readTypes: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRate)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            readTypes.insert(activeEnergy)
        }
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
            if let error {
                DispatchQueue.main.async { self.lastError = error.localizedDescription }
            }
            completion(success)
        }
    }
#else
    func start(launch: WatchWorkoutLaunchPayload) {}
    func stop() {}
#endif
}

#if canImport(HealthKit) && os(watchOS)
extension WatchWorkoutSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .ended, .stopped:
                self.isActive = false
            case .running:
                self.isActive = true
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.isActive = false
        }
    }
}
#endif
