// SnifferState.swift — Observable state for MIDI2Sniffer

import DequeModule
import Foundation
import MIDI2Kit
import Observation

@Observable
@MainActor
public final class SnifferState {
    public var messages: Deque<CapturedMessage> = []
    public var filteredMessages: Deque<CapturedMessage> = []
    public var filter = FilterConfig()
    public var isCapturing = false
    public var selectedMessageID: UUID?
    public var availableSources: [SourceInfo] = []
    public var availableDestinations: [DestinationInfo] = []
    public var routes: [MIDIRoute] = []
    public var routeMIDICI = false
    public var messageCount: Int = 0
    public var startTime: Date?

    private var engine: MIDISnifferEngine?
    public var isScrollPaused = false
    private var refilterTask: Task<Void, Never>?
    private var filteredCountAtRefilter: Int = 0
    private static let maxMessageCount = 100_000
    private static let batchRemoveCount = 10_000

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

    private nonisolated func mainActorSend<T: Sendable>(
        _ action: @MainActor @escaping (SnifferState, T) -> Void
    ) -> @Sendable (T) -> Void {
        { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self else { return }
                action(self, value)
            }
        }
    }

    public func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        isScrollPaused = false
        startTime = .now

        let engine = MIDISnifferEngine(
            onMessage: mainActorSend { $0.appendMessage($1) },
            onSourcesUpdated: mainActorSend { $0.updateSources($1) },
            onDestinationsUpdated: mainActorSend { $0.updateDestinations($1) }
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

    public func togglePause() {
        isScrollPaused.toggle()
        if !isScrollPaused { refilter() }
    }

    // MARK: - Message handling

    private func appendMessage(_ message: CapturedMessage) {
        messages.append(message)
        if messages.count > Self.maxMessageCount + Self.batchRemoveCount {
            messages.removeFirst(Self.batchRemoveCount)
            refilter()
        }
        messageCount = messages.count
        guard !isScrollPaused else { return }
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
            syncEnabledSourcesToEngine()
        }
    }

    public func setAllSources(enabled: Bool) {
        for i in availableSources.indices {
            availableSources[i].isEnabled = enabled
        }
        updateEnabledSources()
        syncEnabledSourcesToEngine()
    }

    private func updateEnabledSources() {
        let enabled = Set(availableSources.filter(\.isEnabled).map(\.name))
        filter.enabledSources = enabled
        refilter()
    }

    private func syncEnabledSourcesToEngine() {
        let enabledIDs = Set(availableSources.filter(\.isEnabled).map(\.id))
        let engine = self.engine
        Task { await engine?.setEnabledSources(enabledIDs) }
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

    public func toggleRouteMIDICI() {
        routeMIDICI.toggle()
        let value = routeMIDICI
        Task { await engine?.setRouteMIDICI(value) }
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
        refilterTask?.cancel()
        let snapshot = messages
        filteredCountAtRefilter = filteredMessages.count
        let currentFilter = filter
        refilterTask = Task.detached { [weak self] in
            let filtered = Deque(snapshot.filter { currentFilter.matches($0) })
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                // Preserve messages appended to filteredMessages since refilter started
                let newCount = self.filteredMessages.count - self.filteredCountAtRefilter
                let tail = newCount > 0 ? Array(self.filteredMessages.suffix(newCount)) : []
                self.filteredMessages = filtered
                self.filteredMessages.append(contentsOf: tail)
                self.messageCount = self.messages.count
            }
        }
    }

    // MARK: - Export

    public func prepareExportData() async -> Data? {
        let msgs = Array(filteredMessages)
        let start = startTime
        return await Task.detached {
            CaptureSession.export(messages: msgs, startTime: start)
        }.value
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
