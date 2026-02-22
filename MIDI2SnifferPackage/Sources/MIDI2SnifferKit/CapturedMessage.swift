// CapturedMessage.swift — Data model for captured MIDI messages

import Foundation

public struct CapturedMessage: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let monotonicTime: UInt64
    public let sourceID: UInt32?
    public let sourceName: String
    public let rawData: [UInt8]
    public let umpWords: [UInt32]
    public let decoded: DecodedMessage

    public init(
        timestamp: Date = .now,
        monotonicTime: UInt64 = mach_absolute_time(),
        sourceID: UInt32? = nil,
        sourceName: String,
        rawData: [UInt8],
        umpWords: [UInt32] = [],
        decoded: DecodedMessage
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.monotonicTime = monotonicTime
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.rawData = rawData
        self.umpWords = umpWords
        self.decoded = decoded
    }
}

public enum MessageCategory: String, Sendable, CaseIterable, Codable {
    case note = "Note"
    case cc = "CC"
    case pc = "PC"
    case pitchBend = "PB"
    case pressure = "Pressure"
    case ci = "CI"
    case pe = "PE"
    case system = "System"
    case unknown = "Unknown"
}

public enum DecodedMessage: Sendable {
    // MIDI 2.0 Channel Voice
    case noteOn(ch: UInt8, note: UInt8, velocity16: UInt16, isMIDI2: Bool)
    case noteOff(ch: UInt8, note: UInt8, isMIDI2: Bool)
    case controlChange(ch: UInt8, cc: UInt8, value32: UInt32, value7: UInt8, isMIDI2: Bool)
    case programChange(ch: UInt8, program: UInt8, bank: String?, isMIDI2: Bool)
    case pitchBend(ch: UInt8, value32: UInt32, isMIDI2: Bool)
    case channelPressure(ch: UInt8, value32: UInt32, isMIDI2: Bool)
    case polyPressure(ch: UInt8, note: UInt8, value32: UInt32, isMIDI2: Bool)

    // MIDI-CI Discovery
    case ciDiscovery(srcMUID: String, identity: String)
    case ciDiscoveryReply(srcMUID: String, dstMUID: String, identity: String)
    case ciInvalidateMUID(muid: String)
    case ciEndpointInfo(srcMUID: String, dstMUID: String)
    case ciEndpointInfoReply(srcMUID: String, dstMUID: String)
    case ciNAK(srcMUID: String, dstMUID: String)
    case ciACK(srcMUID: String, dstMUID: String)

    // PE Capability
    case peCapabilityInquiry(srcMUID: String, dstMUID: String)
    case peCapabilityReply(srcMUID: String, dstMUID: String)

    // PE Get/Set
    case peGetInquiry(srcMUID: String, dstMUID: String, resource: String?, requestID: UInt8)
    case peGetReply(srcMUID: String, dstMUID: String, headerJSON: String, bodyJSON: String, requestID: UInt8, chunk: Int, totalChunks: Int)
    case peSetInquiry(srcMUID: String, dstMUID: String, resource: String?, requestID: UInt8, bodyJSON: String)
    case peSetReply(srcMUID: String, dstMUID: String, requestID: UInt8)

    // PE Subscribe/Notify
    case peSubscribe(srcMUID: String, dstMUID: String, resource: String?, command: String?)
    case peSubscribeReply(srcMUID: String, dstMUID: String, subscribeId: String?)
    case peNotify(srcMUID: String, dstMUID: String, resource: String?, bodyJSON: String, subscribeId: String?)

    // 128-bit UMP messages
    case data128(hex: String)
    case flexData(hex: String)
    case umpStream(hex: String)

    // System/Other
    case sysEx(bytes: Int)
    case rawMIDI1(statusByte: UInt8, data1: UInt8, data2: UInt8)
    case unknown(hex: String)

