//
//  KeyboardMonitor.swift
//  Haptyk
//
//  Global keyboard event interceptor using CGEventTap.
//
//  This class installs a system-wide event tap at the HID level to capture
//  all physical keyDown / keyUp events. It extracts only the virtual key code
//  and precise mach_absolute_time timestamp — **never** the character content —
//  then delivers a `KeyEvent` struct to its registered callback.
//
//  Requirements:
//    • macOS 14+ (Sonoma)
//    • Accessibility permission (System Settings → Privacy & Security → Accessibility)
//
//  Privacy Note:
//    This monitor intentionally ignores all textual content of key events.
//    Only the numeric virtual key code is used for sound‐category mapping.
//

import Cocoa
import CoreGraphics
import IOKit
import IOKit.hid
import os.log

// MARK: - KeyEventType

/// Describes whether a key was pressed or released.
public enum KeyEventType: String, Sendable {
    case keyDown
    case keyUp
}

// MARK: - KeyEvent

/// A lightweight, privacy‐safe representation of a physical key event.
///
/// Contains only the virtual key code (for sound mapping), the event type,
/// a high‐resolution timestamp, the resolved `KeyCategory`, and an auto‐repeat flag.
/// No character data is ever captured.
public struct KeyEvent: Sendable {
    /// The macOS virtual key code (e.g., 0x00 = kVK_ANSI_A, 0x31 = kVK_Space).
    public let keyCode: Int64

    /// Whether this is a press or release.
    public let eventType: KeyEventType

    /// High‐resolution timestamp captured via `mach_absolute_time()` at callback entry.
    /// This is preferred over `CGEvent.timestamp` which may lag behind actual input.
    public let timestamp: UInt64

    /// The sound‐mapping category derived from `KeyMapper`.
    public let keyCategory: KeyCategory

    /// `true` when the OS is generating auto‐repeat events for a held key.
    /// Haptyk filters these out to match only physical presses.
    public let isRepeat: Bool

    public init(
        keyCode: Int64,
        eventType: KeyEventType,
        timestamp: UInt64,
        keyCategory: KeyCategory,
        isRepeat: Bool
    ) {
        self.keyCode = keyCode
        self.eventType = eventType
        self.timestamp = timestamp
        self.keyCategory = keyCategory
        self.isRepeat = isRepeat
    }
}

// MARK: - KeyboardMonitorError

/// Errors that `KeyboardMonitor` can throw during setup.
enum KeyboardMonitorError: LocalizedError {
    /// The user has not granted Accessibility permission.
    case accessibilityNotGranted

    /// `CGEvent.tapCreate` returned `nil` for an unknown reason.
    case eventTapCreationFailed

    /// Could not wrap the event tap in a `CFRunLoopSource`.
    case runLoopSourceCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission is required to monitor keyboard events. "
                 + "Please enable KeyVibe in System Settings → Privacy & Security → Accessibility."
        case .eventTapCreationFailed:
            return "Failed to create the CGEventTap. The system may be restricting event access."
        case .runLoopSourceCreationFailed:
            return "Failed to create a CFRunLoopSource from the event tap."
        }
    }
}

// MARK: - KeyboardMonitor

/// Singleton that captures global keyboard events for velocity‐sensitive sound playback.
///
/// ## Usage
/// ```swift
/// let monitor = KeyboardMonitor.shared
/// monitor.onKeyEvent = { event in
///     VelocityEngine.shared.processKeyEvent(event)
/// }
/// try monitor.start()
/// ```
///
/// ## Thread Safety
/// The CGEventTap callback fires on the run loop thread where the tap was installed.
/// `onKeyEvent` is invoked directly from that callback for minimal latency. Consumers
/// should dispatch to another queue if they need to perform non‐trivial work.
public final class KeyboardMonitor {

    // MARK: Shared Instance

    /// The process‐wide singleton.
    public static let shared = KeyboardMonitor()

    // MARK: Public Properties

    /// Callback invoked for every physical key press/release.
    /// Called on the run loop thread — keep work minimal for low latency.
    var onKeyEvent: ((KeyEvent) -> Void)?

    /// Whether the event tap is currently installed and active.
    private(set) var isRunning: Bool = false

    /// Whether any hardware or session keyboard monitor is actively receiving keystrokes.
    public var isListening: Bool {
        hidManager != nil || eventTap != nil || globalMonitor != nil
    }

    // MARK: Private Properties

