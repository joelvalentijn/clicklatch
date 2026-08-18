// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import AppKit
import SwiftUI

struct MenuBarView: View {

    @State private var model = AppModel.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Toggle("Enable click lock", isOn: Binding(
            get: { model.preferences.enabled },
            set: { model.setEnabled($0) }
        ))

        Text(model.statusText)

        Divider()

        if !model.permission.isTrusted {
            Button("Grant Accessibility permission…") {
                model.permission.openSystemSettings()
            }
            Divider()
        }

        Button("Check for Updates…") {
            NSApp.activate()
            openSettings()
            Task { await model.updater.check() }
        }

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit ClickLocker") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
