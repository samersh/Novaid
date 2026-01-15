import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia

/// Hardware-accelerated H.264 video encoding and decoding service
/// Based on WebRTC and Zoho Lens best practices
@MainActor
class VideoCodecService: NSObject {
    static let shared = VideoCodecService()

    // MARK: - Encoder Properties
    private var encodingSession: VTCompressionSession?
    private let encodingQueue = DispatchQueue(label: "com.novaid.videoEncoding", qos: .userInitiated)

    // MARK: - Decoder Properties
    private var decodingSession: VTDecompressionSession?
    private let decodingQueue = DispatchQueue(label: "com.novaid.videoDecoding", qos: .userInitiated)

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

        encodingQueue.async {
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

        // Get presentation time
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

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

    /// Initialize H.264 hardware decoder
    func setupDecoder(width: Int32, height: Int32) -> Bool {
        print("[VideoCodec] Setting up H.264 hardware decoder: \(width)x\(height)")

        // Clean up existing session
        if let session = decodingSession {
            VTDecompressionSessionInvalidate(session)
            decodingSession = nil
        }

        // Create format description
        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: width,
            height: height,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr, let formatDescription = formatDescription else {
            print("[VideoCodec] ❌ Failed to create format description: \(status)")
            return false
        }

        // Destination image buffer attributes
        let imageBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
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

    // MARK: - Decoding

    /// Decode H.264 data to pixel buffer
    func decode(data: Data, presentationTime: CMTime) {
        guard let session = decodingSession else {
            print("[VideoCodec] ⚠️ No decoding session")
            return
        }

        decodingQueue.async {
            // Create block buffer from data
            var blockBuffer: CMBlockBuffer?
            let dataPointer = (data as NSData).bytes
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
                print("[VideoCodec] ❌ Failed to create block buffer")
                return
            }

            // Copy data into block buffer
            let replaceStatus = CMBlockBufferReplaceDataBytes(
                with: dataPointer,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )

            guard replaceStatus == noErr else {
                print("[VideoCodec] ❌ Failed to copy data")
                return
            }

            // Create sample buffer
            // Note: This is simplified - production code would need proper format description
            // For now, we'll need to reconstruct format from data
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
