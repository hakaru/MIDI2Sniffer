// MIDIRoute.swift — Route model for MIDI Through

import Foundation

public struct MIDIRoute: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let sourceID: UInt32
    public let sourceName: String
    public let destinationID: UInt32
    public let destinationName: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        sourceID: UInt32,
        sourceName: String,
        destinationID: UInt32,
        destinationName: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.destinationID = destinationID
        self.destinationName = destinationName
        self.isEnabled = isEnabled
    }
}
