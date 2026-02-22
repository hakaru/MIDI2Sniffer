// MessageListView.swift — Table of captured messages with color coding

import SwiftUI

struct MessageListView: View {
    @Bindable var state: SnifferState

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter messages...", text: Binding(
                    get: { state.filter.textFilter },
                    set: { state.setTextFilter($0) }
                ))
                .textFieldStyle(.plain)

                if !state.filter.textFilter.isEmpty {
                    Button {
                        state.setTextFilter("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("\(state.filteredMessages.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Message table
            Table(state.filteredMessages, selection: $state.selectedMessageID) {
                TableColumn("Time") { msg in
                    Text(state.relativeTime(for: msg))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 70, max: 90)

                TableColumn("Source") { msg in
                    Text(msg.sourceName)
                        .font(.caption)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 120, max: 180)

                TableColumn("Type") { msg in
                    Text(msg.decoded.category.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(categoryColor(msg.decoded.category))
                        .fontWeight(.medium)
                }
                .width(min: 50, ideal: 60, max: 80)

                TableColumn("Summary") { msg in
                    Text(msg.decoded.summary)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                }
                .width(min: 200, ideal: 400)
            }
        }
    }
}
