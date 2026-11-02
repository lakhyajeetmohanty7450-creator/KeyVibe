//
//  TrialTracker.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  3-day free trial tracking with obfuscated storage and date tamper detection.
//

import Foundation
import CommonCrypto

// MARK: - TrialTracker

public struct TrialTracker {

    private static let installKey = "com.haptyk.internal.ts"
    private static let checksumKey = "com.haptyk.internal.cs"
    private static let salt = "HPTK-2024-SPU-ACCEL-SALT"

    /// Records initial installation timestamp if not previously set.
    public static func recordInstallDateIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: installKey) == nil {
            let now = Date().timeIntervalSince1970
            defaults.set(now, forKey: installKey)
            defaults.set(computeChecksum(timestamp: now), forKey: checksumKey)
        }
    }

    /// Returns the initial install date.
    public static func installDate() -> Date? {
        let defaults = UserDefaults.standard
        let ts = defaults.double(forKey: installKey)
        guard ts > 0 else { return nil }

        // Tamper verification
        let storedCs = defaults.string(forKey: checksumKey)
        if storedCs != computeChecksum(timestamp: ts) {
            // Tampering detected — treat trial as expired
            return Date.distantPast
        }

        return Date(timeIntervalSince1970: ts)
    }

    /// Days remaining in the 3-day evaluation window.
    public static func daysRemaining() -> Int {
        guard let install = installDate() else { return Constants.Trial.durationDays }

        let now = Date()
        let elapsedSeconds = now.timeIntervalSince(install)
        let totalTrialSeconds = Double(Constants.Trial.durationDays) * 86400.0

        if elapsedSeconds >= totalTrialSeconds {
            return 0
        }

        let remainingSeconds = totalTrialSeconds - elapsedSeconds
        return max(1, Int(ceil(remainingSeconds / 86400.0)))
    }

    /// Whether the 3-day trial period has expired.
    public static func isExpired() -> Bool {
        daysRemaining() <= 0
    }

    /// Computes SHA256 checksum with salt to prevent casual UserDefaults plist editing.
    private static func computeChecksum(timestamp: Double) -> String {
        let input = "\(timestamp):\(salt)"
        guard let data = input.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

