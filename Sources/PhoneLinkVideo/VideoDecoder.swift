// VideoDecoder — VideoToolbox H.264/H.265 decompression pipeline plus an
// AVSampleBufferDisplayLayer renderer for screen mirroring.
//
// Flow: stream channel frame bytes -> normalize to AVCC NAL units -> build a
// CMVideoFormatDescription from the parameter sets -> wrap VCL NALs in a
// CMSampleBuffer -> either (a) enqueue directly to an
// AVSampleBufferDisplayLayer (it decodes + renders), or (b) run through a
// VTDecompressionSession to obtain CVPixelBuffers.
//
// SPDX-License-Identifier: MIT

#if canImport(VideoToolbox)
import Foundation
import CoreMedia
import VideoToolbox

public enum VideoDecodeError: Error {
    case missingParameterSets
    case formatDescriptionFailed(OSStatus)
    case blockBufferFailed(OSStatus)
    case sampleBufferFailed(OSStatus)
    case sessionCreateFailed(OSStatus)
    case decodeFailed(OSStatus)
}

// MARK: - Format description from parameter sets

public enum VideoFormatDescriptionBuilder {
    public static func make(codec: VideoCodec, parameterSets: [Data]) throws -> CMFormatDescription {
        guard parameterSets.count >= 2 else { throw VideoDecodeError.missingParameterSets }

        // Keep the parameter-set bytes alive for the duration of the call.
        let buffers = parameterSets.map { [UInt8]($0) }
        var pointers: [UnsafePointer<UInt8>] = []
        var sizes: [Int] = []
        for b in buffers {
            b.withUnsafeBufferPointer { pointers.append($0.baseAddress!) }
            sizes.append(b.count)
        }

        var format: CMFormatDescription?
        let status: OSStatus = pointers.withUnsafeBufferPointer { ptrs in
            sizes.withUnsafeBufferPointer { szs in
                switch codec {
                case .h264:
                    return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: ptrs.count,
                        parameterSetPointers: ptrs.baseAddress!,
                        parameterSetSizes: szs.baseAddress!,
                        nalUnitHeaderLength: 4,
                        formatDescriptionOut: &format)
                case .hevc:
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: ptrs.count,
                        parameterSetPointers: ptrs.baseAddress!,
                        parameterSetSizes: szs.baseAddress!,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &format)
                }
            }
        }
        guard status == noErr, let format else {
            throw VideoDecodeError.formatDescriptionFailed(status)
        }
        return format
    }
}

// MARK: - Sample buffer assembly

public enum SampleBufferBuilder {
    /// Wrap AVCC-formatted VCL NAL data into a CMSampleBuffer for `format`.
    public static func make(avccData: Data, format: CMFormatDescription,
                            presentationTime: CMTime = .invalid) throws -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        let bytes = [UInt8](avccData)

        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: bytes.count,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard status == kCMBlockBufferNoErr, let blockBuffer else {
            throw VideoDecodeError.blockBufferFailed(status)
        }
        status = bytes.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!, blockBuffer: blockBuffer,
                offsetIntoDestination: 0, dataLength: bytes.count)
        }
        guard status == kCMBlockBufferNoErr else {
            throw VideoDecodeError.blockBufferFailed(status)
        }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: presentationTime,
                                        decodeTimeStamp: .invalid)
        var sampleSize = bytes.count
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer else {
            throw VideoDecodeError.sampleBufferFailed(status)
        }
        return sampleBuffer
    }
}

// MARK: - VTDecompressionSession pipeline

public final class VTVideoDecoder {
    public typealias FrameHandler = (CVImageBuffer, CMTime) -> Void

    private var session: VTDecompressionSession?
    private let format: CMFormatDescription
    private let onFrame: FrameHandler

    public init(format: CMFormatDescription, onFrame: @escaping FrameHandler) throws {
        self.format = format
        self.onFrame = onFrame
        try createSession()
    }

    deinit {
        if let session { VTDecompressionSessionInvalidate(session) }
    }

    private func createSession() throws {
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { decompressionOutputRefCon, _, status, _, imageBuffer, pts, _ in
                guard status == noErr, let imageBuffer,
                      let refCon = decompressionOutputRefCon else { return }
                let decoder = Unmanaged<VTVideoDecoder>.fromOpaque(refCon).takeUnretainedValue()
                decoder.onFrame(imageBuffer, pts)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session)
        guard status == noErr, let session else {
            throw VideoDecodeError.sessionCreateFailed(status)
        }
        self.session = session
    }

    /// Decode one sample buffer; frames arrive via the init callback.
    public func decode(_ sampleBuffer: CMSampleBuffer) throws {
        guard let session else { throw VideoDecodeError.sessionCreateFailed(-1) }
        var flagsOut = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil, infoFlagsOut: &flagsOut)
        guard status == noErr else { throw VideoDecodeError.decodeFailed(status) }
    }
}
#endif
