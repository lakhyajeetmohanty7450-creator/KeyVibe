//
//  SoundPackManager.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Discovers, manages, and catalogs all 16 mechanical switch sound profiles.
//

import Foundation
import Combine

// MARK: - SoundPackManager

/// Discovers, selects, and coordinates loading of switch sound profiles into RAM.
public final class SoundPackManager: ObservableObject {

    // MARK: - Shared Instance

    public static let shared = SoundPackManager()

    // MARK: - Published Properties

    @Published public private(set) var availablePacks: [SoundPack] = []
    @Published public var selectedPack: SoundPack? {
        didSet {
            if let pack = selectedPack {
                Preferences.selectedSoundPack = pack.id
                SampleBank.shared.loadPack(pack)
                AudioEngine.shared.playTestSound()
            }
        }
    }

    // MARK: - Initialization

    private init() {
        let packs = Self.builtInPacks()
        let initialPackId = Preferences.selectedSoundPack
        let initial = packs.first(where: { $0.id == initialPackId }) ?? packs.first
        self._availablePacks = Published(initialValue: packs)
        self._selectedPack = Published(initialValue: initial)
    }

    // MARK: - Public API

    public func discoverPacks() {
        self.availablePacks = Self.builtInPacks()
    }

    public func selectPack(byId packId: String) {
        if let match = availablePacks.first(where: { $0.id == packId }) {
            self.selectedPack = match
        }
    }

    public func selectPack(_ pack: SoundPack) {
        self.selectedPack = pack
    }

    public func packsByCategory() -> [SwitchCategory: [SoundPack]] {
        Dictionary(grouping: availablePacks, by: \.category)
    }

    // MARK: - Built-in 16 Switch Manifest

    public static func builtInPacks() -> [SoundPack] {
        return [
            // ── Clicky Switches ───────────────────────────────────────────
            SoundPack(
                id: "cherry-mx-blue",
                name: "Cherry MX Blue PBT",
                category: .clicky,
                description: "Iconic, crisp mechanical snap with sharp acoustic actuation peak."
            ),
            SoundPack(
                id: "kailh-box-navy",
                name: "Kailh Box Navy",
                category: .clicky,
                description: "Thick click-bar switch delivering ultra-crisp, maximum-volume clicks."
            ),
            SoundPack(
                id: "blue-alps",
                name: "Blue Alps",
                category: .clicky,
                description: "Revered vintage clicky switch with deep metallic resonance and complex tone."
            ),

            // ── Thocky & Tactile Switches ─────────────────────────────────
            SoundPack(
                id: "holy-panda",
                name: "Holy Panda",
                category: .tactile,
                description: "Prominent tactile bump paired with an unmistakable resonant bottom-out thock."
            ),
            SoundPack(
                id: "topre-pbt",
                name: "Topre PBT",
                category: .tactile,
                description: "Electrostatic capacitive switch producing a warm, muted housing 'thump'."
            ),
            SoundPack(
                id: "biscuit-tactile",
                name: "Biscuit Tactile",
                category: .tactile,
                description: "Default warm, balanced tactile sound pack with smooth bottom-out."
            ),
            SoundPack(
                id: "cherry-mx-brown",
                name: "Cherry MX Brown",
                category: .tactile,
                description: "Subtle tactile bump with gentle plastic housing clack."
            ),

            // ── Linear Switches ───────────────────────────────────────────
            SoundPack(
                id: "gateron-red-ink",
                name: "Gateron Red Ink V2",
                category: .linear,
                description: "Premium smoky housing linear switch with deep, satisfying bottom-out tone."
            ),
            SoundPack(
                id: "gateron-black-ink",
                name: "Gateron Black Ink",
                category: .linear,
                description: "Heavier linear weight with deep, muted acoustic signature."
            ),
            SoundPack(
                id: "gateron-yellow",
                name: "Gateron Milky Yellow",
                category: .linear,
                description: "Budget king buttery smooth linear keystroke with creamy acoustics."
            ),
            SoundPack(
                id: "nk-cream",
                name: "NK Cream",
                category: .linear,
                description: "Full POM housing linear switch with unique high-pitched bottom-out sound."
            ),
            SoundPack(
                id: "novelkeys-cream",
                name: "NovelKeys Cream Lubed",
                category: .linear,
                description: "Hand-lubed POM linear switch with deep, plush clack."
            ),
            SoundPack(
                id: "alpaca",
                name: "Alpaca V2",
                category: .linear,
                description: "Ultra-smooth nylon/polycarbonate linear switch with clean pop."
            ),
            SoundPack(
                id: "turquoise-tealios",
                name: "Turquoise Tealios",
                category: .linear,
                description: "Crystal-clear housing with polished stem delivering precise, bright clacks."
            ),
            SoundPack(
                id: "cherry-mx-red",
                name: "Cherry MX Red",
                category: .linear,
                description: "Classic light linear switch with snappy, light clacks."
            ),

            // ── Vintage & IBM ─────────────────────────────────────────────
            SoundPack(
                id: "buckling-spring",
                name: "IBM Buckling Spring",
                category: .vintage,
                description: "Legendary IBM Model M metallic spring buckle and heavy chassis resonance."
            )
        ]
    }
}

