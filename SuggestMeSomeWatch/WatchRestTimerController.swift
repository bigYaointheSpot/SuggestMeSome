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
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var isRunning: Bool = false

    private var tickTask: Task<Void, Never>?
    private var hasFiredHalfwayCue: Bool = false

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        let elapsed = totalSeconds - remainingSeconds
        return min(1, max(0, Double(elapsed) / Double(totalSeconds)))
    }

    func start(duration: Int) {
        let clamped = max(0, duration)
        stop(resetVisible: false)
        guard clamped > 0 else { return }
        totalSeconds = clamped
        remainingSeconds = clamped
        hasFiredHalfwayCue = false
        isRunning = true
        playHaptic(.start)

        tickTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if Task.isCancelled { return }
                guard self.isRunning else { return }
                self.tick()
                if self.remainingSeconds == 0 { return }
            }
        }
    }

    func stop(resetVisible: Bool = true) {
        tickTask?.cancel()
        tickTask = nil
        isRunning = false
        if resetVisible {
            remainingSeconds = 0
            totalSeconds = 0
        }
    }

    func skip() {
        stop(resetVisible: true)
        playHaptic(.skip)
    }

    private func tick() {
        guard remainingSeconds > 0 else {
            finish()
            return
        }
        remainingSeconds -= 1
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
        playHaptic(.complete)
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
