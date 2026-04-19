//
//  WatchRestTimerController.swift
//  SuggestMeSomeWatch
//
//  Feature 12 Prompt 5 — Watch-local rest timer controller.
//
//  Rest is a watch-native UX layer. Phone stays the source of truth for
//  workout state and persistence; the rest timer runs on the wrist as a
//  transient post-set prompt and emits haptics for cue + completion.
//

import Combine
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(WatchKit)
import WatchKit
#endif

enum WatchRestTimerDefaults {
    /// Default rest duration used when no phone-provided value is present.
    /// Tuned for common compound-lift cadence so the wrist feels useful
    /// without nudging users toward over-resting.
    static let strengthSeconds: Int = 90
}

/// Platform-neutral haptic cue identifier so call sites compile even when
/// WatchKit is not available (e.g. indexing into the iOS target).
enum WatchRestHapticCue {
    case start
    case halfway
    case nextSetCue
    case complete
    case skip
}

@MainActor
final class WatchRestTimerController: ObservableObject {
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPaused: Bool = false

    private var tickTask: Task<Void, Never>?
    private var hasFiredHalfwayCue: Bool = false
    private var backgroundNotificationFallbackEnabled = false
    private var pendingNotificationIdentifier: String?
    private var pausedRemainingSeconds: Int = 0
    private var targetEndDate: Date?

    func progress(at date: Date = .now) -> Double {
        guard totalSeconds > 0 else { return 0 }
        let elapsed = totalSeconds - remainingSeconds(at: date)
        return min(1, max(0, Double(elapsed) / Double(totalSeconds)))
    }

    func remainingSeconds(at date: Date = .now) -> Int {
        guard isRunning else {
            return max(0, pausedRemainingSeconds)
        }
        guard !isPaused, let targetEndDate else {
            return max(0, pausedRemainingSeconds)
        }
        return max(0, Int(ceil(targetEndDate.timeIntervalSince(date))))
    }

    func start(duration: Int, allowsBackgroundNotificationFallback: Bool = false) {
        let clamped = max(0, duration)
        stop(resetVisible: false)
        guard clamped > 0 else { return }
        totalSeconds = clamped
        pausedRemainingSeconds = clamped
        hasFiredHalfwayCue = false
        backgroundNotificationFallbackEnabled = allowsBackgroundNotificationFallback
        isRunning = true
        isPaused = false
        targetEndDate = Date().addingTimeInterval(TimeInterval(clamped))
        playHaptic(.start)
        scheduleBackgroundNotificationIfNeeded(secondsFromNow: clamped)

        tickTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if Task.isCancelled { return }
                guard self.isRunning else { return }
                guard !self.isPaused else { continue }
                self.tick()
                if self.remainingSeconds() == 0 { return }
            }
        }
    }

    func stop(resetVisible: Bool = true) {
        tickTask?.cancel()
        tickTask = nil
        isRunning = false
        isPaused = false
        backgroundNotificationFallbackEnabled = false
        targetEndDate = nil
        cancelBackgroundNotification()
        if resetVisible {
            pausedRemainingSeconds = 0
            totalSeconds = 0
        }
    }

    func skip() {
        stop(resetVisible: true)
        playHaptic(.skip)
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        pausedRemainingSeconds = remainingSeconds()
        isPaused = true
        targetEndDate = nil
        cancelBackgroundNotification()
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        targetEndDate = Date().addingTimeInterval(TimeInterval(pausedRemainingSeconds))
        scheduleBackgroundNotificationIfNeeded(secondsFromNow: pausedRemainingSeconds)
    }

    private func tick() {
        let remainingSeconds = remainingSeconds()
        pausedRemainingSeconds = remainingSeconds

        guard remainingSeconds > 0 else {
            finish()
            return
        }
        // Subtle wrist tap at the midpoint so users feel the pacing without
        // needing to glance. Only fires once per rest period and only when
        // the rest is long enough to have a meaningful midpoint.
        if !hasFiredHalfwayCue,
           totalSeconds >= 20,
           remainingSeconds * 2 <= totalSeconds,
           remainingSeconds > 3 {
            hasFiredHalfwayCue = true
            playHaptic(.halfway)
        }
        if remainingSeconds == 3 {
            playHaptic(.nextSetCue)
        }
        if remainingSeconds == 0 {
            finish()
        }
    }

    private func finish() {
        tickTask?.cancel()
        tickTask = nil
        isRunning = false
        isPaused = false
        pausedRemainingSeconds = 0
        targetEndDate = nil
        cancelBackgroundNotification()
        playHaptic(.complete)
    }

    private func scheduleBackgroundNotificationIfNeeded(secondsFromNow: Int) {
#if canImport(UserNotifications)
        guard backgroundNotificationFallbackEnabled else { return }
        guard secondsFromNow > 0 else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in
                    self?.scheduleBackgroundNotification(in: center, secondsFromNow: secondsFromNow)
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    Task { @MainActor in
                        self?.scheduleBackgroundNotification(in: center, secondsFromNow: secondsFromNow)
                    }
                }
            case .denied:
                return
            @unknown default:
                return
            }
        }
#else
        _ = secondsFromNow
#endif
    }

    private func scheduleBackgroundNotification(in center: UNUserNotificationCenter, secondsFromNow: Int) {
#if canImport(UserNotifications)
        let identifier = "suggestmesome.rest.\(UUID().uuidString)"
        let content = UNMutableNotificationContent()
        content.title = "Rest Complete"
        content.body = "Time for your next set."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(1, secondsFromNow)),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        cancelBackgroundNotification(in: center)
        center.add(request)
        pendingNotificationIdentifier = identifier
#else
        _ = center
        _ = secondsFromNow
#endif
    }

    private func cancelBackgroundNotification() {
#if canImport(UserNotifications)
        cancelBackgroundNotification(in: UNUserNotificationCenter.current())
#endif
    }

    private func cancelBackgroundNotification(in center: UNUserNotificationCenter) {
        guard let pendingNotificationIdentifier else { return }
        center.removePendingNotificationRequests(withIdentifiers: [pendingNotificationIdentifier])
        self.pendingNotificationIdentifier = nil
    }

    private func playHaptic(_ cue: WatchRestHapticCue) {
#if canImport(WatchKit)
        let device = WKInterfaceDevice.current()
        switch cue {
        case .start:       device.play(.start)
        case .halfway:     device.play(.click)
        case .nextSetCue:  device.play(.directionUp)
        case .complete:    device.play(.success)
        case .skip:        device.play(.click)
        }
#else
        _ = cue
#endif
    }
}