    public var summary: String {
        switch self {
        case .noteOn(let ch, let note, let v, let m2):
            let tag = m2 ? "" : " (M1)"
            return "NoteOn ch=\(ch) n=\(note) v16=\(v)\(tag)"
        case .noteOff(let ch, let note, let m2):
            let tag = m2 ? "" : " (M1)"
            return "NoteOff ch=\(ch) n=\(note)\(tag)"
        case .controlChange(let ch, let cc, let v32, let v7, let m2):
            if m2 {
                return "CC ch=\(ch) cc=\(cc) v32=0x\(String(format: "%08X", v32))"
            }
            return "CC ch=\(ch) cc=\(cc) v=\(v7) (M1)"
        case .programChange(let ch, let p, let bank, let m2):
            let bankStr = bank.map { " bank=\($0)" } ?? ""
            let tag = m2 ? "" : " (M1)"
            return "PC ch=\(ch) p=\(p)\(bankStr)\(tag)"
        case .pitchBend(let ch, let v, let m2):
            let tag = m2 ? "" : " (M1)"
            return "PB ch=\(ch) v=0x\(String(format: "%08X", v))\(tag)"
        case .channelPressure(let ch, let v, _):
            return "ChanPressure ch=\(ch) v=0x\(String(format: "%08X", v))"
        case .polyPressure(let ch, let note, let v, _):
            return "PolyPressure ch=\(ch) n=\(note) v=0x\(String(format: "%08X", v))"
        case .ciDiscovery(let src, let id):
            return "CI Discovery src=\(src) \(id)"
        case .ciDiscoveryReply(let src, let dst, let id):
            return "CI DiscoveryReply \(src)->\(dst) \(id)"
        case .ciInvalidateMUID(let muid):
            return "CI InvalidateMUID \(muid)"
        case .ciEndpointInfo(let src, let dst):
            return "CI EndpointInfo \(src)->\(dst)"
        case .ciEndpointInfoReply(let src, let dst):
            return "CI EndpointInfoReply \(src)->\(dst)"
        case .ciNAK(let src, let dst):
            return "CI NAK \(src)->\(dst)"
        case .ciACK(let src, let dst):
            return "CI ACK \(src)->\(dst)"
        case .peCapabilityInquiry(let src, let dst):
            return "PE CapInquiry \(src)->\(dst)"
        case .peCapabilityReply(let src, let dst):
            return "PE CapReply \(src)->\(dst)"
        case .peGetInquiry(let src, let dst, let res, let req):
            return "PE GET \(src)->\(dst) \(res ?? "?") reqID=\(req)"
        case .peGetReply(let src, let dst, _, _, let req, let chunk, let total):
            return "PE GET-Reply \(src)->\(dst) reqID=\(req) chunk=\(chunk)/\(total)"
        case .peSetInquiry(let src, let dst, let res, let req, _):
            return "PE SET \(src)->\(dst) \(res ?? "?") reqID=\(req)"
        case .peSetReply(let src, let dst, let req):
            return "PE SET-Reply \(src)->\(dst) reqID=\(req)"
        case .peSubscribe(let src, let dst, let res, let cmd):
            return "PE Subscribe \(src)->\(dst) \(res ?? "?") cmd=\(cmd ?? "?")"
        case .peSubscribeReply(let src, let dst, let subId):
            return "PE SubscribeReply \(src)->\(dst) subId=\(subId ?? "?")"
        case .peNotify(let src, let dst, let res, _, let subId):
            return "PE Notify \(src)->\(dst) \(res ?? "?") subId=\(subId ?? "?")"
        case .data128(let hex):
            return "Data128 \(hex)"
        case .flexData(let hex):
            return "FlexData \(hex)"
        case .umpStream(let hex):
            return "UMP Stream \(hex)"
        case .sysEx(let n):
            return "SysEx (\(n) bytes)"
        case .rawMIDI1(let st, let d1, let d2):
            return String(format: "Raw MIDI1 %02X %02X %02X", st, d1, d2)
        case .unknown(let hex):
            return "Unknown: \(hex)"
        }
    }

    public var category: MessageCategory {
        switch self {
        case .noteOn, .noteOff: return .note
        case .controlChange: return .cc
        case .programChange: return .pc
        case .pitchBend: return .pitchBend
        case .channelPressure, .polyPressure: return .pressure
        case .ciDiscovery, .ciDiscoveryReply, .ciInvalidateMUID,
             .ciEndpointInfo, .ciEndpointInfoReply, .ciNAK, .ciACK:
            return .ci
        case .peCapabilityInquiry, .peCapabilityReply,
             .peGetInquiry, .peGetReply, .peSetInquiry, .peSetReply,
             .peSubscribe, .peSubscribeReply, .peNotify:
            return .pe
        case .data128, .flexData, .umpStream: return .system
        case .sysEx: return .system
        case .rawMIDI1, .unknown: return .unknown
        }
    }

    public var detailText: String {
        switch self {
        case .peGetReply(let src, let dst, let hdr, let body, let req, let chunk, let total):
            return """
            PE GET Reply
            \(src) -> \(dst)  ReqID:\(req)  Chunk:\(chunk)/\(total)
            Header: \(hdr)
            Body: \(String(body.prefix(4000)))
            """
        case .peSetInquiry(let src, let dst, let res, let req, let body):
            return """
            PE SET Inquiry
            \(src) -> \(dst)  Resource:\(res ?? "?")  ReqID:\(req)
            Body: \(String(body.prefix(4000)))
            """
        case .peNotify(let src, let dst, let res, let body, let subId):
            return """
            PE Notify
            \(src) -> \(dst)  Resource:\(res ?? "?")  SubscribeID:\(subId ?? "?")
            Body: \(String(body.prefix(4000)))
            """
        default:
            return summary
        }
    }
}
