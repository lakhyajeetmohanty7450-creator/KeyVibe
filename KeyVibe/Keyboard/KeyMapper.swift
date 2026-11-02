//
//  KeyMapper.swift
//  Haptyk
//
//  Maps macOS virtual key codes to `KeyCategory` values for sound sample selection.
//
//  Each physical key on the keyboard is assigned to a category that determines
//  which sound sample set is used. For example, the spacebar has a distinctly
//  different acoustic profile from alphanumeric keys on a mechanical keyboard,
//  so it gets its own category.
//
//  Virtual key codes are hardware‐level identifiers defined in
//  `<Carbon/HIToolbox/Events.h>` (the `kVK_*` constants). They are independent
//  of keyboard layout and modifier state.
//
//  Target: macOS 14+ (Sonoma), Swift 5.9+
//

import Foundation

// MARK: - KeyCategory

/// Classifies a physical key by its acoustic/mechanical group on a keyboard.
///
/// Sound packs provide distinct samples for each category because the physical
/// characteristics (key width, stabiliser presence, travel distance) affect
/// the sound a mechanical switch produces.
public enum KeyCategory: String, CaseIterable, Sendable {
    /// Standard letter and number keys (A‑Z, 0‑9).
    case alphanumeric

    /// The space bar — wider key with stabilisers, distinctive thock.
    case spacebar

    /// Return / Enter key.
    case enter

    /// Delete (Backspace) key.
    case backspace

    /// Tab key.
    case tab

    /// Modifier keys: Shift, Command, Control, Option, Fn, Caps Lock (held‐modifier).
    case modifier

    /// Arrow keys (Up, Down, Left, Right).
    case arrow

    /// Function row keys F1–F12 (and beyond on extended keyboards).
    case function

    /// Punctuation and symbol keys (period, comma, brackets, etc.).
    case punctuation

    /// Escape, Caps Lock when used as a toggle, and other special keys.
    case special
}

// MARK: - KeyMapper

/// Provides O(1) lookup from a macOS virtual key code to its `KeyCategory`,
/// plus helper methods for sound sample naming conventions.
///
/// ## Key Code Reference
/// Virtual key codes are from `<Carbon/HIToolbox/Events.h>`. A selection:
/// ```
/// kVK_ANSI_A          = 0x00    kVK_Return     = 0x24
/// kVK_Space           = 0x31    kVK_Delete     = 0x33
/// kVK_Tab             = 0x30    kVK_Escape     = 0x35
/// kVK_Shift           = 0x38    kVK_Command    = 0x37
/// kVK_UpArrow         = 0x7E    kVK_F1         = 0x7A
/// ```
public struct KeyMapper {

    // MARK: - Public Interface

    /// Returns the `KeyCategory` for a given virtual key code.
    ///
    /// Unknown key codes default to `.alphanumeric` — a safe fallback that
    /// ensures every key produces *some* sound.
    ///
    /// - Parameter keyCode: The macOS virtual key code (from `CGEvent`).
    /// - Returns: The matching `KeyCategory`.
    public static func category(for keyCode: Int64) -> KeyCategory {
        return keyCodeMap[keyCode] ?? .alphanumeric
    }

    /// Returns the filename suffix used in sound pack sample naming.
    ///
    /// Sound packs follow the naming convention:
    /// `<tier>_<action>_<suffix>` — e.g., `hard_press_alpha`, `soft_release_space`.
    ///
    /// - Parameter category: The key category.
    /// - Returns: A short, filesystem‐safe suffix string.
    public static func sampleSuffix(for category: KeyCategory) -> String {
        switch category {
        case .alphanumeric:  return "alpha"
        case .spacebar:      return "space"
        case .enter:         return "enter"
        case .backspace:     return "backspace"
        case .tab:           return "tab"
        case .modifier:      return "modifier"
        case .arrow:         return "arrow"
        case .function:      return "function"
        case .punctuation:   return "punct"
        case .special:       return "special"
        }
    }

