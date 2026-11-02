//
//  AudioRenderer.c
//  Haptyk
//
//  Real-time audio renderer implementation.
//
//  This file contains the lock-free, allocation-free audio mixing engine
//  that runs on CoreAudio's real-time I/O thread. Every function in the
//  render path is designed for deterministic execution time with no
//  system calls that could cause priority inversion.
//
//  Architecture:
//  ┌─────────────────┐     atomic writes     ┌─────────────────────┐
//  │   Main Thread   │ ──────────────────────▶│  HaptykRenderState  │
//  │ (trigger_voice) │                        │     (shared)        │
//  └─────────────────┘                        └────────┬────────────┘
//                                                      │ atomic reads
//                                             ┌────────▼────────────┐
//                                             │  Audio I/O Thread   │
//                                             │ (render_callback)   │
//                                             └─────────────────────┘
//
//  Copyright © 2024 Haptyk. All rights reserved.
//

#include "AudioRenderer.h"
#include <string.h>
#include <stdatomic.h>

// MARK: - Atomic Helpers

/// Atomically load a boolean value with acquire semantics.
/// Acquire ensures all subsequent reads see stores that happened before
/// the corresponding release store.
static inline bool atomic_load_bool(const bool *ptr) {
    return __atomic_load_n(ptr, __ATOMIC_ACQUIRE);
}

/// Atomically store a boolean value with release semantics.
/// Release ensures all prior stores are visible to threads that
/// subsequently perform an acquire load on the same variable.
static inline void atomic_store_bool(bool *ptr, bool value) {
    __atomic_store_n(ptr, value, __ATOMIC_RELEASE);
}

/// Atomically load a float value with acquire semantics.
/// Note: float atomic operations are safe on ARM64 and x86_64 when
/// naturally aligned (which struct layout guarantees).
static inline float atomic_load_float(const float *ptr) {
    uint32_t raw = __atomic_load_n((const uint32_t *)ptr, __ATOMIC_ACQUIRE);
    float result;
    memcpy(&result, &raw, sizeof(float));
    return result;
}

/// Atomically store a float value with release semantics.
static inline void atomic_store_float(float *ptr, float value) {
    uint32_t raw;
    memcpy(&raw, &value, sizeof(float));
    __atomic_store_n((uint32_t *)ptr, raw, __ATOMIC_RELEASE);
}

/// Atomically load a 32-bit integer with acquire semantics.
static inline int32_t atomic_load_i32(const int32_t *ptr) {
    return __atomic_load_n(ptr, __ATOMIC_ACQUIRE);
}

/// Atomically store a 32-bit integer with release semantics.
static inline void atomic_store_i32(int32_t *ptr, int32_t value) {
    __atomic_store_n(ptr, value, __ATOMIC_RELEASE);
}

/// Atomically increment a 32-bit integer. Returns the previous value.
static inline int32_t atomic_increment_i32(int32_t *ptr) {
    return __atomic_fetch_add(ptr, 1, __ATOMIC_ACQ_REL);
}

/// Atomically decrement a 32-bit integer. Returns the previous value.
static inline int32_t atomic_decrement_i32(int32_t *ptr) {
    return __atomic_fetch_sub(ptr, 1, __ATOMIC_ACQ_REL);
}

// MARK: - Initialization

void haptyk_render_init(HaptykRenderState *state, uint32_t sampleRate) {
    // Zero-initialize the entire state structure.
    // This sets all voice buffers to NULL, positions to 0, gains to 0,
    // and isActive flags to false.
    memset(state, 0, sizeof(HaptykRenderState));
    
    // Configure operating parameters
    state->sampleRate = sampleRate;
    atomic_store_float(&state->masterVolume, 1.0f);
    atomic_store_bool(&state->isMuted, false);
    atomic_store_i32(&state->activeVoiceCount, 0);
    
    // Explicitly mark all voices as inactive (redundant after memset,
    // but ensures atomic visibility semantics are correct)
    for (int i = 0; i < HAPTYK_MAX_VOICES; i++) {
        atomic_store_bool(&state->voices[i].isActive, false);
    }
}

// MARK: - Voice Triggering (Main Thread)

