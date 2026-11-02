//
//  MenuBarView.swift
//  Haptyk
//
//  Main SwiftUI view displayed inside the menu bar popover.
//  Provides the primary interface for controlling Haptyk: sound pack selection,
//  volume and sensitivity adjustment, feature toggles, and quick access to
//  settings and diagnostics.
//
//  Layout Structure:
//  ┌──────────────────────────┐
//  │ Header (name + status)   │
//  ├──────────────────────────┤
//  │ Sound Pack Selector      │
//  ├──────────────────────────┤
//  │ Volume Slider            │
//  │ Sensitivity Slider (Pro) │
//  ├──────────────────────────┤
//  │ Quick Toggles            │
//  ├──────────────────────────┤
//  │ Labs (collapsible)       │
//  ├──────────────────────────┤
//  │ Footer (version, quit)   │
//  └──────────────────────────┘
//
//  Created for Haptyk — a velocity-sensitive mechanical keyboard sound engine.
//  Copyright © 2024 Haptyk. All rights reserved.
//

import SwiftUI

// MARK: - MenuBarView

/// The primary content view for the Haptyk menu bar popover.
///
/// Displays all key controls in a compact, vertically-stacked layout
/// optimized for popover presentation. All settings are persisted via
/// `@AppStorage` backed by `UserDefaults`.
struct MenuBarView: View {

    // MARK: - State & Storage

    /// Current volume level (0.0–1.0).
    @AppStorage("haptyk.volume") private var volume: Double = 0.75

    /// Current sensitivity value (0.0–1.0).
    @AppStorage("haptyk.sensitivity") private var sensitivity: Double = 0.5

    /// Whether sound output is muted.
    @AppStorage("haptyk.isMuted") private var isMuted: Bool = false

    /// Whether AutoCAPS on Slam is enabled.
    @AppStorage("haptyk.autoCapsOnSlam") private var autoCapsOnSlam: Bool = false

    /// Whether Vine Boom Mode is enabled.
    @AppStorage("haptyk.vineBoomMode") private var vineBoomMode: Bool = false

    /// Whether typing metrics collection is active.
    @AppStorage("haptyk.typingMetrics") private var typingMetricsEnabled: Bool = true

    /// The identifier of the currently selected sound pack.
    @AppStorage("haptyk.selectedSoundPack") private var selectedSoundPackID: String = "cherry-mx-blue"

    /// Whether the user has a Pro license.
    @AppStorage("haptyk.isProUser") private var isProUser: Bool = true

    /// Whether the Labs section is expanded.
    @AppStorage("haptyk.isLabsExpanded") private var isLabsExpanded: Bool = false

    /// Whether the app is actively monitoring keyboard input.
    @AppStorage("haptyk.isListening") private var isListening: Bool = true

    /// Today's total key press count (read from typing metrics).
    @AppStorage("haptyk.todayKeyCount") private var todayKeyCount: Int = 0

    /// Today's average force tier as a descriptive string.
    @AppStorage("haptyk.todayAvgForce") private var todayAvgForce: String = "Medium"

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            Divider()
            soundPackSection
            Divider()
            volumeSection
            sensitivitySection
            Divider()
            togglesSection
            Divider()
            labsSection
            Divider()
            footerSection
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Header Section

