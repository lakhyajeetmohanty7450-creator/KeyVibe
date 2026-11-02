//
//  SensitivityView.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Force curve sensitivity tuning view for adjusting transition thresholds.
//

import SwiftUI

// MARK: - SensitivityView

public struct SensitivityView: View {
    @Binding public var sensitivity: Float
    public var isProUser: Bool = true
    public var onSensitivityChanged: ((Float) -> Void)?

    public init(
        sensitivity: Binding<Float>,
        isProUser: Bool = true,
        onSensitivityChanged: ((Float) -> Void)? = nil
    ) {
        self._sensitivity = sensitivity
        self.isProUser = true
        self.onSensitivityChanged = onSensitivityChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Force Sensitivity", systemImage: "gauge.with.needle")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(sensitivityLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }

            VStack(spacing: 2) {
                Slider(value: $sensitivity, in: 0.0...1.0) {
                    Text("Sensitivity")
                }
                .onChange(of: sensitivity) { newValue in
                    onSensitivityChanged?(newValue)
                    Preferences.sensitivity = newValue
                }

                HStack {
                    Text("Heavy Handed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Balanced")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Light Touch")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var sensitivityLabel: String {
        if sensitivity < 0.35 {
            return "Heavy"
        } else if sensitivity < 0.65 {
            return "Normal"
        } else {
            return "Sensitive"
        }
    }
}