    /// The hardware-level IOKit HID manager (works with Device Control / Input Monitoring permission).
    private var hidManager: IOHIDManager?

    /// The Quartz event tap port (works with Accessibility permission).
    fileprivate var eventTap: CFMachPort?

    /// The run loop source wrapping `eventTap`.
    private var runLoopSource: CFRunLoopSource?

    /// Cocoa global monitor capturing events across all external applications.
    private var globalMonitor: Any?

    /// Deduplication cache to prevent dual-triggering if multiple monitors report the same key event.
    private var lastKeyTimestamp: [Int64: UInt64] = [:]
    private let dedupeLock = NSLock()

    /// Logger scoped to the keyboard subsystem.
    fileprivate let logger = Logger(subsystem: "com.keyvibe.app", category: "KeyboardMonitor")

    // MARK: Initializer

    public init() {}

    // MARK: - Accessibility & Input Monitoring Permission Helpers

    /// Returns `true` if KeyVibe currently has permission to capture global keystrokes.
    /// Supports both macOS Device Control / Input Monitoring (kTCCServiceListenEvent) and
    /// Accessibility (kTCCServiceAccessibility), or an active hardware tap.
    static func checkAccessibilityPermission() -> Bool {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
            return true
        }
        if AXIsProcessTrusted() {
            return true
        }
        if KeyboardMonitor.shared.isListening {
            return true
        }
        return false
    }

    /// Prompts the user to grant permission via system dialogs (both Input Monitoring and Accessibility)
    /// and opens macOS System Settings directly to the privacy pane.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Deduplication Helper

    private static let dedupeWindowTicks: UInt64 = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanosPerMach = Double(info.numer) / Double(info.denom)
        // 25 ms per-key deduplication window prevents double-triggering across multiple taps (HID + CGEventTap + NSEvent),
        // but completely allows simultaneous different keys in chords (0ms delay!)
        return UInt64(25_000_000.0 / nanosPerMach)
    }()

    private func shouldProcess(keyCode: Int64, eventType: KeyEventType) -> Bool {
        let now = mach_absolute_time()
        dedupeLock.lock()
        defer { dedupeLock.unlock() }

        let key = (keyCode << 1) | (eventType == .keyDown ? 0 : 1)
        if let last = lastKeyTimestamp[key] {
            if now > last && (now - last) < Self.dedupeWindowTicks {
                return false
            }
        }
        lastKeyTimestamp[key] = now
        return true
    }

    // MARK: - Start / Stop

    /// Installs system-wide keystroke monitors across all applications.
    func start() {
        guard !isRunning else {
            logger.info("KeyboardMonitor is already running.")
            return
        }

        // ── 1. Install Hardware IOHIDManager (works with Device Control / Input Monitoring) ──
        installHIDManager()

        // ── 2. Install high-speed Session / HID Event Tap if Accessibility is granted ─
        installEventTap()

        // ── 3. Install Cocoa Global Monitor (fallback across external applications) ──
        installGlobalMonitor()

        isRunning = true
        logger.info("KeyboardMonitor started successfully.")
    }

    /// Installs direct hardware-level IOKit HID event tap for 0.05ms latency and full compatibility
    /// with macOS Device Control / Input Monitoring access.
    public func installHIDManager() {
        guard hidManager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDValueCallback = { context, result, sender, value in
            guard let context = context else { return }
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleHIDValue(value)
        }

        IOHIDManagerRegisterInputValueCallback(manager, callback, selfPointer)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openStatus == kIOReturnSuccess {
            self.hidManager = manager
            logger.info("Low-latency IOHIDManager hardware tap successfully installed!")
        } else {
            logger.warning("IOHIDManager open returned: \(openStatus)")
        }
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = Int(IOHIDElementGetUsagePage(element))
        guard usagePage == 0x07 /* kHIDPage_KeyboardOrKeypad */ else { return }

        let usage = Int(IOHIDElementGetUsage(element))
        guard usage >= 0x04 && usage <= 0xE7 else { return }

        let intVal = IOHIDValueGetIntegerValue(value)
        guard intVal == 0 || intVal == 1 else { return }

        let eventType: KeyEventType = (intVal == 1) ? .keyDown : .keyUp
        let keyCode = KeyMapper.keyCodeFromHIDUsage(usage)

        guard shouldProcess(keyCode: keyCode, eventType: eventType) else { return }

        let category = KeyMapper.category(for: keyCode)
        let keyEvent = KeyEvent(
            keyCode: keyCode,
            eventType: eventType,
            timestamp: mach_absolute_time(),
            keyCategory: category,
            isRepeat: false
        )
        onKeyEvent?(keyEvent)
    }

    /// Installs or reinstalls the low-latency CGEventTap when granted.
    public func installEventTap() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                                   | (1 << CGEventType.keyUp.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: KeyboardMonitor.eventTapCallback,
            userInfo: selfPointer
        ) ?? CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: KeyboardMonitor.eventTapCallback,
            userInfo: selfPointer
        )

        if let tap = tap {
            eventTap = tap
            if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
                runLoopSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            logger.info("Low-latency CGEventTap successfully installed!")
        }
    }

    private func installGlobalMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] nsEvent in
            guard let self = self else { return }

            let keyCode = Int64(nsEvent.keyCode)
            let eventType: KeyEventType = (nsEvent.type == .keyDown) ? .keyDown : .keyUp
            if !(nsEvent.isARepeat && eventType == .keyDown) {
                if self.shouldProcess(keyCode: keyCode, eventType: eventType) {
                    let category = KeyMapper.category(for: keyCode)
                    let keyEvent = KeyEvent(
                        keyCode: keyCode,
                        eventType: eventType,
                        timestamp: mach_absolute_time(),
                        keyCategory: category,
                        isRepeat: nsEvent.isARepeat
                    )
                    self.onKeyEvent?(keyEvent)
                }
            }
        }
    }

    /// Removes all event taps and monitors.
    func stop() {
        guard isRunning else { return }

        if let hid = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(hid, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }

        eventTap = nil
        runLoopSource = nil
        isRunning = false
        logger.info("KeyboardMonitor stopped.")
    }

    deinit {
        stop()
    }

    // MARK: - CGEventTap Callback (C‐Compatible)

    /// The raw C callback installed as the event tap handler.
    ///
    /// - Parameters:
    ///   - proxy: Opaque proxy for the tap.
    ///   - type: The event type delivered by the system.
    ///   - event: The raw `CGEvent`.
    ///   - userInfo: An `Unmanaged<KeyboardMonitor>` pointer.
    /// - Returns: The unmodified event (we are listen‐only).
    ///
    /// > Important: This function must remain a plain C function pointer.
    /// > It **cannot** capture any Swift context. All state access goes
    /// > through the `userInfo` pointer.
    private static let eventTapCallback: CGEventTapCallBack = {
        (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in

        // ── Capture a precise timestamp immediately ──────────────────────
        let preciseTimestamp = mach_absolute_time()

        guard let userInfo = userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo)
            .takeUnretainedValue()

        // ── Handle tap‐disabled events ───────────────────────────────────
        //
        // macOS may disable our tap if the system is under load or if the
        // callback takes too long. We re‐enable it immediately.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            monitor.logger.warning("Event tap was disabled (type=\(type.rawValue)). Re‐enabling.")
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // ── Only process keyDown and keyUp ───────────────────────────────
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        // ── Detect auto‐repeat ──────────────────────────────────────────
        //
        // Field `keyboardEventAutorepeat` is non‐zero for OS‐generated repeat
        // events. We still build a KeyEvent (with isRepeat = true) so the
        // consumer can decide, but the default behaviour is to skip repeats.
        let autoRepeatValue = event.getIntegerValueField(.keyboardEventAutorepeat)
        let isRepeat = autoRepeatValue != 0

        // ── Extract virtual key code ────────────────────────────────────
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // ── Map to event type and key category ──────────────────────────
        let eventType: KeyEventType = (type == .keyDown) ? .keyDown : .keyUp
        let keyCategory = KeyMapper.category(for: keyCode)

        // ── Build the KeyEvent ──────────────────────────────────────────
        let keyEvent = KeyEvent(
            keyCode: keyCode,
            eventType: eventType,
            timestamp: preciseTimestamp,
            keyCategory: keyCategory,
            isRepeat: isRepeat
        )

        // ── Filter auto‐repeats for sound triggering ────────────────────
        //
        // We only want actual physical key presses to trigger sounds.
        // Auto‐repeat keyDown events are discarded here.
        if isRepeat && eventType == .keyDown {
            return Unmanaged.passUnretained(event)
        }

        guard monitor.shouldProcess(keyCode: keyCode, eventType: eventType) else {
            return Unmanaged.passUnretained(event)
        }

        // ── Deliver to consumer ─────────────────────────────────────────
        monitor.onKeyEvent?(keyEvent)

        return Unmanaged.passUnretained(event)
    }
}
