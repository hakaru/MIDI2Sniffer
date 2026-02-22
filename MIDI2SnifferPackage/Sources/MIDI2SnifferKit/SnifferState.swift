// SnifferState.swift — Observable state for MIDI2Sniffer

import Foundation
import MIDI2Kit
import Observation

@Observable
@MainActor
public final class SnifferState {
    public var messages: [CapturedMessage] = []
    public var filteredMessages: [CapturedMessage] = []
    public var filter = FilterConfig()
    public var isCapturing = false
    public var selectedMessageID: UUID?
    public var availableSources: [SourceInfo] = []
    public var availableDestinations: [DestinationInfo] = []
    public var routes: [MIDIRoute] = []
    public var messageCount: Int = 0
    public var startTime: Date?

    private var engine: MIDISnifferEngine?
    private var isPaused = false

    public struct SourceInfo: Identifiable, Sendable {
        public let id: UInt32
        public let name: String
        public let manufacturer: String?
        public var isEnabled: Bool

        public init(id: UInt32, name: String, manufacturer: String?, isEnabled: Bool = true) {
            self.id = id
            self.name = name
            self.manufacturer = manufacturer
            self.isEnabled = isEnabled
        }
    }

    public struct DestinationInfo: Identifiable, Sendable {
        public let id: UInt32
        public let name: String
        public let manufacturer: String?

        public init(id: UInt32, name: String, manufacturer: String?) {
            self.id = id
            self.name = name
            self.manufacturer = manufacturer
        }
    }

    public init() {}

    public var selectedMessage: CapturedMessage? {
        guard let id = selectedMessageID else { return nil }
        return messages.first(where: { $0.id == id })
    }

    // MARK: - Engine lifecycle

    public func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        isPaused = false
        startTime = .now

        let engine = MIDISnifferEngine(
            onMessage: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.appendMessage(message)
                }
            },
            onSourcesUpdated: { [weak self] sources in
                Task { @MainActor [weak self] in
                    self?.updateSources(sources)
                }
            },
            onDestinationsUpdated: { [weak self] destinations in
                Task { @MainActor [weak self] in
                    self?.updateDestinations(destinations)
                }
            }
        )
        self.engine = engine

        Task {
            do {
                try await engine.start()
            } catch {
                self.isCapturing = false
                print("Sniffer start failed: \(error)")
            }
        }
    }

    public func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        Task {
            await engine?.stop()
            engine = nil
        }
    }

    public func toggleCapture() {
        if isCapturing {
            stopCapture()
        } else {
            startCapture()
        }
    }

    public func clear() {
        messages.removeAll()
        filteredMessages.removeAll()
        messageCount = 0
        selectedMessageID = nil
    }

    // MARK: - Message handling

    private func appendMessage(_ message: CapturedMessage) {
        guard !isPaused else { return }
        messages.append(message)
        messageCount = messages.count
        if filter.matches(message) {
            filteredMessages.append(message)
        }
    }

    // MARK: - Source management

    private func updateSources(_ sources: [MIDISourceInfo]) {
        let existing = Dictionary(uniqueKeysWithValues: availableSources.map { ($0.id, $0.isEnabled) })
        availableSources = sources.map { s in
            SourceInfo(
                id: s.sourceID.value,
                name: s.name,
                manufacturer: s.manufacturer,
                isEnabled: existing[s.sourceID.value] ?? true
            )
        }
        updateEnabledSources()
    }

    public func toggleSource(_ id: UInt32) {
        if let idx = availableSources.firstIndex(where: { $0.id == id }) {
            availableSources[idx].isEnabled.toggle()
            updateEnabledSources()
        }
    }

    public func setAllSources(enabled: Bool) {
        for i in availableSources.indices {
            availableSources[i].isEnabled = enabled
        }
        updateEnabledSources()
    }

    private func updateEnabledSources() {
        let enabled = Set(availableSources.filter(\.isEnabled).map(\.name))
        filter.enabledSources = enabled
        refilter()
    }

    // MARK: - Destination management

    private func updateDestinations(_ destinations: [MIDIDestinationInfo]) {
        availableDestinations = destinations.map { d in
            DestinationInfo(
                id: d.destinationID.value,
                name: d.name,
                manufacturer: d.manufacturer
            )
        }
        // Disable routes whose destination is no longer available
        let availableIDs = Set(destinations.map(\.destinationID.value))
        for i in routes.indices {
            if !availableIDs.contains(routes[i].destinationID) {
                routes[i].isEnabled = false
            }
        }
        syncRoutesToEngine()
    }

    // MARK: - Route management

    public func addRoute(sourceID: UInt32, destinationID: UInt32) {
        guard let source = availableSources.first(where: { $0.id == sourceID }),
              let dest = availableDestinations.first(where: { $0.id == destinationID }) else { return }
        // Avoid duplicates
        if routes.contains(where: { $0.sourceID == sourceID && $0.destinationID == destinationID }) { return }
        let route = MIDIRoute(
            sourceID: sourceID,
            sourceName: source.name,
            destinationID: destinationID,
            destinationName: dest.name
        )
        routes.append(route)
        syncRoutesToEngine()
    }

    public func removeRoute(_ id: UUID) {
        routes.removeAll(where: { $0.id == id })
        syncRoutesToEngine()
    }

    public func toggleRoute(_ id: UUID) {
        if let idx = routes.firstIndex(where: { $0.id == id }) {
            routes[idx].isEnabled.toggle()
            syncRoutesToEngine()
        }
    }

    private func syncRoutesToEngine() {
        let currentRoutes = routes
        Task {
            await engine?.updateRoutes(currentRoutes)
        }
    }

    // MARK: - Filter

    public func toggleCategory(_ cat: MessageCategory) {
        if filter.enabledCategories.contains(cat) {
            filter.enabledCategories.remove(cat)
        } else {
            filter.enabledCategories.insert(cat)
        }
        refilter()
    }

    public func setTextFilter(_ text: String) {
        filter.textFilter = text
        refilter()
    }

    private func refilter() {
        filteredMessages = messages.filter { filter.matches($0) }
    }

    // MARK: - Elapsed time

    public var elapsedSinceStart: TimeInterval? {
        guard let start = startTime else { return nil }
        return Date.now.timeIntervalSince(start)
    }

    public func relativeTime(for message: CapturedMessage) -> String {
        guard let start = startTime else { return "0.000" }
        let delta = message.timestamp.timeIntervalSince(start)
        return String(format: "%.3f", delta)
    }
}
