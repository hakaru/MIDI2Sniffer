// MIDISnifferEngine.swift — CoreMIDITransport passive listener

import Foundation
import MIDI2Kit

public actor MIDISnifferEngine {
    private var transport: CoreMIDITransport?
    private var receiveTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private let messageHandler: @Sendable (CapturedMessage) -> Void
    private let sourceUpdateHandler: @Sendable ([MIDISourceInfo]) -> Void

    public init(
        onMessage: @escaping @Sendable (CapturedMessage) -> Void,
        onSourcesUpdated: @escaping @Sendable ([MIDISourceInfo]) -> Void
    ) {
        self.messageHandler = onMessage
        self.sourceUpdateHandler = onSourcesUpdated
    }

    public func start() throws {
        guard transport == nil else { return }
        let t = try CoreMIDITransport(clientName: "MIDI2Sniffer")
        self.transport = t

        receiveTask = Task { [weak self] in
            for await received in t.received {
                guard let self else { break }
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
            }
        }

        Task {
            try? await t.connectToAllSources()
            await refreshSources()
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
    }

    private func refreshSources() async {
        guard let t = transport else { return }
        let sources = await t.sources
        sourceUpdateHandler(sources)
    }

    private func sourceNameFor(_ sourceID: MIDISourceID?) async -> String {
        guard let sid = sourceID, let t = transport else { return "Unknown" }
        let sources = await t.sources
        return sources.first(where: { $0.sourceID == sid })?.name ?? "Source \(sid.value)"
    }
}
