//
//  LaunchAtLoginHelper.swift
//  KeyVibe
//
//  Manages automatic startup on macOS login using SMAppService.
//

import Foundation
import ServiceManagement

public final class LaunchAtLoginHelper: ObservableObject {
    public static let shared = LaunchAtLoginHelper()

    @Published public var isEnabled: Bool = false

    private init() {
        refresh()
    }

    public func refresh() {
        if #available(macOS 13.0, *) {
            self.isEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }

    public func setEnabled(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("Failed to change launchAtLogin: \(error)")
            }
            refresh()
        }
    }
}