int haptyk_render_trigger_voice(HaptykRenderState *state,
                                 const float *buffer,
                                 uint32_t bufferLength,
                                 float gain,
                                 bool isStereo) {
    // Validate inputs — no-op on invalid data
    if (__builtin_expect(buffer == NULL || bufferLength == 0, 0)) {
        return -1;
    }
    
    // Clamp gain to valid range
    if (gain < 0.0f) gain = 0.0f;
    if (gain > 1.0f) gain = 1.0f;
    
    // --- Phase 1: Search for an inactive voice slot ---
    int slotIndex = -1;
    for (int i = 0; i < HAPTYK_MAX_VOICES; i++) {
        if (!atomic_load_bool(&state->voices[i].isActive)) {
            slotIndex = i;
            break;
        }
    }
    
    // --- Phase 2: Voice stealing if no free slots ---
    // Steal the voice with the highest playback position (closest to finishing).
    // This is the least disruptive choice for the listener.
    if (__builtin_expect(slotIndex == -1, 0)) {
        uint32_t maxPosition = 0;
        int stealIndex = -1;
        
        for (int i = 0; i < HAPTYK_MAX_VOICES; i++) {
            uint32_t pos = __atomic_load_n(&state->voices[i].playbackPosition,
                                            __ATOMIC_ACQUIRE);
            if (pos > maxPosition) {
                maxPosition = pos;
                stealIndex = i;
            }
        }
        
        // If all voices were triggered at the exact same frame (maxPosition == 0),
        // use round-robin rather than always clobbering slot 0.
        if (stealIndex == -1) {
            static uint32_t rr = 0;
            stealIndex = (rr++) % HAPTYK_MAX_VOICES;
        }
        
        // Deactivate the stolen voice before reconfiguring
        atomic_store_bool(&state->voices[stealIndex].isActive, false);
        atomic_decrement_i32(&state->activeVoiceCount);
        slotIndex = stealIndex;
    }
    
    // --- Phase 3: Configure the voice slot ---
    // Order matters: set all parameters BEFORE marking active.
    // The release store on isActive acts as a fence ensuring all prior
    // stores (buffer, gain, position) are visible to the audio thread.
    HaptykVoice *voice = &state->voices[slotIndex];
    
    voice->buffer = buffer;
    voice->bufferLength = bufferLength;
    voice->isStereo = isStereo;
    voice->gainL = gain;
    voice->gainR = gain;
    
    // Reset playback position — atomic store ensures the audio thread
    // sees 0 and not a stale position from a previous voice
    __atomic_store_n(&voice->playbackPosition, 0, __ATOMIC_RELEASE);
    
    // --- Phase 4: Activate the voice ---
    // This MUST be the last store. The release semantics ensure all
    // the above configuration is visible when the audio thread reads
    // isActive == true with acquire semantics.
    atomic_increment_i32(&state->activeVoiceCount);
    atomic_store_bool(&voice->isActive, true);
    
    return slotIndex;
}

// MARK: - Real-Time Render Callback (Audio Thread)

