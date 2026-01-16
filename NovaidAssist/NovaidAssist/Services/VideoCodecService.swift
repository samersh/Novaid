import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia

/// Hardware-accelerated H.264 video encoding and decoding service
/// Based on WebRTC and Zoho Lens best practices
/// Thread-safe: Uses dedicated encoding/decoding queues
class VideoCodecService: NSObject {
    static let shared = VideoCodecService()

    // MARK: - Encoder Properties
    private var encodingSession: VTCompressionSession?
    private let encodingQueue = DispatchQueue(label: "com.novaid.videoEncoding", qos: .userInitiated)
    private var encodedFrameCount: Int64 = 0

    // MARK: - Decoder Properties
    private var decodingSession: VTDecompressionSession?
    private let decodingQueue = DispatchQueue(label: "com.novaid.videoDecoding", qos: .userInitiated)
    private var formatDescription: CMFormatDescription?
    private var frameCounter: Int64 = 0

    // MARK: - Configuration
    // Industry standard: 720p at 30fps for remote assistance
    private let targetWidth: Int32 = 720
    private let targetHeight: Int32 = 1280
    private let targetFrameRate: Int32 = 30

    // Adaptive bitrate: Start at 2.5 Mbps, adjust based on network
    private var currentBitrate: Int = 2_500_000 // 2.5 Mbps
    private let minBitrate: Int = 500_000       // 500 Kbps
    private let maxBitrate: Int = 4_000_000     // 4 Mbps

    // Network monitoring
    private var packetsLost: Int = 0
    private var packetsSent: Int = 0
    private var lastBitrateAdjustment: Date = Date()

    // Callbacks
    var onEncodedFrame: ((Data, CMTime, Bool) -> Void)?  // Data, presentationTime, isKeyframe
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Encoder Setup

    /// Initialize H.264 hardware encoder
    func setupEncoder(width: Int32, height: Int32) -> Bool {
        print("[VideoCodec] Setting up H.264 hardware encoder: \(width)x\(height) @ \(targetFrameRate)fps")

        // Clean up existing session
        if let session = encodingSession {
            VTCompressionSessionInvalidate(session)
            encodingSession = nil
        }

        // Create compression session
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encodingOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            print("[VideoCodec] ❌ Failed to create compression session: \(status)")
            return false
        }

        // Configure encoder properties
        configureEncoder(session: session)

        // Prepare to encode
        VTCompressionSessionPrepareToEncodeFrames(session)

