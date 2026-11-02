//
//  AppDelegate.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  The application delegate owns every subsystem and orchestrates the full
//  lifecycle: hardware checks → permission requests → sensor + keyboard
//  monitoring → audio engine → menu bar UI → licensing.
//

import AppKit
import ApplicationServices   // AXIsProcessTrusted
import os.log

// MARK: - AppDelegate

/// Central orchestrator for the Haptyk application.
///
/// `AppDelegate` is responsible for:
/// 1. Verifying hardware compatibility (Apple Silicon with built-in accelerometer).
/// 2. Requesting Accessibility permissions (required for the global `CGEventTap`).
/// 3. Initialising and holding strong references to every subsystem manager.
/// 4. Tearing everything down cleanly on termination.
///
/// All subsystems are initialised **lazily** inside
/// `applicationDidFinishLaunching(_:)` and torn down in
/// `applicationWillTerminate(_:)`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Subsystem References
    // Strong references keep each manager alive for the app's lifetime.

    /// Manages the 1 kHz accelerometer data stream from the built-in IMU.
    private var accelerometerManager: AccelerometerManager?

    /// Installs a global `CGEventTap` to capture every key-down / key-up event.
    private var keyboardMonitor: KeyboardMonitor?

    /// Correlates accelerometer peaks with keyboard events to classify force.
    private var velocityEngine: VelocityEngine?

    /// Owns the `AVAudioEngine` graph and renders sound samples in real time.
    private var audioEngine: AudioEngine?

    /// Creates and manages the `NSStatusItem` in the system menu bar.
    private var menuBarController: MenuBarController?

    /// Handles trial period validation and Pro license verification.
    private var licenseManager: LicenseManager?

    /// Periodic timer to detect when user grants Accessibility permission in System Settings.
    private var permissionPollTimer: Timer?

    /// Local event monitor to enable typing sounds in Haptyk even without Accessibility.
    private var localEventMonitor: Any?

    // MARK: - Private Helpers

    /// Dedicated logger for lifecycle events.
    private let log = HaptykLogger(category: .ui)

    // MARK: - NSApplicationDelegate — Launch

    /// Called once the application has finished launching.
    ///
    /// The method runs through a strict initialisation sequence:
    /// 1. Register user-preference defaults.
    /// 2. Hardware compatibility check (exits on failure).
    /// 3. Accessibility permission check (prompts on failure).
    /// 4. Start accelerometer stream.
    /// 5. Start keyboard event tap.
    /// 6. Initialise velocity engine.
    /// 7. Initialise audio engine.
    /// 8. Initialise menu bar UI.
    /// 9. Initialise licensing.
    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("KeyVibe \(Constants.App.version) launching…")

        // -----------------------------------------------------------------
        // Step 0 — Register default preferences
        // -----------------------------------------------------------------
        Preferences.registerDefaults()

        // -----------------------------------------------------------------
        // Step 1 — Hardware Compatibility Check
        // -----------------------------------------------------------------
        let hwSupport = HardwareDetector.checkCompatibility()
        if !hwSupport.isCompatible {
            log.warning("Hardware acceleration degraded: \(hwSupport.description). Running in baseline medium-force fallback mode.")
        } else {
            log.info("Hardware compatibility confirmed: \(hwSupport.description)")
        }

        // -----------------------------------------------------------------
        // Step 2 — Accessibility Permission
        // -----------------------------------------------------------------
        requestAccessibilityPermissionIfNeeded()

        // -----------------------------------------------------------------
        // Step 3 — Accelerometer
        // -----------------------------------------------------------------
        log.info("Starting accelerometer stream…")
        accelerometerManager = AccelerometerManager()
        accelerometerManager?.start()

        // -----------------------------------------------------------------
        // Step 4 — Keyboard Monitor & Accessibility Auto-Reconnect
        // -----------------------------------------------------------------
        log.info("Installing keyboard event tap…")
        keyboardMonitor = KeyboardMonitor()
        checkAndStartKeyboardMonitor()

        // Poll every 1s so as soon as user enables toggle in System Settings, it activates
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAndStartKeyboardMonitor()
        }

        // Local event monitor: guarantees typing sounds work inside Haptyk without any permissions
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            if self?.keyboardMonitor?.isRunning != true {
                let keyCode = Int64(event.keyCode)
                let eventType: KeyEventType = (event.type == .keyDown) ? .keyDown : .keyUp
                let category = KeyMapper.category(for: keyCode)
                let keyEvent = KeyEvent(
                    keyCode: keyCode,
                    eventType: eventType,
                    timestamp: mach_absolute_time(),
                    keyCategory: category,
                    isRepeat: event.isARepeat
                )
                self?.velocityEngine?.processKeyEvent(keyEvent)
            }
            return event
        }

        // -----------------------------------------------------------------
        // Step 5 — Velocity Engine
        // -----------------------------------------------------------------
        log.info("Initialising velocity engine…")
        if let accel = accelerometerManager, let kbd = keyboardMonitor {
            velocityEngine = VelocityEngine(
                accelerometerManager: accel,
                keyboardMonitor: kbd
            )
        }

        // -----------------------------------------------------------------
        // Step 6 — Audio Engine & Sound Pack
        // -----------------------------------------------------------------
        log.info("Starting audio engine…")
        let engine = AudioEngine.shared
        audioEngine = engine
        engine.start()

        if let pack = SoundPackManager.shared.selectedPack {
            SampleBank.shared.loadPack(pack)
        }

        // Wire Velocity Engine output to Audio Engine renderer
        velocityEngine?.onVelocityResolved = { [weak self] event, velocity in
            self?.audioEngine?.playKeySound(for: event, velocity: velocity)
        }

        // -----------------------------------------------------------------
        // Step 7 — Menu Bar
        // -----------------------------------------------------------------
        log.info("Creating menu bar item…")
        menuBarController = MenuBarController()
        menuBarController?.setup()

        // -----------------------------------------------------------------
        // Step 8 — Licensing
        // -----------------------------------------------------------------
        log.info("Checking license status…")
        licenseManager = LicenseManager()
        licenseManager?.validateOnLaunch()

        log.info("Launch sequence complete ✓")

        // Surface the menu bar popover so the user sees the active app immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.menuBarController?.showPopover()
        }
    }

    // MARK: - NSApplicationDelegate — Termination

    /// Tears down every subsystem in reverse order.
    func applicationWillTerminate(_ notification: Notification) {
        log.info("Haptyk shutting down…")

        permissionPollTimer?.invalidate()
        permissionPollTimer = nil

        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }

        licenseManager = nil

        menuBarController?.tearDown()
        menuBarController = nil

        audioEngine?.stop()
        audioEngine = nil

        velocityEngine = nil

        keyboardMonitor?.stop()
        keyboardMonitor = nil

        accelerometerManager?.stop()
        accelerometerManager = nil

        log.info("Shutdown complete.")
    }

    // MARK: - Accessibility Monitor Polling

    private func checkAndStartKeyboardMonitor() {
        guard AXIsProcessTrusted() else { return }
        if keyboardMonitor?.isRunning != true {
            do {
                try keyboardMonitor?.start()
                log.info("Accessibility granted! Global KeyboardMonitor started successfully.")
            } catch {
                log.warning("KeyboardMonitor start failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Hardware Compatibility

    /// Runs `HardwareDetector.checkCompatibility()` and shows a blocking
    /// alert when the current machine is not supported.
    ///
    /// - Returns: `true` if the hardware is compatible.
    private func performHardwareCheck() -> Bool {
        let result = HardwareDetector.checkCompatibility()

        guard result.isCompatible else {
            log.error("Incompatible hardware detected: \(result.modelIdentifier)")

            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Unsupported Mac"
            alert.informativeText = """
                Haptyk requires an Apple Silicon MacBook with a built-in \
                accelerometer.

                Detected model: \(result.modelIdentifier)
                Reason: \(result.reason ?? "Unknown")

                The application will now quit.
                """
            alert.addButton(withTitle: "Quit")
            alert.runModal()

            return false
        }

        log.info("Hardware OK — \(result.modelIdentifier)")
        return true
    }

    // MARK: - Accessibility Permission

    /// Checks whether the process is trusted for Accessibility and, if not,
    /// requests permission natively without blocking the main run loop.
    private func requestAccessibilityPermissionIfNeeded() {
        if !AXIsProcessTrusted() {
            log.warning("Accessibility permission not yet granted — prompting system dialog.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                let promptOptions: NSDictionary = [
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
                ]
                _ = AXIsProcessTrustedWithOptions(promptOptions)
            }
        } else {
            log.info("Accessibility permission already granted.")
        }
    }
}
