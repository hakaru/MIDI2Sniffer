// MessageDecoder.swift — UMP / CI / PE message decoder

import Foundation
import MIDI2Kit

public enum MessageDecoder: Sendable {

    // MARK: - Main entry point

    public static func decode(
        data: [UInt8],
        umpWords: [UInt32],
        sourceName: String,
        sourceID: UInt32?
    ) -> CapturedMessage {
        let decoded: DecodedMessage

        if isCISysEx(data) {
            decoded = decodeCIMessage(data)
        } else if !umpWords.isEmpty {
            decoded = decodeUMP(umpWords: umpWords)
        } else if let first = data.first, first >= 0x80 && first < 0xF0 {
            decoded = decodeRawMIDI1(data)
        } else if data.first == 0xF0 {
            decoded = .sysEx(bytes: data.count)
        } else {
            let hex = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            decoded = .unknown(hex: hex)
        }

        return CapturedMessage(
            sourceID: sourceID,
            sourceName: sourceName,
            rawData: data,
            umpWords: umpWords,
            decoded: decoded
        )
    }

    // MARK: - CI SysEx detection

    private static func isCISysEx(_ data: [UInt8]) -> Bool {
        data.count >= 5 && data[0] == 0xF0 && data[1] == 0x7E && data[3] == 0x0D
    }

    // MARK: - UMP decode

    private static func decodeUMP(umpWords: [UInt32]) -> DecodedMessage {
        guard let w1 = umpWords.first else { return .unknown(hex: "empty UMP") }
        let mt = (w1 >> 28) & 0xF
        let st = (w1 >> 20) & 0xF
        let ch = UInt8((w1 >> 16) & 0xF)
        let w2 = umpWords.count > 1 ? umpWords[1] : UInt32(0)

        switch mt {
        case 4: // MIDI 2.0 Channel Voice
            return decodeMIDI2ChannelVoice(st: st, ch: ch, w1: w1, w2: w2)
        case 2: // MIDI 1.0 Channel Voice
            return decodeMIDI1ChannelVoice(st: st, ch: ch, w1: w1)
        case 0x5: // Data128 / SysEx8
            let hex = umpWords.map { String(format: "%08X", $0) }.joined(separator: " ")
            return .data128(hex: hex)
        case 0xD: // Flex Data
            let hex = umpWords.map { String(format: "%08X", $0) }.joined(separator: " ")
            return .flexData(hex: hex)
        case 0xF: // UMP Stream
            let hex = umpWords.map { String(format: "%08X", $0) }.joined(separator: " ")
            return .umpStream(hex: hex)
        default:
            let hex = umpWords.map { String(format: "%08X", $0) }.joined(separator: " ")
            return .unknown(hex: "UMP mt=\(mt) \(hex)")
        }
    }

    private static func decodeMIDI2ChannelVoice(st: UInt32, ch: UInt8, w1: UInt32, w2: UInt32) -> DecodedMessage {
        let index = UInt8((w1 >> 8) & 0x7F)

        switch st {
        case 0x9: // Note On
            let v16 = UInt16(w2 >> 16)
            return .noteOn(ch: ch, note: index, velocity16: v16, isMIDI2: true)
        case 0x8: // Note Off
            return .noteOff(ch: ch, note: index, isMIDI2: true)
        case 0xB: // CC
            let v7 = UInt8(w2 >> 25)
            return .controlChange(ch: ch, cc: index, value32: w2, value7: v7, isMIDI2: true)
        case 0xC: // Program Change
            let program = UInt8((w2 >> 24) & 0x7F)
            let bankValid = (w2 & 0x80000000) != 0
            var bankStr: String? = nil
            if bankValid {
                let msb = UInt8((w2 >> 8) & 0x7F)
                let lsb = UInt8(w2 & 0x7F)
                bankStr = "\(msb):\(lsb)"
            }
            return .programChange(ch: ch, program: program, bank: bankStr, isMIDI2: true)
        case 0xE: // Pitch Bend
            return .pitchBend(ch: ch, value32: w2, isMIDI2: true)
        case 0xD: // Channel Pressure
            return .channelPressure(ch: ch, value32: w2, isMIDI2: true)
        case 0xA: // Poly Pressure
            return .polyPressure(ch: ch, note: index, value32: w2, isMIDI2: true)
        default:
            let hex = String(format: "%08X %08X", w1, w2)
            return .unknown(hex: "M2 st=0x\(String(format: "%X", st)) \(hex)")
        }
    }

