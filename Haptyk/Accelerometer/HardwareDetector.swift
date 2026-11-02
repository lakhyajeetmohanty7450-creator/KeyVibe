//
//  HardwareDetector.swift
//  Haptyk
//
//  Detects hardware capabilities and compatibility for the Haptyk
//  velocity-sensitive keyboard sound engine. Checks for:
//  - Mac model identifier and Apple Silicon generation
//  - Internal accelerometer (SPU motion sensor) presence
//  - Lid open/closed (clamshell) state
//  - External keyboard connection
//
//  Compatibility matrix (from Haptyk spec):
//  ┌──────────────────────────┬────────────┐
//  │ Model                    │ Support    │
//  ├──────────────────────────┼────────────┤
//  │ M2+ MacBook Air/Pro      │ Full       │
//  │ M1 MacBook Air/Pro 13"   │ Unsupported│
//  │ Intel MacBooks            │ Unsupported│
//  │ iMac / Mac mini / Studio │ Unsupported│
//  │ Mac Pro / Mac Pro Tower   │ Unsupported│
//  └──────────────────────────┴────────────┘
//
//  Created for the Haptyk project.
//  Copyright © 2024 Haptyk. All rights reserved.
//

import Foundation
import IOKit
import os.log

// MARK: - HardwareSupport

/// Represents the hardware compatibility status for the Haptyk sound engine.
///
/// The engine requires an internal MacBook accelerometer (SPU motion sensor)
/// to measure keystroke force. Desktop Macs and older MacBooks lack this sensor.
enum HardwareSupport: Equatable, CustomStringConvertible {

    /// Accelerometer is present and functional. Full velocity-sensitive audio.
    case fullSupport

    /// This Mac model does not have a compatible accelerometer.
    /// Includes M1 MacBook Air/Pro 13", all Intel Macs, and all desktops.
    case unsupportedModel

    /// The Mac has an accelerometer but the lid is closed (clamshell mode).
    /// The accelerometer may not return meaningful keystroke data when typing
    /// on an external keyboard with the lid closed.
    case clamshellMode

    /// An external keyboard is detected. The accelerometer is available, but
    /// keystrokes on an external keyboard won't propagate vibrations to the
    /// MacBook chassis. This is informational — the engine still functions
    /// for the built-in keyboard.
    case externalKeyboard

    var description: String {
        switch self {
        case .fullSupport:
            return "Full accelerometer support available"
        case .unsupportedModel:
            return "Unsupported Mac model — no compatible accelerometer"
        case .clamshellMode:
            return "Accelerometer available but lid is closed (clamshell mode)"
        case .externalKeyboard:
            return "External keyboard detected — accelerometer may not sense external keystrokes"
        }
    }
}

// MARK: - HardwareDetector

