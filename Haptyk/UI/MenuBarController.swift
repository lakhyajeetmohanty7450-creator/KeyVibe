//
//  MenuBarController.swift
//  Haptyk
//
//  Primary user interface controller for the macOS menu bar status item.
//  Manages an NSStatusItem with a keyboard icon, an NSPopover for the main
//  settings panel, and a right-click context menu for quick actions.
//
//  Architecture:
//  - The status item lives in the system menu bar for the app's entire lifetime.
//  - Left-click toggles an NSPopover containing the SwiftUI `MenuBarView`.
//  - Right-click presents a lightweight NSMenu with Quit and Mute shortcuts.
//  - An event monitor auto-dismisses the popover on outside clicks.
//
//  Created for Haptyk — a velocity-sensitive mechanical keyboard sound engine.
//  Copyright © 2024 Haptyk. All rights reserved.
//

import AppKit
import SwiftUI
import Combine

// MARK: - MenuBarController

/// Controls the macOS menu bar status item, popover presentation, and context menu.
///
/// `MenuBarController` owns the `NSStatusItem` and manages its lifecycle.
/// It is designed to be instantiated once by the `AppDelegate` and kept alive
/// for the entire application session.
///
/// Usage:
/// ```swift
/// let controller = MenuBarController()
/// controller.setup()
/// ```
final class MenuBarController: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// Whether the popover is currently visible.
    @Published private(set) var isPopoverShown: Bool = false

    /// Whether the app is currently muted. Drives the status item icon state.
    @Published var isMuted: Bool = false {
        didSet { updateStatusItemIcon() }
    }

    // MARK: - Private Properties

    /// The system menu bar status item. Retained for the app's lifetime.
    private var statusItem: NSStatusItem!

    /// The popover that hosts the SwiftUI `MenuBarView`.
    private var popover: NSPopover!

    /// Monitors clicks outside the popover to auto-dismiss it.
    private var eventMonitor: Any?

    /// Cancellable subscriptions for Combine publishers.
    private var cancellables = Set<AnyCancellable>()

    /// The hosting view for the SwiftUI content inside the popover.
    private var hostingController: NSHostingController<MenuBarView>?

    // MARK: - Constants

    /// Popover width in points. Height is determined by SwiftUI content.
    private static let popoverWidth: CGFloat = 320

    /// SF Symbol name for the normal (unmuted) status item icon.
    private static let normalIconName = "keyboard.fill"

    /// SF Symbol name for the muted status item icon.
    private static let mutedIconName = "keyboard"

    // MARK: - Initialization

    override init() {
        super.init()
    }

    deinit {
        removeEventMonitor()
    }

    // MARK: - Setup

    /// Configures the status item, popover, and event monitoring.
    ///
    /// Call this method once during application launch, typically from
    /// `applicationDidFinishLaunching(_:)` in your `AppDelegate`.
    func setup() {
        configureStatusItem()
        configurePopover()
        bindPreferences()
    }

    /// Cleans up status item and event monitors on application termination.
    func tearDown() {
        removeEventMonitor()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        popover?.close()
        popover = nil
    }

    // MARK: - Status Item Configuration

    /// Creates and configures the `NSStatusItem` with a keyboard icon and click actions.
    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem.button else {
            assertionFailure("[MenuBarController] Failed to access status item button.")
            return
        }

        // Configure the button icon
        updateStatusItemIcon()

        // Set accessibility
        button.toolTip = "KeyVibe — Mechanical Keyboard Sound Engine"
        button.setAccessibilityLabel("KeyVibe Menu")
        button.setAccessibilityHelp("Click to open KeyVibe settings. Right-click for quick actions.")

        // Wire up click handling
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Updates the status item icon based on the current mute state.
    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }

        let iconName = isMuted ? Self.mutedIconName : Self.normalIconName

        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Haptyk") {
            // Configure for menu bar template rendering
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let configuredImage = image.withSymbolConfiguration(config) ?? image
            configuredImage.isTemplate = true

            // If muted, add a visual slash overlay via compositing
            if isMuted {
                button.image = createMutedIcon(base: configuredImage)
            } else {
                button.image = configuredImage
            }
        }
    }

    /// Creates a muted variant of the keyboard icon with a diagonal strikethrough.
    ///
    /// - Parameter base: The base keyboard icon to modify.
    /// - Returns: A new `NSImage` with a diagonal line overlay indicating mute.
    private func createMutedIcon(base: NSImage) -> NSImage {
        let size = base.size
        let result = NSImage(size: size, flipped: false) { rect in
            // Draw the base icon
            base.draw(in: rect)

            // Draw a diagonal strikethrough line
            let path = NSBezierPath()
            path.lineWidth = 1.5
            let inset: CGFloat = 2.0
            path.move(to: NSPoint(x: rect.maxX - inset, y: rect.maxY - inset))
            path.line(to: NSPoint(x: rect.minX + inset, y: rect.minY + inset))
            NSColor.labelColor.setStroke()
            path.stroke()

            return true
        }
        result.isTemplate = true
        return result
    }

    // MARK: - Popover Configuration

    /// Creates and configures the `NSPopover` with the SwiftUI `MenuBarView`.
    private func configurePopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: Self.popoverWidth, height: 0) // Height auto-sized
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // Create the SwiftUI hosting controller
        let menuBarView = MenuBarView()
        let hosting = NSHostingController(rootView: menuBarView)
        hostingController = hosting

        popover.contentViewController = hosting
    }

    // MARK: - Preferences Binding

    /// Subscribes to preferences changes to keep the UI in sync.
    private func bindPreferences() {
        // Observe mute state from UserDefaults
        UserDefaults.standard.publisher(for: \.haptykMuted)
            .receive(on: RunLoop.main)
            .sink { [weak self] muted in
                self?.isMuted = muted
            }
            .store(in: &cancellables)
    }

    // MARK: - Click Handling

    /// Dispatches left-click vs right-click on the status item button.
    ///
    /// - Parameter sender: The status item button that was clicked.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Popover Presentation

    /// Shows the popover anchored to the status item button.
    func showPopover() {
        guard let button = statusItem.button else { return }
        guard !popover.isShown else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        isPopoverShown = true

        // Install an event monitor for clicks outside the popover
        installEventMonitor()

        // Bring the app to front so popover can receive focus
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hides the popover with animation.
    func hidePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
        isPopoverShown = false
        removeEventMonitor()
    }

    /// Toggles the popover's visibility.
    func togglePopover() {
        if popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }

    // MARK: - Context Menu

    /// Presents a right-click context menu below the status item.
    private func showContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Mute toggle
        let muteItem = NSMenuItem(
            title: isMuted ? "Unmute" : "Mute",
            action: #selector(toggleMute),
            keyEquivalent: "m"
        )
        muteItem.target = self
        muteItem.image = NSImage(
            systemSymbolName: isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
            accessibilityDescription: isMuted ? "Unmute" : "Mute"
        )
        menu.addItem(muteItem)

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(
            systemSymbolName: "gear",
            accessibilityDescription: "Settings"
        )
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit KeyVibe",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(
            systemSymbolName: "power",
            accessibilityDescription: "Quit"
        )
        menu.addItem(quitItem)

        // Present the menu from the status item
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Clear the menu so left-click goes back to popover behavior
        statusItem.menu = nil
    }

    // MARK: - Menu Actions

    /// Toggles the mute state and persists to UserDefaults.
    @objc private func toggleMute() {
        isMuted.toggle()
        UserDefaults.standard.haptykMuted = isMuted
    }

    /// Opens the full settings window.
    @objc private func openSettings() {
        hidePopover()
        SettingsWindowController.shared.showWindow()
    }

    /// Terminates the application.
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Event Monitor

    /// Installs a global event monitor to detect clicks outside the popover.
    private func installEventMonitor() {
        removeEventMonitor() // Ensure no duplicate monitors

        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.hidePopover()
        }
    }

    /// Removes the global event monitor if installed.
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - NSPopoverDelegate

extension MenuBarController: NSPopoverDelegate {

    func popoverDidClose(_ notification: Notification) {
        isPopoverShown = false
        removeEventMonitor()
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        // Allow the user to detach the popover into a floating window
        return true
    }
}

// MARK: - SettingsWindowController

/// Singleton controller for the full Settings window.
///
/// Manages a single `NSWindow` instance hosting the `SettingsWindow` SwiftUI view.
/// The window is lazily created and reused across show/hide cycles.
final class SettingsWindowController {

    /// Shared singleton instance.
    static let shared = SettingsWindowController()

    /// The managed settings window.
    private var window: NSWindow?

    private init() {}

    /// Shows the settings window, creating it if necessary.
    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsWindow()
        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "KeyVibe Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 500, height: 400))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.setAccessibilityLabel("KeyVibe Settings Window")

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    /// Key for the mute state in UserDefaults.
    private static let haptykMutedKey = "haptyk.isMuted"

    /// Whether Haptyk sound output is currently muted.
    @objc dynamic var haptykMuted: Bool {
        get { bool(forKey: Self.haptykMutedKey) }
        set { set(newValue, forKey: Self.haptykMutedKey) }
    }
}
