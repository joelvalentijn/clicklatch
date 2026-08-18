// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld
import PackageDescription

let package = Package(
    name: "ClickLocker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClickLocker",
            path: "Sources/ClickLocker"
        )
    ]
)
