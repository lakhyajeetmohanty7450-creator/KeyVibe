//
//  VineBoomFeature.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Easter Egg: Slamming the Enter key triggers a deep, thunderous Vine Boom
//  sub-bass drop sound effect.
//

import Foundation
import Combine

// MARK: - VineBoomFeature

public final class VineBoomFeature: ObservableObject {

    @Published public var isEnabled: Bool = false
    @Published public private(set) var triggerCount: Int = 0

    private var boomBuffer: PCMBuffer?

    public init() {
        self.boomBuffer = synthesizeVineBoom()
    }

    /// Evaluates if this keystroke is an Enter slam and triggers boom audio.
    public func shouldTrigger(event: KeyEvent, velocity: VelocityResult) -> Bool {
        guard isEnabled else { return false }
        guard event.eventType == .keyDown else { return false }
        guard event.keyCategory == .enter else { return false }
        guard velocity.forceTier == .slam else { return false }

        triggerCount += 1
        playBoom()
        return true
    }

    public func resetDailyCount() {
        triggerCount = 0
    }

    private func playBoom() {
        guard let buffer = boomBuffer else { return }
        AudioEngine.shared.triggerPCMBuffer(buffer, gain: 1.0)
    }

    /// Synthesizes the iconic thunderous pitch-dropping 808 distortion boom.
    private func synthesizeVineBoom() -> PCMBuffer {
        let sampleRate = Constants.Audio.sampleRate
        let duration = 1.2 // 1.2 seconds of boom
        let frameCount = Int(duration * sampleRate)
        var samples = [Float](repeating: 0.0, count: frameCount)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            // Exponential pitch drop from 180Hz down to 42Hz
            let pitch = 42.0 + 138.0 * exp(-t * 8.0)
            let env = Float(exp(-t * 2.5))

            // Overdriven saturated sine wave
            let rawSine = sin(2.0 * .pi * pitch * t)
            // Soft clipping saturation
            let saturated = tanh(rawSine * 2.2)

            samples[i] = Float(saturated) * env * 0.95
        }

        return PCMBuffer(samples: samples, frameCount: frameCount, channelCount: 1, sampleRate: sampleRate)
    }
}
