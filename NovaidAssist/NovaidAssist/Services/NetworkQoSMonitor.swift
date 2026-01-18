import Foundation

/// Network Quality of Service Monitor
/// Tracks RTT, jitter, and packet loss to determine optimal streaming mode
class NetworkQoSMonitor {

    // MARK: - Quality Modes (Chalk-style)
    enum StreamingMode: String {
        case normal          // RTT < 200ms, jitter < 30ms, loss < 2%
        case lowBandwidth    // RTT 200-400ms OR jitter 30-60ms OR loss 2-6%
        case freezeFrame     // RTT > 400ms OR jitter > 60ms OR loss > 6%
        case audioOnly       // RTT > 800ms OR loss > 10%

        var targetFPS: Int {
            switch self {
            case .normal: return 30
            case .lowBandwidth: return 15
            case .freezeFrame: return 1  // 1 keyframe per second
            case .audioOnly: return 0    // No video
            }
        }

        var shouldUseStillFrames: Bool {
            self == .freezeFrame || self == .audioOnly
        }
    }

    // MARK: - QoS Metrics
    struct QoSMetrics {
        var rttMs: Double = 0
        var jitterMs: Double = 0
        var packetLossPct: Double = 0
        var timestamp: Date = Date()

        var recommendedMode: StreamingMode {
            // Mode 3: Audio only (severe)
            if rttMs > 800 || packetLossPct > 10 {
                return .audioOnly
            }

            // Mode 2: Freeze-frame (high latency)
            if rttMs > 400 || jitterMs > 60 || packetLossPct > 6 {
                return .freezeFrame
            }

            // Mode 1: Low bandwidth (degraded)
            if rttMs > 200 || jitterMs > 30 || packetLossPct > 2 {
                return .lowBandwidth
            }

            // Mode 0: Normal
            return .normal
        }
    }

    // MARK: - Properties
    private var currentMetrics = QoSMetrics()
    private var currentMode: StreamingMode = .normal
    private var modeChangeCallback: ((StreamingMode) -> Void)?

    // RTT tracking (ping-pong)
    private var sentPings: [String: Date] = [:]  // pingId -> sentTime
    private var rttSamples: [Double] = []
    private let maxRTTSamples = 10

    // Packet loss tracking
    private var expectedSequence: Int = 0
    private var receivedSequence: Int = 0
    private var lostPackets: Int = 0

    // Update frequency
    private var lastUpdate: Date = Date()
    private let updateInterval: TimeInterval = 2.0  // Check every 2 seconds

    // MARK: - Public API

    func setModeChangeCallback(_ callback: @escaping (StreamingMode) -> Void) {
        self.modeChangeCallback = callback
    }

    /// Record RTT for a ping-pong roundtrip
    func recordPingSent(pingId: String) {
        sentPings[pingId] = Date()
    }

    func recordPongReceived(pingId: String) {
        guard let sentTime = sentPings.removeValue(forKey: pingId) else { return }

        let rtt = Date().timeIntervalSince(sentTime) * 1000  // Convert to ms
        rttSamples.append(rtt)

        // Keep only recent samples
        if rttSamples.count > maxRTTSamples {
            rttSamples.removeFirst()
        }

        updateMetrics()
    }

    /// Record packet received with sequence number
    func recordPacketReceived(sequence: Int) {
        if sequence > expectedSequence {
            lostPackets += (sequence - expectedSequence)
        }
        expectedSequence = sequence + 1
        receivedSequence += 1

        updateMetrics()
    }

    /// Manually update metrics (e.g., from external monitoring)
    func updateQoS(rttMs: Double, jitterMs: Double, packetLossPct: Double) {
        currentMetrics.rttMs = rttMs
        currentMetrics.jitterMs = jitterMs
        currentMetrics.packetLossPct = packetLossPct
        currentMetrics.timestamp = Date()

        checkModeSwitch()
    }

    // MARK: - Private Methods

    private func updateMetrics() {
        let now = Date()
        guard now.timeIntervalSince(lastUpdate) >= updateInterval else { return }
        lastUpdate = now

        // Calculate RTT
        if !rttSamples.isEmpty {
            currentMetrics.rttMs = rttSamples.reduce(0, +) / Double(rttSamples.count)
        }

        // Calculate jitter (variance in RTT)
        if rttSamples.count >= 2 {
            let avgRTT = currentMetrics.rttMs
            let variance = rttSamples.map { pow($0 - avgRTT, 2) }.reduce(0, +) / Double(rttSamples.count)
            currentMetrics.jitterMs = sqrt(variance)
        }

        // Calculate packet loss percentage
        if receivedSequence > 0 {
            currentMetrics.packetLossPct = Double(lostPackets) / Double(receivedSequence + lostPackets) * 100
        }

        currentMetrics.timestamp = now

        checkModeSwitch()

        // Log metrics
        print("[QoS] RTT: \(String(format: "%.1f", currentMetrics.rttMs))ms, " +
              "Jitter: \(String(format: "%.1f", currentMetrics.jitterMs))ms, " +
              "Loss: \(String(format: "%.2f", currentMetrics.packetLossPct))%")
    }

    private func checkModeSwitch() {
        let recommendedMode = currentMetrics.recommendedMode

        if recommendedMode != currentMode {
            print("[QoS] 🔄 Mode switch: \(currentMode.rawValue) → \(recommendedMode.rawValue)")
            currentMode = recommendedMode
            modeChangeCallback?(recommendedMode)
        }
    }

    func getCurrentMode() -> StreamingMode {
        return currentMode
    }

    func getCurrentMetrics() -> QoSMetrics {
        return currentMetrics
    }
}
