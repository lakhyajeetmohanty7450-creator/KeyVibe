//
//  LabsManager.swift
//  Haptyk
//
//  Central controller for all "Labs" experimental features.
//
//  Labs are opt-in, playful features that demonstrate what velocity-sensitive
//  typing can do beyond realistic key sounds. Each lab feature can be
//  independently enabled/disabled from the menu bar UI.
//
//  Architecture:
//  - LabsManager owns all feature instances and dispatches keystrokes to them.
//  - Each feature independently decides whether to act on a given keystroke.
//  - LabsManager is a singleton accessed from the main keyboard processing pipeline.
//
//  Threading:
//  - All methods are called on the main thread.
//  - Published properties drive SwiftUI/AppKit bindings.
//
//  Copyright © 2024 Haptyk. All rights reserved.
//

import Foundation
import Combine

// MARK: - LabsManager

/// Central controller for all "Labs" experimental features.
///
/// `LabsManager` acts as the single entry point for the keyboard processing
/// pipeline to dispatch velocity-resolved keystrokes to all active lab features.
/// It owns each feature instance, coordinates daily resets, and provides
/// observable state for the settings UI.
///
/// ## Usage
/// ```swift
/// // In the keyboard event handler:
/// LabsManager.shared.processKeystroke(event: keyEvent, velocity: velocityResult)
/// ```
///
/// ## Feature List
/// - **AutoCaps**: Converts characters to uppercase when typed with slam force
/// - **VineBoom**: Plays a dramatic sound effect when Enter is slammed
/// - **TypingMetrics**: Local typing statistics and force percentile tracking
final class LabsManager: ObservableObject {

    // MARK: - Singleton

    /// Shared singleton instance.
    static let shared = LabsManager()

    // MARK: - Feature Instances

    /// Slam-force auto-capitalization feature.
    let autoCaps = AutoCapsFeature()

    /// Vine Boom sound effect on Enter slam.
    let vineBoom = VineBoomFeature()

    /// Local typing statistics tracker.
    let typingMetrics = TypingMetrics()

    // MARK: - Properties

    /// Whether any labs feature is currently enabled.
    var hasActiveFeature: Bool {
        autoCaps.isEnabled || vineBoom.isEnabled || typingMetrics.isEnabled
    }

    /// Cancellable storage for Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// The calendar date of the last processed keystroke, used for midnight reset detection.
    private var lastKeystrokeDate: Date?

    // MARK: - Initialization

    private init() {
        setupMidnightResetObserver()
        loadPersistedState()
    }

    // MARK: - Keystroke Processing

    /// Process a velocity-resolved keystroke through all active lab features.
    ///
    /// This is the main dispatch method called from the keyboard monitoring pipeline
    /// after velocity classification is complete. Each enabled feature receives the
    /// keystroke and independently decides whether to act on it.
    ///
    /// - Parameters:
    ///   - event: The keyboard event containing key code, category, and direction.
    ///   - velocity: The velocity classification result containing force magnitude and tier.
    func processKeystroke(event: KeyEvent, velocity: VelocityResult) {
        // Check for midnight rollover and reset daily metrics if needed
        checkDailyReset()

        // Dispatch to auto-caps feature
        if autoCaps.isEnabled {
            autoCaps.processKeystroke(event: event, velocity: velocity)
        }

        // Dispatch to vine boom feature (check is internal to the feature)
        if vineBoom.isEnabled {
            _ = vineBoom.shouldTrigger(event: event, velocity: velocity)
        }

        // Always record metrics if enabled (regardless of other features)
        if typingMetrics.isEnabled {
            typingMetrics.recordKeystroke(
                force: velocity.magnitude,
                tier: velocity.tier
            )
        }
    }

