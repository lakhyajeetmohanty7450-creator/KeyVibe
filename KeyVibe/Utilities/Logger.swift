//
//  Logger.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Lightweight, subsystem-aware logging wrapper around Apple's Unified
//  Logging (`os.log`). Each subsystem category gets its own `OSLog`
//  instance so that Console.app filters work out of the box.
//

import Foundation
import os.log

// MARK: - Log Category

/// Predefined logging categories that map 1-to-1 with Haptyk subsystems.
///
/// Using a closed enum (rather than raw strings) prevents typos and makes
/// it trivial to discover every log channel at the call-site.
enum LogCategory: String {
    /// IOKit HID accelerometer stream.
    case accelerometer
    /// CGEventTap keyboard monitoring.
    case keyboard
    /// AVAudioEngine render pipeline.
    case audio
    /// Force-classification / velocity correlation.
    case velocity
    /// Menu bar, popover, and settings UI.
    case ui
    /// Trial / Pro license verification.
    case licensing
}

// MARK: - KeyVibeLogger

typealias HaptykLogger = KeyVibeLogger

/// A thin, zero-cost abstraction over `os_log` tailored for KeyVibe.
struct KeyVibeLogger {

    // MARK: - Properties

    /// The underlying `OSLog` handle used for all messages emitted by
    /// this logger instance.
    private let osLog: OSLog

    /// Human-readable category label (e.g. "audio", "keyboard").
    let category: LogCategory

    // MARK: - Initialisation

    /// Creates a logger for the given subsystem category.
    ///
    /// - Parameter category: The `LogCategory` this logger reports under.
    ///   The `OSLog` subsystem is always `Constants.App.bundleIdentifier`.
    init(category: LogCategory) {
        self.category = category
        self.osLog = OSLog(
            subsystem: Constants.App.bundleIdentifier,
            category: category.rawValue
        )
    }

    // MARK: - Logging Methods

    /// Logs a **debug**-level message.
    ///
    /// Debug messages are only captured when a log profile or Console.app
    /// explicitly enables them.  In debug builds the file and line are
    /// appended automatically.
    ///
    /// - Parameters:
    ///   - message: A human-readable description of the event.
    ///   - file:    Injected automatically — do not pass explicitly.
    ///   - line:    Injected automatically — do not pass explicitly.
    func debug(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        #if DEBUG
        os_log(
            .debug,
            log: osLog,
            "%{public}s [%{public}s:%{public}d]",
            message(),
            abbreviatedFile(file),
            line
        )
        #else
        os_log(.debug, log: osLog, "%{public}s", message())
        #endif
    }

    /// Logs an **info**-level message.
    ///
    /// Info messages are persisted only when they occur close in time to
    /// an error or fault, making them ideal for "breadcrumb" context.
    ///
    /// - Parameters:
    ///   - message: A human-readable description of the event.
    ///   - file:    Injected automatically — do not pass explicitly.
    ///   - line:    Injected automatically — do not pass explicitly.
    func info(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        #if DEBUG
        os_log(
            .info,
            log: osLog,
            "%{public}s [%{public}s:%{public}d]",
            message(),
            abbreviatedFile(file),
            line
        )
        #else
        os_log(.info, log: osLog, "%{public}s", message())
        #endif
    }

    /// Logs a **warning**-level message (maps to `OSLogType.default`).
    ///
    /// Warnings indicate unexpected-but-recoverable situations.  Apple's
    /// Unified Logging has no explicit "warning" level so we use
    /// `.default`, which is always persisted.
    ///
    /// - Parameters:
    ///   - message: A human-readable description of the event.
    ///   - file:    Injected automatically — do not pass explicitly.
    ///   - line:    Injected automatically — do not pass explicitly.
    func warning(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        #if DEBUG
        os_log(
            .default,
            log: osLog,
            "⚠️ %{public}s [%{public}s:%{public}d]",
            message(),
            abbreviatedFile(file),
            line
        )
        #else
        os_log(.default, log: osLog, "⚠️ %{public}s", message())
        #endif
    }

    /// Logs an **error**-level message.
    ///
    /// Errors represent failures that disrupt functionality. These are
    /// always persisted and surfaced prominently in Console.app.
    ///
    /// - Parameters:
    ///   - message: A human-readable description of the error.
    ///   - file:    Injected automatically — do not pass explicitly.
    ///   - line:    Injected automatically — do not pass explicitly.
    func error(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        #if DEBUG
        os_log(
            .error,
            log: osLog,
            "❌ %{public}s [%{public}s:%{public}d]",
            message(),
            abbreviatedFile(file),
            line
        )
        #else
        os_log(.error, log: osLog, "❌ %{public}s", message())
        #endif
    }

    // MARK: - Private Helpers

    /// Strips the module prefix from `#fileID` to keep log lines concise.
    ///
    /// `#fileID` produces strings like `"Haptyk/AudioEngine.swift"`.
    /// We return just `"AudioEngine.swift"`.
    private func abbreviatedFile(_ fileID: String) -> String {
        if let lastSlash = fileID.lastIndex(of: "/") {
            return String(fileID[fileID.index(after: lastSlash)...])
        }
        return fileID
    }
}
