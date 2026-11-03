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

    private static let logFilePath = "/tmp/keyvibe.log"
    private static func writeToFile(_ line: String) {
        let entry = "\(Date()): \(line)\n"
        if let data = entry.data(using: .utf8) {
            if let fileHandle = FileHandle(forWritingAtPath: logFilePath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try? fileHandle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: logFilePath), options: .atomic)
            }
        }
    }

    /// Logs a **debug**-level message.
    func debug(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        let msg = message()
        Self.writeToFile("[\(category.rawValue)] [DEBUG] \(msg)")
        #if DEBUG
        os_log(
            .debug,
            log: osLog,
            "%{public}s [%{public}s:%{public}d]",
            msg,
            abbreviatedFile(file),
            line
        )
        #else
        os_log(.debug, log: osLog, "%{public}s", msg)
        #endif
    }

    /// Logs an **info**-level message.
    func info(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        let msg = message()
        Self.writeToFile("[\(category.rawValue)] [INFO] \(msg)")
        #if DEBUG
        os_log(
            .info,
            log: osLog,
            "%{public}s [%{public}s:%{public}d]",
            msg,
            abbreviatedFile(file),
            line
        )
        #else
        os_log(.info, log: osLog, "%{public}s", msg)
        #endif
    }

    /// Logs a **warning**-level message (maps to `OSLogType.default`).
    func warning(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        let msg = message()
        Self.writeToFile("[\(category.rawValue)] [WARN] \(msg)")
        #if DEBUG
        os_log(
            .default,
            log: osLog,
            "⚠️ %{public}s [%{public}s:%{public}d]",
            msg,
            abbreviatedFile(file),
            line
        )
        #else
        os_log(.default, log: osLog, "⚠️ %{public}s", msg)
        #endif
    }

    /// Logs an **error**-level message.
    func error(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        let msg = message()
        Self.writeToFile("[\(category.rawValue)] [ERROR] \(msg)")
        #if DEBUG
        os_log(
            .error,
            log: osLog,
            "❌ %{public}s [%{public}s:%{public}d]",
            msg,
            abbreviatedFile(file),
            line
        )
        #else
        os_log(.error, log: osLog, "❌ %{public}s", msg)
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
