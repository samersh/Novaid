import Foundation
import CoreVideo

/// WebRTC-style adaptive jitter buffer for smooth video playout
/// Compensates for network jitter by buffering frames and playing them out at the right time
/// Based on industry standards from Vuforia Chalk, Zoho Lens, and WebRTC NetEQ
class JitterBuffer {

    // MARK: - Buffered Frame
    struct BufferedFrame {
        let pixelBuffer: CVPixelBuffer
        let captureTimestamp: Date      // When frame was captured on iPhone
        let receiveTimestamp: Date      // When frame was received on iPad
        let sequenceNumber: Int64       // Frame sequence number for ordering

        var age: TimeInterval {
            return Date().timeIntervalSince(receiveTimestamp)
        }
    }

    // MARK: - Configuration
    private let targetBufferDelay: TimeInterval = 0.050      // 50ms target (industry standard)
    private let minBufferDelay: TimeInterval = 0.020         // 20ms minimum
    private let maxBufferDelay: TimeInterval = 0.120         // 120ms maximum
    private let maxFrameAge: TimeInterval = 0.150            // Drop frames older than 150ms

    // MARK: - Buffer State
    private var frameBuffer: [BufferedFrame] = []
    private let bufferQueue = DispatchQueue(label: "com.novaid.jitterBuffer", qos: .userInteractive)

    // Adaptive buffer management
    private var currentBufferDelay: TimeInterval
    private var lastPlayoutTime: Date?
    private var consecutiveLateFrames: Int = 0
    private var consecutiveEarlyFrames: Int = 0

    // Statistics
    private var framesReceived: Int = 0
    private var framesDroppedOld: Int = 0
    private var framesDroppedDuplicate: Int = 0
    private var framesPlayed: Int = 0
    private var lastStatsLog: Date = Date()

    // Last sequence number to detect duplicates
    private var lastSequenceNumber: Int64 = -1

    init() {
        self.currentBufferDelay = targetBufferDelay
        print("[JitterBuffer] 🎬 Initialized with target delay: \(Int(targetBufferDelay * 1000))ms")
    }

    // MARK: - Public API

    /// Add a received frame to the buffer
    func addFrame(pixelBuffer: CVPixelBuffer, captureTimestamp: Date, sequenceNumber: Int64) {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }

            self.framesReceived += 1

            // Detect duplicate frames (already processed)
            if sequenceNumber <= self.lastSequenceNumber {
                self.framesDroppedDuplicate += 1
                return
            }

            let frame = BufferedFrame(
                pixelBuffer: pixelBuffer,
                captureTimestamp: captureTimestamp,
                receiveTimestamp: Date(),
                sequenceNumber: sequenceNumber
            )

            // Add to buffer
            self.frameBuffer.append(frame)

            // Sort by sequence number (maintain order)
            self.frameBuffer.sort { $0.sequenceNumber < $1.sequenceNumber }

            // Clean up old frames
            self.removeOldFrames()

