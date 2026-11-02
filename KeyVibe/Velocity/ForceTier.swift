//
//  ForceTier.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Defines the 4-tier force classification spectrum:
//  - Soft: Light brush / quiet tap
//  - Medium: Baseline normal mechanical typing
//  - Hard: Forceful bottom-out strike
//  - Slam: Maximum impact typing (triggers Labs features)
//

import Foundation

// MARK: - ForceTier

/// Represents the categorized force tier of a keystroke.
public enum ForceTier: Int, CaseIterable, Comparable, Sendable, Codable {
    case soft = 0
    case medium = 1
    case hard = 2
    case slam = 3

    public static func < (lhs: ForceTier, rhs: ForceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// User-facing display name.
    public var displayName: String {
        switch self {
        case .soft: return "Soft"
        case .medium: return "Medium"
        case .hard: return "Hard"
        case .slam: return "Slam"
        }
    }

    /// File naming prefix for sound sample assets.
    public var samplePrefix: String {
        switch self {
        case .soft: return "soft"
        case .medium: return "medium"
        case .hard: return "hard"
        case .slam: return "slam"
        }
    }
}

// MARK: - CrossfadeWeights

/// Linear gain crossfade weights between two adjacent force tiers.
///
/// Ensures smooth transitions without audible stepping artifacts when typing
/// intensity fluctuates around tier boundaries.
public struct CrossfadeWeights: Sendable {
    public let lowerTier: ForceTier
    public let upperTier: ForceTier
    /// Gain multiplier for the lower tier (0.0 – 1.0).
    public let lowerWeight: Float
    /// Gain multiplier for the upper tier (0.0 – 1.0). Note: lowerWeight + upperWeight = 1.0.
    public let upperWeight: Float

    public init(lowerTier: ForceTier, upperTier: ForceTier, lowerWeight: Float, upperWeight: Float) {
        self.lowerTier = lowerTier
        self.upperTier = upperTier
        self.lowerWeight = lowerWeight
        self.upperWeight = upperWeight
    }

    /// Pure single-tier weight (100% on one tier).
    public static func single(_ tier: ForceTier) -> CrossfadeWeights {
        CrossfadeWeights(lowerTier: tier, upperTier: tier, lowerWeight: 1.0, upperWeight: 0.0)
    }
}

// MARK: - ForceTierClassifier

/// Classifies continuous impact magnitude into discrete force tiers and
/// calculates relative positioning for crossfading.
public struct ForceTierClassifier: Sendable {

    public var softThreshold: Double
    public var mediumThreshold: Double
    public var hardThreshold: Double
    public var slamThreshold: Double

    public init(
        softThreshold: Double = Constants.ForceTiers.softThreshold,
        mediumThreshold: Double = Constants.ForceTiers.mediumThreshold,
        hardThreshold: Double = Constants.ForceTiers.hardThreshold,
        slamThreshold: Double = Constants.ForceTiers.slamThreshold
    ) {
        self.softThreshold = softThreshold
        self.mediumThreshold = mediumThreshold
        self.hardThreshold = hardThreshold
        self.slamThreshold = slamThreshold
    }

    /// Categorizes a peak delta magnitude into its primary force tier.
    public func classify(_ magnitude: Double) -> ForceTier {
        if magnitude < mediumThreshold {
            return .soft
        } else if magnitude < hardThreshold {
            return .medium
        } else if magnitude < slamThreshold {
            return .hard
        } else {
            return .slam
        }
    }

    /// Adjusts thresholds based on user-configured sensitivity (0.0 – 2.0).
    ///
    /// Higher sensitivity lowers the force required to reach Hard and Slam tiers.
    public mutating func adjustSensitivity(_ sensitivity: Double) {
        // sensitivity is 0.0 (least sensitive) to 2.0 (most sensitive), 1.0 is default
        let factor = max(0.2, 2.0 - sensitivity)
        self.softThreshold = Constants.ForceTiers.softThreshold * factor
        self.mediumThreshold = Constants.ForceTiers.mediumThreshold * factor
        self.hardThreshold = Constants.ForceTiers.hardThreshold * factor
        self.slamThreshold = Constants.ForceTiers.slamThreshold * factor
    }
}

