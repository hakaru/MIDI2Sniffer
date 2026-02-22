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
                exportToFile()
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

    private func exportToFile() {
        #if canImport(AppKit)
        guard let data = CaptureSession.export(messages: state.messages, startTime: state.startTime) else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "capture-\(formattedNow()).midi2sniff.json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("Export failed: \(error)")
        }
        #endif
    }

    private func formattedNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: .now)
    }
}
