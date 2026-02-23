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

    // sourceID.value → name cache (updated on setupChanged / refreshSources)
    private var sourceNameCache: [UInt32: String] = [:]

    // macOS/iOS CoreMIDI MUIDs (blacklist) — learned from Discovery srcMUID
    // and DiscoveryReply destMUID. Used to block OS-originated CI from routing.
    private var macOSMUIDs: Set<UInt32> = []
    private static let broadcastMUID: UInt32 = 0x0FFF_FFFF

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
                await self.learnMacOSMUID(received)
                await self.forwardIfRouted(received)
                let sourceName = await self.sourceNameFor(received.sourceID)
                let message = MessageDecoder.decode(
                    data: received.data,
                    umpWords: received.umpWords,
                    sourceName: sourceName,
                    sourceID: received.sourceID?.value
                )
                self.messageHandler(message)
            }
        }

        setupTask = Task { [weak self] in
            for await _ in t.setupChanged {
                guard let self else { break }
                try? await t.connectToAllSources()
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

    private var _routeMIDICI = false

    public func setRouteMIDICI(_ enabled: Bool) {
        _routeMIDICI = enabled
    }

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

        if isMIDICI(received) {
            if !_routeMIDICI { return }
            if !shouldRouteCIMessage(received.data) { return }
        }

        for destID in destinations {
            let dest = MIDIDestinationID(destID)
            do {
                if !received.umpWords.isEmpty {
                    try await t.sendUMP(received.umpWords, to: dest)
                } else if !received.data.isEmpty {
                    try await t.send(received.data, to: dest)
                }
            } catch {
                NSLog("[MIDI2Sniffer] Route forward failed: dest=\(destID) error=\(error)")
            }
        }
    }

    // MARK: - MUID learning & filtering

    /// Learn macOS/iOS CoreMIDI MUIDs to blacklist from routing.
    /// Discovery (0x70) srcMUID = OS initiator. DiscoveryReply (0x71) destMUID = OS initiator.
    private func learnMacOSMUID(_ received: MIDIReceivedData) {
        let d = received.data
        guard d.count >= 13, d[0] == 0xF0, d[1] == 0x7E, d[3] == 0x0D else { return }
        let subID = d[4]
        switch subID {
        case 0x70: // Discovery — srcMUID is the OS initiator
            let muid = parseMUID(d, offset: 5)
            guard muid != Self.broadcastMUID else { return }
            if macOSMUIDs.insert(muid).inserted {
                NSLog("[MIDI2Sniffer] Blacklisted OS MUID: 0x%07X (Discovery src)", muid)
            }
        case 0x71: // DiscoveryReply — destMUID is the OS initiator
            let muid = parseMUID(d, offset: 9)
            guard muid != Self.broadcastMUID else { return }
            if macOSMUIDs.insert(muid).inserted {
                NSLog("[MIDI2Sniffer] Blacklisted OS MUID: 0x%07X (DiscoveryReply dst)", muid)
            }
        case 0x7E: // InvalidateMUID
            let muid = parseMUID(d, offset: 5)
            macOSMUIDs.remove(muid)
        default:
            break
        }
    }

    /// Block CI messages where srcMUID or destMUID belongs to macOS/iOS CoreMIDI.
    /// Device-to-device CI (and broadcast) passes through.
    private func shouldRouteCIMessage(_ data: [UInt8]) -> Bool {
        guard data.count >= 13 else { return false }
        let srcMUID = parseMUID(data, offset: 5)
        let dstMUID = parseMUID(data, offset: 9)
        if macOSMUIDs.contains(srcMUID) { return false }
        if dstMUID != Self.broadcastMUID && macOSMUIDs.contains(dstMUID) { return false }
        return true
    }

    /// Parse a 28-bit MUID from 4 × 7-bit bytes at the given offset (LSB first).
    private func parseMUID(_ data: [UInt8], offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return b0 | (b1 << 7) | (b2 << 14) | (b3 << 21)
    }

    /// Check if received data is a MIDI-CI message (Universal Non-Realtime SysEx, sub-ID 0x0D)
    private func isMIDICI(_ received: MIDIReceivedData) -> Bool {
        // MIDI 1.0 SysEx: F0 7E 7F 0D ...
        let d = received.data
        if d.count >= 4 && d[0] == 0xF0 && d[1] == 0x7E && d[2] == 0x7F && d[3] == 0x0D {
            return true
        }
        // UMP 64-bit Data Message (type 0x3): payload starts with 7E 7F 0D
        guard let w0 = received.umpWords.first, (w0 >> 28) & 0xF == 0x3 else { return false }
        let status = (w0 >> 20) & 0xF
        guard status == 0 || status == 1 else { return false } // Complete or Start only
        let b1 = UInt8((w0 >> 8) & 0xFF)
        let b2 = UInt8(w0 & 0xFF)
        guard received.umpWords.count >= 2 else { return false }
        let b3 = UInt8((received.umpWords[1] >> 24) & 0xFF)
        return b1 == 0x7E && b2 == 0x7F && b3 == 0x0D
    }

    // MARK: - Selective source connection

    public func setEnabledSources(_ enabledIDs: Set<UInt32>) async {
        guard let t = transport else { return }
        let allSources = await t.sources
        for s in allSources {
            let sid = s.sourceID
            if enabledIDs.contains(sid.value) {
                try? await t.connect(to: sid)
            } else {
                try? await t.disconnect(from: sid)
            }
        }
    }

    // MARK: - Source / Destination refresh

    private func refreshSources() async {
        guard let t = transport else { return }
        let sources = await t.sources
        var cache: [UInt32: String] = [:]
        for s in sources {
            cache[s.sourceID.value] = s.name
        }
        sourceNameCache = cache
        sourceUpdateHandler(sources)
    }

    private func refreshDestinations() async {
        guard let t = transport else { return }
        let destinations = await t.destinations
        destinationUpdateHandler(destinations)
    }

    private func sourceNameFor(_ sourceID: MIDISourceID?) -> String {
        guard let sid = sourceID else { return "Unknown" }
        return sourceNameCache[sid.value] ?? "Source \(sid.value)"
    }
}