    private static func decodeMIDI1ChannelVoice(st: UInt32, ch: UInt8, w1: UInt32) -> DecodedMessage {
        let d1 = UInt8((w1 >> 8) & 0x7F)
        let d2 = UInt8(w1 & 0x7F)

        switch st {
        case 0x9:
            let v16 = UInt16(d2) << 9
            return .noteOn(ch: ch, note: d1, velocity16: v16, isMIDI2: false)
        case 0x8:
            return .noteOff(ch: ch, note: d1, isMIDI2: false)
        case 0xB:
            let v32 = UInt32(d2) << 25
            return .controlChange(ch: ch, cc: d1, value32: v32, value7: d2, isMIDI2: false)
        case 0xC:
            return .programChange(ch: ch, program: d1, bank: nil, isMIDI2: false)
        case 0xE:
            let v14 = UInt16(d1) | (UInt16(d2) << 7)
            let v32 = UInt32(v14) << 18
            return .pitchBend(ch: ch, value32: v32, isMIDI2: false)
        case 0xD:
            let v32 = UInt32(d1) << 25
            return .channelPressure(ch: ch, value32: v32, isMIDI2: false)
        case 0xA:
            let v32 = UInt32(d2) << 25
            return .polyPressure(ch: ch, note: d1, value32: v32, isMIDI2: false)
        default:
            return .unknown(hex: String(format: "M1 st=0x%X %08X", st, w1))
        }
    }

    // MARK: - Raw MIDI 1.0 decode

    private static func decodeRawMIDI1(_ data: [UInt8]) -> DecodedMessage {
        guard let first = data.first else {
            return .unknown(hex: "empty")
        }
        let statusNibble = first >> 4
        let ch = first & 0x0F

        switch statusNibble {
        case 0x9 where data.count >= 3:
            let v16 = UInt16(data[2]) << 9
            return .noteOn(ch: ch, note: data[1], velocity16: v16, isMIDI2: false)
        case 0x8 where data.count >= 3:
            return .noteOff(ch: ch, note: data[1], isMIDI2: false)
        case 0xB where data.count >= 3:
            let v32 = UInt32(data[2]) << 25
            return .controlChange(ch: ch, cc: data[1], value32: v32, value7: data[2], isMIDI2: false)
        case 0xC where data.count >= 2:
            return .programChange(ch: ch, program: data[1], bank: nil, isMIDI2: false)
        case 0xE where data.count >= 3:
            let v14 = UInt16(data[1]) | (UInt16(data[2]) << 7)
            let v32 = UInt32(v14) << 18
            return .pitchBend(ch: ch, value32: v32, isMIDI2: false)
        case 0xD where data.count >= 2:
            let v32 = UInt32(data[1]) << 25
            return .channelPressure(ch: ch, value32: v32, isMIDI2: false)
        case 0xA where data.count >= 3:
            let v32 = UInt32(data[2]) << 25
            return .polyPressure(ch: ch, note: data[1], value32: v32, isMIDI2: false)
        default:
            return .rawMIDI1(statusByte: first,
                            data1: data.count > 1 ? data[1] : 0,
                            data2: data.count > 2 ? data[2] : 0)
        }
    }

    // MARK: - CI/PE SysEx decode

