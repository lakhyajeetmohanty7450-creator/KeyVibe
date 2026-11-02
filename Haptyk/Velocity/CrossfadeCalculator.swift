//
//  CrossfadeCalculator.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Computes continuous linear gain blending weights between adjacent force
//  tier recordings to eliminate audible stepping artifacts during typing.
//

import Foundation

// MARK: - CrossfadeCalculator

/// Calculates real-time audio gain crossfades between adjacent force tiers.
///
/// ## Crossfade Spectrum Architecture:
/// ```
///  0.0 ─────────── [Soft] ─────────── [Medium] ─────────── [Hard] ─────────── [Slam] ───► Force
///        100% Soft        Blend S/M           Blend M/H          Blend H/S      100% Slam
/// ```
public struct CrossfadeCalculator: Sendable {

    public init() {}

    /// Calculates the two participating tiers and their respective linear gain
    /// multipliers for the given impact magnitude.
    ///
    /// - Parameters:
    ///   - magnitude: Peak acceleration magnitude above baseline in Gs.
    ///   - classifier: The current active classifier with sensitivity thresholds.
    /// - Returns: `CrossfadeWeights` representing lower/upper tiers and gains.
    public func calculateWeights(magnitude: Double, classifier: ForceTierClassifier) -> CrossfadeWeights {
        if magnitude <= classifier.softThreshold {
            return .single(.soft)
        } else if magnitude < classifier.mediumThreshold {
            let range = classifier.mediumThreshold - classifier.softThreshold
            let ratio = Float(max(0.0, min(1.0, (magnitude - classifier.softThreshold) / range)))
            return CrossfadeWeights(
                lowerTier: .soft,
                upperTier: .medium,
                lowerWeight: 1.0 - ratio,
                upperWeight: ratio
            )
        } else if magnitude < classifier.hardThreshold {
            let range = classifier.hardThreshold - classifier.mediumThreshold
            let ratio = Float(max(0.0, min(1.0, (magnitude - classifier.mediumThreshold) / range)))
            return CrossfadeWeights(
                lowerTier: .medium,
                upperTier: .hard,
                lowerWeight: 1.0 - ratio,
                upperWeight: ratio
            )
        } else if magnitude < classifier.slamThreshold {
            let range = classifier.slamThreshold - classifier.hardThreshold
            let ratio = Float(max(0.0, min(1.0, (magnitude - classifier.hardThreshold) / range)))
            return CrossfadeWeights(
                lowerTier: .hard,
                upperTier: .slam,
                lowerWeight: 1.0 - ratio,
                upperWeight: ratio
            )
        } else {
            return .single(.slam)
        }
    }
}

