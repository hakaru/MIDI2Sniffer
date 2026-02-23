// ToolbarView.swift — Capture/Stop/Clear/Pause/Export toolbar

import SwiftUI
import UniformTypeIdentifiers

struct CaptureDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ToolbarView: ToolbarContent {
    @Bindable var state: SnifferState
    @Binding var isExporting: Bool
    @Binding var exportDocument: CaptureDocument?

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
                state.togglePause()
            } label: {
                Label(
                    state.isScrollPaused ? "Resume" : "Pause",
                    systemImage: state.isScrollPaused ? "play.fill" : "pause.fill"
                )
            }
            .help(state.isScrollPaused ? "Resume display" : "Pause display")
            .disabled(!state.isCapturing)

            Button {
                state.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Clear messages (Cmd+K)")
            .keyboardShortcut("k", modifiers: .command)

            Button {
                Task {
                    if let data = await state.prepareExportData() {
                        exportDocument = CaptureDocument(data: data)
                        isExporting = true
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export to JSON (Cmd+E)")
            .keyboardShortcut("e", modifiers: .command)
            .disabled(state.filteredMessages.isEmpty)
        }

        ToolbarItem(placement: .status) {
            HStack(spacing: 4) {
                if state.isCapturing {
                    Circle()
                        .fill(state.isScrollPaused ? .orange : .red)
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
