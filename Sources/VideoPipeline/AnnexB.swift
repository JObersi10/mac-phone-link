import Foundation

/// Helpers for working with H.264 Annex-B byte streams (the format scrcpy
/// emits: NAL units separated by `00 00 00 01` / `00 00 01` start codes).
///
/// VideoToolbox does not consume Annex-B directly — it wants parameter sets
/// supplied out of band and frame NAL units length-prefixed (AVCC). These
/// helpers bridge the two.
public enum AnnexB {
    /// Split an Annex-B buffer into its constituent NAL units (payload only,
    /// start codes stripped).
    public static func nalUnits(_ data: [UInt8]) -> [[UInt8]] {
        var units: [[UInt8]] = []
        var i = 0
        let n = data.count
        var unitStart: Int? = nil

        func isStartCode(_ idx: Int) -> Int? {
            if idx + 3 < n, data[idx] == 0, data[idx+1] == 0, data[idx+2] == 0, data[idx+3] == 1 {
                return 4
            }
            if idx + 2 < n, data[idx] == 0, data[idx+1] == 0, data[idx+2] == 1 {
                return 3
            }
            return nil
        }

        while i < n {
            if let scLen = isStartCode(i) {
                if let start = unitStart, i > start {
                    units.append(Array(data[start..<i]))
                }
                i += scLen
                unitStart = i
            } else {
                i += 1
            }
        }
        if let start = unitStart, start < n {
            units.append(Array(data[start..<n]))
        }
        return units
    }

    /// NAL unit type is the low 5 bits of the first byte. 7 = SPS, 8 = PPS.
    public static func type(of nal: [UInt8]) -> UInt8 {
        guard let first = nal.first else { return 0 }
        return first & 0x1f
    }

    /// Convert Annex-B frame data to AVCC (each NAL prefixed by a 4-byte
    /// big-endian length), skipping parameter-set NALs (handled separately).
    public static func toAVCC(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        for nal in nalUnits(data) {
            let t = type(of: nal)
            if t == 7 || t == 8 { continue } // SPS/PPS go in the format description
            let len = UInt32(nal.count)
            out.append(UInt8((len >> 24) & 0xff))
            out.append(UInt8((len >> 16) & 0xff))
            out.append(UInt8((len >> 8) & 0xff))
            out.append(UInt8(len & 0xff))
            out.append(contentsOf: nal)
        }
        return out
    }
}
