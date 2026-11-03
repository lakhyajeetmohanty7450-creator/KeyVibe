//
//  SettingsWindow.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Comprehensive Settings Window with Tabs:
//  - General: Permissions, Startup, Power management
//  - Sound: Sound pack browser, master gain, test playback
//  - Velocity Curve: Interactive force threshold calibration
//  - Labs: AutoCAPS on Slam, Vine Boom, Typing metrics
//  - License: 3-day trial countdown, Pro activation ($8 perpetual)
//

import SwiftUI
import AppKit

// MARK: - SettingsWindow View

public struct SettingsWindow: View {
    public init() {}

    public var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            SoundTab()
                .tabItem { Label("Sound Packs", systemImage: "waveform") }

            VelocityTab()
                .tabItem { Label("Force Curve", systemImage: "gauge.with.needle") }

            LabsTab()
                .tabItem { Label("Labs", systemImage: "flask.fill") }

            LicenseTab()
                .tabItem { Label("License", systemImage: "key.fill") }
        }
        .frame(width: 540, height: 420)
        .padding(20)
    }
}

final class GeneralSettingsModel: ObservableObject {
    @Published var hasAccessibility: Bool = KeyboardMonitor.checkAccessibilityPermission()
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            let current = KeyboardMonitor.checkAccessibilityPermission()
            if self?.hasAccessibility != current {
                self?.hasAccessibility = current
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @AppStorage("com.keyvibe.launchAtLogin") private var launchAtLogin = false
    @ObservedObject private var model = GeneralSettingsModel()

    var body: some View {
        Form {
            Section("System Permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: model.hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.hasAccessibility ? .green : .red)
                        Text("Accessibility Permission:")
                        Spacer()
                        if model.hasAccessibility {
                            Text("Granted ✓").foregroundStyle(.green).fontWeight(.semibold)
                        } else {
                            Button("Grant Permission...") {
                                KeyboardMonitor.requestAccessibilityPermission()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if !model.hasAccessibility {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("To hear typing sounds in other apps (VS Code, Word, Chrome):")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("1. Click 'Grant Permission...' above (or open System Settings → Privacy & Security → Accessibility).")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("2. Turn ON the toggle next to KeyVibe.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("3. If KeyVibe is not in the list, click the '+' button and select /Applications/KeyVibe.app.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
                    }
                }
            }

            Section("Hardware Sensor Telemetry") {
                let status = HardwareDetector.checkCompatibility()
                HStack {
                    Text("Chassis Motion Sensor:")
                    Spacer()
                    Text(status.description)
                        .font(.caption)
                        .foregroundStyle(status.isCompatible ? .green : .red)
                }
                HStack {
                    Text("Detected Mac Model:")
                    Spacer()
                    Text(HardwareDetector.getMacModel())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Power Saving") {
                Text("Automatic audio engine sleep is enabled after 3 minutes of keyboard inactivity, keeping CPU usage under 1% and conserving MacBook battery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Sound Tab

struct SoundTab: View {
    @ObservedObject var packManager = SoundPackManager.shared
    @AppStorage("com.keyvibe.masterVolume") private var volume: Double = 0.8
    @AppStorage("com.keyvibe.isMuted") private var isMuted: Bool = false

    var body: some View {
        Form {
            Section("Active Switch Profile") {
                Picker("Switch:", selection: Binding(
                    get: { packManager.selectedPack?.id ?? "cherry-mx-blue" },
                    set: { packManager.selectPack(byId: $0) }
                )) {
                    ForEach(packManager.availablePacks) { pack in
                        Text("\(pack.name) (\(pack.category.rawValue))").tag(pack.id)
                    }
                }

                if let current = packManager.selectedPack {
                    Text(current.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Volume & Master Output") {
                Slider(value: $volume, in: 0...1) {
                    Text("Master Volume: \(Int(volume * 100))%")
                }
                Toggle("Mute Audio", isOn: $isMuted)
            }
        }
        .padding()
    }
}

// MARK: - Velocity Tab

struct VelocityTab: View {
    @AppStorage("com.keyvibe.sensitivity") private var sensitivity: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Force Spectrum Thresholds")
                .font(.headline)

            Text("Calibrate how accelerometer vibration magnitude maps to mechanical sound velocity tiers.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                TierBar(title: "Soft (Brushes)", threshold: Constants.ForceTiers.softThreshold, color: .green)
                TierBar(title: "Medium (Normal)", threshold: Constants.ForceTiers.mediumThreshold, color: .blue)
                TierBar(title: "Hard (Bottom-Out)", threshold: Constants.ForceTiers.hardThreshold, color: .orange)
                TierBar(title: "Slam (Maximum Impact)", threshold: Constants.ForceTiers.slamThreshold, color: .red)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            Divider()

            HStack {
                Text("Global Sensitivity:")
                Slider(value: $sensitivity, in: 0...1)
                Text("\(Int(sensitivity * 100))%")
            }
        }
        .padding()
    }
}

struct TierBar: View {
    let title: String
    let threshold: Double
    let color: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .frame(width: 140, alignment: .leading)
            ProgressView(value: threshold, total: 1.5)
                .tint(color)
            Text(String(format: "%.2f G", threshold))
                .font(.caption2)
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
        }
    }
}

// MARK: - Labs Tab

struct LabsTab: View {
    @AppStorage("com.keyvibe.autoCapsEnabled") private var autoCaps = false
    @AppStorage("com.keyvibe.vineBoomEnabled") private var vineBoom = false
    @AppStorage("com.keyvibe.typingMetricsEnabled") private var metrics = true

    var body: some View {
        Form {
            Section("Interactive Force Extensions") {
                Toggle("AutoCAPS on Slam", isOn: $autoCaps)
                Text("Typing a key with slam-level force automatically emits UPPERCASE letters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Vine Boom on Enter Slam", isOn: $vineBoom)
                Text("Slamming the Return key triggers an iconic Vine Boom sound effect instead of a key click.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy-Preserving Local Metrics") {
                Toggle("Enable Local Typing Metrics", isOn: $metrics)
                Text("Calculates daily key counts, typing speed (taps per minute), and force percentiles. All metrics stay strictly in RAM and are never recorded to disk or sent over network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - License Tab

final class LicenseTabModel: ObservableObject {
    @Published var emailInput: String = ""
    @Published var keyInput: String = ""
    @Published var alertMessage: String?
}

struct LicenseTab: View {
    @ObservedObject var licenseManager = LicenseManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("License & Edition")
                .font(.headline)

            HStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("KeyVibe Community Edition")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("100% Free & Open. All Pro features and 16 sound profiles are permanently unlocked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("Unlocked Features", systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("All 16 authentic mechanical switch sound profiles")
                        .font(.caption)
                }
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Custom force curve & sensitivity calibration")
                        .font(.caption)
                }
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("System-wide typing audio across all apps")
                        .font(.caption)
                }
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Labs features (Vine Boom mode, Auto-Caps on Slam)")
                        .font(.caption)
                }
            }
            .padding(.top, 4)
        }
        .padding()
    }
}

