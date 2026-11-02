//
//  TypingMetrics.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Privacy-first, in-memory typing analytics:
//  Tracks daily keystroke counts, rolling taps per minute (TPM), and calculates
//  a relative force percentile comparing impact intensity against baseline averages.
//

import Foundation
import Combine

// MARK: - TypingMetrics

public final class TypingMetrics: ObservableObject {

    public static let shared = TypingMetrics()

    // MARK: - Published Properties

    @Published public var isEnabled: Bool = true
    @Published public private(set) var todayKeyCount: Int = 0
    @Published public private(set) var todayAvgForce: Double = 0.0
    @Published public private(set) var todayMaxForce: Double = 0.0
    @Published public private(set) var todayTypingSpeedTPM: Double = 0.0
    @Published public private(set) var forcePercentile: Int = 50
    @Published public private(set) var tierDistribution: [ForceTier: Int] = [
        .soft: 0, .medium: 0, .hard: 0, .slam: 0
    ]

    // MARK: - Private State

    private var recentKeystrokeTimestamps: [Date] = []
    private var totalForceAccumulator: Double = 0.0
    private let metricsLock = NSLock()

    public init() {
        loadPersistedStats()
    }

    // MARK: - Recording

    /// Records a single keystroke's impact metrics.
    public func recordKeystroke(force: Double, tier: ForceTier) {
        guard isEnabled else { return }

        metricsLock.lock()
        defer { metricsLock.unlock() }

        todayKeyCount += 1
        totalForceAccumulator += force
        todayAvgForce = totalForceAccumulator / Double(todayKeyCount)

        if force > todayMaxForce {
            todayMaxForce = force
        }

        tierDistribution[tier, default: 0] += 1

        let now = Date()
        recentKeystrokeTimestamps.append(now)

        // Prune timestamps older than 60 seconds
        let windowCutoff = now.addingTimeInterval(-60.0)
        recentKeystrokeTimestamps.removeAll { $0 < windowCutoff }

        // Taps per minute = count of taps in last 60 seconds
        todayTypingSpeedTPM = Double(recentKeystrokeTimestamps.count)

        // Calculate force percentile (baseline median typing force = 0.45G)
        calculateForcePercentile()

        // Mirror to AppStorage keys used by MenuBarView
        UserDefaults.standard.set(todayKeyCount, forKey: "haptyk.todayKeyCount")
        UserDefaults.standard.set(tier.displayName, forKey: "haptyk.todayAvgForce")
    }

    private func calculateForcePercentile() {
        // Normal distribution approximation: mean = 0.45G, standard deviation = 0.20G
        let mean = 0.45
        let stdDev = 0.20
        let zScore = (todayAvgForce - mean) / stdDev

        // Error function approximation for cumulative normal distribution
        let percentile = 0.5 * (1.0 + tanh(zScore * 0.797885)) * 100.0
        self.forcePercentile = max(1, min(99, Int(percentile)))
    }

    public func resetDaily() {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        todayKeyCount = 0
        totalForceAccumulator = 0.0
        todayAvgForce = 0.0
        todayMaxForce = 0.0
        todayTypingSpeedTPM = 0.0
        forcePercentile = 50
        tierDistribution = [.soft: 0, .medium: 0, .hard: 0, .slam: 0]
        recentKeystrokeTimestamps.removeAll()

        UserDefaults.standard.set(0, forKey: "haptyk.todayKeyCount")
        UserDefaults.standard.set("Medium", forKey: "haptyk.todayAvgForce")
    }

    private func loadPersistedStats() {
        let storedCount = UserDefaults.standard.integer(forKey: "haptyk.todayKeyCount")
        if storedCount > 0 {
            self.todayKeyCount = storedCount
        }
    }
}

