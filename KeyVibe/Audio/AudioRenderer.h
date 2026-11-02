//
//  AudioRenderer.h
//  Haptyk
//
//  Real-time audio render callback for velocity-sensitive keyboard sounds.
//
//  This header defines the data structures and functions for the real-time
//  audio rendering pipeline. All functions called from the render thread
//  are designed to be lock-free and allocation-free.
//
//  Thread Safety:
//  - haptyk_render_callback: Called on the real-time audio thread (CoreAudio IOProc)
//  - haptyk_render_trigger_voice: Called from the main thread
//  - Shared state is synchronized using C11 atomic operations
//
//  Copyright © 2024 Haptyk. All rights reserved.
//

#ifndef AudioRenderer_h
#define AudioRenderer_h

#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>
#include <stdbool.h>

// MARK: - Constants

/// Maximum number of simultaneous voice playback slots.
/// 64 voices provides massive polyphony for simultaneous key presses,
/// fast typing rolls, and overlapping press/release samples without voice stealing.
#define HAPTYK_MAX_VOICES 64

// MARK: - Voice State

/// Single voice playback state.
///
/// Each voice represents one active sound being played back. Voices are
/// triggered from the main thread and consumed by the audio render thread.
/// The `isActive` flag serves as the synchronization point between threads.
typedef struct {
    const float *buffer;        ///< Pointer to PCM sample data (interleaved stereo or mono)
    uint32_t bufferLength;      ///< Total frames in the buffer
    uint32_t playbackPosition;  ///< Current read position (in frames)
    float gainL;                ///< Left channel gain (includes crossfade weight)
    float gainR;                ///< Right channel gain
    bool isActive;              ///< Whether this voice is currently playing
    bool isStereo;              ///< true = interleaved stereo source, false = mono
} HaptykVoice;

// MARK: - Render State

/// Global render state — accessed from both main and real-time audio threads.
///
/// This struct is the single shared data structure between the main application
/// thread and the CoreAudio render thread. All fields that are written from
/// one thread and read from another use atomic operations.
typedef struct {
    HaptykVoice voices[HAPTYK_MAX_VOICES]; ///< Voice pool for polyphonic playback
    float masterVolume;         ///< Master output volume, 0.0 – 1.0
    bool isMuted;               ///< Global mute state
    uint32_t sampleRate;        ///< Audio sample rate (e.g., 44100 or 48000)
    int32_t activeVoiceCount;   ///< Atomic counter of currently playing voices
} HaptykRenderState;

// MARK: - API Functions

/// Initialize the render state to safe defaults.
///
/// Must be called before any other render function. Sets all voices to inactive,
/// master volume to 1.0, and configures the sample rate.
///
/// @param state   Pointer to the render state to initialize.
/// @param sampleRate  The audio sample rate (e.g., 44100 or 48000).
void haptyk_render_init(HaptykRenderState *state, uint32_t sampleRate);

/// Trigger a new voice for playback.
///
/// Called from the main thread when a key event occurs. Finds the first
/// available (inactive) voice slot and configures it for playback. If all
/// slots are occupied, steals the voice with the highest playback position
/// (closest to completion).
///
/// Thread Safety: Uses atomic stores for the isActive flag to ensure
/// visibility on the audio render thread.
///
/// @param state       Pointer to the global render state.
/// @param buffer      Pointer to interleaved Float32 PCM data. Must remain
///                    valid for the duration of playback.
/// @param bufferLength Number of frames in the buffer.
/// @param gain        Playback gain (typically 0.0 – 1.0 from crossfade weight).
/// @param isStereo    true if buffer contains interleaved stereo data.
/// @return The voice slot index (0 – HAPTYK_MAX_VOICES-1), or -1 on failure.
int haptyk_render_trigger_voice(HaptykRenderState *state,
                                 const float *buffer,
                                 uint32_t bufferLength,
                                 float gain,
                                 bool isStereo);

/// Real-time audio render callback — fills the output buffer with mixed audio.
///
/// This is the HOT PATH. Called on the CoreAudio I/O thread at regular intervals.
/// Mixes all active voices into the output buffer with per-voice gain and
/// master volume applied.
///
/// @warning This function MUST NOT:
/// - Allocate or free memory (malloc, free, new, delete)
/// - Acquire locks or mutexes
/// - Perform file or network I/O
/// - Call Objective-C runtime functions (objc_msgSend)
/// - Call printf, NSLog, or any logging function
/// - Do anything that could cause a priority inversion or page fault
///
/// @param state       Pointer to the global render state.
/// @param outputData  CoreAudio buffer list to fill with rendered audio.
/// @param frameCount  Number of frames to render.
/// @return noErr on success.
OSStatus haptyk_render_callback(HaptykRenderState *state,
                                 AudioBufferList *outputData,
                                 uint32_t frameCount);

/// Set the master output volume.
///
/// Thread-safe via atomic write. Takes effect on the next render callback
/// invocation.
///
/// @param state   Pointer to the global render state.
/// @param volume  New volume level, clamped to 0.0 – 1.0.
void haptyk_render_set_volume(HaptykRenderState *state, float volume);

/// Set the global mute state.
///
/// Thread-safe via atomic write. When muted, the render callback writes
/// silence without processing voices (saving CPU).
///
/// @param state   Pointer to the global render state.
/// @param muted   true to mute, false to unmute.
void haptyk_render_set_muted(HaptykRenderState *state, bool muted);

#endif /* AudioRenderer_h */
