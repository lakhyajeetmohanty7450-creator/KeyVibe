//
//  MainWindowView.swift
//  KeyVibe
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 KeyVibe. All rights reserved.
//
//  Interactive main dashboard for KeyVibe:
//  - Real-time switch profile selection across 16 authentic mechanical switches
//  - Interactive typing test area with live force tier meter
//  - Volume and sensitivity calibration
//  - Comprehensive features showcase and Labs toggles (AutoCAPS, Vine Boom)
//  - System-wide hardware monitoring status
//

import SwiftUI

final class TestTypingModel: ObservableObject {
    @Published var testText: String = ""
    @Published var lastForceTier: String = "Medium"
    @Published var lastForceMagnitude: Double = 0.45
}

public struct MainWindowView: View {
    @ObservedObject var soundPackManager = SoundPackManager.shared
    @AppStorage("com.keyvibe.selectedSoundPack") private var selectedSoundPackID: String = "cherry-mx-blue"
    @AppStorage("com.keyvibe.masterVolume") private var volume: Double = 0.8
    @AppStorage("com.keyvibe.sensitivity") private var sensitivity: Double = 0.5
    @AppStorage("com.keyvibe.isMuted") private var isMuted: Bool = false
    @AppStorage("com.keyvibe.autoCapsEnabled") private var autoCapsEnabled: Bool = false
    @AppStorage("com.keyvibe.vineBoomEnabled") private var vineBoomEnabled: Bool = false
    @AppStorage("keyvibe.isProUser") private var isProUser: Bool = true

    @ObservedObject var metrics = TypingMetrics.shared
    @ObservedObject private var testModel = TestTypingModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(alignment: .center) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("KeyVibe")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("COMMUNITY EDITION · 100% FREE")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundStyle(.green)
                    }

                    Text("Velocity-Sensitive Mechanical Keyboard Sound Utility for macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(isMuted ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(isMuted ? "Muted" : "Active Across All Apps")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.quaternary))
            }

            // Feature Badges Banner
            HStack(spacing: 8) {
                featureBadge(icon: "waveform.path", title: "16 Switch Profiles", desc: "All Free")
                featureBadge(icon: "speaker.wave.3.fill", title: "64-Voice Polyphony", desc: "Zero Lag Chords")
                featureBadge(icon: "macbook.gen2", title: "Chassis Accelerometer", desc: "1 kHz Sensing")
                featureBadge(icon: "globe", title: "Universal Tap", desc: "VS Code, Word, Chrome")
            }

            Divider()

            // Main controls grid
            HStack(alignment: .top, spacing: 20) {
                // Left Column: Switch & Audio Configuration
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Mechanical Switch Profile", systemImage: "waveform")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        SoundPackPicker(selectedPackID: $selectedSoundPackID)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        VolumeSliderView(
                            volume: Binding(
                                get: { Float(volume) },
                                set: { volume = Double($0) }
                            ),
                            isMuted: $isMuted
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SensitivityView(
                            sensitivity: Binding(
                                get: { Float(sensitivity) },
                                set: { sensitivity = Double($0) }
                            ),
                            isProUser: isProUser
                        )
                    }

                    // Interactive Labs Features
                    VStack(alignment: .leading, spacing: 8) {
                        Label("KeyVibe Labs Features", systemImage: "flask.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        HStack {
                            Toggle("AutoCAPS on Slam", isOn: $autoCapsEnabled)
                                .font(.caption)
                                .onChange(of: autoCapsEnabled) { _, val in
                                    LabsManager.shared.autoCaps.isEnabled = val
                                    Preferences.autoCapsEnabled = val
                                }

                            Spacer()

                            Toggle("Vine Boom on Enter Slam", isOn: $vineBoomEnabled)
                                .font(.caption)
                                .onChange(of: vineBoomEnabled) { _, val in
                                    LabsManager.shared.vineBoom.isEnabled = val
                                    Preferences.vineBoomEnabled = val
                                }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Right Column: Interactive typing test & Live Meter
                VStack(alignment: .leading, spacing: 12) {
                    Label("Live Typing Test & Telemetry", systemImage: "text.cursor")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("Test your typing velocity and simultaneous multi-key chords below:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $testModel.testText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 95)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))

                    // Live force meter
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Current Force Tier:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(metrics.todayKeyCount > 0 ? (UserDefaults.standard.string(forKey: "com.keyvibe.todayAvgForce") ?? "Medium") : "Medium (Ready)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(tierColor)
                            Spacer()
                            Text("\(metrics.todayKeyCount) keys typed today")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: min(1.5, max(0.45, metrics.todayMaxForce)), total: 1.5)
                            .tint(tierColor)

                        HStack {
                            Text("Soft")
                                .font(.system(size: 9))
                                .foregroundStyle(.green)
                            Spacer()
                            Text("Medium")
                                .font(.system(size: 9))
                                .foregroundStyle(.blue)
                            Spacer()
                            Text("Hard")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Spacer()
                            Text("Slam")
                                .font(.system(size: 9))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            // Footer / status
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("KeyVibe listens globally in background. You can safely close this window anytime.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Settings...") {
                    SettingsWindowController.shared.showWindow()
                }
                .font(.caption)

                Button("Quit KeyVibe") {
                    NSApp.terminate(nil)
                }
                .font(.caption)
            }
        }
        .padding(20)
        .frame(width: 740, height: 490)
        .onAppear {
            LabsManager.shared.autoCaps.isEnabled = autoCapsEnabled
            LabsManager.shared.vineBoom.isEnabled = vineBoomEnabled
        }
    }

    private func featureBadge(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                Text(desc)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
    }

    private var tierColor: Color {
        let tier = UserDefaults.standard.string(forKey: "com.keyvibe.todayAvgForce") ?? "Medium"
        switch tier.lowercased() {
        case "soft": return .green
        case "medium": return .blue
        case "hard": return .orange
        case "slam": return .red
        default: return .blue
        }
    }
}