OSStatus haptyk_render_callback(HaptykRenderState *state,
                                 AudioBufferList *outputData,
                                 uint32_t frameCount) {
    // --- Early exit: Muted ---
    // When muted, write silence and skip all voice processing.
    if (__builtin_expect(atomic_load_bool(&state->isMuted), 0)) {
        for (uint32_t buf = 0; buf < outputData->mNumberBuffers; buf++) {
            memset(outputData->mBuffers[buf].mData, 0,
                   outputData->mBuffers[buf].mDataByteSize);
        }
        return noErr;
    }
    
    // Load master volume once per callback invocation.
    // This avoids redundant atomic loads in the inner loop.
    const float masterVol = atomic_load_float(&state->masterVolume);
    
    // Get output buffer pointers.
    // We expect a non-interleaved stereo layout from AVAudioSourceNode:
    // Buffer 0 = Left channel, Buffer 1 = Right channel
    // But we also handle the interleaved case (single buffer with 2 channels).
    float *outLeft  = NULL;
    float *outRight = NULL;
    
    if (outputData->mNumberBuffers >= 2) {
        // Non-interleaved stereo (standard AVAudioSourceNode layout)
        outLeft  = (float *)outputData->mBuffers[0].mData;
        outRight = (float *)outputData->mBuffers[1].mData;
    } else if (outputData->mNumberBuffers == 1) {
        // Single interleaved buffer — we'll write stereo interleaved
        outLeft  = (float *)outputData->mBuffers[0].mData;
        outRight = NULL; // Sentinel: indicates interleaved mode
    } else {
        return noErr;
    }
    
    // --- Zero the output buffer ---
    // We accumulate voice contributions additively, so start from silence.
    if (outRight != NULL) {
        memset(outLeft,  0, frameCount * sizeof(float));
        memset(outRight, 0, frameCount * sizeof(float));
    } else {
        memset(outLeft, 0, outputData->mBuffers[0].mDataByteSize);
    }
    
    // --- Mix all active voices ---
    for (int v = 0; v < HAPTYK_MAX_VOICES; v++) {
        HaptykVoice *voice = &state->voices[v];
        
        // Skip inactive voices.
        // Acquire semantics ensure we see all configuration stores that
        // happened before the release store on isActive.
        if (__builtin_expect(!atomic_load_bool(&voice->isActive), 1)) {
            continue;
        }
        
        // Load voice parameters (set by main thread before isActive=true)
        const float *sampleBuf  = voice->buffer;
        const uint32_t bufLen   = voice->bufferLength;
        const float gL          = voice->gainL * masterVol;
        const float gR          = voice->gainR * masterVol;
        const bool stereo       = voice->isStereo;
        uint32_t pos            = __atomic_load_n(&voice->playbackPosition,
                                                   __ATOMIC_RELAXED);
        
        // Validate buffer pointer — defensive check
        if (__builtin_expect(sampleBuf == NULL, 0)) {
            atomic_store_bool(&voice->isActive, false);
            atomic_decrement_i32(&state->activeVoiceCount);
            continue;
        }
        
        // --- Per-frame mixing loop ---
        if (outRight != NULL) {
            // Non-interleaved stereo output
            if (stereo) {
                // Stereo source → stereo output
                for (uint32_t f = 0; f < frameCount; f++) {
                    if (__builtin_expect(pos >= bufLen, 0)) {
                        // Voice has finished — deactivate
                        atomic_store_bool(&voice->isActive, false);
                        atomic_decrement_i32(&state->activeVoiceCount);
                        break;
                    }
                    
                    // Read interleaved stereo samples: [L0, R0, L1, R1, ...]
                    const uint32_t sampleIdx = pos * 2;
                    const float sL = sampleBuf[sampleIdx];
                    const float sR = sampleBuf[sampleIdx + 1];
                    
                    outLeft[f]  += sL * gL;
                    outRight[f] += sR * gR;
                    
                    pos++;
                }
            } else {
                // Mono source → stereo output (duplicate to both channels)
                for (uint32_t f = 0; f < frameCount; f++) {
                    if (__builtin_expect(pos >= bufLen, 0)) {
                        atomic_store_bool(&voice->isActive, false);
                        atomic_decrement_i32(&state->activeVoiceCount);
                        break;
                    }
                    
                    const float sample = sampleBuf[pos];
                    outLeft[f]  += sample * gL;
                    outRight[f] += sample * gR;
                    
                    pos++;
                }
            }
        } else {
            // Interleaved stereo output (single buffer)
            if (stereo) {
                for (uint32_t f = 0; f < frameCount; f++) {
                    if (__builtin_expect(pos >= bufLen, 0)) {
                        atomic_store_bool(&voice->isActive, false);
                        atomic_decrement_i32(&state->activeVoiceCount);
                        break;
                    }
                    
                    const uint32_t sampleIdx = pos * 2;
                    const uint32_t outIdx    = f * 2;
                    outLeft[outIdx]     += sampleBuf[sampleIdx]     * gL;
                    outLeft[outIdx + 1] += sampleBuf[sampleIdx + 1] * gR;
                    
                    pos++;
                }
            } else {
                for (uint32_t f = 0; f < frameCount; f++) {
                    if (__builtin_expect(pos >= bufLen, 0)) {
                        atomic_store_bool(&voice->isActive, false);
                        atomic_decrement_i32(&state->activeVoiceCount);
                        break;
                    }
                    
                    const float sample = sampleBuf[pos];
                    const uint32_t outIdx = f * 2;
                    outLeft[outIdx]     += sample * gL;
                    outLeft[outIdx + 1] += sample * gR;
                    
                    pos++;
                }
            }
        }
        
        // Update the playback position atomically.
        // Relaxed ordering is sufficient here — the audio thread is the
        // only writer during playback, and the main thread only reads
        // this for voice-stealing heuristics where approximate values
        // are acceptable.
        __atomic_store_n(&voice->playbackPosition, pos, __ATOMIC_RELAXED);
    }
    
    return noErr;
}

// MARK: - Volume & Mute Control (Thread-Safe)

void haptyk_render_set_volume(HaptykRenderState *state, float volume) {
    // Clamp to valid range
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    
    atomic_store_float(&state->masterVolume, volume);
}

void haptyk_render_set_muted(HaptykRenderState *state, bool muted) {
    atomic_store_bool(&state->isMuted, muted);
}
