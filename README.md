# KeyVibe: Velocity-Sensitive Mechanical Keyboard Sound Utility for macOS

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-orange" alt="Architecture">
  <img src="https://img.shields.io/badge/Language-Swift%205.9%20%2B%20C11-red" alt="Language">
  <img src="https://img.shields.io/badge/Latency-%3C%200.5%20ms-brightgreen" alt="Latency">
  <img src="https://img.shields.io/badge/Polyphony-64%20Voices-blueviolet" alt="Polyphony">
  <img src="https://img.shields.io/badge/License-Community%20Edition%20(100%25%20Free)-green" alt="License">
</p>

**KeyVibe** is a native macOS application and menu bar sound utility that transforms your typing experience into an authentic mechanical keyboard. It dynamically measures physical keystroke impact force using the MEMS chassis accelerometer embedded in Apple Silicon MacBooks.

By correlating global key event timestamps with high-frequency chassis vibration telemetry at ~1,000 Hz, KeyVibe classifies typing intensity across a 4-tier spectrum (Soft, Medium, Hard, Slam) and crossfades between acoustic mechanical switch recordings in real time.

---

## ✨ Features

- **🎹 16 Authentic Mechanical Switch Profiles (100% Free & Unlocked):**
  - **Cherry MX Blue:** Classic tactile clicky switch with sharp snap
  - **Cherry MX Red:** Silky smooth, light linear switch
  - **Cherry MX Brown:** Balanced tactile bump for everyday typing
  - **Holy Panda:** Highly coveted deep, round, tactile "thock"
  - **Gateron Ink Black:** Premium deep acoustic profile with smooth glide
  - **Topre 45g:** Electrostatic capacitive dome with plush PBT bottom-out
  - **IBM Model M:** Vintage 1980s buckling spring with metallic reverberation
  - **NovelKeys Cream:** Full POM housing with custom signature acoustic clack
  - **Kailh Box White:** Crisp click-bar mechanism
  - **Alpaca Linear:** Smooth factory-lubricated linear
  - **Zealios V2 67g:** Ultra-crisp, pronounced high-tactile bump
  - **Boba U4T:** Deep, muted tactile sound with solid bottom-out
  - **Gateron Yellow:** Popular buttery smooth mid-weight linear
  - **TTC Gold Pink:** Featherlight linear switch
  - **Cherry MX Black:** Classic stiff linear switch
  - **Everglide Aqua King:** Crystal polycarbonate housing linear
- **⚡ 64-Voice Multi-Key Polyphony Engine:**
  - Simultaneous chords, rollover typing, and overlapping press/release samples without audio dropouts or voice stealing.
- **🌐 Universal System-Wide Keystroke Interception:**
  - Operates globally with sub-millisecond latency (`< 0.5 ms`) across **VS Code**, **Microsoft Word**, **Google Chrome**, **Terminal**, **Notes**, and any application.
- **🎯 Real-Time Chassis Accelerometer & Velocity Engine:**
  - Samples Apple Silicon chassis MEMS accelerometer at 1,000 Hz.
  - Dynamically classifies strikes into **Soft**, **Medium**, **Hard**, and **Slam**.
  - Smooth dynamic crossfading between neighboring audio samples based on physical impact.
- **🧪 KeyVibe Experimental Labs:**
  - **AutoCAPS on Slam:** Automatically types in uppercase when striking a letter with slam force.
  - **Vine Boom on Enter:** Triggers a deep, thunderous sub-bass drop when hitting Enter hard.
  - **Daily Typing Insights:** Live metrics tracking daily keystroke counts, average impact force, and peak Gs.
- **🛡️ Strict Keystroke Privacy:**
  - Zero key logging. Only numeric virtual key codes are mapped to acoustic categories; characters are never inspected, stored, or transmitted.

---

## 🚀 Building & Running

```bash
# Build KeyVibe.app
./build.sh

# Install into /Applications
cp -R build/KeyVibe.app /Applications/

# Launch
open /Applications/KeyVibe.app
```