        encodingSession = session
        print("[VideoCodec] ✅ H.264 hardware encoder ready")
        return true
    }

    private func configureEncoder(session: VTCompressionSession) {
        // Real-time encoding for low latency
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_RealTime,
            value: kCFBooleanTrue
        )

        // Profile level (Baseline for compatibility, Main for quality)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ProfileLevel,
            value: kVTProfileLevel_H264_Main_AutoLevel
        )

        // Target bitrate
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AverageBitRate,
            value: currentBitrate as CFNumber
        )

        // Data rate limits (for adaptive bitrate)
        let dataRateLimits = [
            currentBitrate / 8,  // bytes per second
            1                     // per second
        ] as CFArray
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_DataRateLimits,
            value: dataRateLimits
        )

        // Frame rate
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ExpectedFrameRate,
            value: targetFrameRate as CFNumber
        )

        // Max key frame interval (every 2 seconds for quick recovery)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: (targetFrameRate * 2) as CFNumber
        )

        // Allow frame reordering for better compression
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AllowFrameReordering,
            value: kCFBooleanFalse // Disable for lower latency
        )

        // Hardware acceleration
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
            value: kCFBooleanTrue
        )

        print("[VideoCodec] Encoder configured: \(currentBitrate / 1_000_000) Mbps")
    }

    // MARK: - Encoding

    /// Encode a pixel buffer to H.264
    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let session = encodingSession else {
            print("[VideoCodec] ⚠️ No encoding session")
            return
        }

        encodingQueue.async { [weak self] in
            guard let self = self else { return }

            // Force keyframe on first frame and every 60 frames (2 seconds @ 30fps)
            var frameProperties: [CFString: Any]? = nil
            if self.encodedFrameCount == 0 || self.encodedFrameCount % 60 == 0 {
                frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue]
                print("[VideoCodec] 🔑 Forcing keyframe at frame \(self.encodedFrameCount)")
            }

            self.encodedFrameCount += 1

            let status = VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: pixelBuffer,
                presentationTimeStamp: presentationTime,
                duration: .invalid,
                frameProperties: frameProperties as CFDictionary?,
                sourceFrameRefcon: nil,
                infoFlagsOut: nil
            )

            if status != noErr {
                print("[VideoCodec] ❌ Encoding failed: \(status)")
            }
        }
    }

    // Encoding callback
    private let encodingOutputCallback: VTCompressionOutputCallback = {
        (outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer) in

        guard status == noErr else {
            print("[VideoCodec] ❌ Encoding callback error: \(status)")
            return
        }

        guard let sampleBuffer = sampleBuffer else {
            print("[VideoCodec] ⚠️ No sample buffer")
            return
        }

        // Get the service instance
        let service = Unmanaged<VideoCodecService>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()

        // Extract encoded data
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            print("[VideoCodec] ⚠️ Sample buffer not ready")
            return
        }

        // Get data buffer
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("[VideoCodec] ⚠️ No data buffer")
            return
        }

        // Check if this is a keyframe
        var isKeyframe = false
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
        if let attachmentsArray = attachments as? [[CFString: Any]],
           let firstAttachment = attachmentsArray.first {
            if let dependsOnOthers = firstAttachment[kCMSampleAttachmentKey_DependsOnOthers] as? Bool {
                isKeyframe = !dependsOnOthers
            }
        }

        // Copy data
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let copyStatus = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard copyStatus == noErr, let dataPointer = dataPointer else {
            print("[VideoCodec] ❌ Failed to get data pointer")
            return
        }

        // Convert AVCC format to Annex-B format (for WebRTC compatibility)
        // AVCC: [4-byte length][NAL data] → Annex-B: [0x00 0x00 0x00 0x01][NAL data]
        var annexBData = Data()
        let annexBStartCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]

        // For keyframes, prepend SPS/PPS
        if isKeyframe {
            print("[VideoCodec] 🔑 Processing keyframe - adding SPS/PPS")
            if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                // Get SPS
                var spsPointer: UnsafePointer<UInt8>?
                var spsSize: Int = 0
                let spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDescription,
                    parameterSetIndex: 0,
                    parameterSetPointerOut: &spsPointer,
                    parameterSetSizeOut: &spsSize,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )

                if spsStatus == noErr, let spsPointer = spsPointer, spsSize > 0 {
                    annexBData.append(contentsOf: annexBStartCode)
                    annexBData.append(spsPointer, count: spsSize)
                    print("[VideoCodec] ✅ Added SPS (\(spsSize) bytes) to keyframe")
                } else {
                    print("[VideoCodec] ❌ Failed to extract SPS: \(spsStatus)")
                }

                // Get PPS
                var ppsPointer: UnsafePointer<UInt8>?
                var ppsSize: Int = 0
                let ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDescription,
                    parameterSetIndex: 1,
                    parameterSetPointerOut: &ppsPointer,
                    parameterSetSizeOut: &ppsSize,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )

                if ppsStatus == noErr, let ppsPointer = ppsPointer, ppsSize > 0 {
                    annexBData.append(contentsOf: annexBStartCode)
                    annexBData.append(ppsPointer, count: ppsSize)
                    print("[VideoCodec] ✅ Added PPS (\(ppsSize) bytes) to keyframe")
                } else {
                    print("[VideoCodec] ❌ Failed to extract PPS: \(ppsStatus)")
                }
            } else {
                print("[VideoCodec] ❌ No format description for keyframe")
            }
        }

        // Convert AVCC NAL units to Annex-B
        var offset = 0
        while offset + 4 <= length {  // Ensure we have at least 4 bytes for length prefix
            // Read 4-byte length prefix (AVCC format) - big endian
            // Read byte-by-byte to avoid alignment issues
            let byte0 = UInt32(UInt8(bitPattern: dataPointer[offset]))
            let byte1 = UInt32(UInt8(bitPattern: dataPointer[offset + 1]))
            let byte2 = UInt32(UInt8(bitPattern: dataPointer[offset + 2]))
            let byte3 = UInt32(UInt8(bitPattern: dataPointer[offset + 3]))
            let nalLength = Int((byte0 << 24) | (byte1 << 16) | (byte2 << 8) | byte3)

            offset += 4

            // Verify we have enough data for the NAL unit
            guard nalLength > 0 && offset + nalLength <= length else {
                print("[VideoCodec] ⚠️ Invalid NAL length \(nalLength) at offset \(offset), total length: \(length)")
                break
            }

            // Add Annex-B start code
            annexBData.append(contentsOf: annexBStartCode)

            // Add NAL data with proper pointer casting
            let nalPointer = UnsafeRawPointer(dataPointer.advanced(by: offset))
            annexBData.append(nalPointer.assumingMemoryBound(to: UInt8.self), count: nalLength)

            offset += nalLength
        }

        print("[VideoCodec] 📤 Encoded \(isKeyframe ? "KEYFRAME" : "frame"): \(annexBData.count) bytes")

        // Get presentation time
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Call callback on main thread with keyframe flag
        Task { @MainActor in
            service.onEncodedFrame?(annexBData, presentationTime, isKeyframe)
        }
    }

    // MARK: - Adaptive Bitrate

    /// Report packet loss for adaptive bitrate
    func reportPacketLoss(lost: Int, sent: Int) {
        packetsLost += lost
        packetsSent += sent

        // Adjust bitrate every 2 seconds
        let now = Date()
        guard now.timeIntervalSince(lastBitrateAdjustment) >= 2.0 else { return }
        lastBitrateAdjustment = now

        let lossRate = packetsSent > 0 ? Double(packetsLost) / Double(packetsSent) : 0.0
        adjustBitrate(lossRate: lossRate)

        // Reset counters
        packetsLost = 0
        packetsSent = 0
    }

    private func adjustBitrate(lossRate: Double) {
        let oldBitrate = currentBitrate

        if lossRate > 0.15 {
            // High packet loss (>15%) - decrease significantly
            currentBitrate = max(minBitrate, Int(Double(currentBitrate) * 0.7))
            print("[VideoCodec] 📉 High packet loss (\(Int(lossRate * 100))%) - decreasing bitrate")
        } else if lossRate > 0.05 {
            // Moderate packet loss (5-15%) - decrease moderately
            currentBitrate = max(minBitrate, Int(Double(currentBitrate) * 0.85))
            print("[VideoCodec] 📉 Moderate packet loss (\(Int(lossRate * 100))%) - decreasing bitrate")
        } else if lossRate < 0.02 {
            // Low packet loss (<2%) - increase gradually
            currentBitrate = min(maxBitrate, Int(Double(currentBitrate) * 1.1))
            print("[VideoCodec] 📈 Low packet loss (\(Int(lossRate * 100))%) - increasing bitrate")
        }

        if currentBitrate != oldBitrate {
            updateEncoderBitrate()
        }
    }

    private func updateEncoderBitrate() {
        guard let session = encodingSession else { return }

        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AverageBitRate,
            value: currentBitrate as CFNumber
        )

        let dataRateLimits = [
            currentBitrate / 8,
            1
        ] as CFArray
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_DataRateLimits,
            value: dataRateLimits
        )

        print("[VideoCodec] Updated bitrate: \(currentBitrate / 1_000_000) Mbps")
    }

    // MARK: - Decoder Setup

    /// Initialize H.264 hardware decoder with format description
    func setupDecoder(formatDescription: CMFormatDescription) -> Bool {
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        print("[VideoCodec] Setting up H.264 hardware decoder: \(dimensions.width)x\(dimensions.height)")

        // Clean up existing session
        if let session = decodingSession {
            VTDecompressionSessionInvalidate(session)
            decodingSession = nil
        }

        // Store format description
        self.formatDescription = formatDescription

        // Destination image buffer attributes
        let imageBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: dimensions.width,
            kCVPixelBufferHeightKey: dimensions.height,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        // Output callback
        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decodingOutputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        // Create decompression session
        var session: VTDecompressionSession?
        let createStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: imageBufferAttributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &session
        )

        guard createStatus == noErr, let session = session else {
            print("[VideoCodec] ❌ Failed to create decompression session: \(createStatus)")
            return false
        }

        // Configure decoder for real-time playback
        VTSessionSetProperty(
            session,
            key: kVTDecompressionPropertyKey_RealTime,
            value: kCFBooleanTrue
        )

        decodingSession = session
        print("[VideoCodec] ✅ H.264 hardware decoder ready")
        return true
    }

    /// Create format description from SPS/PPS parameter sets
    /// This is needed on the first frame or when stream parameters change
    private func createFormatDescription(from h264Data: Data) -> CMFormatDescription? {
        // Debug: Log first 20 bytes to see what we received
        let previewBytes = h264Data.prefix(min(20, h264Data.count))
        let hexString = previewBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("[VideoCodec] 🔍 Parsing H.264 data (\(h264Data.count) bytes), first bytes: \(hexString)")

        // Parse NAL units to find SPS and PPS
        var spsData: Data?
        var ppsData: Data?
        var nalTypesFound: [UInt8] = []

        var offset = 0
        while offset < h264Data.count - 4 {
            // Look for start code (0x00 0x00 0x00 0x01)
            if h264Data[offset] == 0x00 &&
               h264Data[offset + 1] == 0x00 &&
               h264Data[offset + 2] == 0x00 &&
               h264Data[offset + 3] == 0x01 {

                let nalType = h264Data[offset + 4] & 0x1F
                nalTypesFound.append(nalType)

                // Find next start code or end of data
                var nalEndOffset = offset + 4
                while nalEndOffset < h264Data.count - 4 {
                    if h264Data[nalEndOffset] == 0x00 &&
                       h264Data[nalEndOffset + 1] == 0x00 &&
                       h264Data[nalEndOffset + 2] == 0x00 &&
                       h264Data[nalEndOffset + 3] == 0x01 {
                        break
                    }
                    nalEndOffset += 1
                }

                if nalEndOffset == h264Data.count - 4 {
                    nalEndOffset = h264Data.count
                }

                // Extract NAL unit data (without start code, but WITH NAL header byte)
                // CMVideoFormatDescriptionCreateFromH264ParameterSets expects complete NAL unit
                let nalData = h264Data.subdata(in: (offset + 4)..<nalEndOffset)

                if nalType == 7 { // SPS
                    spsData = nalData
                    print("[VideoCodec] Found SPS (\(nalData.count) bytes, with NAL header)")
                } else if nalType == 8 { // PPS
                    ppsData = nalData
                    print("[VideoCodec] Found PPS (\(nalData.count) bytes, with NAL header)")
                }

                offset = nalEndOffset
            } else {
                offset += 1
            }
        }

        print("[VideoCodec] 🔍 NAL unit types found: \(nalTypesFound.map { String($0) }.joined(separator: ", ")) (7=SPS, 8=PPS, 5=IDR, 1=P-frame)")

        // Create format description if we have both SPS and PPS
        guard let spsData = spsData, let ppsData = ppsData else {
            print("[VideoCodec] ⚠️ Missing SPS or PPS - SPS: \(spsData != nil), PPS: \(ppsData != nil)")
            return nil
        }

        var formatDescription: CMFormatDescription?

        // Create format description with proper pointer lifetime management
        let status = spsData.withUnsafeBytes { spsBytes in
            ppsData.withUnsafeBytes { ppsBytes in
                var parameterSetPointers: [UnsafePointer<UInt8>] = [
                    spsBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    ppsBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
                ]
                let parameterSetSizes = [spsData.count, ppsData.count]

                return parameterSetPointers.withUnsafeMutableBufferPointer { pointers in
                    CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 2,
                        parameterSetPointers: pointers.baseAddress!,
                        parameterSetSizes: parameterSetSizes,
                        nalUnitHeaderLength: 4,
                        formatDescriptionOut: &formatDescription
                    )
                }
            }
        }

        if status == noErr {
            print("[VideoCodec] ✅ Created format description from SPS/PPS")
            return formatDescription
        } else {
            print("[VideoCodec] ❌ Failed to create format description: \(status)")
            return nil
        }
    }

    // MARK: - Decoding

    /// Convert Annex-B format (start codes) to AVCC format (length prefixes)
    private func convertAnnexBToAVCC(_ annexBData: Data) -> Data? {
        var avccData = Data()
        var offset = 0
        var nalUnitsConverted = 0
        var nalTypes: [UInt8] = []

        while offset < annexBData.count - 4 {
            // Look for start code (0x00 0x00 0x00 0x01)
            if annexBData[offset] == 0x00 &&
               annexBData[offset + 1] == 0x00 &&
               annexBData[offset + 2] == 0x00 &&
               annexBData[offset + 3] == 0x01 {

                let nalType = annexBData[offset + 4] & 0x1F

                // Find next start code or end of data
                var nalEndOffset = offset + 4
                while nalEndOffset < annexBData.count - 4 {
                    if annexBData[nalEndOffset] == 0x00 &&
                       annexBData[nalEndOffset + 1] == 0x00 &&
                       annexBData[nalEndOffset + 2] == 0x00 &&
                       annexBData[nalEndOffset + 3] == 0x01 {
                        break
                    }
                    nalEndOffset += 1
                }

                if nalEndOffset == annexBData.count - 4 {
                    nalEndOffset = annexBData.count
                }

                // Skip SPS and PPS NAL units (decoder doesn't need them in frames)
                if nalType == 7 || nalType == 8 {
                    offset = nalEndOffset
                    continue
                }

                nalTypes.append(nalType)
                nalUnitsConverted += 1

                // Get NAL unit length (excluding start code)
                let nalLength = nalEndOffset - (offset + 4)

                // Write 4-byte length prefix (big endian)
                var lengthBytes: [UInt8] = [
                    UInt8((nalLength >> 24) & 0xFF),
                    UInt8((nalLength >> 16) & 0xFF),
                    UInt8((nalLength >> 8) & 0xFF),
                    UInt8(nalLength & 0xFF)
                ]
                avccData.append(contentsOf: lengthBytes)

                // Copy NAL data (without start code)
                avccData.append(annexBData.subdata(in: (offset + 4)..<nalEndOffset))

                offset = nalEndOffset
            } else {
                offset += 1
            }
        }

        let typesString = nalTypes.map { String($0) }.joined(separator: ", ")
        print("[VideoCodec] 🔄 Converted \(nalUnitsConverted) NAL units (types: \(typesString)): \(annexBData.count) → \(avccData.count) bytes")

        return avccData.isEmpty ? nil : avccData
    }

    /// Decode H.264 data to pixel buffer
    func decode(data: Data) {
        print("[VideoCodec] 📥 Received H.264 data: \(data.count) bytes")

        decodingQueue.async { [weak self] in
            guard let self = self else { return }

            // If we don't have a decoder session, try to create format description from this data
            if self.decodingSession == nil {
                print("[VideoCodec] No decoder yet, attempting to parse SPS/PPS...")
                if let formatDesc = self.createFormatDescription(from: data) {
                    if !self.setupDecoder(formatDescription: formatDesc) {
                        print("[VideoCodec] ❌ Failed to setup decoder")
                        return
                    }
                    print("[VideoCodec] ✅ Decoder setup complete, will now decode this keyframe")
                    // Continue to decode this keyframe (contains IDR frame which is needed as reference)
                } else {
                    // No SPS/PPS found yet, skip this frame
                    print("[VideoCodec] ⚠️ No SPS/PPS found, skipping frame")
                    return
                }
            }

            guard let session = self.decodingSession,
                  let formatDescription = self.formatDescription else {
                print("[VideoCodec] ⚠️ No decoding session or format description")
                return
            }

            // Convert Annex-B format (start codes) to AVCC format (length prefixes)
            // VTDecompressionSession expects AVCC format
            guard let avccData = self.convertAnnexBToAVCC(data) else {
                print("[VideoCodec] ❌ Failed to convert Annex-B to AVCC")
                return
            }

            // Create block buffer from AVCC data
            var blockBuffer: CMBlockBuffer?
            let createStatus = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: avccData.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: avccData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )

            guard createStatus == noErr, let blockBuffer = blockBuffer else {
                print("[VideoCodec] ❌ Failed to create block buffer: \(createStatus)")
                return
            }

            // Copy AVCC data into block buffer
            avccData.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                CMBlockBufferReplaceDataBytes(
                    with: baseAddress,
                    blockBuffer: blockBuffer,
                    offsetIntoDestination: 0,
                    dataLength: avccData.count  // Use AVCC size, not original Annex-B size
                )
            }

            // Create sample buffer
            var sampleBuffer: CMSampleBuffer?

            // Create timing info
            let presentationTime = CMTime(value: self.frameCounter, timescale: 30)
            var timingInfo = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 30),
                presentationTimeStamp: presentationTime,
                decodeTimeStamp: .invalid
            )

            // Create sample buffer
            let sampleStatus = CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                formatDescription: formatDescription,
                sampleCount: 1,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timingInfo,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &sampleBuffer
            )

            guard sampleStatus == noErr, let sampleBuffer = sampleBuffer else {
                print("[VideoCodec] ❌ Failed to create sample buffer: \(sampleStatus)")
                return
            }

            // Set attachments for real-time decoding
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)
            if let attachmentsArray = attachments as? [[CFString: Any]] {
                var dict = attachmentsArray[0]
                dict[kCMSampleAttachmentKey_DisplayImmediately] = kCFBooleanTrue
            }

            // Decode the frame
            var flagsOut: VTDecodeInfoFlags = []
            let decodeStatus = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sampleBuffer,
                flags: [._EnableAsynchronousDecompression],
                frameRefcon: nil,
                infoFlagsOut: &flagsOut
            )

            if decodeStatus != noErr {
                print("[VideoCodec] ❌ Decoding failed: \(decodeStatus)")
            }

            self.frameCounter += 1
        }
    }

    // Decoding callback
    private let decodingOutputCallback: VTDecompressionOutputCallback = {
        (decompressionOutputRefCon, sourceFrameRefCon, status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration) in

        guard status == noErr else {
            print("[VideoCodec] ❌ Decoding callback error: \(status)")
            return
        }

        guard let imageBuffer = imageBuffer else {
            print("[VideoCodec] ⚠️ No image buffer")
            return
        }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        print("[VideoCodec] ✅ Decoded frame: \(width)x\(height)")

        // Get the service instance
        let service = Unmanaged<VideoCodecService>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()

        // Call callback on main thread
        Task { @MainActor in
            service.onDecodedFrame?(imageBuffer)
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        if let session = encodingSession {
            VTCompressionSessionInvalidate(session)
            encodingSession = nil
        }

        if let session = decodingSession {
            VTDecompressionSessionInvalidate(session)
            decodingSession = nil
        }

        print("[VideoCodec] Cleaned up encoder and decoder")
    }
}