/// Static utility for probing the current Mac's hardware capabilities
/// relevant to the Haptyk velocity-sensing engine.
///
/// All methods are safe to call from any thread. They perform synchronous
/// IOKit registry lookups and `sysctl` calls that typically complete in
/// microseconds.
struct HardwareDetector {

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "com.haptyk.app",
        category: "HardwareDetector"
    )

    // MARK: - Primary Check

    /// Performs a comprehensive hardware compatibility check.
    ///
    /// Evaluation order:
    /// 1. Check if the Mac model is in the supported set (M2+ MacBook).
    /// 2. Probe IOKit for accelerometer service presence.
    /// 3. Check lid (clamshell) state.
    /// 4. Check for external keyboard (informational).
    ///
    /// - Returns: The most relevant `HardwareSupport` case.
    static func checkCompatibility() -> HardwareSupport {
        let model = getMacModel()
        logger.info("Detected Mac model: \(model, privacy: .public)")

        // Step 1: Model compatibility gate.
        guard isModelSupported(model) else {
            logger.warning("Model \(model, privacy: .public) is not in the supported compatibility list")
            return .unsupportedModel
        }

        // Step 2: Verify accelerometer presence in IOKit registry.
        guard hasAccelerometer() else {
            logger.warning("No accelerometer service found in IOKit registry for model \(model, privacy: .public)")
            return .unsupportedModel
        }

        // Step 3: Clamshell / lid closed check.
        if isLidClosed() {
            logger.info("Lid is closed — clamshell mode detected")
            return .clamshellMode
        }

        // Step 4: External keyboard (informational, does not block).
        if isExternalKeyboardConnected() {
            logger.info("External keyboard detected — accelerometer may not capture external keystrokes")
            return .externalKeyboard
        }

        logger.info("Full hardware support confirmed for model \(model, privacy: .public)")
        return .fullSupport
    }

    // MARK: - Mac Model

    /// Returns the Mac model identifier string, e.g. `"MacBookPro18,1"`.
    ///
    /// Uses `sysctlbyname("hw.model")` which is available on all macOS versions.
    /// Falls back to `"Unknown"` if the sysctl call fails.
    static func getMacModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            logger.error("sysctlbyname('hw.model') failed to return size")
            return "Unknown"
        }

        var model = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &model, &size, nil, 0) == 0 else {
            logger.error("sysctlbyname('hw.model') failed to read value")
            return "Unknown"
        }

        return String(cString: model)
    }

    // MARK: - Apple Silicon Check

    /// Returns `true` if the current Mac uses Apple Silicon (arm64).
    ///
    /// Checks `hw.optional.arm64` sysctl. This is more reliable than
    /// compile-time `#if arch(arm64)` for runtime detection.
    static func isAppleSilicon() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)

        if result == 0 {
            return value == 1
        }

        // Fallback: check architecture at compile time.
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Accelerometer Presence

    /// Probes the IOKit registry for an accelerometer (SPU motion sensor) service.
    ///
    /// Searches for IOHIDSensor services matching the accelerometer usage page.
    /// This does not open the device — it only checks for service existence.
    ///
    /// - Returns: `true` if an accelerometer service was found.
    static func hasAccelerometer() -> Bool {
        // Strategy: Search for the Apple SPU motion sensor in IOKit HID.
        // The sensor typically registers under the AppleSPUHIDDevice or
        // similar class with a primary usage of accelerometer.

        let matchingDict = IOServiceMatching("AppleSPUHIDDevice") as NSMutableDictionary

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matchingDict,
            &iterator
        )

        guard result == KERN_SUCCESS else {
            // Try alternative class names used on different macOS versions.
            return hasAccelerometerFallback()
        }

        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            // No AppleSPUHIDDevice found — try fallback.
            return hasAccelerometerFallback()
        }

        IOObjectRelease(service)
        logger.debug("Accelerometer found via AppleSPUHIDDevice")
        return true
    }

    /// Fallback accelerometer detection using broader IOKit matching.
    ///
    /// Searches for any HID sensor service with accelerometer usage,
    /// accommodating variations across macOS and hardware revisions.
    private static func hasAccelerometerFallback() -> Bool {
        // Try matching by IOHIDSensor or AppleHIDMotionSensor class names
        // used on various Apple Silicon MacBooks.
        let classNames = [
            "AppleHIDMotionSensor",
            "IOHIDEventDriver",
            "AppleSPUHIDDriver"
        ]

        for className in classNames {
            guard let matchingDict = IOServiceMatching(className) as? NSMutableDictionary else {
                continue
            }

            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(
                kIOMainPortDefault,
                matchingDict as CFDictionary,
                &iterator
            )

            guard result == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            let service = IOIteratorNext(iterator)
            if service != 0 {
                IOObjectRelease(service)
                logger.debug("Accelerometer found via fallback class: \(className, privacy: .public)")
                return true
            }
        }

        // Last resort: check for the SMC motion sensor (older approach).
        return hasSMCMotionSensor()
    }

    /// Checks for the legacy SMC-based Sudden Motion Sensor (SMS).
    ///
    /// The SMS was used on Intel MacBooks. While Haptyk doesn't support
    /// Intel, this provides diagnostic information in logs.
    private static func hasSMCMotionSensor() -> Bool {
        guard let matchingDict = IOServiceMatching("SMCMotionSensor") as? NSMutableDictionary else {
            return false
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matchingDict as CFDictionary,
            &iterator
        )

        guard result == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        if service != 0 {
            IOObjectRelease(service)
            logger.debug("Legacy SMCMotionSensor found (Intel) — not supported by Haptyk")
            return true // Sensor exists, but model check will gate it out.
        }

        return false
    }

    // MARK: - Lid / Clamshell State

    /// Returns `true` if the MacBook lid appears to be closed (clamshell mode).
    ///
    /// Checks the `AppleClamshellState` property in the IOKit `AppleClamshellState`
    /// registry entry. When the lid is closed and an external display is connected,
    /// macOS enters clamshell mode.
    ///
    /// - Note: If the property is unavailable (e.g., on a desktop Mac),
    ///   returns `false`.
    static func isLidClosed() -> Bool {
        guard let matchingDict = IOServiceMatching("IOPMrootDomain") as? NSMutableDictionary else {
            return false
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matchingDict as CFDictionary,
            &iterator
        )

        guard result == KERN_SUCCESS else {
            logger.debug("Failed to query IOPMrootDomain for clamshell state")
            return false
        }

        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        // Read the "AppleClamshellState" property.
        guard let clamshellState = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            logger.debug("AppleClamshellState property not found — assuming lid open")
            return false
        }

        if let boolValue = clamshellState as? Bool {
            return boolValue
        }

        // Some systems return it as a number (0 or 1).
        if let numValue = clamshellState as? NSNumber {
            return numValue.boolValue
        }

        return false
    }

    // MARK: - External Keyboard Detection

    /// Returns `true` if at least one external keyboard is connected.
    ///
    /// Searches the IOKit HID registry for keyboard devices that are not
    /// the built-in keyboard. Filters by transport type — built-in keyboards
    /// use SPI/internal transport, while external ones use USB or Bluetooth.
    static func isExternalKeyboardConnected() -> Bool {
        let matchingDict = NSMutableDictionary()
        // HID Usage Page 1 (Generic Desktop), Usage 6 (Keyboard)
        matchingDict[kIOHIDDeviceUsagePageKey] = 0x01 // kHIDPage_GenericDesktop
        matchingDict[kIOHIDDeviceUsageKey] = 0x06     // kHIDUsage_GD_Keyboard

        let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(hidManager, matchingDict)
        IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let deviceSet = IOHIDManagerCopyDevices(hidManager) as? Set<IOHIDDevice> else {
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
            return false
        }

        defer {
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        for device in deviceSet {
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString)
            let transportStr = transport as? String ?? ""

            // Built-in keyboards typically report "SPI" or "iBus" transport.
            // External keyboards use "USB", "Bluetooth", "BluetoothLowEnergy".
            let builtInTransports: Set<String> = ["SPI", "iBus", "Fifo"]

            if !builtInTransports.contains(transportStr) && !transportStr.isEmpty {
                logger.debug("External keyboard detected via transport: \(transportStr, privacy: .public)")
                return true
            }

            // Also check the "Built-In" property directly.
            if let builtIn = IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString) as? Bool,
               !builtIn {
                logger.debug("External keyboard detected via Built-In=false property")
                return true
            }
        }

        return false
    }

    // MARK: - Model Compatibility Table

    /// Determines if the given Mac model identifier is in the supported set.
    ///
    /// **Supported**: M2 and later MacBook Air and MacBook Pro models:
    /// - MacBookAir10,x (M2 Air) and later
    /// - MacBookPro17,x (M2 Pro/Max 14"/16") and later
    /// - Mac15,x series (M3 generation identifiers)
    /// - Mac16,x series (M4 generation identifiers)
    ///
    /// **Unsupported**: M1 models (MacBookAir10,1, MacBookPro17,1, MacBookPro18,x
    /// for M1 Pro/Max), all Intel, all desktops.
    ///
    /// - Parameter model: The `hw.model` string (e.g., `"Mac14,2"`).
    /// - Returns: `true` if the model has a compatible accelerometer.
    private static func isModelSupported(_ model: String) -> Bool {
        // Must be Apple Silicon.
        guard isAppleSilicon() else {
            logger.info("Intel architecture detected — unsupported")
            return false
        }

        // Must be a portable Mac (MacBook of some kind).
        let isPortable = model.hasPrefix("MacBook") || isPortableMacIdentifier(model)
        guard isPortable else {
            logger.info("Non-portable Mac detected — unsupported (model: \(model, privacy: .public))")
            return false
        }

        // M1 MacBook models are excluded — they lack the SPU motion sensor
        // or have insufficient sensitivity for keystroke velocity detection.
        if isM1MacBookModel(model) {
            logger.info("M1 MacBook model detected — unsupported (model: \(model, privacy: .public))")
            return false
        }

        return true
    }

    /// Checks if the model identifier corresponds to an M1-generation MacBook.
    ///
    /// M1 MacBook identifiers:
    /// - `MacBookAir10,1` — M1 MacBook Air (2020)
    /// - `MacBookPro17,1` — M1 MacBook Pro 13" (2020)
    /// - `MacBookPro18,1` — M1 Pro MacBook Pro 16" (2021)
    /// - `MacBookPro18,2` — M1 Max MacBook Pro 16" (2021)
    /// - `MacBookPro18,3` — M1 Pro MacBook Pro 14" (2021)
    /// - `MacBookPro18,4` — M1 Max MacBook Pro 14" (2021)
    private static func isM1MacBookModel(_ model: String) -> Bool {
        let m1Models: Set<String> = [
            "MacBookAir10,1",
            "MacBookPro17,1",
            "MacBookPro18,1",
            "MacBookPro18,2",
            "MacBookPro18,3",
            "MacBookPro18,4"
        ]
        return m1Models.contains(model)
    }

    /// Checks if a `MacXX,Y` style identifier is a portable Mac.
    ///
    /// Starting with the M2 generation, Apple began using `Mac14,x` and later
    /// `Mac15,x`, `Mac16,x` identifiers for all Mac models. We need to
    /// distinguish portable (MacBook) from desktop (iMac, Mac mini, etc.).
    ///
    /// This uses a known mapping. Models not in any list are conservatively
    /// treated as potentially portable and deferred to the accelerometer check.
    private static func isPortableMacIdentifier(_ model: String) -> Bool {
        // Known portable Mac identifiers (M2+ generation new naming scheme).
        let portablePrefixes: Set<String> = [
            // M2 MacBook Air
            "Mac14,2",   // MacBook Air 13" M2
            "Mac14,15",  // MacBook Air 15" M2
            // M2 MacBook Pro
            "Mac14,5",   // MacBook Pro 14" M2 Max
            "Mac14,6",   // MacBook Pro 16" M2 Max
            "Mac14,7",   // MacBook Pro 13" M2
            "Mac14,9",   // MacBook Pro 14" M2 Pro
            "Mac14,10",  // MacBook Pro 16" M2 Pro
            // M3 MacBook Air
            "Mac15,12",  // MacBook Air 13" M3
            "Mac15,13",  // MacBook Air 15" M3
            // M3 MacBook Pro
            "Mac15,3",   // MacBook Pro 14" M3 base
            "Mac15,6",   // MacBook Pro 14" M3 Pro
            "Mac15,7",   // MacBook Pro 16" M3 Pro
            "Mac15,8",   // MacBook Pro 14" M3 Max
            "Mac15,9",   // MacBook Pro 16" M3 Max
            "Mac15,10",  // MacBook Pro 14" M3 Pro
            "Mac15,11",  // MacBook Pro 16" M3 Pro
            // M4 MacBook Air
            "Mac16,12",  // MacBook Air 13" M4
            "Mac16,13",  // MacBook Air 15" M4
            // M4 MacBook Pro
            "Mac16,1",   // MacBook Pro 14" M4
            "Mac16,5",   // MacBook Pro 14" M4 Pro
            "Mac16,6",   // MacBook Pro 14" M4 Max
            "Mac16,7",   // MacBook Pro 16" M4 Pro
            "Mac16,8",   // MacBook Pro 16" M4 Max
            // M5+ MacBook Models
            "Mac17,1", "Mac17,2", "Mac17,3", "Mac17,4", "Mac17,5", "Mac17,6", "Mac17,7", "Mac17,8"
        ]

        // Known desktop Mac identifiers (explicitly excluded).
        let desktopModels: Set<String> = [
            // iMac
            "Mac15,4", "Mac15,5",
            // Mac mini
            "Mac14,3", "Mac14,12", "Mac16,10", "Mac16,11",
            // Mac Studio
            "Mac14,13", "Mac14,14", "Mac15,14", "Mac15,15",
            // Mac Pro
            "Mac14,8", "Mac15,2",
        ]

        if portablePrefixes.contains(model) {
            return true
        }

        if desktopModels.contains(model) {
            return false
        }

        // Unknown model — check if it starts with "MacBook" (legacy naming)
        // or conservatively return true to let the accelerometer probe decide.
        if model.hasPrefix("MacBook") {
            return true
        }

        // For truly unknown `MacXX,Y` identifiers from future generations,
        // allow the accelerometer presence check to be the final gate.
        logger.info("Unknown model identifier \(model, privacy: .public) — deferring to accelerometer probe")
        return true
    }
}

// MARK: - HardwareSupport Compatibility Extensions

extension HardwareSupport {
    /// Whether the Mac is compatible with Haptyk.
    var isCompatible: Bool {
        switch self {
        case .fullSupport, .clamshellMode, .externalKeyboard:
            return true
        case .unsupportedModel:
            return false
        }
    }

    /// The current Mac's model identifier string.
    var modelIdentifier: String {
        return HardwareDetector.getMacModel()
    }

    /// Explanatory reason if incompatible or degraded.
    var reason: String? {
        switch self {
        case .unsupportedModel:
            return "This Mac model does not have a compatible internal accelerometer or is an unsupported architecture."
        case .clamshellMode:
            return "The MacBook lid is closed. Accelerometer data cannot be measured from an external keyboard."
        case .externalKeyboard:
            return "An external keyboard is being used. Accelerometer data cannot be measured."
        case .fullSupport:
            return nil
        }
    }
}

