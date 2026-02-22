// FilterConfig.swift — Filter configuration for message display

import Foundation

public struct FilterConfig: Sendable {
    public var enabledCategories: Set<MessageCategory>
    public var enabledSources: Set<String>
    public var textFilter: String

    public init() {
        self.enabledCategories = Set(MessageCategory.allCases)
        self.enabledSources = []
        self.textFilter = ""
    }

    public func matches(_ message: CapturedMessage) -> Bool {
        guard enabledCategories.contains(message.decoded.category) else {
            return false
        }
        if !enabledSources.isEmpty && !enabledSources.contains(message.sourceName) {
            return false
        }
        if !textFilter.isEmpty {
            let lower = textFilter.lowercased()
            return message.decoded.summary.lowercased().contains(lower)
                || message.sourceName.lowercased().contains(lower)
        }
        return true
    }
}
