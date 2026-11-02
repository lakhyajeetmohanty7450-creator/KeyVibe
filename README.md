# Haptyk: Velocity-Sensitive Mechanical Keyboard Sound Utility for macOS

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-orange" alt="Architecture">
  <img src="https://img.shields.io/badge/Language-Swift%205.9%20%2B%20C11-red" alt="Language">
  <img src="https://img.shields.io/badge/Latency-%3C%201%20ms-brightgreen" alt="Latency">
  <img src="https://img.shields.io/badge/License-MIT-purple" alt="License">
</p>

**Haptyk** is a native macOS menu bar sound engine that measures keystroke force using the hidden MEMS chassis accelerometer embedded in Apple Silicon MacBooks. By correlating global key event timestamps with high-frequency chassis vibration telemetry at ~1,000 Hz, Haptyk classifies typing intensity across a 4-tier spectrum and crossfades between acoustic mechanical switch recordings in real time.

---

## Technical Architecture Overview

```
                      ┌───────────────────────────────────────────────┐
                      │    Apple Silicon Hardware Telemetry Layer     │
                      │  Internal SPU MEMS Accelerometer @ 1,000 Hz   │
                      └───────────────────────┬───────────────────────┘
                                              │ (x, y, z vectors @ 1 kHz)
                                              ▼
                      ┌───────────────────────────────────────────────┐
                      │    Lock-Free Circular Ring Buffer (2048)      │
                      │   Monotonic mach_absolute_time indexing       │
                      └───────────────────────┬───────────────────────┘
                                              │
┌───────────────────────────┐                 │ Temporal Correlation Window
│   CGEventTap Global Keys  │                 │ (10 ms sliding window)
│ (.keyDown / .keyUp HID)   │                 ▼
└─────────────┬─────────────┘    ┌────────────────────────────────────┐
              └─────────────────▶│     Velocity Correlation Engine    │
                                 │ Peak Delta: M = sqrt(dx²+dy²+dz²) │
                                 └─────────────────┬──────────────────┘
                                                   │
                                                   ▼
                                 ┌────────────────────────────────────┐
                                 │     Force Tier Classification      │
                                 │ Soft (0.15G) ── Medium (0.45G)     │
                                 │ Hard (0.75G) ── Slam (1.20G)       │
                                 └─────────────────┬──────────────────┘
                                                   │
                                                   ▼
                                 ┌────────────────────────────────────┐
                                 │   Linear Audio Gain Crossfader     │
                                 │ Proportional adjacent-tier weights │
                                 └─────────────────┬──────────────────┘
                                                   │
                                                   ▼
                                 ┌────────────────────────────────────┐
                                 │   High-Priority Core Audio Engine  │
                                 │ AVAudioSourceNode + C Render Loop  │
                                 │ Polyphonic uncompressed PCM in RAM │
                                 └─────────────────┬──────────────────┘
                                                   │ (< 1 ms latency)
                                                   ▼
                                 ┌────────────────────────────────────┐
                                 │  Hardware Speaker / Headphone Out  │
                                 └────────────────────────────────────┘
```

---

## Core Pipeline Implementation

### 1. Hardware Telemetry Layer (`AccelerometerManager.swift`)
- Discovers the internal Apple SPU motion sensor via private IOKit HID channels (`IOHIDManagerCreate`).
- Subscribes to value callbacks delivered at ~1,000 Hz on a dedicated `QOS_CLASS_USER_INTERACTIVE` background thread.
- Scales 16-bit integer sensor values into standard G-force vectors.
- Buffers samples in a pre-allocated circular ring buffer (`RingBuffer.swift`) using branchless bitmask indexing.
- Dynamically self-calibrates resting chassis baseline vectors (gravity offset subtraction).

### 2. Keystroke Interception & Privacy (`KeyboardMonitor.swift`, `KeyMapper.swift`)
- Uses `CGEvent.tapCreate()` at `.cghidEventTap` level with required Accessibility authorization.
- Captures virtual key codes (`kVK_ANSI_*`) and entry-time `mach_absolute_time()` timestamps.
- **Strict Privacy**: Textual character content, passwords, or strings are **never** inspected, recorded, logged, stored on disk, or transmitted over network.

### 3. Velocity Correlation Engine (`VelocityEngine.swift`, `CrossfadeCalculator.swift`)
- Computes vector magnitude delta $M = \sqrt{(x - x_0)^2 + (y - y_0)^2 + (z - z_0)^2}$ within a 10 ms window centered on key impact.
- Classifies force across four discrete tiers:
  - **Soft** ($< 0.45\,\text{G}$): Light keystroke or quiet brush.
  - **Medium** ($0.45 - 0.75\,\text{G}$): Normal mechanical typing baseline.
  - **Hard** ($0.75 - 1.20\,\text{G}$): Forceful, intended bottom-out strike.
  - **Slam** ($\ge 1.20\,\text{G}$): Heavy impact strike (triggers Labs features).
