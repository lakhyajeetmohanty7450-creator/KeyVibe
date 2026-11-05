//
//  VolumeSliderView.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Volume slider with dynamic speaker icon indicating volume level & mute state.
//

import SwiftUI

// MARK: - VolumeSliderView

public struct VolumeSliderView: View {
    @Binding public var volume: Float
    @Binding public var isMuted: Bool
    public var onVolumeChanged: ((Float) -> Void)?

    public init(
        volume: Binding<Float>,
        isMuted: Binding<Bool>,
        onVolumeChanged: ((Float) -> Void)? = nil
    ) {
        self._volume = volume
        self._isMuted = isMuted
        self.onVolumeChanged = onVolumeChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Master Volume", systemImage: speakerIcon)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(volume * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isMuted ? .secondary : .primary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Button {
                    isMuted.toggle()
                    AudioEngine.shared.isMuted = isMuted
                    Preferences.isMuted = isMuted
                } label: {
                    Image(systemName: speakerIcon)
                        .font(.body)
                        .foregroundStyle(isMuted ? .orange : .primary)
                        .frame(width: 20)
                }
                .buttonStyle(.plain)
                .help(isMuted ? "Unmute" : "Mute")

                Slider(value: $volume, in: 0.0...1.0) {
                    Text("Volume")
                }
                .disabled(isMuted)
                .onChange(of: volume) { newValue in
                    onVolumeChanged?(newValue)
                    AudioEngine.shared.masterVolume = newValue
                    Preferences.masterVolume = newValue
                }
                .onChange(of: isMuted) { newMuted in
                    AudioEngine.shared.isMuted = newMuted
                    Preferences.isMuted = newMuted
                }
            }
        }
    }

    private var speakerIcon: String {
        if isMuted || volume == 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}