    /// Determines whether a key category produces a sound on release.
    ///
    /// Modifiers held down for key combinations (e.g., holding Shift) produce
    /// press sounds but typically muted or no release sounds to avoid noise clutter.
    ///
    /// - Parameter category: The key category.
    /// - Returns: `true` if release sounds should be played.
    public static func hasReleaseSound(for category: KeyCategory) -> Bool {
        switch category {
        case .modifier:
            return false
        default:
            return true
        }
    }

    // MARK: - Virtual Key Code Mapping Table

    /// Complete mapping of macOS virtual key codes to `KeyCategory`.
    ///
    /// Key code constants correspond to the `kVK_*` defines in
    /// `<Carbon/HIToolbox/Events.h>`. The hex values are the canonical
    /// identifiers used across all macOS keyboard layouts.
    ///
    /// ## Layout Independence
    /// Virtual key codes identify the *physical position* on the keyboard,
    /// not the character produced. `0x00` is always the key in the "A" position
    /// on a US ANSI layout regardless of the active input source.
    private static let keyCodeMap: [Int64: KeyCategory] = {
        var map = [Int64: KeyCategory]()

        // ────────────────────────────────────────────────────────────────────
        // MARK: Alphanumeric — Letters (A‑Z)
        // ────────────────────────────────────────────────────────────────────
        //
        // kVK_ANSI_A = 0x00    kVK_ANSI_S = 0x01    kVK_ANSI_D = 0x02
        // kVK_ANSI_F = 0x03    kVK_ANSI_H = 0x04    kVK_ANSI_G = 0x05
        // kVK_ANSI_Z = 0x06    kVK_ANSI_X = 0x07    kVK_ANSI_C = 0x08
        // kVK_ANSI_V = 0x09    kVK_ANSI_B = 0x0B    kVK_ANSI_Q = 0x0C
        // kVK_ANSI_W = 0x0D    kVK_ANSI_E = 0x0E    kVK_ANSI_R = 0x0F
        // kVK_ANSI_Y = 0x10    kVK_ANSI_T = 0x11    kVK_ANSI_O = 0x1F
        // kVK_ANSI_U = 0x20    kVK_ANSI_I = 0x22    kVK_ANSI_P = 0x23
        // kVK_ANSI_L = 0x25    kVK_ANSI_J = 0x26    kVK_ANSI_K = 0x28
        // kVK_ANSI_N = 0x2D    kVK_ANSI_M = 0x2E

        let letterKeyCodes: [Int64] = [
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05,    // A, S, D, F, H, G
            0x06, 0x07, 0x08, 0x09,                  // Z, X, C, V
            0x0B, 0x0C, 0x0D, 0x0E, 0x0F,            // B, Q, W, E, R
            0x10, 0x11,                                // Y, T
            0x1F, 0x20,                                // O, U
            0x22, 0x23,                                // I, P
            0x25, 0x26,                                // L, J
            0x28,                                      // K
            0x2D, 0x2E                                 // N, M
        ]
        for code in letterKeyCodes {
            map[code] = .alphanumeric
        }

        // ────────────────────────────────────────────────────────────────────
        // MARK: Alphanumeric — Number Row (0‑9)
        // ────────────────────────────────────────────────────────────────────
        //
        // kVK_ANSI_1 = 0x12    kVK_ANSI_2 = 0x13    kVK_ANSI_3 = 0x14
        // kVK_ANSI_4 = 0x15    kVK_ANSI_5 = 0x17    kVK_ANSI_6 = 0x16
        // kVK_ANSI_7 = 0x1A    kVK_ANSI_8 = 0x1C    kVK_ANSI_9 = 0x19
        // kVK_ANSI_0 = 0x1D

        let numberKeyCodes: [Int64] = [
            0x12, 0x13, 0x14, 0x15, 0x17,    // 1, 2, 3, 4, 5
            0x16, 0x1A, 0x1C, 0x19, 0x1D     // 6, 7, 8, 9, 0
        ]
        for code in numberKeyCodes {
            map[code] = .alphanumeric
        }

        // ────────────────────────────────────────────────────────────────────
        // MARK: Alphanumeric — Numpad
        // ────────────────────────────────────────────────────────────────────
        //
        // kVK_ANSI_Keypad0     = 0x52    kVK_ANSI_Keypad1     = 0x53
        // kVK_ANSI_Keypad2     = 0x54    kVK_ANSI_Keypad3     = 0x55
        // kVK_ANSI_Keypad4     = 0x56    kVK_ANSI_Keypad5     = 0x57
        // kVK_ANSI_Keypad6     = 0x58    kVK_ANSI_Keypad7     = 0x59
        // kVK_ANSI_Keypad8     = 0x5B    kVK_ANSI_Keypad9     = 0x5C

        let numpadDigitCodes: [Int64] = [
            0x52, 0x53, 0x54, 0x55, 0x56,    // 0‑4
            0x57, 0x58, 0x59, 0x5B, 0x5C     // 5‑9
        ]
        for code in numpadDigitCodes {
            map[code] = .alphanumeric
        }

        // ────────────────────────────────────────────────────────────────────
        // MARK: Spacebar
        // ────────────────────────────────────────────────────────────────────

        map[0x31] = .spacebar      // kVK_Space

        // ────────────────────────────────────────────────────────────────────
        // MARK: Enter / Return
        // ────────────────────────────────────────────────────────────────────

        map[0x24] = .enter         // kVK_Return
        map[0x4C] = .enter         // kVK_ANSI_KeypadEnter

        // ────────────────────────────────────────────────────────────────────
        // MARK: Backspace / Delete
        // ────────────────────────────────────────────────────────────────────

        map[0x33] = .backspace     // kVK_Delete (Backspace on US layout)
        map[0x75] = .backspace     // kVK_ForwardDelete

        // ────────────────────────────────────────────────────────────────────
        // MARK: Tab
        // ────────────────────────────────────────────────────────────────────

        map[0x30] = .tab           // kVK_Tab

        // ────────────────────────────────────────────────────────────────────
        // MARK: Modifier Keys
        // ────────────────────────────────────────────────────────────────────
        //
        // kVK_Shift       = 0x38    kVK_RightShift   = 0x3C
        // kVK_Control     = 0x3B    kVK_RightControl = 0x3E
        // kVK_Option      = 0x3A    kVK_RightOption  = 0x3D
        // kVK_Command     = 0x37    kVK_RightCommand = 0x36
        // kVK_CapsLock    = 0x39    kVK_Function     = 0x3F

        let modifierKeyCodes: [Int64] = [
            0x38, 0x3C,     // Left/Right Shift
            0x3B, 0x3E,     // Left/Right Control
            0x3A, 0x3D,     // Left/Right Option
            0x37, 0x36,     // Left/Right Command
            0x39,           // Caps Lock
            0x3F            // Fn (Function)
        ]
        for code in modifierKeyCodes {
            map[code] = .modifier
        }

        // ────────────────────────────────────────────────────────────────────
        // MARK: Arrow Keys
        // ────────────────────────────────────────────────────────────────────
        //
        // kVK_UpArrow    = 0x7E    kVK_DownArrow  = 0x7D
        // kVK_LeftArrow  = 0x7B    kVK_RightArrow = 0x7C

        map[0x7E] = .arrow    // Up
        map[0x7D] = .arrow    // Down
        map[0x7B] = .arrow    // Left
        map[0x7C] = .arrow    // Right

        // ────────────────────────────────────────────────────────────────────
        // MARK: Function Keys (F1–F20)
        // ────────────────────────────────────────────────────────────────────
        //
        // kVK_F1  = 0x7A    kVK_F2  = 0x78    kVK_F3  = 0x63    kVK_F4  = 0x76
        // kVK_F5  = 0x60    kVK_F6  = 0x61    kVK_F7  = 0x62    kVK_F8  = 0x64
        // kVK_F9  = 0x65    kVK_F10 = 0x6D    kVK_F11 = 0x67    kVK_F12 = 0x6F
        // kVK_F13 = 0x69    kVK_F14 = 0x6B    kVK_F15 = 0x71    kVK_F16 = 0x6A
        // kVK_F17 = 0x40    kVK_F18 = 0x4F    kVK_F19 = 0x50    kVK_F20 = 0x5A

        let functionKeyCodes: [Int64] = [
            0x7A, 0x78, 0x63, 0x76,     // F1–F4
            0x60, 0x61, 0x62, 0x64,     // F5–F8
            0x65, 0x6D, 0x67, 0x6F,     // F9–F12
            0x69, 0x6B, 0x71, 0x6A,     // F13–F16
            0x40, 0x4F, 0x50, 0x5A      // F17–F20
        ]
        for code in functionKeyCodes {
            map[code] = .function
        }

        // ────────────────────────────────────────────────────────────────────
        // MARK: Punctuation & Symbols
        // ────────────────────────────────────────────────────────────────────
        //
        // kVK_ANSI_Equal        = 0x18    kVK_ANSI_Minus         = 0x1B
        // kVK_ANSI_LeftBracket  = 0x21    kVK_ANSI_RightBracket  = 0x1E
        // kVK_ANSI_Quote        = 0x27    kVK_ANSI_Semicolon     = 0x29
        // kVK_ANSI_Backslash    = 0x2A    kVK_ANSI_Comma         = 0x2B
        // kVK_ANSI_Slash        = 0x2C    kVK_ANSI_Period        = 0x2F
        // kVK_ANSI_Grave        = 0x32
        //
        // Numpad operators:
        // kVK_ANSI_KeypadDecimal  = 0x41    kVK_ANSI_KeypadMultiply = 0x43
        // kVK_ANSI_KeypadPlus    = 0x45    kVK_ANSI_KeypadDivide   = 0x4B
        // kVK_ANSI_KeypadMinus   = 0x4E    kVK_ANSI_KeypadEquals   = 0x51
        // kVK_ANSI_KeypadClear   = 0x47

        let punctuationKeyCodes: [Int64] = [
            0x18, 0x1B,             // Equal, Minus
            0x21, 0x1E,             // Left/Right Bracket
            0x27, 0x29,             // Quote, Semicolon
            0x2A, 0x2B,             // Backslash, Comma
            0x2C, 0x2F,             // Slash, Period
            0x32,                   // Grave/Tilde
            0x41, 0x43, 0x45,       // Numpad Decimal, Multiply, Plus
            0x4B, 0x4E, 0x51,       // Numpad Divide, Minus, Equals
            0x47                    // Numpad Clear
        ]
        for code in punctuationKeyCodes {
            map[code] = .punctuation
        }

        // ────────────────────────────────────────────────────────────────────
        // MARK: Special Keys
        // ────────────────────────────────────────────────────────────────────
        //
        // kVK_Escape   = 0x35
        // kVK_Home     = 0x73    kVK_End      = 0x77
        // kVK_PageUp   = 0x74    kVK_PageDown = 0x79
        // kVK_Help     = 0x72
        // ISO Section  = 0x0A    (key between left shift and Z on ISO layouts)

        let specialKeyCodes: [Int64] = [
            0x35,                   // Escape
            0x73, 0x77,             // Home, End
            0x74, 0x79,             // Page Up, Page Down
            0x72,                   // Help / Insert
            0x0A                    // ISO Section key
        ]
        for code in specialKeyCodes {
            map[code] = .special
        }

        return map
    }()
}
