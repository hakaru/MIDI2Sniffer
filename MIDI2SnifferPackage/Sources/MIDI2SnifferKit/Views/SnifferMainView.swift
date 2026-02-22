// SnifferMainView.swift — 3-pane NavigationSplitView layout

import SwiftUI

public struct SnifferMainView: View {
    @State var state = SnifferState()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 260)
        } content: {
            MessageListView(state: state)
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        } detail: {
            MessageDetailView(state: state)
                .navigationSplitViewColumnWidth(min: 300, ideal: 400)
        }
        .toolbar {
            ToolbarView(state: state)
        }
        .navigationTitle("MIDI2Sniffer")
        .onAppear {
            state.startCapture()
        }
    }
}

struct SidebarView: View {
    @Bindable var state: SnifferState

    var body: some View {
        List {
            Section("Sources") {
                Button(state.availableSources.allSatisfy(\.isEnabled) ? "Deselect All" : "Select All") {
                    let allEnabled = state.availableSources.allSatisfy(\.isEnabled)
                    state.setAllSources(enabled: !allEnabled)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)

                if state.availableSources.isEmpty {
                    Text("No MIDI sources")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(state.availableSources) { source in
                        Toggle(source.name, isOn: Binding(
                            get: { source.isEnabled },
                            set: { _ in state.toggleSource(source.id) }
                        ))
                        .font(.callout)
                    }
                }
            }

            Section("Filter") {
                ForEach(MessageCategory.allCases, id: \.self) { cat in
                    Toggle(cat.rawValue, isOn: Binding(
                        get: { state.filter.enabledCategories.contains(cat) },
                        set: { _ in state.toggleCategory(cat) }
                    ))
                    .font(.callout)
                    .foregroundStyle(categoryColor(cat))
                }
            }
        }
        .listStyle(.sidebar)
    }
}
