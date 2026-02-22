// MIDISnifferEngine.swift — CoreMIDITransport passive listener + MIDI Through routing

import Foundation
import MIDI2Kit

public actor MIDISnifferEngine {
    private var transport: CoreMIDITransport?
    private var receiveTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private let messageHandler: @Sendable (CapturedMessage) -> Void
    private let sourceUpdateHandler: @Sendable ([MIDISourceInfo]) -> Void
    private let destinationUpdateHandler: @Sendable ([MIDIDestinationInfo]) -> Void

    // sourceID → [destinationID] lookup for routing
    private var routeTable: [UInt32: [UInt32]] = [:]

    public init(
        onMessage: @escaping @Sendable (CapturedMessage) -> Void,
        onSourcesUpdated: @escaping @Sendable ([MIDISourceInfo]) -> Void,
        onDestinationsUpdated: @escaping @Sendable ([MIDIDestinationInfo]) -> Void
    ) {
        self.messageHandler = onMessage
        self.sourceUpdateHandler = onSourcesUpdated
        self.destinationUpdateHandler = onDestinationsUpdated
    }

    public func start() throws {
        guard transport == nil else { return }
        let t = try CoreMIDITransport(clientName: "MIDI2Sniffer")
        self.transport = t

        receiveTask = Task { [weak self] in
            for await received in t.received {
                guard let self else { break }
                await self.forwardIfRouted(received)
                let sourceName = await self.sourceNameFor(received.sourceID)
                let message = MessageDecoder.decode(
                    data: received.data,
                    umpWord1: received.umpWord1,
                    umpWord2: received.umpWord2,
                    sourceName: sourceName,
                    sourceID: received.sourceID?.value
                )
                self.messageHandler(message)
            }
        }

        setupTask = Task { [weak self] in
            for await _ in t.setupChanged {
                guard let self else { break }
                await self.refreshSources()
                await self.refreshDestinations()
            }
        }

        Task {
            try? await t.connectToAllSources()
            await refreshSources()
            await refreshDestinations()
        }
    }

    public func stop() async {
        receiveTask?.cancel()
        setupTask?.cancel()
        receiveTask = nil
        setupTask = nil
        if let t = transport {
            await t.shutdown()
        }
        transport = nil
    }

    public func reconnect() async {
        guard let t = transport else { return }
        try? await t.reconnectAllSources()
        await refreshSources()
        await refreshDestinations()
    }

    // MARK: - Routing

    public func updateRoutes(_ routes: [MIDIRoute]) {
        var table: [UInt32: [UInt32]] = [:]
        for route in routes where route.isEnabled {
            table[route.sourceID, default: []].append(route.destinationID)
        }
        routeTable = table
    }

    private func forwardIfRouted(_ received: MIDIReceivedData) async {
        guard let sourceID = received.sourceID?.value,
              let destinations = routeTable[sourceID],
              let t = transport else { return }

        for destID in destinations {
            let dest = MIDIDestinationID(destID)
            if received.umpWord1 != 0 {
                try? await t.sendUMP(
                    [received.umpWord1, received.umpWord2],
                    to: dest
                )
            } else {
                try? await t.send(received.data, to: dest)
            }
        }
    }

    // MARK: - Source / Destination refresh

    private func refreshSources() async {
        guard let t = transport else { return }
        let sources = await t.sources
        sourceUpdateHandler(sources)
    }

    private func refreshDestinations() async {
        guard let t = transport else { return }
        let destinations = await t.destinations
        destinationUpdateHandler(destinations)
    }

    private func sourceNameFor(_ sourceID: MIDISourceID?) async -> String {
        guard let sid = sourceID, let t = transport else { return "Unknown" }
        let sources = await t.sources
        return sources.first(where: { $0.sourceID == sid })?.name ?? "Source \(sid.value)"
    }
}
