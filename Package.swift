// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld
import PackageDescription

let package = Package(
    name: "ClickLatch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClickLatch",
            path: "Sources/ClickLatch"
        )
    ]
)
