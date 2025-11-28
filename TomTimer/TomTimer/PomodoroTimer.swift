import Foundation
import Combine
import SwiftUI

/// Central timer model for Pomodoro countdown logic.
/// Owns the countdown, persistence, and basic start/pause/reset operations.
final class PomodoroTimer: ObservableObject {
    // MARK: - Published state used by views
    @Published var timeRemaining: Int
    @Published var isRunning: Bool = false
    @Published var sessionDuration: Int?

    // MARK: - Configuration & persistence
    @AppStorage("timerDuration") private var timerDuration: Int = 1500
    @AppStorage("timerEndDateTimestamp") private var timerEndDateTimestamp: Double = 0
    @AppStorage("sessionDurationBackup") private var storedSessionDuration: Int = 0

    private var timer: Timer?

    init() {
        // Load the stored duration without touching self before init completes
        let stored = UserDefaults.standard.integer(forKey: "timerDuration")
        self.timeRemaining = stored > 0 ? stored : 1500
    }

    // MARK: - Public API

    func startNewSession() {
        // New session uses current timeRemaining as the full session duration
        if sessionDuration == nil {
            sessionDuration = timeRemaining
        }
        storedSessionDuration = sessionDuration ?? timerDuration
        scheduleTimer(resumingExisting: false)
    }

    func resumeIfNeeded() {
        restoreFromPersistenceIfNeeded()
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        persistIfNeeded()
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        timeRemaining = timerDuration
        sessionDuration = nil
        storedSessionDuration = 0
        timerEndDateTimestamp = 0
    }

    /// Should be called when the app is going to background to persist state.
    func persistIfNeeded() {
        guard isRunning else { return }
        let now = Date().timeIntervalSince1970
        timerEndDateTimestamp = now + Double(timeRemaining)
        storedSessionDuration = sessionDuration ?? timerDuration
    }

    /// Restores state from persisted end timestamp, if present.
    func restoreFromPersistenceIfNeeded() {
        guard timerEndDateTimestamp > 0 else { return }

        let now = Date().timeIntervalSince1970
        let remaining = timerEndDateTimestamp - now

        if remaining <= 0 {
            // Timer expired while app was inactive – reset to default
            isRunning = false
            timeRemaining = timerDuration
            sessionDuration = nil
            clearPersistence()
            return
        }

        timeRemaining = Int(remaining)

        if sessionDuration == nil {
            if storedSessionDuration > 0 {
                sessionDuration = storedSessionDuration
            } else {
                sessionDuration = timerDuration
            }
        }

        if timer == nil {
            scheduleTimer(resumingExisting: true)
        }
    }

    // MARK: - Internal helpers

    private func scheduleTimer(resumingExisting: Bool) {
        timer?.invalidate()
        isRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.finish()
            }
        }

        persistIfNeeded()
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        timeRemaining = timerDuration
        sessionDuration = nil
        storedSessionDuration = 0
        timerEndDateTimestamp = 0
    }

    private func clearPersistence() {
        timerEndDateTimestamp = 0
        storedSessionDuration = 0
    }
}
