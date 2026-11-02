//
//  SampleBank.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Pre-caches uncompressed 32-bit float PCM audio buffers in RAM.
//  Guarantees 0ms disk I/O during active typing sessions.
//

import Foundation
import AVFoundation
import os.log

// MARK: - PCMBuffer

/// Uncompressed, ready-to-stream 32-bit float PCM audio buffer.
public struct PCMBuffer: Sendable {
    /// Contiguous floating-point PCM samples (interleaved if stereo).
    public let samples: [Float]
    /// Total audio frame count.
    public let frameCount: Int
    /// Number of channels (1 = mono, 2 = stereo).
    public let channelCount: Int
    /// Audio sample rate in Hz (typically 44,100).
    public let sampleRate: Double

    public init(samples: [Float], frameCount: Int, channelCount: Int = 1, sampleRate: Double = 44100.0) {
        self.samples = samples
        self.frameCount = frameCount
        self.channelCount = channelCount
        self.sampleRate = sampleRate
    }
}

// MARK: - SampleBank

/// In-memory cache manager for switch acoustic audio samples.
public final class SampleBank {

    // MARK: - Shared Instance

    public static let shared = SampleBank()

    // MARK: - In-Memory Cache
    // Cache map: [PackID -> [ForceTier -> [KeyCategory -> [KeyEventType -> PCMBuffer]]]]
    private var cache: [String: [ForceTier: [KeyCategory: [KeyEventType: PCMBuffer]]]] = [:]
    private let cacheLock = NSLock()

    /// Dedicated logger.
    private let log = HaptykLogger(category: .audio)

    // MARK: - Initialization

    private init() {
        // Clean cache initialization without circular singleton dependency
    }

    // MARK: - Pack Loading

    /// Pre-loads all 4 tiers, all key categories, and press/release samples for a pack into RAM.
    public func loadPack(_ pack: SoundPack) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if cache[pack.id] != nil {
            log.info("Sound pack '\(pack.name)' already cached in RAM.")
            return
        }

        log.info("Pre-loading sound pack '\(pack.name)' into RAM...")
        var packMap: [ForceTier: [KeyCategory: [KeyEventType: PCMBuffer]]] = [:]

        for tier in ForceTier.allCases {
            var tierMap: [KeyCategory: [KeyEventType: PCMBuffer]] = [:]

            for category in KeyCategory.allCases {
                var eventMap: [KeyEventType: PCMBuffer] = [:]

                // Press sample
                let pressBuffer = loadOrSynthesizeSample(
                    pack: pack,
                    tier: tier,
                    category: category,
                    eventType: .keyDown
                )
                eventMap[.keyDown] = pressBuffer

                // Release sample
                if KeyMapper.hasReleaseSound(for: category) {
                    let releaseBuffer = loadOrSynthesizeSample(
                        pack: pack,
                        tier: tier,
                        category: category,
                        eventType: .keyUp
                    )
                    eventMap[.keyUp] = releaseBuffer
                }

                tierMap[category] = eventMap
            }
            packMap[tier] = tierMap
        }

