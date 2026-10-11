// VideoStreamController — the pipeline entry point: takes compressed frame
// bytes off the streaming channel and renders them for screen mirroring.
//
// Responsibilities:
//  * Track the current parameter sets (SPS/PPS[/VPS]) and (re)build the
//    CMVideoFormatDescription whenever they change.
//  * Normalize each access unit to AVCC, wrap it in a CMSampleBuffer, and
//    enqueue it on an AVSampleBufferDisplayLayer (which decodes via
//    VideoToolbox) — or route it through a VTDecompressionSession when raw
//    CVPixelBuffers are needed.
//
// SPDX-License-Identifier: MIT

#if canImport(VideoToolbox) && canImport(AVFoundation)
import Foundation
import CoreMedia
import VideoToolbox

public final class VideoStreamController {
    public let codec: VideoCodec

    #if canImport(AppKit)
    /// Set this to the display view to render onto (AVSampleBufferDisplayLayer).
    public weak var displayView: SampleBufferDisplayNSView?
    #endif

    private var format: CMFormatDescription?
    private var parameterSets: [UInt8: Data] = [:]   // nalType -> latest payload
    private var frameIndex: Int64 = 0

    public init(codec: VideoCodec) {
        self.codec = codec
    }

    /// NAL types that are parameter sets (not displayable VCL data).
    private func isParameterSet(_ type: UInt8) -> Bool {
        switch codec {
        case .h264: return type == 7 || type == 8                 // SPS, PPS
        case .hevc: return type == 32 || type == 33 || type == 34 // VPS, SPS, PPS
        }
    }

    /// Parameter sets in the order CoreMedia expects.
    private func orderedParameterSets() -> [Data] {
        switch codec {
        case .h264:
            return [parameterSets[7], parameterSets[8]].compactMap { $0 }
        case .hevc:
            return [parameterSets[32], parameterSets[33], parameterSets[34]].compactMap { $0 }
        }
    }

    /// Feed one access unit (one frame's worth of bytes), Annex B or AVCC.
    /// Returns the CMSampleBuffer that was produced/enqueued, if any.
    @discardableResult
    public func feed(frame data: Data) throws -> CMSampleBuffer? {
        let nalUnits = NALParser.isAnnexB(data)
            ? NALParser.annexBToNALUnits(data)
            : NALParser.avccToNALUnits(data)

        var vcl: [Data] = []
        var sawNewParameterSet = false
        for nal in nalUnits {
            let type = NALParser.nalType(nal, codec: codec)
            if isParameterSet(type) {
                if parameterSets[type] != nal { sawNewParameterSet = true }
                parameterSets[type] = nal
            } else {
                vcl.append(nal)
            }
        }

        if sawNewParameterSet || format == nil {
            let sets = orderedParameterSets()
            if sets.count >= 2 {
                format = try VideoFormatDescriptionBuilder.make(codec: codec, parameterSets: sets)
            }
        }

        guard let format, !vcl.isEmpty else { return nil }

        let avcc = NALParser.toAVCC(vcl)
        let pts = CMTime(value: frameIndex, timescale: 600)
        frameIndex += 1
        let sampleBuffer = try SampleBufferBuilder.make(avccData: avcc, format: format,
                                                        presentationTime: pts)
        #if canImport(AppKit)
        displayView?.enqueue(sampleBuffer)
        #endif
        return sampleBuffer
    }

    /// Reset decoder state (e.g. on reconnect or resolution change).
    public func reset() {
        format = nil
        parameterSets.removeAll()
        frameIndex = 0
        #if canImport(AppKit)
        displayView?.flush()
        #endif
    }
}
#endif
