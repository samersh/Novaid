import Foundation
import MultipeerConnectivity
import Combine
import UIKit
import CoreVideo

/// Service for peer-to-peer connection using MultipeerConnectivity
/// Allows iPhone and iPad to connect directly via WiFi/Bluetooth without a server
@MainActor
class MultipeerService: NSObject, ObservableObject {
    // MARK: - Singleton
    static let shared = MultipeerService()

    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectedPeerId: String?
    @Published var availablePeers: [MCPeerID] = []
    @Published var sessionCode: String = ""
    @Published var isHosting = false
    @Published var isBrowsing = false
    @Published var connectionStatus: String = "Disconnected"
    @Published var incomingInvitation: (from: MCPeerID, handler: (Bool, MCSession?) -> Void)?
    @Published var receivedVideoFrame: UIImage?
    @Published var receivedDeviceOrientation: DeviceOrientation = DeviceOrientation()
    @Published var frozenFrame: UIImage?

    // MARK: - Callbacks
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onDataReceived: ((Data, MCPeerID) -> Void)?
    var onIncomingCall: ((String) -> Void)?
    var onCallAccepted: (() -> Void)?
    var onCallRejected: (() -> Void)?
    var onAnnotationReceived: ((Annotation) -> Void)?
    var onAnnotationUpdated: ((Annotation) -> Void)?
    var onAnnotationPositionUpdated: ((String, CGFloat, CGFloat) -> Void)?
    var onClearAnnotations: (() -> Void)?
    var onToggleFlashlight: ((Bool) -> Void)?
    var onVideoFrozen: (() -> Void)?
    var onVideoResumed: (([Annotation]) -> Void)?
    var onVideoFrameReceived: ((UIImage) -> Void)?
    var onPixelBufferReceived: ((CVPixelBuffer) -> Void)?  // New: for direct pixel buffer transmission
    var onH264DataReceived: ((Data, VideoFrameMetadata) -> Void)?  // H.264 compressed frames with metadata for jitter buffer
    var onSPSPPSReceived: ((Data, Data) -> Void)?  // SPS/PPS parameter sets (sent once at stream start)
    var onFrozenFrameReceived: ((UIImage) -> Void)?
    var onAudioDataReceived: ((Data) -> Void)?

    // ADAPTIVE STREAMING: QoS monitoring callbacks (Chalk-style)
    var onPingReceived: ((String) -> Void)?  // Ping received, respond with pong
    var onPongReceived: ((String) -> Void)?  // Pong received, calculate RTT
    var onStreamingModeChanged: ((String) -> Void)?  // Mode changed by peer
    var onFrameMetadataReceived: ((FrameMetadata) -> Void)?  // Metadata for freeze-frame mode
    var onQoSMetricsReceived: ((Double, Double, Double) -> Void)?  // RTT, jitter, packet loss from peer

    // AR RECONSTRUCTION: Depth and scene understanding callbacks (Zoho Lens / Chalk style)
    var onDepthMapReceived: ((DepthMapData) -> Void)?  // Depth map for 3D reconstruction
    var onDetectedPlanesReceived: ((DetectedPlaneData) -> Void)?  // AR planes from iPhone
    var onAnnotationAnchorDataReceived: ((AnnotationAnchorData) -> Void)?  // 3D anchor for annotation

    // MARK: - Private Properties
    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var lastFrameTime: Date = Date()
    private let minFrameInterval: TimeInterval = 1.0 / 30.0 // 30 FPS max for smoother video

    // Adaptive quality settings based on WebRTC best practices
    private var currentCompressionQuality: CGFloat = 0.5 // Start at 0.5 for better quality
    private let minCompressionQuality: CGFloat = 0.3
    private let maxCompressionQuality: CGFloat = 0.7
    private var framesSent: Int = 0
    private var framesFailed: Int = 0
    private var lastQualityAdjustment: Date = Date()

    // Network monitoring statistics
    private var totalFramesSent: Int = 0
    private var totalFramesFailed: Int = 0
    private var totalBytesSent: Int64 = 0
    private var sessionStartTime: Date?
    private var lastStatsLog: Date = Date()

    private let serviceType = "novaid-assist"

    // MARK: - Initialization
    private override init() {
        super.init()
        setupPeerID()
    }

