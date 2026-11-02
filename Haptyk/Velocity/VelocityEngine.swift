//
//  VelocityEngine.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Event Synchronization & Velocity Engine:
//  Correlates system-wide keyboard events with high-frequency chassis
//  vibration spikes from the internal accelerometer to determine keystroke force.
//

import Foundation
import os.log

// MARK: - VelocityResult

/// The resolved velocity metrics for a single physical keystroke event.
public struct VelocityResult: Sendable {
    /// Discrete primary classification tier.
    public let forceTier: ForceTier

    /// Peak delta acceleration magnitude in Gs measured from sensor.
    public let rawMagnitude: Double

    /// Continuous normalized impact force (0.0 = lightest brush, 1.0 = maximum slam).
    public let normalizedForce: Double

    /// Crossfade blending weights between adjacent force tier audio recordings.
    public let crossfadeWeights: CrossfadeWeights

    public init(
        forceTier: ForceTier,
        rawMagnitude: Double,
        normalizedForce: Double,
        crossfadeWeights: CrossfadeWeights
    ) {
        self.forceTier = forceTier
        self.rawMagnitude = rawMagnitude
        self.normalizedForce = normalizedForce
        self.crossfadeWeights = crossfadeWeights
    }

    /// Default baseline fallback for external keyboards, clamshell mode, or unsupported machines.
    public static var baselineFallback: VelocityResult {
        VelocityResult(
            forceTier: .medium,
            rawMagnitude: 0.45,
            normalizedForce: 0.5,
            crossfadeWeights: .single(.medium)
        )
    }

    /// Convenience aliases
    public var magnitude: Double { rawMagnitude }
    public var tier: ForceTier { forceTier }
}

// MARK: - VelocityEngine

/// Core engine that marries global keypress events with chassis vibration telemetry.
public final class VelocityEngine {

    // MARK: - Properties

    private let accelerometerManager: AccelerometerManager
    private let keyboardMonitor: KeyboardMonitor

    private var classifier = ForceTierClassifier()
    private let crossfadeCalculator = CrossfadeCalculator()

    /// Sensitivity multiplier (0.0 = least sensitive, 2.0 = most sensitive, 1.0 = default).
    public var sensitivity: Double = 1.0 {
        didSet {
            classifier.adjustSensitivity(sensitivity)
        }
    }

    /// Callback fired whenever a keystroke's velocity has been resolved.
    public var onVelocityResolved: ((KeyEvent, VelocityResult) -> Void)?

    /// Remembers the force tier of currently depressed keys for their release sounds.
    private var activeKeyTiers: [Int64: ForceTier] = [:]
    private let tierLock = NSLock()

    /// Dedicated logger.
    private let log = HaptykLogger(category: .velocity)

    // MARK: - Initialization

    public init(
        accelerometerManager: AccelerometerManager = .shared,
        keyboardMonitor: KeyboardMonitor = .shared
    ) {
        self.accelerometerManager = accelerometerManager
        self.keyboardMonitor = keyboardMonitor

        setupKeyboardPipeline()
    }

    // MARK: - Pipeline Setup

    private func setupKeyboardPipeline() {
        keyboardMonitor.onKeyEvent = { [weak self] event in
            self?.processKeyEvent(event)
        }
    }

    // MARK: - Event Processing

    /// Evaluates incoming key event, inspects the accelerometer ring buffer,
    /// and resolves velocity and audio crossfade weights.
    public func processKeyEvent(_ event: KeyEvent) {
        let result: VelocityResult

        switch event.eventType {
        case .keyDown:
            if accelerometerManager.isAvailable {
                // Peak delta within correlation window around keystroke timestamp
                let rawPeak = accelerometerManager.peakMagnitudeInWindow(
                    around: event.timestamp,
                    windowMs: Constants.Accelerometer.correlationWindowMs
                )

                if rawPeak > 0.02 {
                    let adjustedMagnitude = rawPeak * sensitivity
                    let tier = classifier.classify(adjustedMagnitude)
                    let weights = crossfadeCalculator.calculateWeights(
                        magnitude: adjustedMagnitude,
                        classifier: classifier
                    )
                    let normalized = min(1.0, adjustedMagnitude / (Constants.ForceTiers.slamThreshold * 1.5))

                    result = VelocityResult(
                        forceTier: tier,
                        rawMagnitude: rawPeak,
                        normalizedForce: normalized,
                        crossfadeWeights: weights
                    )

                    tierLock.lock()
                    activeKeyTiers[event.keyCode] = tier
                    tierLock.unlock()
                } else {
                    // Micro-tap or baseline keystroke
                    result = .baselineFallback
                    tierLock.lock()
                    activeKeyTiers[event.keyCode] = .medium
                    tierLock.unlock()
                }
            } else {
                // Accelerometer unavailable: fallback to baseline medium
                result = .baselineFallback
            }

        case .keyUp:
            // Key release sound matches the tier of the key-down strike, or soft-medium
            tierLock.lock()
            let correspondingTier = activeKeyTiers.removeValue(forKey: event.keyCode) ?? .medium
            tierLock.unlock()

            result = VelocityResult(
                forceTier: correspondingTier,
                rawMagnitude: 0.3,
                normalizedForce: 0.35,
                crossfadeWeights: .single(correspondingTier)
            )
        }

        // 1. Deliver to Audio Engine callback
        onVelocityResolved?(event, result)

        // 2. Deliver to Labs features (AutoCAPS, Vine Boom, Metrics)
        LabsManager.shared.processKeystroke(event: event, velocity: result)
    }
}
