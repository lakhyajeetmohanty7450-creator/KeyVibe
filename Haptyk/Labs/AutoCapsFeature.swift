//
//  AutoCapsFeature.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Translates physical typing intensity into text formatting:
//  Keystrokes struck with .slam force automatically produce UPPERCASE letters.
//

import Foundation
import CoreGraphics
import Combine

// MARK: - AutoCapsFeature

public final class AutoCapsFeature: ObservableObject {

    @Published public var isEnabled: Bool = false
    @Published public private(set) var slamCount: Int = 0

    public init() {}

    /// Checks if the keystroke qualifies for auto-capitalization.
    public func shouldApplyShift(event: KeyEvent, velocity: VelocityResult) -> Bool {
        guard isEnabled else { return false }
        guard event.eventType == .keyDown else { return false }
        guard event.keyCategory == .alphanumeric else { return false }
        return velocity.forceTier == .slam
    }

    /// Processes keystroke and posts a synthetic Shift key modifier if slammed.
    public func processKeystroke(event: KeyEvent, velocity: VelocityResult) {
        guard shouldApplyShift(event: event, velocity: velocity) else { return }

        slamCount += 1

        // Inject Shift flag into synthetic event stream
        if let eventSource = CGEventSource(stateID: .combinedSessionState) {
            // Post virtual shift down
            let shiftDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x38, keyDown: true)
            shiftDown?.post(tap: .cghidEventTap)

            // Release shift after tiny delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                let shiftUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x38, keyDown: false)
                shiftUp?.post(tap: .cghidEventTap)
            }
        }
    }

    public func resetDailyCount() {
        slamCount = 0
    }
}

