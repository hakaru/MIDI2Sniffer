// RouteManagementView.swift — Route list and add-route popover

import SwiftUI

struct RouteListView: View {
    @Bindable var state: SnifferState

    var body: some View {
        if state.routes.isEmpty {
            Text("No routes")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else {
            ForEach(state.routes) { route in
                Toggle(isOn: Binding(
                    get: { route.isEnabled },
                    set: { _ in state.toggleRoute(route.id) }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(route.sourceName)
                            .font(.callout)
                        Text("→ \(route.destinationName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu {
                    Button("Remove", role: .destructive) {
                        state.removeRoute(route.id)
                    }
                }
            }
        }
    }
}

struct AddRouteView: View {
    @Bindable var state: SnifferState
    @Binding var isPresented: Bool
    @State private var selectedSourceID: UInt32?
    @State private var selectedDestinationID: UInt32?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Route")
                .font(.headline)

            Picker("Source", selection: $selectedSourceID) {
                Text("Select...").tag(nil as UInt32?)
                ForEach(state.availableSources) { source in
                    Text(source.name).tag(source.id as UInt32?)
                }
            }

            Picker("Destination", selection: $selectedDestinationID) {
                Text("Select...").tag(nil as UInt32?)
                ForEach(state.availableDestinations) { dest in
                    Text(dest.name).tag(dest.id as UInt32?)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                Button("Add") {
                    if let src = selectedSourceID, let dst = selectedDestinationID {
                        state.addRoute(sourceID: src, destinationID: dst)
                        isPresented = false
                    }
                }
                .disabled(selectedSourceID == nil || selectedDestinationID == nil)
            }
        }
        .padding()
        .frame(width: 260)
    }
}