    private func setupPeerID() {
        let deviceName = UIDevice.current.name
        peerID = MCPeerID(displayName: deviceName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    // MARK: - Session Code Management

    /// Generate a random 6-digit session code
    func generateSessionCode() -> String {
        let code = String(format: "%06d", Int.random(in: 0...999999))
        sessionCode = code
        return code
    }

    /// Set session code for joining
    func setSessionCode(_ code: String) {
        sessionCode = code
    }

    // MARK: - Hosting (Professional waits for User)

    /// Start hosting a session (Professional mode)
    func startHosting(withCode code: String) {
        sessionCode = code
        stopAll()

        // Create advertiser with session code in discovery info
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["code": code, "role": "professional"],
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        isHosting = true
        connectionStatus = "Waiting for connection..."
        print("[Multipeer] Started hosting with code: \(code)")
    }

    // MARK: - Browsing (User looks for Professional)

    /// Start browsing for hosts (User mode)
    func startBrowsing(forCode code: String) {
        sessionCode = code
        stopAll()

        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        isBrowsing = true
        connectionStatus = "Searching for professional..."
        print("[Multipeer] Started browsing for code: \(code)")
    }

    // MARK: - Connection

    /// Invite a peer to connect
    func invitePeer(_ peer: MCPeerID) {
        let context = sessionCode.data(using: .utf8)
        browser?.invitePeer(peer, to: session, withContext: context, timeout: 30)
        connectionStatus = "Connecting..."
        print("[Multipeer] Invited peer: \(peer.displayName)")
    }

    /// Accept incoming invitation
    func acceptInvitation() {
        guard let invitation = incomingInvitation else { return }
        invitation.handler(true, session)
        incomingInvitation = nil
        connectionStatus = "Connecting..."
        print("[Multipeer] Accepted invitation from: \(invitation.from.displayName)")
    }

    /// Reject incoming invitation
    func rejectInvitation() {
        guard let invitation = incomingInvitation else { return }
        invitation.handler(false, nil)
        incomingInvitation = nil
        print("[Multipeer] Rejected invitation")
    }

    // MARK: - Data Transmission

    /// Send data to connected peer (reliable)
    func sendData(_ data: Data, reliable: Bool = true) {
        guard !session.connectedPeers.isEmpty else {
            return
        }

        do {
            try session.send(data, toPeers: session.connectedPeers, with: reliable ? .reliable : .unreliable)
        } catch {
            print("[Multipeer] Failed to send data: \(error)")
        }
    }

    /// Send a message
    func sendMessage(_ message: MultipeerMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        sendData(data)
    }

    /// Send SPS/PPS parameter sets (sent once at stream start, out-of-band)
    /// This is proper H.264 streaming: format description sent separately from frames
    func sendSPSPPS(spsData: Data, ppsData: Data) {
        guard isConnected, !session.connectedPeers.isEmpty else {
            return
        }

        // Encode SPS/PPS into a single payload
        struct SPSPPSPayload: Codable {
            let sps: Data
            let pps: Data
        }

        let payload = SPSPPSPayload(sps: spsData, pps: ppsData)
        guard let payloadData = try? JSONEncoder().encode(payload) else {
            print("[Multipeer] ❌ Failed to encode SPS/PPS")
            return
        }

        let message = MultipeerMessage(type: .spsPps, payload: payloadData)
        guard let messageData = try? JSONEncoder().encode(message) else {
            print("[Multipeer] ❌ Failed to encode SPS/PPS message")
            return
        }

        // Send reliably - SPS/PPS is critical for decoder initialization
        do {
            try session.send(messageData, toPeers: session.connectedPeers, with: .reliable)
            print("[Multipeer] 🎬 Sent SPS(\(spsData.count)B) + PPS(\(ppsData.count)B) to decoder")
        } catch {
            print("[Multipeer] ❌ Failed to send SPS/PPS: \(error)")
        }
    }

    /// Send H.264 compressed frame (WebRTC-style, 20-100x smaller than raw pixels)
    /// This is the FASTEST method - industry standard for real-time video
    func sendH264Data(_ h264Data: Data, metadata: VideoFrameMetadata) {
        guard isConnected, !session.connectedPeers.isEmpty else { return }

        // Bundle H.264 data with metadata for jitter buffer
        let frameWithMetadata = H264FrameWithMetadata(h264Data: h264Data, metadata: metadata)
        guard let encodedData = try? JSONEncoder().encode(frameWithMetadata) else {
            print("[Multipeer] ❌ Failed to encode frame with metadata")
            return
        }

        let message = MultipeerMessage(type: .h264Frame, payload: encodedData)
        guard let dataToSend = try? JSONEncoder().encode(message) else { return }

        // ULTRA-LOW LATENCY: ALL frames sent unreliable (WebRTC/UDP style)
        // Accept occasional frame loss rather than waiting for retransmission
        // Keyframes sent every 0.5s for fast recovery from packet loss
        let mode: MCSessionSendDataMode = .unreliable

        // Send with unreliable mode
        do {
            try session.send(dataToSend, toPeers: session.connectedPeers, with: mode)
            framesSent += 1
            totalFramesSent += 1
            totalBytesSent += Int64(dataToSend.count)
            adjustQualityIfNeeded()
            logNetworkStatsIfNeeded()
        } catch {
            framesFailed += 1
            totalFramesFailed += 1
            adjustQualityIfNeeded()
            // Silently fail for unreliable frames (expected behavior)
        }
    }

    /// Send CVPixelBuffer directly (zero JPEG conversion, proper color handling)
    /// DEPRECATED: Use H.264 for much better performance (20-100x smaller data)
    func sendPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        // Rate limit to prevent flooding
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= minFrameInterval else { return }
        lastFrameTime = now

        guard isConnected, !session.connectedPeers.isEmpty else { return }

        // Encode pixel buffer to data (preserves YUV format, no color conversion)
        guard let pixelData = PixelBufferTransmissionService.encodePixelBuffer(pixelBuffer) else {
            print("[Multipeer] ❌ Failed to encode pixel buffer")
            return
        }

        let message = MultipeerMessage(type: .pixelBufferFrame, payload: pixelData)
        guard let data = try? JSONEncoder().encode(message) else { return }

        // Send unreliable for speed (like UDP)
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
            framesSent += 1
            totalFramesSent += 1
            totalBytesSent += Int64(data.count)
            adjustQualityIfNeeded()
            logNetworkStatsIfNeeded()
        } catch {
            framesFailed += 1
            totalFramesFailed += 1
            adjustQualityIfNeeded()
        }
    }