    private static func decodeCIMessage(_ data: [UInt8]) -> DecodedMessage {
        guard data.count >= 5 else { return .unknown(hex: "CI too short") }

        let subID2 = data[4]
        let (srcStr, dstStr) = parseMUIDs(data)

        switch subID2 {
        case 0x70: // Discovery
            let identity = parseIdentity(data, offset: 13)
            return .ciDiscovery(srcMUID: srcStr, identity: identity)
        case 0x71: // Discovery Reply
            let identity = parseIdentity(data, offset: 13)
            return .ciDiscoveryReply(srcMUID: srcStr, dstMUID: dstStr, identity: identity)
        case 0x72: // Endpoint Info Inquiry
            return .ciEndpointInfo(srcMUID: srcStr, dstMUID: dstStr)
        case 0x73: // Endpoint Info Reply
            return .ciEndpointInfoReply(srcMUID: srcStr, dstMUID: dstStr)
        case 0x7E: // Invalidate MUID
            return .ciInvalidateMUID(muid: srcStr)
        case 0x7F: // NAK
            return .ciNAK(srcMUID: srcStr, dstMUID: dstStr)
        case 0x7D: // ACK
            return .ciACK(srcMUID: srcStr, dstMUID: dstStr)
        case 0x30: // PE Capability Inquiry
            return .peCapabilityInquiry(srcMUID: srcStr, dstMUID: dstStr)
        case 0x31: // PE Capability Reply
            return .peCapabilityReply(srcMUID: srcStr, dstMUID: dstStr)
        case 0x34: // PE GET Inquiry
            return decodePEGetInquiry(data, src: srcStr, dst: dstStr)
        case 0x35: // PE GET Reply
            return decodePEGetReply(data, src: srcStr, dst: dstStr)
        case 0x36: // PE SET Inquiry
            return decodePESetInquiry(data, src: srcStr, dst: dstStr)
        case 0x37: // PE SET Reply
            return decodePESetReply(data, src: srcStr, dst: dstStr)
        case 0x38: // PE Subscribe
            return decodePESubscribe(data, src: srcStr, dst: dstStr)
        case 0x39: // PE Subscribe Reply
            return decodePESubscribeReply(data, src: srcStr, dst: dstStr)
        case 0x3F: // PE Notify
            return decodePENotify(data, src: srcStr, dst: dstStr)
        default:
            let hex = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            return .unknown(hex: "CI sub=0x\(String(format: "%02X", subID2)) \(hex)")
        }
    }

    // MARK: - MUID extraction

    private static func parseMUIDs(_ data: [UInt8]) -> (src: String, dst: String) {
        guard data.count >= 13 else { return ("?", "?") }
        let s0 = UInt32(data[5]), s1 = UInt32(data[6])
        let s2 = UInt32(data[7]), s3 = UInt32(data[8])
        let src = s0 | (s1 << 7) | (s2 << 14) | (s3 << 21)

        let d0 = UInt32(data[9]), d1 = UInt32(data[10])
        let d2 = UInt32(data[11]), d3 = UInt32(data[12])
        let dst = d0 | (d1 << 7) | (d2 << 14) | (d3 << 21)

        return (String(format: "0x%07X", src), String(format: "0x%07X", dst))
    }

    private static func parseIdentity(_ data: [UInt8], offset: Int) -> String {
        guard data.count > offset + 10 else { return "" }
        let mfr: String
        if data[offset] == 0 {
            mfr = String(format: "0x%02X%02X", data[offset + 1], data[offset + 2])
        } else {
            mfr = String(format: "0x%02X", data[offset])
        }
        let fam = UInt16(data[offset + 3]) | (UInt16(data[offset + 4]) << 8)
        let model = UInt16(data[offset + 5]) | (UInt16(data[offset + 6]) << 8)
        return "mfr=\(mfr) fam=\(fam) model=\(model)"
    }

    // MARK: - PE message decoders

    private static func decodePEGetInquiry(_ data: [UInt8], src: String, dst: String) -> DecodedMessage {
        if let parsed = CIMessageParser.parseFullPEGetInquiry(data) {
            return .peGetInquiry(
                srcMUID: src, dstMUID: dst,
                resource: parsed.resource ?? parsed.resId,
                requestID: parsed.requestID
            )
        }
        // Fallback: extract requestID from byte 13
        let reqID = data.count > 13 ? data[13] : 0
        let resource = extractJSONField(data, field: "resource")
        return .peGetInquiry(srcMUID: src, dstMUID: dst, resource: resource, requestID: reqID)
    }

