//
//  SoundPackPicker.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Categorized dropdown menu for selecting between all 16 mechanical switch profiles.
//

import SwiftUI

// MARK: - SoundPackPicker

public struct SoundPackPicker: View {
    @Binding public var selectedPackID: String
    @ObservedObject private var manager = SoundPackManager.shared

    public init(selectedPackID: Binding<String>) {
        self._selectedPackID = selectedPackID
    }

    public var body: some View {
        Menu {
            ForEach(SwitchCategory.allCases, id: \.self) { category in
                let packs = manager.availablePacks.filter { $0.category == category }
                if !packs.isEmpty {
                    Section(header: Text(category.rawValue)) {
                        ForEach(packs) { pack in
                            Button {
                                selectedPackID = pack.id
                                manager.selectPack(pack)
                            } label: {
                                HStack {
                                    Text(pack.name)
                                    if pack.id == selectedPackID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack {
                if let pack = currentPack {
                    Image(systemName: pack.category.iconName)
                        .foregroundStyle(.tint)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(pack.name)
                            .font(.callout)
                            .fontWeight(.medium)
                        Text(pack.category.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Select Sound Pack")
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Selected Sound Pack: \(currentPack?.name ?? "None")")
    }

    private var currentPack: SoundPack? {
        manager.availablePacks.first(where: { $0.id == selectedPackID })
    }
}

