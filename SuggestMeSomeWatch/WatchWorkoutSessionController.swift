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
//  the companion bridge: `workoutLaunch` starts, live/current payloads pause
//  or resume, and `sessionCompletion` ends the linked HealthKit workout.
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
    @Published private(set) var latestMetricsPayload: WatchWorkoutMetricsPayload?
    @Published private(set) var latestHealthSummaryPayload: WatchWorkoutHealthSummaryPayload?

#if canImport(HealthKit) && os(watchOS)
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var activeWorkoutID: UUID?
    private var activeSessionVersionStableID: String?
    private var currentLifecycleState: WatchWorkoutLifecycleState = .running
    private var latestHeartRateBPM: Double?
    private var latestActiveEnergyKilocalories: Double?

    func start(launch: WatchWorkoutLaunchPayload) {
        let existingWorkoutID = activeWorkoutID
        let targetLifecycleState = launch.lifecycleState ?? .running

        guard launch.usesLinkedWatchHealthSession != false else {
            if workoutSession != nil {
                stop(sendHealthSummary: false)
            }
            activeWorkoutID = launch.workoutID
            activeSessionVersionStableID = launch.sessionVersionStableID
            currentLifecycleState = targetLifecycleState
            publishMetrics(isLinkedHealthSessionActive: false)
            return
        }

        if let activeID = existingWorkoutID,
           activeID == launch.workoutID,
           workoutSession != nil {
            activeSessionVersionStableID = launch.sessionVersionStableID
            currentLifecycleState = targetLifecycleState
            apply(lifecycleState: targetLifecycleState)
            return
        }

        if workoutSession != nil {
            stop(sendHealthSummary: false)
        }

        activeWorkoutID = launch.workoutID
        activeSessionVersionStableID = launch.sessionVersionStableID
        currentLifecycleState = targetLifecycleState

        requestAuthorizationIfNeeded { [weak self] authorized in
            Task { @MainActor in
                guard let self else { return }
                guard authorized else {
                    self.lastError = self.lastError ?? "Apple Health access is unavailable on watch."
                    self.publishMetrics(isLinkedHealthSessionActive: false)
                    return
                }
                self.beginSession(for: launch)
            }
        }
    }

    func pause() {
        guard workoutSession != nil else { return }
        currentLifecycleState = .paused
        workoutSession?.pause()
        publishMetrics(isLinkedHealthSessionActive: true)
    }

    func resume() {
        guard workoutSession != nil else { return }
        currentLifecycleState = .running
        workoutSession?.resume()
        publishMetrics(isLinkedHealthSessionActive: true)
    }

    func apply(lifecycleState: WatchWorkoutLifecycleState) {
        switch lifecycleState {
        case .running:
            resume()
        case .paused:
            pause()
        }
    }

    func stop(sendHealthSummary: Bool = true) {
        let capturedWorkoutID = activeWorkoutID
        let capturedSessionVersionStableID = activeSessionVersionStableID
        let builder = builder
        let session = workoutSession

        workoutSession = nil
        self.builder = nil
        activeWorkoutID = nil
        activeSessionVersionStableID = nil
        isActive = false
        currentLifecycleState = .running
        publishMetrics(
            workoutID: capturedWorkoutID,
            sessionVersionStableID: capturedSessionVersionStableID,
            isLinkedHealthSessionActive: false
        )

        guard let session else { return }
        if sendHealthSummary, let builder {
            let finishDate = Date()
            builder.endCollection(withEnd: finishDate) { [weak self] _, endError in
                builder.finishWorkout { workout, finishError in
                    Task { @MainActor in
                        self?.handleFinishedWorkout(
                            workoutID: capturedWorkoutID,
                            sessionVersionStableID: capturedSessionVersionStableID,
                            workout: workout,
                            error: finishError ?? endError
                        )
                    }
                }
            }
        }
        session.end()
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
            builder.delegate = self
            session.delegate = self

            let startDate = launch.startedAt
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { _, error in
                Task { @MainActor in
                    if let error {
                        self.lastError = error.localizedDescription
                        self.publishMetrics(isLinkedHealthSessionActive: false)
                        return
                    }
                    self.workoutSession = session
                    self.builder = builder
                    self.activeWorkoutID = launch.workoutID
                    self.activeSessionVersionStableID = launch.sessionVersionStableID
                    self.currentLifecycleState = launch.lifecycleState ?? .running
                    self.latestHeartRateBPM = nil
                    self.latestActiveEnergyKilocalories = nil
                    self.isActive = true
                    self.lastError = nil
                    self.publishMetrics(isLinkedHealthSessionActive: true)
                    if self.currentLifecycleState == .paused {
                        self.pause()
                    }
                }
            }
        } catch {
            self.lastError = error.localizedDescription
            publishMetrics(isLinkedHealthSessionActive: false)
        }
    }

    private func handleFinishedWorkout(
        workoutID: UUID?,
        sessionVersionStableID: String?,
        workout: HKWorkout?,
        error: Error?
    ) {
        if let error {
            lastError = error.localizedDescription
            return
        }
        guard let workoutID,
              let workout else { return }

        latestHealthSummaryPayload = WatchWorkoutHealthSummaryPayload(
            workoutID: workoutID,
            sessionVersionStableID: sessionVersionStableID,
            healthKitWorkoutUUID: workout.uuid.uuidString,
            exportedAt: Date(),
            totalActiveEnergyKilocalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
            finalHeartRateBPM: latestHeartRateBPM
        )
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
                Task { @MainActor in
                    self.lastError = error.localizedDescription
                }
            }
            completion(success)
        }
    }

    private func publishMetrics(
        workoutID: UUID? = nil,
        sessionVersionStableID: String? = nil,
        isLinkedHealthSessionActive: Bool
    ) {
        guard let workoutID = workoutID ?? activeWorkoutID else { return }
        latestMetricsPayload = WatchWorkoutMetricsPayload(
            workoutID: workoutID,
            sessionVersionStableID: sessionVersionStableID ?? activeSessionVersionStableID,
            lifecycleState: currentLifecycleState,
            isLinkedHealthSessionActive: isLinkedHealthSessionActive,
            heartRateBPM: latestHeartRateBPM,
            activeEnergyKilocalories: latestActiveEnergyKilocalories,
            capturedAt: Date()
        )
    }

    private func updateMetrics(from builder: HKLiveWorkoutBuilder) {
        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
           let statistics = builder.statistics(for: heartRateType),
           let quantity = statistics.mostRecentQuantity() {
            latestHeartRateBPM = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }

        if let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
           let statistics = builder.statistics(for: energyType),
           let quantity = statistics.sumQuantity() {
            latestActiveEnergyKilocalories = quantity.doubleValue(for: .kilocalorie())
        }

        publishMetrics(isLinkedHealthSessionActive: workoutSession != nil)
    }
#else
    func start(launch: WatchWorkoutLaunchPayload) {
        latestMetricsPayload = WatchWorkoutMetricsPayload(
            workoutID: launch.workoutID,
            sessionVersionStableID: launch.sessionVersionStableID,
            lifecycleState: launch.lifecycleState ?? .running,
            isLinkedHealthSessionActive: false,
            heartRateBPM: nil,
            activeEnergyKilocalories: nil,
            capturedAt: Date()
        )
        isActive = false
    }

    func pause() {}
    func resume() {}
    func apply(lifecycleState: WatchWorkoutLifecycleState) {
        _ = lifecycleState
    }
    func stop(sendHealthSummary: Bool = true) {
        _ = sendHealthSummary
        isActive = false
    }
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
            case .paused:
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
            self.publishMetrics(isLinkedHealthSessionActive: false)
        }
    }
}

extension WatchWorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            self.updateMetrics(from: workoutBuilder)
        }
    }
}
#endif
