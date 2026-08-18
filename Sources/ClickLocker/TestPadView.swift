// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import SwiftUI

/// Practice area: press inside the field, hold until the bar is full, let go and
/// move. If the lock works the dot keeps following the pointer without the mouse
/// button being held.
struct TestPadView: View {

    @State private var model = AppModel.shared
    @State private var puck: CGPoint?
    @State private var pressStart: Date?

    private let padHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pad
            progressBar
            statusLine
        }
    }

    private var pad: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isLocked ? Color.accentColor : Color.secondary.opacity(0.4),
                                  lineWidth: isLocked ? 2 : 1)

                if puck == nil {
                    Text("Press here, hold, let go and move")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Circle()
                    .fill(isLocked ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)
                    .position(puck ?? CGPoint(x: geometry.size.width / 2, y: padHeight / 2))
                    .opacity(puck == nil ? 0 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if pressStart == nil { pressStart = Date() }
                        puck = value.location
                    }
                    .onEnded { _ in
                        pressStart = nil
                    }
            )
        }
        .frame(height: padHeight)
        .onChange(of: model.status.phase) { _, phase in
            // A lock means no onEnded arrives, so stop the meter here.
            if phase != .pressed { pressStart = nil }
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if let pressStart {
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(pressStart)
                let fraction = min(elapsed / model.preferences.holdDuration, 1)
                ProgressView(value: fraction)
                    .tint(fraction >= 1 ? Color.accentColor : Color.secondary)
            }
        } else {
            ProgressView(value: 0)
                .tint(Color.secondary)
        }
    }

    private var statusLine: some View {
        HStack {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            Text(model.statusText)
                .font(.callout)
            Spacer()
            if let held = model.status.lastHoldMilliseconds {
                Text("last press: \(Int(held.rounded())) ms")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isLocked: Bool { model.status.phase == .locked }

    private var indicatorColor: Color {
        guard model.isRunning else { return .secondary }
        switch model.status.phase {
        case .idle: return .green
        case .pressed: return .yellow
        case .locked: return .accentColor
        }
    }
}
