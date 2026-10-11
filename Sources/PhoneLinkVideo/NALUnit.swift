// NALUnit — parse H.264/H.265 bitstreams into NAL units and normalize them to
// AVCC (4-byte length-prefixed) for CoreMedia, plus parameter-set extraction.
//
// Incoming frames from the streaming channel may be Annex B (00 00 00 01 /
// 00 00 01 start codes) or already AVCC; both are handled.
//
// SPDX-License-Identifier: MIT

import Foundation

public enum VideoCodec: Sendable {
    case h264
    case hevc
}

public struct NALUnit: Equatable {
    public let type: UInt8      // codec-specific NAL type
    public let payload: Data    // raw NAL (no start code / length prefix)
}

public enum NALParser {
    /// Split an Annex B byte stream into NAL payloads (start codes removed).
    public static func annexBToNALUnits(_ data: Data) -> [Data] {
        var units: [Data] = []
        let bytes = [UInt8](data)
        let n = bytes.count
        var i = 0
        var unitStart = -1

        func startCodeLength(at idx: Int) -> Int {
            if idx + 3 < n, bytes[idx] == 0, bytes[idx+1] == 0, bytes[idx+2] == 0, bytes[idx+3] == 1 { return 4 }
            if idx + 2 < n, bytes[idx] == 0, bytes[idx+1] == 0, bytes[idx+2] == 1 { return 3 }
            return 0
        }

        while i < n {
            let sc = startCodeLength(at: i)
            if sc > 0 {
                if unitStart >= 0 && i > unitStart {
                    units.append(Data(bytes[unitStart..<i]))
                }
                i += sc
                unitStart = i
            } else {
                i += 1
            }
        }
        if unitStart >= 0 && unitStart < n {
            units.append(Data(bytes[unitStart..<n]))
        }
        return units.filter { !$0.isEmpty }
    }

    /// Split an AVCC (length-prefixed) stream into NAL payloads.
    /// `lengthSize` is the prefix width (usually 4).
    public static func avccToNALUnits(_ data: Data, lengthSize: Int = 4) -> [Data] {
        var units: [Data] = []
        let bytes = [UInt8](data)
        var i = 0
        while i + lengthSize <= bytes.count {
            var length = 0
            for k in 0..<lengthSize { length = (length << 8) | Int(bytes[i + k]) }
            i += lengthSize
            guard length > 0, i + length <= bytes.count else { break }
            units.append(Data(bytes[i..<(i + length)]))
            i += length
        }
        return units
    }

    /// Heuristic: does this look like Annex B (leading start code)?
    public static func isAnnexB(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(4))
        if b.count >= 4, b[0] == 0, b[1] == 0, b[2] == 0, b[3] == 1 { return true }
        if b.count >= 3, b[0] == 0, b[1] == 0, b[2] == 1 { return true }
        return false
    }

    public static func nalType(_ nal: Data, codec: VideoCodec) -> UInt8 {
        guard let first = nal.first else { return 0 }
        switch codec {
        case .h264: return first & 0x1F
        case .hevc: return (first >> 1) & 0x3F
        }
    }

    /// Encode NAL payloads as an AVCC block (4-byte big-endian length prefixes).
    public static func toAVCC(_ nalUnits: [Data]) -> Data {
        var out = Data()
        for nal in nalUnits {
            var len = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
            out.append(nal)
        }
        return out
    }
}
