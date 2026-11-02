//
//  MainWindowView.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Interactive main dashboard for Haptyk:
//  - Real-time switch profile selection
//  - Interactive typing test area with live force tier meter
//  - Volume and sensitivity calibration
//  - Permissions and hardware status
//

import SwiftUI

final class TestTypingModel: ObservableObject {
    @Published var testText: String = ""
    @Published var lastForceTier: String = "Medium"
    @Published var lastForceMagnitude: Double = 0.45
}

public struct MainWindowView: View {
    @ObservedObject var soundPackManager = SoundPackManager.shared
    @AppStorage("haptyk.selectedSoundPack") private var selectedSoundPackID: String = "cherry-mx-blue"
    @AppStorage("haptyk.volume") private var volume: Double = 0.75
    @AppStorage("haptyk.sensitivity") private var sensitivity: Double = 0.5
    @AppStorage("haptyk.isMuted") private var isMuted: Bool = false
    @AppStorage("haptyk.autoCapsOnSlam") private var autoCapsOnSlam: Bool = false
    @AppStorage("haptyk.vineBoomMode") private var vineBoomMode: Bool = false
    @AppStorage("haptyk.isProUser") private var isProUser: Bool = true

    @ObservedObject var metrics = TypingMetrics.shared
    @ObservedObject private var testModel = TestTypingModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("KeyVibe")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Velocity-Sensitive Mechanical Keyboard Sound Utility")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(isMuted ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(isMuted ? "Muted" : "Active & Listening")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.quaternary))
            }

            Divider()

            // Main controls grid
            HStack(alignment: .top, spacing: 24) {
                // Left Column: Sound controls
                VStack(alignment: .leading, spacing: 16) {
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
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Right Column: Interactive typing test & Live Meter
                VStack(alignment: .leading, spacing: 14) {
                    Label("Live Typing Test Area", systemImage: "text.cursor")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("Type below to feel real-time sound playback and test your typing velocity:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $testModel.testText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 90)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))

                    // Live force meter
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Last Impact:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(metrics.todayKeyCount > 0 ? (UserDefaults.standard.string(forKey: "haptyk.todayAvgForce") ?? "Medium") : "Waiting for keystroke...")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(tierColor)
                            Spacer()
                            Text("\(metrics.todayKeyCount) keys typed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: min(1.5, metrics.todayMaxForce), total: 1.5)
                            .tint(tierColor)
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
                    Text("Runs in Menu Bar. You can safely close this window anytime.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open Settings...") {
                    SettingsWindowController.shared.showWindow()
                }
                .font(.caption)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .font(.caption)
            }
        }
        .padding(24)
        .frame(width: 680, height: 420)
    }

    private var tierColor: Color {
        let tier = UserDefaults.standard.string(forKey: "haptyk.todayAvgForce") ?? "Medium"
        switch tier.lowercased() {
        case "soft": return .green
        case "medium": return .blue
        case "hard": return .orange
        case "slam": return .red
        default: return .blue
        }
    }
}
