// MessageDetailView.swift — Hex dump + JSON detail view

import SwiftUI

struct MessageDetailView: View {
    @Bindable var state: SnifferState

    var body: some View {
        if let msg = state.selectedMessage {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack {
                        Text(msg.decoded.category.rawValue)
                            .font(.headline)
                            .foregroundStyle(categoryColor(msg.decoded.category))
                        Spacer()
                        Text(msg.timestamp, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Summary
                    Text(msg.decoded.summary)
                        .font(.system(.body, design: .monospaced))

                    Divider()

                    // Detail
                    Text("Detail")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(msg.decoded.detailText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    Divider()

                    // Raw hex dump
                    Text("Raw Data (\(msg.rawData.count) bytes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(hexDump(msg.rawData))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)

                    // UMP words
                    if msg.umpWord1 != 0 {
                        Divider()
                        Text("UMP Words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "W1: 0x%08X  W2: 0x%08X", msg.umpWord1, msg.umpWord2))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    Spacer()
                }
                .padding()
            }
        } else {
            ContentUnavailableView {
                Label("No Message Selected", systemImage: "waveform.path")
            } description: {
                Text("Select a message from the list to see details.")
            }
        }
    }

    private func hexDump(_ data: [UInt8]) -> String {
        var lines: [String] = []
        let bytesPerLine = 16
        for offset in stride(from: 0, to: data.count, by: bytesPerLine) {
            let end = min(offset + bytesPerLine, data.count)
            let slice = data[offset..<end]
            let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = slice.map { (0x20...0x7E).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            let padded = hex.padding(toLength: bytesPerLine * 3 - 1, withPad: " ", startingAt: 0)
            lines.append(String(format: "%04X: %@ |%@|", offset, padded, ascii))
        }
        return lines.joined(separator: "\n")
    }
}
