// CaptureSession.swift — JSON export for captured sessions

import Foundation
#if canImport(AppKit)
import AppKit
#endif

public struct CaptureSession: Sendable {

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    public struct ExportData: Codable, Sendable {
        public let version: Int
        public let startTime: String
        public let endTime: String
        public let devices: [DeviceEntry]
        public let messages: [MessageEntry]

        public struct DeviceEntry: Codable, Sendable {
            public let name: String
        }

        public struct MessageEntry: Codable, Sendable {
            public let timestamp: String
            public let deltaMs: Double
            public let source: String
            public let category: String
            public let summary: String
            public let rawHex: String
            public let detail: DetailEntry?
        }

        public struct DetailEntry: Codable, Sendable {
            public let ciType: String?
            public let sourceMUID: String?
            public let destMUID: String?
            public let resource: String?
            public let headerJSON: String?
            public let bodyJSON: String?
            public let requestID: UInt8?
            public let subscribeId: String?
        }
    }

    @MainActor
    public static func exportToFile(messages: [CapturedMessage], startTime: Date?) {
        #if canImport(AppKit)
        guard let data = export(messages: messages, startTime: startTime) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "capture-\(filenameDateFormatter.string(from: .now)).midi2sniff.json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("Export failed: \(error)")
        }
        #endif
    }

    public static func export(messages: [CapturedMessage], startTime: Date?) -> Data? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = .current

        let start = startTime ?? messages.first?.timestamp ?? .now
        let end = messages.last?.timestamp ?? .now

        let deviceNames = Set(messages.map(\.sourceName))
        let devices = deviceNames.sorted().map { ExportData.DeviceEntry(name: $0) }

        let entries: [ExportData.MessageEntry] = messages.map { msg in
            let delta = msg.timestamp.timeIntervalSince(start) * 1000
            let hex = msg.rawData.map { String(format: "%02X", $0) }.joined(separator: " ")
            let detail = extractDetail(msg.decoded)

            return ExportData.MessageEntry(
                timestamp: isoFormatter.string(from: msg.timestamp),
                deltaMs: delta,
                source: msg.sourceName,
                category: msg.decoded.category.rawValue,
                summary: msg.decoded.summary,
                rawHex: hex,
                detail: detail
            )
        }

        let export = ExportData(
            version: 1,
            startTime: isoFormatter.string(from: start),
            endTime: isoFormatter.string(from: end),
            devices: devices,
            messages: entries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(export)
    }

    private static func extractDetail(_ decoded: DecodedMessage) -> ExportData.DetailEntry? {
        switch decoded {
        case .peGetInquiry(let src, let dst, let res, let req):
            return .init(ciType: "PE-GET", sourceMUID: src, destMUID: dst,
                        resource: res, headerJSON: nil, bodyJSON: nil,
                        requestID: req, subscribeId: nil)
        case .peGetReply(let src, let dst, let hdr, let body, let req, _, _):
            return .init(ciType: "PE-GET-Reply", sourceMUID: src, destMUID: dst,
                        resource: nil, headerJSON: hdr, bodyJSON: body,
                        requestID: req, subscribeId: nil)
        case .peSetInquiry(let src, let dst, let res, let req, let body):
            return .init(ciType: "PE-SET", sourceMUID: src, destMUID: dst,
                        resource: res, headerJSON: nil, bodyJSON: body,
                        requestID: req, subscribeId: nil)
        case .peSetReply(let src, let dst, let req):
            return .init(ciType: "PE-SET-Reply", sourceMUID: src, destMUID: dst,
                        resource: nil, headerJSON: nil, bodyJSON: nil,
                        requestID: req, subscribeId: nil)
        case .peSubscribe(let src, let dst, let res, let cmd):
            return .init(ciType: "PE-Subscribe", sourceMUID: src, destMUID: dst,
                        resource: res, headerJSON: nil, bodyJSON: cmd,
                        requestID: nil, subscribeId: nil)
        case .peSubscribeReply(let src, let dst, let subId):
            return .init(ciType: "PE-SubscribeReply", sourceMUID: src, destMUID: dst,
                        resource: nil, headerJSON: nil, bodyJSON: nil,
                        requestID: nil, subscribeId: subId)
        case .peNotify(let src, let dst, let res, let body, let subId):
            return .init(ciType: "PE-Notify", sourceMUID: src, destMUID: dst,
                        resource: res, headerJSON: nil, bodyJSON: body,
                        requestID: nil, subscribeId: subId)
        case .ciDiscovery(let src, let id):
            return .init(ciType: "Discovery", sourceMUID: src, destMUID: nil,
                        resource: nil, headerJSON: nil, bodyJSON: id,
                        requestID: nil, subscribeId: nil)
        case .ciDiscoveryReply(let src, let dst, let id):
            return .init(ciType: "DiscoveryReply", sourceMUID: src, destMUID: dst,
                        resource: nil, headerJSON: nil, bodyJSON: id,
                        requestID: nil, subscribeId: nil)
        default:
            return nil
        }
    }
}
