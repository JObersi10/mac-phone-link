import Foundation
import CoreMedia
import VideoToolbox
import ScrcpyProtocol

public enum DecoderError: Error {
    case missingParameterSets
    case formatDescriptionFailed(OSStatus)
    case blockBufferFailed(OSStatus)
    case sampleBufferFailed(OSStatus)
    case sessionCreateFailed(OSStatus)
    case decodeFailed(OSStatus)
}

/// Hardware-accelerated H.264 decoder built on VideoToolbox.
///
/// Feed it `MediaPacket`s from `ScrcpyProtocol.VideoDemuxer`. Config packets
/// (SPS/PPS) rebuild the format description and (re)create the decompression
/// session; frame packets are decoded and delivered as `CVImageBuffer`s on the
/// `onFrame` callback.
public final class H264Decoder {
    public var onFrame: ((CVImageBuffer, CMTime) -> Void)?

    private var formatDescription: CMFormatDescription?
    private var session: VTDecompressionSession?
    private var sps: [UInt8]?
    private var pps: [UInt8]?

    public init() {}

    deinit { invalidateSession() }

    public func decode(_ packet: MediaPacket) throws {
        if packet.isConfig {
            try ingestParameterSets(from: packet.payload)
            return
        }
        guard session != nil else {
            // No config seen yet — drop until the first SPS/PPS arrives.
            return
        }
        let avcc = AnnexB.toAVCC(packet.payload)
        guard !avcc.isEmpty else { return }
        try decodeAVCC(avcc, pts: packet.pts)
    }

    // MARK: - Parameter sets

    private func ingestParameterSets(from payload: [UInt8]) throws {
        for nal in AnnexB.nalUnits(payload) {
            switch AnnexB.type(of: nal) {
            case 7: sps = nal
            case 8: pps = nal
            default: break
            }
        }
        guard let sps, let pps else { throw DecoderError.missingParameterSets }
        try rebuildFormatDescription(sps: sps, pps: pps)
    }

    private func rebuildFormatDescription(sps: [UInt8], pps: [UInt8]) throws {
        var formatDesc: CMFormatDescription?
        let status = sps.withUnsafeBufferPointer { spsPtr in
            pps.withUnsafeBufferPointer { ppsPtr -> OSStatus in
                let paramSetPointers: [UnsafePointer<UInt8>] = [spsPtr.baseAddress!, ppsPtr.baseAddress!]
                let paramSetSizes: [Int] = [sps.count, pps.count]
                return paramSetPointers.withUnsafeBufferPointer { ptrs in
                    paramSetSizes.withUnsafeBufferPointer { sizes in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: ptrs.baseAddress!,
                            parameterSetSizes: sizes.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &formatDesc)
                    }
                }
            }
        }
        guard status == noErr, let formatDesc else {
            throw DecoderError.formatDescriptionFailed(status)
        }
        self.formatDescription = formatDesc
        try createSession(formatDescription: formatDesc)
    }

    // MARK: - Session

    private func createSession(formatDescription: CMFormatDescription) throws {
        invalidateSession()

        let decoderSpec: [CFString: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ]
        let imageAttrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpec as CFDictionary,
            imageBufferAttributes: imageAttrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session)
        guard status == noErr, let session else {
            throw DecoderError.sessionCreateFailed(status)
        }
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        self.session = session
    }

    private func invalidateSession() {
        if let session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
    }

    // MARK: - Decode

    private func decodeAVCC(_ avcc: [UInt8], pts: UInt64) throws {
        guard let formatDescription, let session else { return }

        // Allocate a block buffer that OWNS its memory, then copy the AVCC bytes
        // into it. Decode is asynchronous, so the sample buffer may outlive this
        // call — it must not point at a local Swift array's storage.
        var blockBuffer: CMBlockBuffer?
        let allocStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer)
        guard allocStatus == kCMBlockBufferNoErr, let blockBuffer else {
            throw DecoderError.blockBufferFailed(allocStatus)
        }
        let copyStatus = avcc.withUnsafeBytes { raw -> OSStatus in
            CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avcc.count)
        }
        guard copyStatus == kCMBlockBufferNoErr else {
            throw DecoderError.blockBufferFailed(copyStatus)
        }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = avcc.count
        let timescale: CMTimeScale = 1_000_000 // pts is microseconds
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(pts), timescale: timescale),
            decodeTimeStamp: .invalid)

        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer)
        guard sampleStatus == noErr, let sampleBuffer else {
            throw DecoderError.sampleBufferFailed(sampleStatus)
        }

        let flags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
        var flagsOut = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: flags,
            frameRefcon: nil,
            infoFlagsOut: &flagsOut)
        guard decodeStatus == noErr else {
            throw DecoderError.decodeFailed(decodeStatus)
        }
    }

    fileprivate func emit(_ image: CVImageBuffer, pts: CMTime) {
        onFrame?(image, pts)
    }
}

/// C callback trampoline: VideoToolbox hands decoded frames back here.
private func decompressionCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard status == noErr, let imageBuffer, let refCon = decompressionOutputRefCon else { return }
    let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()
    decoder.emit(imageBuffer, pts: presentationTimeStamp)
}
