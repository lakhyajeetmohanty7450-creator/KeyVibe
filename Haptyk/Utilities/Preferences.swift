//
//  Preferences.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Type-safe, reactive `UserDefaults` wrapper using a custom
//  `@Preference` property wrapper.  Every persisted setting is defined
//  once — with its key, default value, and a Combine publisher — so the
//  rest of the app never touches raw `UserDefaults` directly.
//

import Combine
import Foundation

// MARK: - Preference Property Wrapper

/// A property wrapper that reads and writes a single `UserDefaults` key,
/// automatically namespaced with the `"com.haptyk."` prefix.
///
/// The wrapper also vends a Combine `Publisher` so SwiftUI views and
/// reactive pipelines can observe changes:
///
/// ```swift
/// @Preference(key: "masterVolume", defaultValue: 0.8)
/// static var masterVolume: Float
///
/// // Subscribe:
/// Preferences.$masterVolume.sink { newVolume in … }
/// ```
///
/// - Important: `Value` must conform to a type natively supported by
///   `UserDefaults` (`Bool`, `Int`, `Float`, `Double`, `String`, `Data`,
///   `Date`, `URL`, arrays/dicts of the above).
@propertyWrapper
struct Preference<Value> {

    // MARK: Properties

    /// The fully-qualified defaults key (e.g. `"com.haptyk.masterVolume"`).
    let key: String

    /// The value returned when the key has never been written.
    let defaultValue: Value

    /// The `UserDefaults` suite this wrapper targets.
    private let defaults: UserDefaults

    /// A `CurrentValueSubject` that mirrors the stored value so that
    /// Combine subscribers get the initial value immediately and every
    /// subsequent change.
    private let subject: CurrentValueSubject<Value, Never>

    // MARK: Initialisation

    /// - Parameters:
    ///   - key: Short key name (without prefix). The wrapper prepends
    ///     `"com.haptyk."` automatically.
    ///   - defaultValue: Fallback when the key is absent.
    ///   - defaults: Defaults suite to use. Almost always `.standard`.
    init(
        key: String,
        defaultValue: Value,
        defaults: UserDefaults = .standard
    ) {
        let fullKey = "com.haptyk.\(key)"
        self.key = fullKey
        self.defaultValue = defaultValue
        self.defaults = defaults

        // Seed the subject with the current persisted value (or the default).
        let initial = defaults.object(forKey: fullKey) as? Value ?? defaultValue
        self.subject = CurrentValueSubject<Value, Never>(initial)
    }

    // MARK: Wrapped Value

    var wrappedValue: Value {
        get {
            defaults.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            defaults.set(newValue, forKey: key)
            subject.send(newValue)
        }
    }

    // MARK: Projected Value (Combine Publisher)

    /// A Combine publisher that emits the current value on subscription
    /// and every time the preference changes via this wrapper.
    ///
    /// Access with the `$` prefix: `Preferences.$masterVolume`.
    var projectedValue: AnyPublisher<Value, Never> {
        subject.eraseToAnyPublisher()
    }
}

// MARK: - Preferences

/// Centralised, type-safe access to every user preference.
///
/// All properties are `static` so usage is simply:
/// ```swift
/// let vol = Preferences.masterVolume
/// Preferences.masterVolume = 0.6
/// ```
///
/// Combine observation:
/// ```swift
/// Preferences.$isMuted.sink { muted in … }
/// ```
struct Preferences {

    // MARK: - Sound Pack

    /// The identifier of the currently-selected sound pack
    /// (e.g. `"cherry-mx-blue"`, `"topre-45g"`).
    @Preference(key: "selectedSoundPack", defaultValue: "cherry-mx-blue")
    static var selectedSoundPack: String

    // MARK: - Audio

    /// Master output volume in the range `[0.0, 1.0]`.
    @Preference(key: "masterVolume", defaultValue: 0.8)
    static var masterVolume: Float

    /// Accelerometer sensitivity multiplier in `[0.0, 1.0]`.
    /// Higher values lower the force thresholds, making the keyboard
    /// sound "harder" at lighter touches.
    @Preference(key: "sensitivity", defaultValue: 0.5)
    static var sensitivity: Float

    /// When `true` all audio output is muted without tearing down the
    /// engine (allows instant un-mute).
    @Preference(key: "isMuted", defaultValue: false)
    static var isMuted: Bool

    // MARK: - Feature Flags

    /// When `true` the "auto-caps lock" feature is enabled, which
    /// switches to an aggressive sound pack while Caps Lock is active.
    @Preference(key: "autoCapsEnabled", defaultValue: false)
    static var autoCapsEnabled: Bool

    /// When `true` the "Vine boom" Easter-egg sound is enabled on
    /// certain key combos. 🤫
    @Preference(key: "vineBoomEnabled", defaultValue: false)
    static var vineBoomEnabled: Bool

    /// When `true` anonymous typing metrics (WPM, daily key count) are
    /// collected locally for the stats dashboard.
    @Preference(key: "typingMetricsEnabled", defaultValue: true)
    static var typingMetricsEnabled: Bool

    // MARK: - Onboarding

    /// `true` on the very first launch; set to `false` after the
    /// onboarding flow completes.
    @Preference(key: "isFirstLaunch", defaultValue: true)
    static var isFirstLaunch: Bool

    /// `true` once the user has finished every onboarding step.
    @Preference(key: "hasCompletedOnboarding", defaultValue: false)
    static var hasCompletedOnboarding: Bool

    // MARK: - Default Registration

    /// Registers fallback values with `UserDefaults.standard` so that
    /// KVO and Cocoa Bindings see meaningful defaults even before the
    /// property wrapper has been accessed.
    ///
    /// **Call once** in `applicationDidFinishLaunching(_:)`.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            "com.haptyk.selectedSoundPack": "cherry-mx-blue",
            "com.haptyk.masterVolume": Float(0.8),
            "com.haptyk.sensitivity": Float(0.5),
            "com.haptyk.isMuted": false,
            "com.haptyk.autoCapsEnabled": false,
            "com.haptyk.vineBoomEnabled": false,
            "com.haptyk.typingMetricsEnabled": true,
            "com.haptyk.isFirstLaunch": true,
            "com.haptyk.hasCompletedOnboarding": false,
            "haptyk.isProUser": true,
        ])
    }
}