    private static func decodePEGetReply(_ data: [UInt8], src: String, dst: String) -> DecodedMessage {
        if let parsed = CIMessageParser.parseFullPEReply(data) {
            let hdrJSON = String(data: parsed.headerData, encoding: .utf8) ?? "{}"
            let bodyJSON = String(data: parsed.propertyData, encoding: .utf8) ?? ""
            return .peGetReply(
                srcMUID: src, dstMUID: dst,
                headerJSON: hdrJSON, bodyJSON: bodyJSON,
                requestID: parsed.requestID,
                chunk: parsed.thisChunk, totalChunks: parsed.numChunks
            )
        }
        return .peGetReply(
            srcMUID: src, dstMUID: dst,
            headerJSON: "{}", bodyJSON: "",
            requestID: 0, chunk: 1, totalChunks: 1
        )
    }

    private static func decodePESetInquiry(_ data: [UInt8], src: String, dst: String) -> DecodedMessage {
        if let parsed = CIMessageParser.parseFullPESetInquiry(data) {
            let bodyJSON = String(data: parsed.propertyData, encoding: .utf8) ?? ""
            return .peSetInquiry(
                srcMUID: src, dstMUID: dst,
                resource: parsed.resource ?? parsed.resId,
                requestID: parsed.requestID,
                bodyJSON: bodyJSON
            )
        }
        let reqID = data.count > 13 ? data[13] : 0
        return .peSetInquiry(srcMUID: src, dstMUID: dst, resource: nil, requestID: reqID, bodyJSON: "")
    }

    private static func decodePESetReply(_ data: [UInt8], src: String, dst: String) -> DecodedMessage {
        let reqID = data.count > 13 ? data[13] : 0
        return .peSetReply(srcMUID: src, dstMUID: dst, requestID: reqID)
    }

    private static func decodePESubscribe(_ data: [UInt8], src: String, dst: String) -> DecodedMessage {
        let resource = extractJSONField(data, field: "resource")
        let command = extractJSONField(data, field: "command")
        return .peSubscribe(srcMUID: src, dstMUID: dst, resource: resource, command: command)
    }

    private static func decodePESubscribeReply(_ data: [UInt8], src: String, dst: String) -> DecodedMessage {
        if let parsed = CIMessageParser.parseFullSubscribeReply(data) {
            let subId = parsed.subscribeId
            return .peSubscribeReply(srcMUID: src, dstMUID: dst, subscribeId: subId)
        }
        return .peSubscribeReply(srcMUID: src, dstMUID: dst, subscribeId: nil)
    }

    private static func decodePENotify(_ data: [UInt8], src: String, dst: String) -> DecodedMessage {
        if let parsed = CIMessageParser.parseFullNotify(data) {
            let bodyJSON = String(data: parsed.propertyData, encoding: .utf8) ?? ""
            return .peNotify(
                srcMUID: src, dstMUID: dst,
                resource: parsed.resource,
                bodyJSON: bodyJSON,
                subscribeId: parsed.subscribeId
            )
        }
        let resource = extractJSONField(data, field: "resource")
        return .peNotify(srcMUID: src, dstMUID: dst, resource: resource, bodyJSON: "", subscribeId: nil)
    }

    // MARK: - JSON field extraction (fallback)

    private static func extractJSONField(_ data: [UInt8], field: String) -> String? {
        guard let jsonStr = extractFirstJSON(from: data) else { return nil }
        guard let jsonData = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let value = dict[field] else { return nil }
        if let str = value as? String { return str }
        return "\(value)"
    }

    private static func extractFirstJSON(from data: [UInt8]) -> String? {
        guard let startIdx = data.firstIndex(of: 0x7B) else { return nil }
        var depth = 0
        var endIdx = startIdx
        for i in startIdx..<data.count {
            if data[i] == 0x7B { depth += 1 }
            if data[i] == 0x7D { depth -= 1 }
            if depth == 0 {
                endIdx = i
                break
            }
        }
        guard depth == 0 else { return nil }
        let slice = Array(data[startIdx...endIdx])
        return String(bytes: slice, encoding: .utf8)
    }
}
