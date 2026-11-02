//
//  LicenseManager.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Commercial licensing and trial state machine:
//  3-day unrestricted free trial -> $8 one-time perpetual Pro license.
//

import Foundation
import Combine
import Security

// MARK: - LicenseStatus

public enum LicenseStatus: Equatable, Sendable {
    case unknown
    case trial(daysRemaining: Int)
    case trialExpired
    case pro
}

// MARK: - LicenseManager

public final class LicenseManager: ObservableObject {

    public static let shared = LicenseManager()

    @Published public private(set) var licenseStatus: LicenseStatus = .pro
    @Published public private(set) var isProUser: Bool = true

    public init() {
        validateOnLaunch()
    }

    /// Validates license state upon application launch.
    public func validateOnLaunch() {
        // Completely Free & Unrestricted: All features unlocked forever
        self.licenseStatus = .pro
        self.isProUser = true
        UserDefaults.standard.set(true, forKey: "haptyk.isProUser")
    }

    public func activateLicense(email: String, licenseKey: String) -> Bool {
        self.licenseStatus = .pro
        self.isProUser = true
        UserDefaults.standard.set(true, forKey: "haptyk.isProUser")
        return true
    }

    public func deactivateLicense() {
        self.licenseStatus = .pro
        self.isProUser = true
        UserDefaults.standard.set(true, forKey: "haptyk.isProUser")
    }
}