    /// Displays the app name, version, and current listening status.
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("KeyVibe")
                    .font(.headline)
                    .fontWeight(.bold)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            // Listening status indicator
            statusIndicator
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("KeyVibe, \(statusText)")
    }

    /// Descriptive text for the current app status.
    private var statusText: String {
        if isMuted {
            return "Muted"
        } else if isListening {
            return "Listening"
        } else {
            return "Paused"
        }
    }

    /// Color for the status indicator dot and text.
    private var statusColor: Color {
        if isMuted {
            return .orange
        } else if isListening {
            return .green
        } else {
            return .secondary
        }
    }

    /// A small animated status indicator dot.
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .shadow(color: statusColor.opacity(0.5), radius: 3, x: 0, y: 0)
            .accessibilityHidden(true)
    }

    // MARK: - Sound Pack Section

    /// Sound pack selection picker with category icon.
    private var soundPackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sound Pack", systemImage: "waveform")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            SoundPackPicker(selectedPackID: $selectedSoundPackID)
        }
    }

    // MARK: - Volume Section

    /// Volume control slider with dynamic speaker icon.
    private var volumeSection: some View {
        VolumeSliderView(
            volume: Binding(
                get: { Float(volume) },
                set: { volume = Double($0) }
            ),
            isMuted: $isMuted,
            onVolumeChanged: { newVolume in
                // Volume changes are persisted automatically via @AppStorage
                _ = newVolume
            }
        )
    }

    // MARK: - Sensitivity Section

    /// Force curve sensitivity slider (Pro feature).
    private var sensitivitySection: some View {
        SensitivityView(
            sensitivity: Binding(
                get: { Float(sensitivity) },
                set: { sensitivity = Double($0) }
            ),
            isProUser: isProUser,
            onSensitivityChanged: { newSensitivity in
                // Sensitivity changes are persisted automatically via @AppStorage
                _ = newSensitivity
            }
        )
    }

    // MARK: - Toggles Section

    /// Quick toggle switches for key features.
    private var togglesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quick Toggles", systemImage: "switch.2")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            toggleRow(
                title: "Mute",
                icon: "speaker.slash.fill",
                isOn: $isMuted,
                help: "Silence all keyboard sounds"
            )

            toggleRow(
                title: "AutoCAPS on Slam",
                icon: "textformat.characters.uppercase",
                isOn: $autoCapsOnSlam,
                help: "Automatically capitalize when typing with high force"
            )

            toggleRow(
                title: "Vine Boom Mode",
                icon: "bolt.fill",
                isOn: $vineBoomMode,
                help: "Play the iconic boom sound on slam-force keystrokes"
            )

            toggleRow(
                title: "Typing Metrics",
                icon: "chart.bar.fill",
                isOn: $typingMetricsEnabled,
                help: "Track keystroke count and average typing force"
            )

            // Show metrics summary if enabled
            if typingMetricsEnabled {
                metricsSummaryRow
            }
        }
    }

    /// A reusable toggle row with icon, label, and accessibility support.
    ///
    /// - Parameters:
    ///   - title: The display title for the toggle.
    ///   - icon: SF Symbol name for the row icon.
    ///   - isOn: Binding to the toggle state.
    ///   - help: Accessibility help description.
    private func toggleRow(
        title: String,
        icon: String,
        isOn: Binding<Bool>,
        help: String
    ) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: icon)
                .font(.callout)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .accessibilityLabel(title)
        .accessibilityHint(help)
    }

    /// Shows today's typing statistics in a compact row.
    private var metricsSummaryRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "number")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(todayKeyCount)")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("keys today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "gauge.medium")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Avg:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(todayAvgForce)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(forceColor(for: todayAvgForce))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today: \(todayKeyCount) keys, average force \(todayAvgForce)")
    }

    /// Returns a color corresponding to the force tier name.
    private func forceColor(for force: String) -> Color {
        switch force.lowercased() {
        case "soft": return .green
        case "medium": return .blue
        case "hard": return .orange
        case "slam": return .red
        default: return .primary
        }
    }

    // MARK: - Labs Section

    /// Collapsible section for experimental features.
    private var labsSection: some View {
        DisclosureGroup(isExpanded: $isLabsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                labsFeatureRow(
                    title: "Haptic Feedback",
                    description: "Trigger trackpad haptics on key press",
                    icon: "hand.tap.fill",
                    storageKey: "haptyk.labs.hapticFeedback"
                )

                labsFeatureRow(
                    title: "Adaptive Volume",
                    description: "Auto-adjust volume based on ambient noise",
                    icon: "waveform.badge.mic",
                    storageKey: "haptyk.labs.adaptiveVolume"
                )

                labsFeatureRow(
                    title: "Key Visualizer",
                    description: "Show real-time force visualization overlay",
                    icon: "rectangle.split.3x3",
                    storageKey: "haptyk.labs.keyVisualizer"
                )

                Text("Labs features are experimental and may change.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(.top, 4)
        } label: {
            Label {
                HStack(spacing: 4) {
                    Text("Labs")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("β")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(.purple)
                        )
                }
            } icon: {
                Image(systemName: "flask.fill")
            }
            .foregroundStyle(.secondary)
        }
    }

    /// A row for an individual labs feature with toggle.
    ///
    /// - Parameters:
    ///   - title: The feature name.
    ///   - description: A brief description of what the feature does.
    ///   - icon: SF Symbol name.
    ///   - storageKey: The `UserDefaults` key for persisting the toggle state.
    private func labsFeatureRow(
        title: String,
        description: String,
        icon: String,
        storageKey: String
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.purple)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: storageKey) },
                set: { UserDefaults.standard.set($0, forKey: storageKey) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }

    // MARK: - Footer Section

    /// Footer with app version, settings link, and quit button.
    private var footerSection: some View {
        HStack {
            // Version info
            Text("v\(appVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            // Settings button
            Button {
                SettingsWindowController.shared.showWindow()
            } label: {
                Label("Settings…", systemImage: "gear")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Open Settings")

            Text("·")
                .foregroundStyle(.quaternary)

            // Quit button
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Quit KeyVibe")
        }
    }

    /// The application version string from the main bundle.
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Menu Bar View") {
    MenuBarView()
        .frame(width: 320)
}
#endif