    /// Send video frame with orientation (compressed JPEG with adaptive quality)
    /// DEPRECATED: Use sendPixelBuffer() for better performance and color accuracy
    func sendVideoFrame(_ image: UIImage, orientation: DeviceOrientation = DeviceOrientation()) {
        // Rate limit to prevent flooding
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= minFrameInterval else { return }
        lastFrameTime = now

        guard isConnected, !session.connectedPeers.isEmpty else { return }

        // Adaptive quality based on network performance (WebRTC-inspired)
        guard let jpegData = image.jpegData(compressionQuality: currentCompressionQuality) else { return }

        // Create video frame with orientation message
        let frameData = VideoFrameData(imageData: jpegData, orientation: orientation)
        guard let framePayload = try? JSONEncoder().encode(frameData) else { return }

        let message = MultipeerMessage(type: .videoFrameWithOrientation, payload: framePayload)
        guard let data = try? JSONEncoder().encode(message) else { return }

        // Send unreliable for speed (like UDP)
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
            framesSent += 1
            totalFramesSent += 1
            totalBytesSent += Int64(data.count)
            adjustQualityIfNeeded()
            logNetworkStatsIfNeeded()
        } catch {
            framesFailed += 1
            totalFramesFailed += 1
            adjustQualityIfNeeded()
        }
    }

    /// Adjust compression quality based on network performance (WebRTC-inspired adaptive quality)
    private func adjustQualityIfNeeded() {
        // Adjust every 2 seconds (similar to WebRTC bitrate adjustment)
        let now = Date()
        guard now.timeIntervalSince(lastQualityAdjustment) >= 2.0 else { return }
        lastQualityAdjustment = now

        guard framesSent > 0 else { return }

        let failureRate = Double(framesFailed) / Double(framesSent + framesFailed)
        let oldQuality = currentCompressionQuality

        if failureRate > 0.1 {
            // High failure rate (>10%) - reduce quality for smaller frames
            currentCompressionQuality = max(minCompressionQuality, currentCompressionQuality - 0.05)
            print("[Multipeer] 📉 High failure rate (\(Int(failureRate * 100))%) - reducing quality to \(String(format: "%.2f", currentCompressionQuality))")
        } else if failureRate < 0.02 && currentCompressionQuality < maxCompressionQuality {
            // Low failure rate (<2%) - increase quality gradually
            currentCompressionQuality = min(maxCompressionQuality, currentCompressionQuality + 0.03)
            print("[Multipeer] 📈 Low failure rate (\(Int(failureRate * 100))%) - increasing quality to \(String(format: "%.2f", currentCompressionQuality))")
        }

        // Reset counters
        framesSent = 0
        framesFailed = 0
    }

    /// Log network statistics periodically for monitoring
    private func logNetworkStatsIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastStatsLog) >= 10.0 else { return }
        lastStatsLog = now

        let totalFrames = totalFramesSent + totalFramesFailed
        guard totalFrames > 0 else { return }

        let successRate = Double(totalFramesSent) / Double(totalFrames) * 100
        let avgBytesPerFrame = totalFramesSent > 0 ? totalBytesSent / Int64(totalFramesSent) : 0
        let mbTransferred = Double(totalBytesSent) / 1_000_000.0

        if let startTime = sessionStartTime {
            let duration = now.timeIntervalSince(startTime)
            let fps = Double(totalFramesSent) / duration
            let mbps = (Double(totalBytesSent) * 8.0) / (duration * 1_000_000.0)

            print("[Multipeer] 📊 Network Stats: \(totalFramesSent) frames sent, \(String(format: "%.1f", successRate))% success rate, \(String(format: "%.1f", fps)) FPS, \(String(format: "%.2f", mbps)) Mbps, \(avgBytesPerFrame) bytes/frame, Quality: \(String(format: "%.2f", currentCompressionQuality))")
        } else {
            sessionStartTime = now
        }
    }

    /// Reset network statistics (called on new connection)
    private func resetNetworkStats() {
        totalFramesSent = 0
        totalFramesFailed = 0
        totalBytesSent = 0
        framesSent = 0
        framesFailed = 0
        sessionStartTime = Date()
        lastStatsLog = Date()
        currentCompressionQuality = 0.5 // Reset to default quality
        print("[Multipeer] 📊 Network statistics reset for new session")
    }

    /// Send frozen frame (compressed JPEG)
    func sendFrozenFrame(_ image: UIImage) {
        guard isConnected, !session.connectedPeers.isEmpty else { return }

        // Compress to JPEG with good quality for frozen frame (for annotation drawing)
        guard let jpegData = image.jpegData(compressionQuality: 0.75) else { return }

        let message = MultipeerMessage(type: .frozenFrame, payload: jpegData)
        guard let data = try? JSONEncoder().encode(message) else { return }

        // Send reliably
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("[Multipeer] Failed to send frozen frame: \(error)")
        }
    }

    /// Send audio data
    func sendAudioData(_ audioData: Data) {
        guard isConnected, !session.connectedPeers.isEmpty else {
            print("[Multipeer] ⚠️ Cannot send audio - not connected")
            return
        }

        let message = MultipeerMessage(type: .audioData, payload: audioData)
        guard let data = try? JSONEncoder().encode(message) else {
            print("[Multipeer] ❌ Failed to encode audio message")
            return
        }

        // Send unreliable for low latency (like UDP)
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
            print("[Multipeer] ✅ Sent audio data: \(audioData.count) bytes to \(session.connectedPeers.count) peer(s)")
        } catch {
            print("[Multipeer] ❌ Failed to send audio: \(error.localizedDescription)")
        }
    }

    /// Send call request
    func sendCallRequest() {
        let message = MultipeerMessage(type: .callRequest, payload: nil)
        sendMessage(message)
    }

    /// Send call accepted
    func sendCallAccepted() {
        let message = MultipeerMessage(type: .callAccepted, payload: nil)
        sendMessage(message)
        onCallAccepted?()
    }

    /// Send call rejected
    func sendCallRejected() {
        let message = MultipeerMessage(type: .callRejected, payload: nil)
        sendMessage(message)
    }

    /// Send call ended
    func sendCallEnded() {
        let message = MultipeerMessage(type: .callEnded, payload: nil)
        sendMessage(message)
    }

    /// Send annotation
    func sendAnnotation(_ annotation: Annotation) {
        guard let data = try? JSONEncoder().encode(annotation) else { return }
        let message = MultipeerMessage(type: .annotation, payload: data)
        sendMessage(message)
    }

    /// Send annotation update with AR world position
    func sendAnnotationUpdate(_ annotation: Annotation) {
        guard let data = try? JSONEncoder().encode(annotation) else {
            print("[Multipeer] ❌ Failed to encode annotation update")
            return
        }
        let message = MultipeerMessage(type: .annotationUpdate, payload: data)
        sendMessage(message)
        print("[Multipeer] ✅ Sent annotation update with world position: \(annotation.worldPosition?.debugDescription ?? "none")")
    }

    /// Send lightweight annotation position update for AR tracking
    func sendAnnotationPositionUpdate(id: String, normalizedX: CGFloat, normalizedY: CGFloat) {
        guard isConnected, !session.connectedPeers.isEmpty else { return }

        let update = AnnotationPositionUpdate(id: id, normalizedX: normalizedX, normalizedY: normalizedY)
        guard let data = try? JSONEncoder().encode(update) else { return }
        let message = MultipeerMessage(type: .annotationPositionUpdate, payload: data)

        // Send unreliable for low latency (positions update frequently)
        do {
            guard let messageData = try? JSONEncoder().encode(message) else { return }
            try session.send(messageData, toPeers: session.connectedPeers, with: .unreliable)
        } catch {
            // Silently fail for position updates to avoid log spam
        }
    }

    /// Send freeze video command
    func sendFreezeVideo() {
        let message = MultipeerMessage(type: .freezeVideo, payload: nil)
        sendMessage(message)
    }

    /// Send resume video command with annotations
    func sendResumeVideo(annotations: [Annotation]) {
        guard let data = try? JSONEncoder().encode(annotations) else { return }
        let message = MultipeerMessage(type: .resumeVideo, payload: data)
        sendMessage(message)
    }

    /// Send clear all annotations command
    func sendClearAnnotations() {
        let message = MultipeerMessage(type: .clearAnnotations, payload: nil)
        sendMessage(message)
        print("[Multipeer] Sent clear annotations command")
    }

    /// Send toggle flashlight command
    func sendToggleFlashlight(on: Bool) {
        let payload = try? JSONEncoder().encode(on)
        let message = MultipeerMessage(type: .toggleFlashlight, payload: payload)
        sendMessage(message)
        print("[Multipeer] Sent toggle flashlight command: \(on ? "ON" : "OFF")")
    }

    // MARK: - Adaptive Streaming Methods (Chalk-style)

    /// Send ping for RTT measurement
    func sendPing(pingId: String) {
        let ping = PingMessage(pingId: pingId, timestamp: Date())
        let payload = try? JSONEncoder().encode(ping)
        let message = MultipeerMessage(type: .ping, payload: payload)
        sendMessage(message)
    }

    /// Send pong response for RTT measurement
    func sendPong(pingId: String) {
        let pong = PongMessage(pingId: pingId, timestamp: Date())
        let payload = try? JSONEncoder().encode(pong)
        let message = MultipeerMessage(type: .pong, payload: payload)
        sendMessage(message)
    }

    /// Send streaming mode change notification
    func sendStreamingModeChange(_ mode: String) {
        let modeMsg = StreamingModeMessage(mode: mode, timestamp: Date())
        let payload = try? JSONEncoder().encode(modeMsg)
        let message = MultipeerMessage(type: .streamingModeChange, payload: payload)
        sendMessage(message)
        print("[Multipeer] 🎯 Sent streaming mode change: \(mode)")
    }

    /// Send frame metadata for freeze-frame mode
    func sendFrameMetadata(frameId: String, timestamp: Date, intrinsics: [Float], worldFromCamera: [Float], trackingState: String) {
        let metadata = FrameMetadata(
            frameId: frameId,
            timestamp: timestamp,
            cameraIntrinsics: intrinsics,
            worldFromCamera: worldFromCamera,
            trackingState: trackingState
        )
        let payload = try? JSONEncoder().encode(metadata)
        let message = MultipeerMessage(type: .frameMetadata, payload: payload)
        sendMessage(message)
    }

    /// Send QoS metrics to peer
    func sendQoSMetrics(rttMs: Double, jitterMs: Double, packetLossPct: Double) {
        let metrics = QoSMetricsMessage(
            rttMs: rttMs,
            jitterMs: jitterMs,
            packetLossPct: packetLossPct,
            timestamp: Date()
        )
        let payload = try? JSONEncoder().encode(metrics)
        let message = MultipeerMessage(type: .qosMetrics, payload: payload)
        sendMessage(message)
    }

    // MARK: - AR Reconstruction Methods (Zoho Lens / Chalk style)

    /// Send depth map data to iPad for 3D reconstruction
    func sendDepthMap(_ depthMapData: DepthMapData) {
        let payload = try? JSONEncoder().encode(depthMapData)
        let message = MultipeerMessage(type: .depthMap, payload: payload)
        sendMessage(message)
    }

    /// Send detected AR planes to iPad
    func sendDetectedPlanes(_ planesData: DetectedPlaneData) {
        let payload = try? JSONEncoder().encode(planesData)
        let message = MultipeerMessage(type: .detectedPlanes, payload: payload)
        sendMessage(message)
    }

    /// Send annotation anchor data (3D position + orientation)
    func sendAnnotationAnchorData(_ anchorData: AnnotationAnchorData) {
        let payload = try? JSONEncoder().encode(anchorData)
        let message = MultipeerMessage(type: .annotationAnchorData, payload: payload)
        sendMessage(message)
        print("[Multipeer] 📍 Sent annotation anchor: \(anchorData.annotationId) at position \(anchorData.worldPosition)")
    }

    // MARK: - Cleanup

    func stopAll() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        isHosting = false
        isBrowsing = false
    }

    func disconnect() {
        stopAll()
        session.disconnect()
        isConnected = false
        connectedPeerId = nil
        availablePeers = []
        connectionStatus = "Disconnected"
        receivedVideoFrame = nil
        onDisconnected?()
    }
}