            // Log stats periodically
            self.logStatsIfNeeded()
        }
    }

    /// Get the next frame ready for playout (returns nil if no frame is ready)
    func getNextFrame() -> CVPixelBuffer? {
        var frameToReturn: CVPixelBuffer?

        bufferQueue.sync {
            guard !frameBuffer.isEmpty else { return }

            let now = Date()

            // Check if we should wait for more frames (buffer not full enough)
            if let firstFrame = frameBuffer.first {
                let timeSinceReceive = now.timeIntervalSince(firstFrame.receiveTimestamp)

                // Wait until frame has been buffered for at least currentBufferDelay
                if timeSinceReceive < currentBufferDelay {
                    // Not ready yet, need to buffer more
                    consecutiveEarlyFrames += 1

                    // If we're consistently early, we can reduce buffer size
                    if consecutiveEarlyFrames > 10 {
                        adjustBufferDelay(increase: false)
                        consecutiveEarlyFrames = 0
                    }
                    return
                }

                // Check if frame is too old (arrived too late)
                if firstFrame.age > maxFrameAge {
                    framesDroppedOld += 1
                    frameBuffer.removeFirst()
                    consecutiveLateFrames += 1

                    // If we're consistently late, increase buffer size
                    if consecutiveLateFrames > 5 {
                        adjustBufferDelay(increase: true)
                        consecutiveLateFrames = 0
                    }
                    return
                }

                // Frame is ready for playout
                let frame = frameBuffer.removeFirst()
                frameToReturn = frame.pixelBuffer
                framesPlayed += 1
                lastPlayoutTime = now
                lastSequenceNumber = frame.sequenceNumber

                // Reset counters on successful playout
                consecutiveLateFrames = 0
                consecutiveEarlyFrames = 0

                // Calculate actual playout delay for monitoring
                let actualDelay = now.timeIntervalSince(frame.captureTimestamp)
                if actualDelay > 0.200 {
                    print("[JitterBuffer] ⚠️ High glass-to-glass latency: \(Int(actualDelay * 1000))ms")
                }
            }
        }

        return frameToReturn
    }

    /// Get current buffer size (number of frames)
    func getBufferSize() -> Int {
        return bufferQueue.sync { frameBuffer.count }
    }

    /// Get current buffer delay in ms
    func getCurrentBufferDelay() -> Int {
        return bufferQueue.sync { Int(currentBufferDelay * 1000) }
    }

    /// Clear all buffered frames (used on stream restart)
    func flush() {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            self.frameBuffer.removeAll()
            self.lastSequenceNumber = -1
            print("[JitterBuffer] 🔄 Buffer flushed")
        }
    }

    // MARK: - Private Methods

    private func removeOldFrames() {
        let now = Date()

        // Remove frames that are too old
        frameBuffer.removeAll { frame in
            if frame.age > maxFrameAge {
                framesDroppedOld += 1
                return true
            }
            return false
        }

        // Limit buffer size to prevent memory growth (max 10 frames = 500ms at 20 FPS)
        while frameBuffer.count > 10 {
            frameBuffer.removeFirst()
            framesDroppedOld += 1
        }
    }

    private func adjustBufferDelay(increase: Bool) {
        let oldDelay = currentBufferDelay

        if increase {
            // Increase buffer to handle more jitter
            currentBufferDelay = min(currentBufferDelay * 1.2, maxBufferDelay)
        } else {
            // Decrease buffer to reduce latency
            currentBufferDelay = max(currentBufferDelay * 0.9, minBufferDelay)
        }

        if abs(currentBufferDelay - oldDelay) > 0.001 {
            print("[JitterBuffer] 📊 Adjusted buffer delay: \(Int(oldDelay * 1000))ms → \(Int(currentBufferDelay * 1000))ms")
        }
    }

    private func logStatsIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(lastStatsLog) >= 5.0 {
            let bufferSize = frameBuffer.count
            let bufferMs = Int(currentBufferDelay * 1000)

            print("╔═══════════════════════════════════════════╗")
            print("║  📊 JITTER BUFFER STATS                   ║")
            print("╠═══════════════════════════════════════════╣")
            print("║ Buffer Size:     \(String(format: "%2d", bufferSize)) frames                  ║")
            print("║ Buffer Delay:    \(String(format: "%3d", bufferMs))ms                     ║")
            print("║ Received:        \(String(format: "%5d", framesReceived)) frames              ║")
            print("║ Played:          \(String(format: "%5d", framesPlayed)) frames              ║")
            print("║ Dropped (old):   \(String(format: "%5d", framesDroppedOld)) frames              ║")
            print("║ Dropped (dup):   \(String(format: "%5d", framesDroppedDuplicate)) frames              ║")
            print("╚═══════════════════════════════════════════╝")

            lastStatsLog = now

            // Reset counters
            framesReceived = 0
            framesPlayed = 0
            framesDroppedOld = 0
            framesDroppedDuplicate = 0
        }
    }
}
