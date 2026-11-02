//
//  SoundPack.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Model representing a mechanical switch audio profile pack.
//

import Foundation

// MARK: - SwitchCategory

/// The acoustic character category of the mechanical switch.
public enum SwitchCategory: String, Codable, CaseIterable, Sendable {
    case clicky = "Clicky"
    case tactile = "Tactile & Thocky"
    case linear = "Linear"
    case vintage = "Vintage & IBM"

    /// SF Symbol icon associated with this acoustic profile.
    public var iconName: String {
        switch self {
        case .clicky: return "sparkles"
        case .tactile: return "waveform.path.ecg"
        case .linear: return "water.waves"
        case .vintage: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - SoundPack

/// A complete switch sound profile containing audio recordings across all 4 force tiers.
public struct SoundPack: Identifiable, Codable, Hashable, Sendable {
    /// Unique filesystem and preference identifier (e.g. "cherry-mx-blue").
    public let id: String

    /// Human-readable switch name (e.g. "Cherry MX Blue PBT").
    public let name: String

    /// Acoustic category.
    public let category: SwitchCategory

    /// Short technical acoustic description.
    public let description: String

    /// Author or sampling engineer.
    public let author: String

    /// Open source license (e.g. "MIT").
    public let license: String

    /// Whether this pack has unique recorded samples for all 4 force tiers.
    public let hasTieredSamples: Bool

    public init(
        id: String,
        name: String,
        category: SwitchCategory,
        description: String,
        author: String = "Haptyk Acoustic Labs",
        license: String = "MIT",
        hasTieredSamples: Bool = true
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
        self.author = author
        self.license = license
        self.hasTieredSamples = hasTieredSamples
    }
}

