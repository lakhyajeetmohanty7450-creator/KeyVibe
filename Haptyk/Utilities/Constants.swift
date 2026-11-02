//
//  Constants.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Central, compile-time constants organised by subsystem.
//  Every numeric literal in the codebase should trace back to a value
//  defined here so that tuning is easy and auditable.
//

import Foundation

// MARK: - Constants

/// Application-wide constants grouped by subsystem.
public enum Constants {

    // MARK: - Accelerometer

    /// Parameters for the IOKit HID accelerometer stream.
    public enum Accelerometer {
        /// Target sample rate in Hz.
        /// Apple Silicon MacBooks expose the IMU at up to ~1600 Hz;
        /// we cap at 1 kHz to balance resolution and CPU cost.
        public static let sampleRate: Double = 1000.0

        /// Lock-free ring buffer capacity in samples.
        /// Must be a power of two for efficient index masking.
        /// 2048 samples ≈ 2 s of history at 1 kHz.
        public static let bufferSize: Int = 2048

        /// Correlation window in milliseconds used to find the
        /// acceleration peak nearest to a keystroke timestamp.
        public static let correlationWindowMs: Double = 10.0
    }

    // MARK: - Audio

    /// Parameters for the AVAudioEngine render pipeline.
    public enum Audio {
        /// Render sample rate in Hz (CD quality).
        public static let sampleRate: Double = 44100.0

        /// Frames per audio buffer. 128 frames at 44.1 kHz ≈ 2.9 ms
        /// round-trip latency — well below the perceptual threshold.
        public static let bufferFrames: Int = 128

        /// Maximum number of overlapping voices (polyphony).
        /// Beyond this limit the oldest voice is stolen.
        public static let maxSimultaneousVoices: Int = 8

        /// Seconds of keyboard inactivity before the audio engine is
        /// suspended to save power. The engine resumes transparently
        /// on the next keystroke.
        public static let idleTimeoutSeconds: Double = 180.0
    }

    // MARK: - Force Tiers

    /// Thresholds (in *g*) that partition raw accelerometer magnitude
    /// into four perceptual tiers.  Values between adjacent thresholds
    /// trigger a linear crossfade between the two neighbouring samples
    /// for smooth sonic transitions.
    public enum ForceTiers {
        /// Upper bound for the **Soft** tier.
        public static let softThreshold: Double = 0.15

        /// Upper bound for the **Medium** tier.
        public static let mediumThreshold: Double = 0.45

        /// Upper bound for the **Hard** tier.
        public static let hardThreshold: Double = 0.75

        /// Lower bound for the **Slam** tier.
        /// Values ≥ this are clamped to maximum intensity.
        public static let slamThreshold: Double = 1.2
    }

    // MARK: - Trial / Licensing

    /// Free-trial and pricing parameters.
    public enum Trial {
        /// Duration of the free trial in calendar days.
        public static let durationDays: Int = 3

        /// One-time purchase price for Haptyk Pro (USD).
        public static let proPriceUSD: Double = 8.0
    }

    // MARK: - App Identity

    /// Application metadata that must stay in sync with Info.plist.
    public enum App {
        /// The CFBundleIdentifier used for UserDefaults suites,
        /// OSLog subsystems, and keychain access groups.
        public static let bundleIdentifier = "com.keyvibe.app"

        /// Human-readable product name.
        public static let appName = "KeyVibe"

        /// Semantic version string (also in Info.plist).
        public static let version = "1.0.0"
    }
}