    /// Evaluate whether auto-caps should modify the CGEvent for a given keystroke.
    ///
    /// This is called from the `CGEventTap` callback to determine if the event
    /// should have its shift flag injected. Returns `true` if the event was modified.
    ///
    /// - Parameters:
    ///   - event: The keyboard event.
    ///   - velocity: The velocity classification result.
    /// - Returns: `true` if the event's shift flag should be set.
    func shouldApplyAutoCaps(event: KeyEvent, velocity: VelocityResult) -> Bool {
        guard autoCaps.isEnabled else { return false }
        return autoCaps.shouldApplyShift(event: event, velocity: velocity)
    }

    /// Check whether the vine boom sound should replace the normal key sound.
    ///
    /// - Parameters:
    ///   - event: The keyboard event.
    ///   - velocity: The velocity classification result.
    /// - Returns: `true` if the vine boom should play instead of the normal key click.
    func shouldPlayVineBoom(event: KeyEvent, velocity: VelocityResult) -> Bool {
        guard vineBoom.isEnabled else { return false }
        return vineBoom.shouldTrigger(event: event, velocity: velocity)
    }

    // MARK: - Daily Reset

    /// Reset all metrics for a new day.
    ///
    /// Called automatically at midnight or manually from the settings UI.
    /// Persists the previous day's stats before clearing.
    func resetDailyMetrics() {
        HaptykLog.info("[LabsManager] Resetting daily metrics")

        autoCaps.resetDailyCount()
        vineBoom.resetDailyCount()
        typingMetrics.resetDaily()

        lastKeystrokeDate = Date()
    }

    // MARK: - Persistence

    /// Save all feature enabled states to UserDefaults.
    func persistState() {
        let defaults = UserDefaults.standard
        defaults.set(autoCaps.isEnabled, forKey: Keys.autoCapsEnabled)
        defaults.set(vineBoom.isEnabled, forKey: Keys.vineBoomEnabled)
        defaults.set(typingMetrics.isEnabled, forKey: Keys.metricsEnabled)
    }

    // MARK: - Private Helpers

    /// Load persisted feature states from UserDefaults.
    private func loadPersistedState() {
        let defaults = UserDefaults.standard

        // Only load if keys exist (preserve defaults on first launch)
        if defaults.object(forKey: Keys.autoCapsEnabled) != nil {
            autoCaps.isEnabled = defaults.bool(forKey: Keys.autoCapsEnabled)
        }
        if defaults.object(forKey: Keys.vineBoomEnabled) != nil {
            vineBoom.isEnabled = defaults.bool(forKey: Keys.vineBoomEnabled)
        }
        if defaults.object(forKey: Keys.metricsEnabled) != nil {
            typingMetrics.isEnabled = defaults.bool(forKey: Keys.metricsEnabled)
        }
    }

    /// Check if the calendar date has rolled over since the last keystroke.
    private func checkDailyReset() {
        let now = Date()
        if let lastDate = lastKeystrokeDate {
            if !Calendar.current.isDate(now, inSameDayAs: lastDate) {
                resetDailyMetrics()
            }
        }
        lastKeystrokeDate = now
    }

    /// Set up an observer for system clock changes / midnight rollover.
    private func setupMidnightResetObserver() {
        // Listen for significant time change (midnight, timezone change, etc.)
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetDailyMetrics()
            }
            .store(in: &cancellables)
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let autoCapsEnabled  = "com.haptyk.labs.autoCaps.enabled"
        static let vineBoomEnabled  = "com.haptyk.labs.vineBoom.enabled"
        static let metricsEnabled   = "com.haptyk.labs.metrics.enabled"
    }
}

// MARK: - Logging Utility

/// Lightweight logging namespace for Haptyk.
///
/// Provides structured, leveled logging without depending on external frameworks.
/// In release builds, debug-level messages are compiled out.
enum HaptykLog {

    /// Log an informational message.
    static func info(_ message: String) {
        #if DEBUG
        print("ℹ️ \(message)")
        #endif
    }

    /// Log a warning message.
    static func warning(_ message: String) {
        print("⚠️ \(message)")
    }

    /// Log an error message.
    static func error(_ message: String) {
        print("❌ \(message)")
    }
}

