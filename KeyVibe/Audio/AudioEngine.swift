//
//  AudioEngine.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Low-latency Core Audio pipeline using AVAudioEngine + AVAudioSourceNode.
//  Streams position-matched and force-scaled PCM audio samples directly
//  to hardware output in sub-millisecond latency.
//

import Foundation
import AVFoundation
import os.log

// MARK: - AudioEngine

/// Manages the real-time audio playback graph via Core Audio and AVAudioEngine.
public final class AudioEngine {

    // MARK: - Shared Instance

    public static let shared = AudioEngine()

    // MARK: - Core Audio Graph

    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private let renderState: UnsafeMutablePointer<HaptykRenderState>

    // MARK: - Subsystem References

    private let sampleBank = SampleBank.shared
    private let soundPackManager = SoundPackManager.shared
    private let log = HaptykLogger(category: .audio)

    // MARK: - Idle Management

    private var idleTimer: Timer?
    private var isEngineSuspended: Bool = false
    private let idleTimeoutSeconds: TimeInterval = Constants.Audio.idleTimeoutSeconds

    // MARK: - Public Properties

    /// Master volume (0.0 to 1.0).
    public var masterVolume: Float {
        get { renderState.pointee.masterVolume }
        set {
            haptyk_render_set_volume(renderState, newValue)
            Preferences.masterVolume = newValue
        }
    }

    /// Global mute toggle.
    public var isMuted: Bool {
        get { renderState.pointee.isMuted }
        set {
            haptyk_render_set_muted(renderState, newValue)
            Preferences.isMuted = newValue
        }
    }

    // MARK: - Initialization

    public init() {
        self.renderState = .allocate(capacity: 1)
        haptyk_render_init(renderState, UInt32(Constants.Audio.sampleRate))
        self.masterVolume = max(0.6, Preferences.masterVolume)
        self.isMuted = false
    }

    deinit {
        stop()
        renderState.deallocate()
    }

    // MARK: - Lifecycle

    /// Configures and starts the Core Audio render graph.
    public func start() {
        guard audioEngine == nil else {
            log.info("AudioEngine already started.")
            return
        }

        log.info("Configuring AVAudioEngine + AVAudioSourceNode graph...")
        let engine = AVAudioEngine()
        let sampleRate = Constants.Audio.sampleRate
        let channelCount: AVAudioChannelCount = 2 // Stereo output
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount) else {
            log.error("Failed to create standard audio format.")
            return
        }

        // Configure real-time C render callback node with raw pointer (exclusivity-safe)
        let statePtr = self.renderState
        let node = AVAudioSourceNode(format: outputFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            return haptyk_render_callback(statePtr, audioBufferList, frameCount)
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: outputFormat)
        engine.mainMixerNode.outputVolume = 1.0

        do {
            engine.prepare()
            try engine.start()
            self.audioEngine = engine
            self.sourceNode = node
            log.info("AudioEngine started successfully. Running on real-time IO thread.")
        } catch {
            log.error("Failed to start AVAudioEngine: \(error.localizedDescription)")
        }
    }

    /// Stops the audio engine.
    public func stop() {
        idleTimer?.invalidate()
        idleTimer = nil

        audioEngine?.stop()
        if let node = sourceNode {
            audioEngine?.detach(node)
        }
        audioEngine = nil
        sourceNode = nil
        log.info("AudioEngine stopped.")
    }

    // MARK: - Sound Triggering

    /// Plays the mechanical switch sound for a keystroke event based on its resolved velocity.
    public func playKeySound(for event: KeyEvent, velocity: VelocityResult) {
        // If muted or license prohibits playback, return immediately
        guard !isMuted else { return }

        // Ensure engine is running (auto-recover if audio device changed or woke from sleep)
        if let engine = audioEngine, !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                log.error("Failed to recover AudioEngine: \(error.localizedDescription)")
            }
        }

        guard let activePack = soundPackManager.selectedPack ?? soundPackManager.availablePacks.first else { return }
        log.info("AudioEngine playKeySound: keyCode=\(event.keyCode), category=\(event.keyCategory.rawValue), pack=\(activePack.id)")

        // Get crossfaded buffers and gains from SampleBank
        let blendedBuffers = sampleBank.crossfadedBuffers(
            pack: activePack.id,
            weights: velocity.crossfadeWeights,
            category: event.keyCategory,
            eventType: event.eventType
        )

        if blendedBuffers.isEmpty {
            if let fallbackBuf = sampleBank.buffer(pack: activePack.id, tier: .medium, category: event.keyCategory, eventType: event.eventType) {
                triggerPCMBuffer(fallbackBuf, gain: 1.0)
            }
        } else {
            for (pcm, tierGain) in blendedBuffers {
                triggerPCMBuffer(pcm, gain: tierGain)
            }
        }
    }

    /// Triggers raw PCM buffer playback directly on the real-time C audio thread with zero latency.
    public func triggerPCMBuffer(_ pcm: PCMBuffer, gain: Float = 1.0) {
        _ = haptyk_render_trigger_voice(
            self.renderState,
            pcm.pointer,
            UInt32(pcm.frameCount),
            gain,
            pcm.channelCount == 2
        )
    }

    /// Plays an instant acoustic sample for the active switch pack (used for UI previews and verification).
    public func playTestSound() {
        guard let activePack = soundPackManager.selectedPack ?? soundPackManager.availablePacks.first else { return }
        log.info("AudioEngine playTestSound: pack=\(activePack.id)")
        if let buf = sampleBank.buffer(pack: activePack.id, tier: .medium, category: .alphanumeric, eventType: .keyDown) {
            triggerPCMBuffer(buf, gain: 1.0)
        }
    }
}