        cache[pack.id] = packMap
        log.info("Pack '\(pack.name)' loaded successfully.")
    }

    /// Unloads a pack's audio buffers to reclaim RAM.
    public func unloadPack(_ packID: String) {
        cacheLock.lock()
        cache.removeValue(forKey: packID)
        cacheLock.unlock()
    }

    // MARK: - Buffer Retrieval

    /// Retrieves the single matching PCM buffer.
    public func buffer(
        pack: String,
        tier: ForceTier,
        category: KeyCategory,
        eventType: KeyEventType
    ) -> PCMBuffer? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let packMap = cache[pack] else { return nil }
        guard let tierMap = packMap[tier] else { return nil }

        // Fallback: if category specific sample not found, use alphanumeric
        if let categoryMap = tierMap[category], let buf = categoryMap[eventType] {
            return buf
        }
        return tierMap[.alphanumeric]?[eventType]
    }

    /// Returns the two crossfaded buffers and their respective calculated gains.
    public func crossfadedBuffers(
        pack: String,
        weights: CrossfadeWeights,
        category: KeyCategory,
        eventType: KeyEventType
    ) -> [(buffer: PCMBuffer, gain: Float)] {
        var results: [(buffer: PCMBuffer, gain: Float)] = []

        if weights.lowerWeight > 0.001 {
            if let buf = buffer(pack: pack, tier: weights.lowerTier, category: category, eventType: eventType) {
                results.append((buffer: buf, gain: weights.lowerWeight))
            }
        }

        if weights.upperWeight > 0.001 && weights.upperTier != weights.lowerTier {
            if let buf = buffer(pack: pack, tier: weights.upperTier, category: category, eventType: eventType) {
                results.append((buffer: buf, gain: weights.upperWeight))
            }
        }

        return results
    }

    // MARK: - Audio Loading & Procedural Synthesis

    private func loadOrSynthesizeSample(
        pack: SoundPack,
        tier: ForceTier,
        category: KeyCategory,
        eventType: KeyEventType
    ) -> PCMBuffer {
        // 1. Try to load authentic WAV recordings from bundle resources
        let action = (eventType == .keyDown) ? "press" : "release"
        let suffix = KeyMapper.sampleSuffix(for: category)
        let filename = "\(tier.samplePrefix)_\(action)_\(suffix)"

        var candidateURLs: [URL] = []
        if let u = Bundle.main.url(forResource: filename, withExtension: "wav", subdirectory: "SoundPacks/\(pack.id)") {
            candidateURLs.append(u)
        }
        if let res = Bundle.main.resourceURL {
            candidateURLs.append(res.appendingPathComponent("SoundPacks/\(pack.id)/\(filename).wav"))
            candidateURLs.append(res.appendingPathComponent("SoundPacks/Packs/\(pack.id)/\(filename).wav"))
            // Fallback to medium tier if specific tier file is missing
            candidateURLs.append(res.appendingPathComponent("SoundPacks/\(pack.id)/medium_\(action)_\(suffix).wav"))
        }

        for url in candidateURLs {
            if FileManager.default.fileExists(atPath: url.path) {
                if let loaded = loadWavFile(url: url) {
                    return loaded
                }
            }
        }

        // 2. Procedural synthesis fallback
        return synthesizeSwitchSample(pack: pack, tier: tier, category: category, eventType: eventType)
    }

    private func loadWavFile(url: URL) -> PCMBuffer? {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = UInt32(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
            try file.read(into: buffer)

            guard let floatData = buffer.floatChannelData else { return nil }
            let channels = Int(format.channelCount)
            let frames = Int(buffer.frameLength)

            var interleaved = [Float](repeating: 0, count: frames * channels)
            for ch in 0..<channels {
                let channelBuffer = floatData[ch]
                for f in 0..<frames {
                    interleaved[f * channels + ch] = channelBuffer[f]
                }
            }
            return PCMBuffer(samples: interleaved, frameCount: frames, channelCount: channels, sampleRate: format.sampleRate)
        } catch {
            return nil
        }
    }

    /// Physically-modeled procedural acoustic synthesis for mechanical switches.
    private func synthesizeSwitchSample(
        pack: SoundPack,
        tier: ForceTier,
        category: KeyCategory,
        eventType: KeyEventType
    ) -> PCMBuffer {
        let sampleRate = Constants.Audio.sampleRate
        // Impact duration in ms: 25ms to 60ms
        let durationMs: Double = (eventType == .keyDown) ? (35.0 + Double(tier.rawValue) * 8.0) : 22.0
        let frameCount = Int((durationMs / 1000.0) * sampleRate)
        var samples = [Float](repeating: 0.0, count: frameCount)

        // Base frequency dependent on key category (Spacebar has lower, deeper pitch)
        var basePitch: Double = 420.0
        switch category {
        case .spacebar: basePitch = 160.0
        case .enter: basePitch = 240.0
        case .backspace: basePitch = 280.0
        case .modifier: basePitch = 320.0
        default: basePitch = 480.0
        }

        // Force tier modifies resonance and impact amplitude
        let forceAmp: Float = (eventType == .keyDown) ? (0.35 + Float(tier.rawValue) * 0.22) : 0.25
        let decayRate: Double = (eventType == .keyDown) ? (50.0 - Double(tier.rawValue) * 6.0) : 80.0

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let envelope = Float(exp(-t * decayRate))

            var sampleVal: Float = 0.0

            switch pack.category {
            case .clicky:
                // Sharp click burst + body resonance
                let clickEnv = Float(exp(-t * 220.0))
                let clickPulse = Float(sin(2.0 * .pi * (basePitch * 3.8) * t))
                let body = Float(sin(2.0 * .pi * basePitch * t))
                let noise = Float.random(in: -0.15...0.15) * clickEnv
                sampleVal = (clickPulse * 0.55 * clickEnv + body * 0.45 + noise) * envelope

            case .tactile:
                // Deep thock: warm sine base with slight spring harmonic
                let thock = Float(sin(2.0 * .pi * basePitch * t))
                let sub = Float(sin(2.0 * .pi * (basePitch * 0.5) * t)) * 0.3
                let tap = Float.random(in: -0.1...0.1) * Float(exp(-t * 180.0))
                sampleVal = (thock * 0.7 + sub + tap) * envelope

            case .linear:
                // Smooth clack: gentle plastic impact
                let clack = Float(sin(2.0 * .pi * (basePitch * 1.2) * t))
                let noise = Float.random(in: -0.08...0.08) * Float(exp(-t * 150.0))
                sampleVal = (clack * 0.75 + noise) * envelope

            case .vintage:
                // Buckling spring: 1.2kHz spring ringing ping + bottom out
                let spring = Float(sin(2.0 * .pi * 1250.0 * t)) * Float(exp(-t * 35.0))
                let clack = Float(sin(2.0 * .pi * basePitch * t))
                sampleVal = (spring * 0.4 + clack * 0.6) * envelope
            }

            samples[i] = sampleVal * forceAmp
        }

        return PCMBuffer(samples: samples, frameCount: frameCount, channelCount: 1, sampleRate: sampleRate)
    }
}