// MARK: - MCSessionDelegate
extension MultipeerService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                print("[Multipeer] Connected to: \(peerID.displayName)")
                self.isConnected = true
                self.connectedPeerId = peerID.displayName
                self.connectionStatus = "Connected to \(peerID.displayName)"
                self.stopAll()
                self.resetNetworkStats()
                self.onConnected?()

            case .connecting:
                print("[Multipeer] Connecting to: \(peerID.displayName)")
                self.connectionStatus = "Connecting..."

            case .notConnected:
                print("[Multipeer] Disconnected from: \(peerID.displayName)")
                self.isConnected = false
                self.connectedPeerId = nil
                self.connectionStatus = "Disconnected"
                self.onDisconnected?()

            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // LEGACY: Check if this is raw H.264 data (large frame with 0xFF prefix - old format without metadata)
        // This path should not be used anymore since we now always bundle metadata with frames
        if data.count > 1 && data[0] == 0xFF {
            // Raw H.264 keyframe - extract actual H.264 data (skip 1-byte prefix)
            let h264Data = data.subdata(in: 1..<data.count)
            print("[Multipeer] ⚠️ Received LEGACY RAW H.264 frame without metadata: \(h264Data.count) bytes")

            // Create fallback metadata for legacy frames (best-effort)
            let fallbackMetadata = VideoFrameMetadata(
                sequenceNumber: 0,  // Unknown sequence
                captureTimestamp: Date(),  // Assume captured now
                presentationTime: CMTime.zero,  // Unknown presentation time
                isKeyframe: true  // Raw frames were always keyframes
            )

            Task { @MainActor in
                self.onH264DataReceived?(h264Data, fallbackMetadata)
            }
            return
        }

        // Parse JSON-encoded message (small frames and other messages)
        guard let message = try? JSONDecoder().decode(MultipeerMessage.self, from: data) else {
            print("[Multipeer] ⚠️ Failed to decode message (\(data.count) bytes)")
            return
        }

        Task { @MainActor in
            self.onDataReceived?(data, peerID)

            switch message.type {
            case .callRequest:
                self.onIncomingCall?(peerID.displayName)

            case .callAccepted:
                self.onCallAccepted?()

            case .callRejected:
                self.onCallRejected?()

            case .callEnded:
                self.onDisconnected?()

            case .annotation:
                if let payload = message.payload,
                   let annotation = try? JSONDecoder().decode(Annotation.self, from: payload) {
                    self.onAnnotationReceived?(annotation)
                }

            case .annotationUpdate:
                if let payload = message.payload,
                   let annotation = try? JSONDecoder().decode(Annotation.self, from: payload) {
                    print("[Multipeer] ✅ Received annotation update with world position: \(annotation.worldPosition?.debugDescription ?? "none")")
                    self.onAnnotationUpdated?(annotation)
                }

            case .annotationPositionUpdate:
                if let payload = message.payload,
                   let update = try? JSONDecoder().decode(AnnotationPositionUpdate.self, from: payload) {
                    self.onAnnotationPositionUpdated?(update.id, update.normalizedX, update.normalizedY)
                }

            case .freezeVideo:
                self.onVideoFrozen?()

            case .resumeVideo:
                if let payload = message.payload,
                   let annotations = try? JSONDecoder().decode([Annotation].self, from: payload) {
                    self.onVideoResumed?(annotations)
                }

            case .clearAnnotations:
                print("[Multipeer] Received clear annotations command")
                self.onClearAnnotations?()

            case .toggleFlashlight:
                if let payload = message.payload,
                   let isOn = try? JSONDecoder().decode(Bool.self, from: payload) {
                    print("[Multipeer] Received toggle flashlight: \(isOn ? "ON" : "OFF")")
                    self.onToggleFlashlight?(isOn)
                }

            case .videoFrame:
                if let payload = message.payload,
                   let image = UIImage(data: payload) {
                    self.receivedVideoFrame = image
                    self.onVideoFrameReceived?(image)
                }

            case .videoFrameWithOrientation:
                if let payload = message.payload,
                   let frameData = try? JSONDecoder().decode(VideoFrameData.self, from: payload),
                   let image = UIImage(data: frameData.imageData) {
                    self.receivedVideoFrame = image
                    self.receivedDeviceOrientation = frameData.orientation
                    self.onVideoFrameReceived?(image)
                }

            case .spsPps:
                // SPS/PPS parameter sets (sent once at stream start for decoder initialization)
                if let payload = message.payload {
                    struct SPSPPSPayload: Codable {
                        let sps: Data
                        let pps: Data
                    }
                    if let spsPpsPayload = try? JSONDecoder().decode(SPSPPSPayload.self, from: payload) {
                        print("[Multipeer] 🎬 Received SPS(\(spsPpsPayload.sps.count)B) + PPS(\(spsPpsPayload.pps.count)B)")
                        self.onSPSPPSReceived?(spsPpsPayload.sps, spsPpsPayload.pps)
                    }
                }

            case .h264Frame:
                // WebRTC-STYLE: H.264 compressed frame with metadata for jitter buffer
                if let payload = message.payload,
                   let frameWithMetadata = try? JSONDecoder().decode(H264FrameWithMetadata.self, from: payload) {
                    self.onH264DataReceived?(frameWithMetadata.h264Data, frameWithMetadata.metadata)
                    // print("[Multipeer] ✅ Received H.264 frame: \(frameWithMetadata.h264Data.count) bytes, seq: \(frameWithMetadata.metadata.sequenceNumber)")
                }

            case .pixelBufferFrame:
                // Fallback: Direct CVPixelBuffer transmission (no JPEG, proper YUV handling)
                if let payload = message.payload,
                   let pixelBuffer = PixelBufferTransmissionService.decodePixelBuffer(from: payload) {
                    self.onPixelBufferReceived?(pixelBuffer)
                    print("[Multipeer] ✅ Received CVPixelBuffer frame: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
                }

            case .frozenFrame:
                if let payload = message.payload,
                   let image = UIImage(data: payload) {
                    self.frozenFrame = image
                    self.onFrozenFrameReceived?(image)
                    print("[Multipeer] Received frozen frame")
                }

            case .audioData:
                if let payload = message.payload {
                    print("[Multipeer] ✅ Received audio data: \(payload.count) bytes")
                    self.onAudioDataReceived?(payload)
                } else {
                    print("[Multipeer] ⚠️ Received audio message with no payload")
                }

            // ADAPTIVE STREAMING: QoS monitoring message handlers (Chalk-style)

            case .ping:
                // Received ping - respond with pong immediately
                if let payload = message.payload,
                   let ping = try? JSONDecoder().decode(PingMessage.self, from: payload) {
                    // Auto-respond with pong
                    self.sendPong(pingId: ping.pingId)
                    self.onPingReceived?(ping.pingId)
                }

            case .pong:
                // Received pong - calculate RTT
                if let payload = message.payload,
                   let pong = try? JSONDecoder().decode(PongMessage.self, from: payload) {
                    self.onPongReceived?(pong.pingId)
                }

            case .streamingModeChange:
                // Peer changed streaming mode
                if let payload = message.payload,
                   let modeMsg = try? JSONDecoder().decode(StreamingModeMessage.self, from: payload) {
                    print("[Multipeer] 🎯 Received mode change: \(modeMsg.mode)")
                    self.onStreamingModeChanged?(modeMsg.mode)
                }

            case .frameMetadata:
                // Received frame metadata for freeze-frame mode
                if let payload = message.payload,
                   let metadata = try? JSONDecoder().decode(FrameMetadata.self, from: payload) {
                    self.onFrameMetadataReceived?(metadata)
                }

            case .qosMetrics:
                // Received QoS metrics from peer
                if let payload = message.payload,
                   let metrics = try? JSONDecoder().decode(QoSMetricsMessage.self, from: payload) {
                    self.onQoSMetricsReceived?(metrics.rttMs, metrics.jitterMs, metrics.packetLossPct)
                }

            // AR RECONSTRUCTION: Depth and scene understanding handlers

            case .depthMap:
                // Received depth map for 3D reconstruction
                if let payload = message.payload,
                   let depthMap = try? JSONDecoder().decode(DepthMapData.self, from: payload) {
                    print("[Multipeer] 🗺️ Received depth map: \(depthMap.width)x\(depthMap.height)")
                    self.onDepthMapReceived?(depthMap)
                }

            case .detectedPlanes:
                // Received detected AR planes from iPhone
                if let payload = message.payload,
                   let planes = try? JSONDecoder().decode(DetectedPlaneData.self, from: payload) {
                    print("[Multipeer] 🏗️ Received \(planes.planes.count) detected planes")
                    self.onDetectedPlanesReceived?(planes)
                }

            case .annotationAnchorData:
                // Received 3D anchor data for annotation
                if let payload = message.payload,
                   let anchorData = try? JSONDecoder().decode(AnnotationAnchorData.self, from: payload) {
                    print("[Multipeer] 📍 Received annotation anchor: \(anchorData.annotationId)")
                    self.onAnnotationAnchorDataReceived?(anchorData)
                }
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Handle incoming stream if needed
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Handle resource transfer
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Handle completed resource transfer
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // Check if the invitation has the matching session code
            if let contextData = context,
               let receivedCode = String(data: contextData, encoding: .utf8),
               receivedCode == self.sessionCode {
                // Auto-accept if codes match
                print("[Multipeer] Auto-accepting invitation from \(peerID.displayName) with matching code")
                invitationHandler(true, self.session)
                self.onIncomingCall?(peerID.displayName)
            } else {
                // Store invitation for manual handling
                self.incomingInvitation = (peerID, invitationHandler)
                self.onIncomingCall?(peerID.displayName)
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            print("[Multipeer] Failed to advertise: \(error)")
            self.connectionStatus = "Failed to start hosting"
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            print("[Multipeer] Found peer: \(peerID.displayName), info: \(String(describing: info))")

            // Check if the peer has our session code
            if let peerCode = info?["code"], peerCode == self.sessionCode {
                // Found matching peer, auto-connect
                print("[Multipeer] Found matching peer with code \(peerCode)")

                // Add to list if not already there
                if !self.availablePeers.contains(where: { $0.displayName == peerID.displayName }) {
                    self.availablePeers.append(peerID)
                }

                // Always try to invite when we find a matching code
                // (even if peer is already in list from previous discovery with different code)
                if !self.isConnected {
                    print("[Multipeer] Inviting peer with matching code...")
                    self.invitePeer(peerID)
                } else {
                    print("[Multipeer] Already connected, skipping invite")
                }
            } else {
                // Just add to list (wrong code, don't invite)
                if !self.availablePeers.contains(where: { $0.displayName == peerID.displayName }) {
                    self.availablePeers.append(peerID)
                }
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            print("[Multipeer] Lost peer: \(peerID.displayName)")
            self.availablePeers.removeAll { $0.displayName == peerID.displayName }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            print("[Multipeer] Failed to browse: \(error)")
            self.connectionStatus = "Failed to search"
        }
    }
}

// MARK: - Message Types
struct MultipeerMessage: Codable {
    enum MessageType: String, Codable {
        case callRequest
        case callAccepted
        case callRejected
        case callEnded
        case annotation
        case annotationUpdate
        case annotationPositionUpdate
        case clearAnnotations
        case toggleFlashlight
        case freezeVideo
        case resumeVideo
        case videoFrame
        case videoFrameWithOrientation
        case pixelBufferFrame  // CVPixelBuffer transmission (raw YUV ~1.3MB/frame)
        case h264Frame  // H.264 compressed frame (10-50KB/frame - WebRTC standard)
        case spsPps  // SPS/PPS parameter sets (sent once at stream start)
        case frozenFrame
        case audioData

        // ADAPTIVE STREAMING: QoS monitoring and mode switching (Chalk-style)
        case ping  // RTT measurement - sender to receiver
        case pong  // RTT measurement - response from receiver
        case streamingModeChange  // Notify mode switch (normal/lowBandwidth/freezeFrame/audioOnly)
        case frameMetadata  // Camera intrinsics + pose for freeze-frame mode
        case qosMetrics  // Share QoS metrics (RTT, jitter, packet loss)

        // AR RECONSTRUCTION: Depth and scene understanding (Zoho Lens / Chalk style)
        case depthMap  // Depth data from iPhone LiDAR or ARKit depth estimation
        case detectedPlanes  // ARPlaneAnchors from iPhone scene understanding
        case annotationAnchorData  // 3D anchor position + orientation for annotation
    }

    let type: MessageType
    let payload: Data?
}

/// Lightweight position update for AR tracking
struct AnnotationPositionUpdate: Codable {
    let id: String
    let normalizedX: CGFloat
    let normalizedY: CGFloat
}

// MARK: - Device Orientation Data
struct DeviceOrientation: Codable {
    enum OrientationState: String, Codable {
        case portrait
        case portraitUpsideDown
        case landscapeLeft
        case landscapeRight
        case unknown
    }

    var state: OrientationState = .landscapeRight

    init(state: OrientationState = .landscapeRight) {
        self.state = state
    }
}

// MARK: - Video Frame Data with Orientation
struct VideoFrameData: Codable {
    let imageData: Data
    let orientation: DeviceOrientation
}

// MARK: - H.264 Frame with Metadata for Jitter Buffer
struct H264FrameWithMetadata: Codable {
    let h264Data: Data
    let metadata: VideoFrameMetadata
}

// MARK: - Adaptive Streaming Data Structures (Chalk-style)

/// Ping message for RTT measurement
struct PingMessage: Codable {
    let pingId: String
    let timestamp: Date
}

/// Pong response for RTT measurement
struct PongMessage: Codable {
    let pingId: String
    let timestamp: Date
}

/// Streaming mode change notification
struct StreamingModeMessage: Codable {
    let mode: String  // "normal", "lowBandwidth", "freezeFrame", "audioOnly"
    let timestamp: Date
}

/// Frame metadata for freeze-frame mode (Chalk-style)
struct FrameMetadata: Codable {
    let frameId: String
    let timestamp: Date
    let cameraIntrinsics: [Float]  // 3x3 matrix flattened
    let worldFromCamera: [Float]  // 4x4 transform matrix flattened
    let trackingState: String
}

/// QoS metrics sharing
struct QoSMetricsMessage: Codable {
    let rttMs: Double
    let jitterMs: Double
    let packetLossPct: Double
    let timestamp: Date
}

// MARK: - AR Reconstruction Data Structures (Zoho Lens / Chalk style)

/// Depth map data from iPhone for 3D reconstruction
struct DepthMapData: Codable {
    let width: Int
    let height: Int
    let depthData: Data  // Compressed depth values (Float32 array)
    let cameraIntrinsics: [Float]  // 3x3 matrix
    let cameraTransform: [Float]  // 4x4 world-from-camera matrix
    let timestamp: Date
}

/// Detected AR plane information
struct DetectedPlaneData: Codable {
    struct Plane: Codable {
        let identifier: String
        let center: [Float]  // 3D position (x, y, z)
        let extent: [Float]  // Size (width, height)
        let transform: [Float]  // 4x4 transform matrix
        let classification: String  // "wall", "floor", "table", etc.
        let alignment: String  // "horizontal", "vertical"
    }

    let planes: [Plane]
    let timestamp: Date
}

/// AR anchor data for annotation positioning
struct AnnotationAnchorData: Codable {
    let annotationId: String
    let worldPosition: [Float]  // 3D position (x, y, z)
    let worldOrientation: [Float]  // Quaternion (x, y, z, w)
    let anchoredToPlaneId: String?  // Plane identifier if anchored to plane
    let timestamp: Date
}
