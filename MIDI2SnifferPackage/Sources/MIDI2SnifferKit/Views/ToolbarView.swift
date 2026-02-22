// ToolbarView.swift — Capture/Stop/Clear/Export toolbar

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ToolbarView: ToolbarContent {
    @Bindable var state: SnifferState

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                state.toggleCapture()
            } label: {
                Label(
                    state.isCapturing ? "Stop" : "Capture",
                    systemImage: state.isCapturing ? "stop.fill" : "record.circle"
                )
            }
            .help(state.isCapturing ? "Stop capture (Space)" : "Start capture (Space)")
            .keyboardShortcut(.space, modifiers: [])

            Button {
                state.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Clear messages (Cmd+K)")
            .keyboardShortcut("k", modifiers: .command)

            Button {
                CaptureSession.exportToFile(messages: state.messages, startTime: state.startTime)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export to JSON (Cmd+E)")
            .keyboardShortcut("e", modifiers: .command)
            .disabled(state.messages.isEmpty)
        }

        ToolbarItem(placement: .status) {
            HStack(spacing: 4) {
                if state.isCapturing {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                }
                Text("\(state.messageCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
