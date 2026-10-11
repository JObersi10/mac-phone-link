// H264SPS — parse an H.264 SPS NAL to recover the coded picture dimensions.
//
// The mirror's real resolution isn't known until the stream's SPS arrives;
// feeding the true size into the cursor-coordinate mapping is what makes remote
// control land on the right pixel. This is a minimal SPS parser (Exp-Golomb bit
// reader) covering the fields up to frame cropping — enough for width/height.
//
// SPDX-License-Identifier: MIT

import Foundation

public struct H264Dimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int
}

public enum H264SPS {

    /// Parse width/height from an SPS NAL unit (with or without the 1-byte NAL
    /// header; emulation-prevention bytes are stripped). Returns nil on malformed
    /// input.
    public static func dimensions(fromSPS nal: Data) -> H264Dimensions? {
        guard !nal.isEmpty else { return nil }
        // Drop the NAL header byte if present (type 7 in the low 5 bits).
        var bytes = [UInt8](nal)
        if (bytes[0] & 0x1f) == 7 { bytes.removeFirst() }
        let rbsp = stripEmulationPrevention(bytes)
        var r = BitReader(rbsp)

        _ = r.read(8)                       // profile_idc
        _ = r.read(8)                       // constraint flags + reserved
        _ = r.read(8)                       // level_idc
        _ = r.ue()                          // seq_parameter_set_id

        let profile = rbsp.first.map { Int($0) } ?? 0
        if [100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135].contains(profile) {
            let chroma = r.ue()             // chroma_format_idc
            if chroma == 3 { _ = r.read(1) } // separate_colour_plane_flag
            _ = r.ue()                      // bit_depth_luma_minus8
            _ = r.ue()                      // bit_depth_chroma_minus8
            _ = r.read(1)                   // qpprime_y_zero_transform_bypass_flag
            if r.read(1) == 1 {             // seq_scaling_matrix_present_flag
                let count = (chroma != 3) ? 8 : 12
                for i in 0..<count { skipScalingList(&r, size: i < 6 ? 16 : 64) }
            }
        }

        _ = r.ue()                          // log2_max_frame_num_minus4
        let pocType = r.ue()                // pic_order_cnt_type
        if pocType == 0 {
            _ = r.ue()                      // log2_max_pic_order_cnt_lsb_minus4
        } else if pocType == 1 {
            _ = r.read(1)                   // delta_pic_order_always_zero_flag
            _ = r.se()                      // offset_for_non_ref_pic
            _ = r.se()                      // offset_for_top_to_bottom_field
            let n = r.ue()                  // num_ref_frames_in_pic_order_cnt_cycle
            for _ in 0..<n { _ = r.se() }
        }
        _ = r.ue()                          // max_num_ref_frames
        _ = r.read(1)                       // gaps_in_frame_num_value_allowed_flag

        let picWidthInMbs = r.ue() + 1
        let picHeightInMapUnits = r.ue() + 1
        let frameMbsOnly = r.read(1)        // frame_mbs_only_flag
        if frameMbsOnly == 0 { _ = r.read(1) } // mb_adaptive_frame_field_flag
        _ = r.read(1)                       // direct_8x8_inference_flag

        var cropL = 0, cropR = 0, cropT = 0, cropB = 0
        if r.read(1) == 1 {                 // frame_cropping_flag
            cropL = r.ue(); cropR = r.ue(); cropT = r.ue(); cropB = r.ue()
        }

        guard picWidthInMbs > 0, picHeightInMapUnits > 0 else { return nil }
        let width = picWidthInMbs * 16 - (cropL + cropR) * 2
        let height = (2 - frameMbsOnly) * picHeightInMapUnits * 16 - (cropT + cropB) * 2
        guard width > 0, height > 0, width < 16384, height < 16384 else { return nil }
        return H264Dimensions(width: width, height: height)
    }

    private static func stripEmulationPrevention(_ b: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(b.count)
        var zeros = 0
        for x in b {
            if zeros >= 2 && x == 3 { zeros = 0; continue }  // drop 0x03 after 0x0000
            out.append(x)
            zeros = (x == 0) ? zeros + 1 : 0
        }
        return out
    }

    private static func skipScalingList(_ r: inout BitReader, size: Int) {
        var lastScale = 8, nextScale = 8
        for _ in 0..<size {
            if nextScale != 0 {
                let delta = r.se()
                nextScale = (lastScale + delta + 256) % 256
            }
            lastScale = (nextScale == 0) ? lastScale : nextScale
        }
    }
}

/// Minimal MSB-first bit reader with Exp-Golomb (ue/se) support.
struct BitReader {
    private let bytes: [UInt8]
    private var bit = 0
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func read(_ n: Int) -> Int {
        var v = 0
        for _ in 0..<n {
            let byteIndex = bit >> 3
            guard byteIndex < bytes.count else { return v << 1 } // ran out → pad 0
            let b = bytes[byteIndex]
            let shift = 7 - (bit & 7)
            v = (v << 1) | Int((b >> shift) & 1)
            bit += 1
        }
        return v
    }

    /// Unsigned Exp-Golomb.
    mutating func ue() -> Int {
        var zeros = 0
        while bit < bytes.count * 8 && read(1) == 0 { zeros += 1 }
        if zeros == 0 { return 0 }
        return (1 << zeros) - 1 + read(zeros)
    }

    /// Signed Exp-Golomb.
    mutating func se() -> Int {
        let k = ue()
        let sign = (k & 1) == 1 ? 1 : -1
        return sign * ((k + 1) / 2)
    }
}
