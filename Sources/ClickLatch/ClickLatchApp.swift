// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import AppKit
import SwiftUI

@main
struct ClickLatchApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: menuBarSymbol)
        }

        Settings {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }

    private var menuBarSymbol: String {
        guard model.isRunning else { return "cursorarrow" }
        return model.status.phase == .locked ? "cursorarrow.click.2" : "cursorarrow.click"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let model = AppModel.shared
            // Explain what is needed right away on first launch.
            if !model.permission.isTrusted && model.preferences.enabled {
                model.permission.request()
            }
            model.handleLaunch()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Without this a mouse button could stay pressed down.
        MainActor.assumeIsolated {
            AppModel.shared.shutDown()
        }
    }
}
