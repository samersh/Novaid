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
    // ULTRA-LOW LATENCY: Use userInteractive QoS (highest priority for real-time video)
    private let encodingQueue = DispatchQueue(label: "com.novaid.videoEncoding", qos: .userInteractive)

    // MARK: - Decoder Properties
    private var decodingSession: VTDecompressionSession?
    // ULTRA-LOW LATENCY: Use userInteractive QoS (highest priority for real-time video)
    private let decodingQueue = DispatchQueue(label: "com.novaid.videoDecoding", qos: .userInteractive)
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
    var onEncodedFrame: ((Data, CMTime) -> Void)?
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?

    // MARK: - Latency Monitoring
    private var frameCaptureTimestamps: [Int64: Date] = [:]  // frameNumber -> captureTime (iPhone only)
    private var frameDecodeStartTimes: [Int64: Date] = [:]  // frameNumber -> decodeStartTime (iPad only)
    private var encodeLatencySamples: [TimeInterval] = []  // iPhone encode latency
    private var decodeLatencySamples: [TimeInterval] = []  // iPad decode latency
    private var lastLatencyLog: Date = Date()
    private let maxLatencySamples = 30  // Track last 30 frames

    // MARK: - Frame Dropping Strategy (prevents queue buildup)
    private var pendingEncodingFrames = 0
    private var pendingDecodingFrames = 0
    private let maxPendingFrames = 2  // Drop frames if more than 2 are pending
    private var droppedFrames = 0
    private var lastDropLog: Date = Date()

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
        // ULTRA-LOW LATENCY: Real-time encoding (equivalent to x264 tune=zerolatency)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_RealTime,
            value: kCFBooleanTrue
        )

        // Profile level: Baseline for lowest latency (no B-frames, simpler decoding)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ProfileLevel,
            value: kVTProfileLevel_H264_Baseline_AutoLevel  // Changed from Main to Baseline
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

        // Expected frame duration for immediate encoding
        let frameDuration = CMTime(value: 1, timescale: targetFrameRate)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ExpectedDuration,
            value: frameDuration as CFTypeRef
        )

        // ULTRA-LOW LATENCY: Keyframe every 1 second (reduced from 2 seconds)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: targetFrameRate as CFNumber  // 30 frames = 1 second
        )

        // CRITICAL: Disable frame reordering (no B-frames) for lowest latency
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AllowFrameReordering,
            value: kCFBooleanFalse
        )

        // ULTRA-LOW LATENCY: Maximum one frame of latency
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxH264SliceBytes,
            value: 0 as CFNumber  // No slice size limit
        )

        // Hardware acceleration
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
            value: kCFBooleanTrue
        )

        // ULTRA-LOW LATENCY: Prioritize encoding speed over quality
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_Quality,
            value: 0.5 as CFNumber  // Balance between quality and speed
        )

        print("[VideoCodec] 🚀 Encoder configured for ULTRA-LOW LATENCY: \(currentBitrate / 1_000_000) Mbps, Baseline Profile, 1s keyframe interval")
    }

    // MARK: - Encoding

    /// Encode a pixel buffer to H.264
    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime, captureTime: Date = Date()) {
        guard let session = encodingSession else {
            print("[VideoCodec] ⚠️ No encoding session")
            return
        }

        // FRAME DROPPING: Check if encoder is overwhelmed
        if pendingEncodingFrames >= maxPendingFrames {
            droppedFrames += 1
            logFrameDropIfNeeded()
            return  // Drop this frame to prevent queue buildup
        }

        // LATENCY TRACKING: Record capture timestamp
        let frameNumber = presentationTime.value
        frameCaptureTimestamps[frameNumber] = captureTime

        pendingEncodingFrames += 1

        encodingQueue.async { [weak self] in
            let status = VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: pixelBuffer,
                presentationTimeStamp: presentationTime,
                duration: .invalid,
                frameProperties: nil,
                sourceFrameRefcon: nil,
                infoFlagsOut: nil
            )

            if status != noErr {
                print("[VideoCodec] ❌ Encoding failed: \(status)")
            }

            // Decrement pending count after encoding completes
            self?.pendingEncodingFrames -= 1
        }
    }

    private func logFrameDropIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(lastDropLog) >= 3.0 {
            print("[VideoCodec] ⚠️ Dropped \(droppedFrames) frames in last 3s (encoder overwhelmed)")
            droppedFrames = 0
            lastDropLog = now
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

        // LATENCY TRACKING: Measure encode latency (iPhone only)
        let encodeEndTime = Date()
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let frameNumber = presentationTime.value

        if let captureTime = service.frameCaptureTimestamps[frameNumber] {
            let encodeLatency = encodeEndTime.timeIntervalSince(captureTime) * 1000  // Convert to ms
            service.recordEncodeLatency(encodeLatency)

            // Clean up
            service.frameCaptureTimestamps.removeValue(forKey: frameNumber)
        }

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

        // Create Data object
        let data = Data(bytes: dataPointer, count: length)

        // Call callback on main thread
        Task { @MainActor in
            service.onEncodedFrame?(data, presentationTime)
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

        // ULTRA-LOW LATENCY: Configure decoder for immediate real-time playback
        VTSessionSetProperty(
            session,
            key: kVTDecompressionPropertyKey_RealTime,
            value: kCFBooleanTrue
        )

        // ULTRA-LOW LATENCY: Use single thread for lowest latency
        VTSessionSetProperty(
            session,
            key: kVTDecompressionPropertyKey_ThreadCount,
            value: 1 as CFNumber
        )

        decodingSession = session
        print("[VideoCodec] 🚀 H.264 hardware decoder ready for ULTRA-LOW LATENCY")
        return true
    }

    /// Create format description from SPS/PPS parameter sets
    /// This is needed on the first frame or when stream parameters change
    private func createFormatDescription(from h264Data: Data) -> CMFormatDescription? {
        // Parse NAL units to find SPS and PPS
        var spsData: Data?
        var ppsData: Data?

        var offset = 0
        while offset < h264Data.count - 4 {
            // Look for start code (0x00 0x00 0x00 0x01)
            if h264Data[offset] == 0x00 &&
               h264Data[offset + 1] == 0x00 &&
               h264Data[offset + 2] == 0x00 &&
               h264Data[offset + 3] == 0x01 {

                let nalType = h264Data[offset + 4] & 0x1F

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

                // Extract NAL unit data (without start code)
                let nalData = h264Data.subdata(in: (offset + 4)..<nalEndOffset)

                if nalType == 7 { // SPS
                    spsData = nalData
                    print("[VideoCodec] Found SPS (\(nalData.count) bytes)")
                } else if nalType == 8 { // PPS
                    ppsData = nalData
                    print("[VideoCodec] Found PPS (\(nalData.count) bytes)")
                }

                offset = nalEndOffset
            } else {
                offset += 1
            }
        }

        // Create format description if we have both SPS and PPS
        guard let spsData = spsData, let ppsData = ppsData else {
            return nil
        }

        let parameterSets = [spsData, ppsData]
        let parameterSetSizes = parameterSets.map { $0.count }

        var formatDescription: CMFormatDescription?

        // Create parameter set pointers with proper type casting
        let status = parameterSets.withUnsafeBufferPointer { parameterSetsBuffer in
            var parameterSetPointers = parameterSets.map { data in
                data.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
            }

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

        if status == noErr {
            print("[VideoCodec] ✅ Created format description from SPS/PPS")
            return formatDescription
        } else {
            print("[VideoCodec] ❌ Failed to create format description: \(status)")
            return nil
        }
    }

    // MARK: - Decoding

    /// Decode H.264 data to pixel buffer
    func decode(data: Data) {
        // FRAME DROPPING: Check if decoder is overwhelmed
        if pendingDecodingFrames >= maxPendingFrames {
            droppedFrames += 1
            logFrameDropIfNeeded()
            return  // Drop this frame to prevent queue buildup
        }

        pendingDecodingFrames += 1
        let decodeStartTime = Date()  // LATENCY TRACKING: Record decode start time

        decodingQueue.async { [weak self] in
            guard let self = self else { return }

            // If we don't have a decoder session, try to create format description from this data
            if self.decodingSession == nil {
                if let formatDesc = self.createFormatDescription(from: data) {
                    _ = self.setupDecoder(formatDescription: formatDesc)
                } else {
                    // No SPS/PPS found yet, skip this frame
                    self.pendingDecodingFrames -= 1
                    return
                }
            }

            guard let session = self.decodingSession,
                  let formatDescription = self.formatDescription else {
                print("[VideoCodec] ⚠️ No decoding session or format description")
                self.pendingDecodingFrames -= 1
                return
            }

            // Store decode start time for this frame
            let frameNum = self.frameCounter
            self.frameDecodeStartTimes[frameNum] = decodeStartTime

            // Create block buffer from data
            var blockBuffer: CMBlockBuffer?
            let createStatus = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: data.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: data.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )

            guard createStatus == noErr, let blockBuffer = blockBuffer else {
                print("[VideoCodec] ❌ Failed to create block buffer: \(createStatus)")
                return
            }

            // Copy data into block buffer
            data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                CMBlockBufferReplaceDataBytes(
                    with: baseAddress,
                    blockBuffer: blockBuffer,
                    offsetIntoDestination: 0,
                    dataLength: data.count
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

            // Decrement pending count after decoding completes
            self.pendingDecodingFrames -= 1
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

        // Get the service instance
        let service = Unmanaged<VideoCodecService>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()

        // LATENCY TRACKING: Measure decode latency (iPad only)
        let decodeEndTime = Date()
        let frameNumber = presentationTimeStamp.value

        // Calculate decode-only latency (time spent in decoder)
        if let decodeStartTime = service.frameDecodeStartTimes[frameNumber] {
            let decodeLatency = decodeEndTime.timeIntervalSince(decodeStartTime) * 1000  // Convert to ms
            service.recordDecodeLatency(decodeLatency)

            // Clean up
            service.frameDecodeStartTimes.removeValue(forKey: frameNumber)
        }

        // Call callback on main thread
        Task { @MainActor in
            service.onDecodedFrame?(imageBuffer)
        }
    }

    // MARK: - Latency Monitoring

    /// Record encode latency (iPhone only)
    private func recordEncodeLatency(_ latencyMs: TimeInterval) {
        encodeLatencySamples.append(latencyMs)

        // Keep only last N samples
        if encodeLatencySamples.count > maxLatencySamples {
            encodeLatencySamples.removeFirst()
        }

        // Log average encode latency every 3 seconds
        let now = Date()
        if now.timeIntervalSince(lastLatencyLog) >= 3.0 {
            let avgLatency = encodeLatencySamples.reduce(0, +) / Double(encodeLatencySamples.count)
            let minLatency = encodeLatencySamples.min() ?? 0
            let maxLatency = encodeLatencySamples.max() ?? 0

            print("[VideoCodec] ⏱️  Encode latency - Avg: \(String(format: "%.1f", avgLatency))ms, Min: \(String(format: "%.1f", minLatency))ms, Max: \(String(format: "%.1f", maxLatency))ms")

            lastLatencyLog = now
        }
    }

    /// Record decode latency (iPad only)
    private func recordDecodeLatency(_ latencyMs: TimeInterval) {
        decodeLatencySamples.append(latencyMs)

        // Keep only last N samples
        if decodeLatencySamples.count > maxLatencySamples {
            decodeLatencySamples.removeFirst()
        }

        // Log average decode latency every 3 seconds
        let now = Date()
        if now.timeIntervalSince(lastLatencyLog) >= 3.0 {
            let avgLatency = decodeLatencySamples.reduce(0, +) / Double(decodeLatencySamples.count)
            let minLatency = decodeLatencySamples.min() ?? 0
            let maxLatency = decodeLatencySamples.max() ?? 0

            print("[VideoCodec] ⏱️  Decode latency - Avg: \(String(format: "%.1f", avgLatency))ms, Min: \(String(format: "%.1f", minLatency))ms, Max: \(String(format: "%.1f", maxLatency))ms")

            lastLatencyLog = now
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