- Calculates real-time linear crossfade gain weights ($W_{\text{lower}} + W_{\text{upper}} = 1.0$) between adjacent recording layers to eliminate stepped volume transitions.

### 4. Low-Latency Real-Time Audio Engine (`AudioRenderer.c`, `AudioEngine.swift`)
- Native C11 lock-free, allocation-free mixing loop running inside Core Audio's `AVAudioSourceNode` IOProc.
- Polyphonic pool of 8 simultaneous voices with automatic oldest-voice stealing.
- In-memory RAM caching (`SampleBank.swift`) of uncompressed 32-bit float PCM buffers (0 ms disk latency).
- Automatic power management: suspends Core Audio thread after 3 minutes of keyboard inactivity, keeping overall CPU usage under 1%.

---

## 16 Mechanical Switch Profiles Included

| Category | Switch Profile | Acoustic Character |
|:---|:---|:---|
| **Clicky** | **Cherry MX Blue PBT** | Sharp, crisp tactile actuation snap |
| | **Kailh Box Navy** | Heavy click-bar with maximum acoustic volume |
| | **Blue Alps** | Vintage metallic resonance and complex multi-tonal click |
| **Tactile & Thocky** | **Holy Panda** | Prominent tactile bump with resonant bottom-out thock |
| | **Topre PBT** | Electrostatic capacitive warm housing thump |
| | **Biscuit Tactile** | Default warm, balanced tactile sound pack |
| | **Cherry MX Brown** | Subtle tactile bump with gentle clack |
| **Linear** | **Gateron Red Ink V2** | Premium smoky housing with deep bottom-out tone |
| | **Gateron Black Ink** | Heavy linear spring with muted clack |
| | **Gateron Milky Yellow** | Creamy, buttery-smooth linear acoustics |
| | **NK Cream** | Unique full-POM housing high-pitched bottom out |
| | **NovelKeys Cream Lubed** | Hand-lubed POM switch with deep plush sound |
| | **Alpaca V2** | Clean nylon/polycarbonate pop |
| | **Turquoise Tealios** | Bright, precise clack with polished stem travel |
| | **Cherry MX Red** | Lightweight, snappy linear actuation |
| **Vintage** | **IBM Buckling Spring** | Iconic Model M ringing spring ping and chassis resonance |

---

## "Labs" Interactive Extensions

1. **AutoCAPS on Slam**: Typing a letter with slam-level force automatically injects a Shift modifier into the system stream, converting intense typing into UPPERCASE formatting.
2. **Vine Boom Mode**: Slamming the Enter key triggers a deep, thunderous 808 sub-bass drop sound effect instead of a key click.
3. **Local Typing Metrics**: In-memory rolling window tracking taps per minute (TPM), daily key counts, and force percentiles comparing your typing force against baseline averages.

---

## Hardware Compatibility Matrix

| MacBook Model Series | Processor Architecture | Motion Sensor | Status |
|:---|:---|:---|:---|
| MacBook Pro 14" & 16" | M1 Pro/Max, M2, M3, M4, M5+ | Present | **Fully Supported** |
| MacBook Air 13" & 15" | M2, M3, M4+ | Present | **Fully Supported** |
| MacBook Pro 13" | M2 | Present | **Fully Supported** |
| MacBook Air & Pro 13" | M1 (Base) | Absent | *Unsupported (Medium Fallback)* |
| Intel MacBooks | Core i5 / i7 / i9 | Absent | *Unsupported (Medium Fallback)* |
| Desktop Macs (mini/Studio/Pro) | All architectures | Absent | *Unsupported (Medium Fallback)* |

*Fallback Note: When running on unsupported hardware, in clamshell mode, or when using an external desktop keyboard, Haptyk automatically falls back to consistent medium-tier mechanical sound playback without crashing.*

---

## Building and Running

### Build from Terminal
```bash
cd Haptyk
./build.sh
```

### Run Application Bundle
```bash
open build/Haptyk.app
```

### Grant Accessibility Permission
On first launch, macOS will request Accessibility access (`System Settings` → `Privacy & Security` → `Accessibility`). Grant access to enable the system-wide `CGEventTap`.

---

## Commercial & Licensing Architecture

- **3-Day Free Trial**: Full, unrestricted access to all 16 sound packs and velocity detection upon initial installation.
- **Pro License**: \$8 one-time purchase (no recurring subscriptions) providing custom force curve sensitivity calibration and Labs features.
- Stored securely in macOS Keychain with salted SHA-256 date tamper detection.

