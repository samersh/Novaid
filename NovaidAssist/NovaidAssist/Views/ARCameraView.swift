import SwiftUI
import ARKit
import RealityKit

/// AR Camera view for the User side with proper landscape video streaming and world tracking
struct ARCameraView: UIViewRepresentable {
    @ObservedObject var annotationManager: ARAnnotationManager
    var isVideoFrozen: Bool = false

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        context.coordinator.annotationManager = annotationManager

        // Configure AR session for world tracking with plane detection
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic

        // Enable scene reconstruction if available (for better tracking)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        arView.session.delegate = context.coordinator
        arView.session.run(configuration)

        // Keep screen awake
        UIApplication.shared.isIdleTimerDisabled = true

        // Start frame streaming
        context.coordinator.startFrameStreaming()

        print("[AR] ARKit session started with plane detection")
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.processNewAnnotations()

        // Handle freeze/resume
        if isVideoFrozen != context.coordinator.isVideoFrozen {
            context.coordinator.isVideoFrozen = isVideoFrozen
            if isVideoFrozen {
                context.coordinator.freezeVideo()
            } else {
                context.coordinator.resumeVideo()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        UIApplication.shared.isIdleTimerDisabled = false
        coordinator.cleanup()
    }

    class Coordinator: NSObject, ARSessionDelegate {
        var arView: ARView?
        var annotationManager: ARAnnotationManager?
        private var annotationAnchors: [String: AnchorEntity] = [:]
        private let frameQueue = DispatchQueue(label: "com.novaid.arFrameQueue", qos: .userInteractive)
        private var isSessionReady = false
        private var detectedPlanes: [UUID: ARPlaneAnchor] = [:]
        private var currentOrientation = DeviceOrientation()
        var isVideoFrozen = false
        private var lastCapturedFrame: UIImage?

        // LATENCY OPTIMIZATION: Throttle annotation position updates
        private var lastAnnotationUpdateTime: Date = Date()
        private let minAnnotationUpdateInterval: TimeInterval = 1.0 / 10.0  // 10 FPS for annotations (was 30 FPS)

        // H.264 encoder for WebRTC-style low-latency transmission (20-100x smaller than raw pixels)
        private let videoCodec = VideoCodecService.shared
        private var isEncoderSetup = false
        private var frameNumber: Int64 = 0

        // ADAPTIVE STREAMING: QoS monitoring and mode switching (Chalk-style)
        private let qosMonitor = NetworkQoSMonitor()
        private var currentStreamingMode: NetworkQoSMonitor.StreamingMode = .normal
        private var targetFPS: Int = 30
        private var lastFrameCaptureTime: Date = Date()
        private var frameCaptureInterval: TimeInterval = 0  // 0 = capture every frame

        // AR RECONSTRUCTION: Depth and plane data transmission (Zoho Lens / Chalk style)
        private var lastPlaneUpdateTime: Date = Date()
        private let planeUpdateInterval: TimeInterval = 2.0  // Send planes every 2 seconds
        private var lastDepthMapTime: Date = Date()
        private let depthMapInterval: TimeInterval = 0.5  // Send depth every 500ms

        func startFrameStreaming() {
            // Setup H.264 hardware encoder for WebRTC-style transmission
            setupH264Encoder()

            // REMOVED: Timer-based frame capture (was causing frame drops)
            // Instead, we now use ARSession's native frame callbacks in session(_ session: ARSession, didUpdate frame:)

            // Setup adaptive streaming based on network quality (Chalk-style)
            setupQoSMonitoring()

            // Enable device orientation notifications
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            print("[AR] Device orientation tracking started")
            print("[AR] ✅ Using ARSession native frame callbacks for adaptive FPS capture")
        }

        private func setupQoSMonitoring() {
            // Set up callback for mode changes
            qosMonitor.setModeChangeCallback { [weak self] newMode in
                guard let self = self else { return }

                self.currentStreamingMode = newMode
                self.targetFPS = newMode.targetFPS

                // Calculate frame interval based on target FPS
                self.frameCaptureInterval = self.targetFPS > 0 ? (1.0 / Double(self.targetFPS)) : 0

                print("[QoS] 🎯 Mode changed to: \(newMode.rawValue) (target FPS: \(self.targetFPS))")

                // Send mode change notification to iPad
                Task { @MainActor in
                    MultipeerService.shared.sendStreamingModeChange(newMode.rawValue)
                }
            }

            // Set up pong callback to record RTT
            Task { @MainActor in
                MultipeerService.shared.onPongReceived = { [weak self] pingId in
                    guard let self = self else { return }
                    self.qosMonitor.recordPongReceived(pingId: pingId)

                    // Periodically send QoS metrics to iPad
                    let metrics = self.qosMonitor.getCurrentMetrics()
                    Task { @MainActor in
                        MultipeerService.shared.sendQoSMetrics(
                            rttMs: metrics.rttMs,
                            jitterMs: metrics.jitterMs,
                            packetLossPct: metrics.packetLossPct
                        )
                    }
                }
            }

            // Start ping-pong RTT measurement
            startPingPongMonitoring()

            print("[QoS] ✅ Adaptive streaming initialized (Chalk-style)")
        }

        private func startPingPongMonitoring() {
            // Send ping every 1 second to measure RTT
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }

                let pingId = UUID().uuidString
                self.qosMonitor.recordPingSent(pingId: pingId)

                Task { @MainActor in
                    MultipeerService.shared.sendPing(pingId: pingId)
                }
            }
        }

        private func setupH264Encoder() {
            guard !isEncoderSetup else { return }

            // Setup H.264 encoder with 720p @ 30fps (WebRTC standard)
            let success = videoCodec.setupEncoder(width: 720, height: 1280)

            if success {
                isEncoderSetup = true
                print("[AR] ✅ H.264 hardware encoder setup (720p @ 30fps)")

                // Setup callback for SPS/PPS extraction (sent once at stream start)
                videoCodec.onSPSPPSExtracted = { [weak self] spsData, ppsData in
                    self?.sendSPSPPS(spsData: spsData, ppsData: ppsData)
                }

                // Setup callback for encoded frames
                videoCodec.onEncodedFrame = { [weak self] h264Data, presentationTime in
                    self?.sendH264Frame(h264Data)
                }
            } else {
                print("[AR] ❌ Failed to setup H.264 encoder, falling back to pixel buffer transmission")
            }
        }

        func freezeVideo() {
            isVideoFrozen = true

            // Capture and send the current frozen frame
            if let lastFrame = lastCapturedFrame {
                Task { @MainActor in
                    MultipeerService.shared.sendFrozenFrame(lastFrame)
                    print("[AR] Sent frozen frame to iPad")
                }
            }
            print("[AR] Video frozen - frame capture paused")
        }

        func resumeVideo() {
            isVideoFrozen = false
            print("[AR] Video resumed - frame capture resumed")
        }

        private func captureAndSendFrame(from frame: ARFrame) {
            // Skip if video is frozen
            guard !isVideoFrozen else { return }

            // ADAPTIVE STREAMING: Respect current mode's target FPS
            let now = Date()

            // Audio-only mode: Don't capture any frames
            if currentStreamingMode == .audioOnly {
                return
            }

            // Check if we should capture this frame based on target FPS
            if frameCaptureInterval > 0 {
                let timeSinceLastCapture = now.timeIntervalSince(lastFrameCaptureTime)
                guard timeSinceLastCapture >= frameCaptureInterval else {
                    return  // Skip this frame to maintain target FPS
                }
            }

            lastFrameCaptureTime = now

            // ULTRA-LOW LATENCY: Process frames directly from ARSession callback
            frameQueue.async { [weak self] in
                self?.processAndSendFrame(frame)
            }
        }

        private func processAndSendFrame(_ frame: ARFrame) {
            let pixelBuffer = frame.capturedImage
            let captureTime = Date()  // LATENCY TRACKING: Record capture timestamp

            if isEncoderSetup {
                // WebRTC-STYLE: H.264 hardware encoding (20-100x smaller than raw pixels)
                // - 1.3MB raw pixel data → 10-50KB H.264 compressed
                // - Hardware accelerated (GPU) - near zero CPU overhead
                // - Dramatically lower latency due to smaller data size
                // - Industry standard for real-time video (WebRTC, Zoom, etc.)

                // FREEZE-FRAME MODE: Force keyframe generation for freeze-frame mode (1 FPS)
                // This ensures each frame can be decoded independently
                let forceKeyframe = currentStreamingMode == .freezeFrame

                let presentationTime = CMTime(seconds: Double(frameNumber) / 30.0, preferredTimescale: 600)
                videoCodec.encode(
                    pixelBuffer: pixelBuffer,
                    presentationTime: presentationTime,
                    captureTime: captureTime,
                    forceKeyframe: forceKeyframe
                )

                // Include frame metadata for freeze-frame mode (Chalk-style)
                if currentStreamingMode == .freezeFrame {
                    sendFrameMetadata(frame: frame)
                }

                frameNumber += 1
            } else {
                // Fallback: Send pixel buffer directly (only if H.264 encoder failed)
                Task { @MainActor in
                    MultipeerService.shared.sendPixelBuffer(pixelBuffer)
                }
            }

            // Store thumbnail for freeze functionality (async, low priority)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }

                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let context = CIContext(options: [.useSoftwareRenderer: false])
                guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

                let thumbnailImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

                Task { @MainActor in
                    self.lastCapturedFrame = thumbnailImage
                }
            }
        }

        private func sendFrameMetadata(frame: ARFrame) {
            // Extract camera intrinsics (3x3 matrix)
            let intrinsics = frame.camera.intrinsics
            let intrinsicsArray: [Float] = [
                intrinsics[0, 0], intrinsics[0, 1], intrinsics[0, 2],
                intrinsics[1, 0], intrinsics[1, 1], intrinsics[1, 2],
                intrinsics[2, 0], intrinsics[2, 1], intrinsics[2, 2]
            ]

            // Extract camera transform (4x4 world-from-camera matrix)
            let transform = frame.camera.transform
            let transformArray: [Float] = [
                transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w,
                transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w,
                transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w,
                transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w
            ]

            // Send metadata to iPad for freeze-frame annotation
            Task { @MainActor in
                MultipeerService.shared.sendFrameMetadata(
                    frameId: String(frameNumber),
                    timestamp: Date(),
                    intrinsics: intrinsicsArray,
                    worldFromCamera: transformArray,
                    trackingState: frame.camera.trackingState.description
                )
            }
        }

        private func sendSPSPPS(spsData: Data, ppsData: Data) {
            Task { @MainActor in
                MultipeerService.shared.sendSPSPPS(spsData: spsData, ppsData: ppsData)
            }
        }

        private func sendH264Frame(_ h264Data: Data) {
            Task { @MainActor in
                MultipeerService.shared.sendH264Data(h264Data)
            }
        }

        func processNewAnnotations() {
            guard let arView = arView,
                  let manager = annotationManager,
                  isSessionReady else { return }

            // Place new annotations using raycasting
            for annotation in manager.annotations {
                if annotationAnchors[annotation.id] != nil { continue }

                if let firstPoint = annotation.points.first {
                    placeAnnotationWithRaycast(annotation, normalizedPoint: firstPoint, in: arView)
                }
            }

            // Remove deleted annotations
            let currentIds = Set(manager.annotations.map { $0.id })
            for (id, anchor) in annotationAnchors where !currentIds.contains(id) {
                arView.scene.removeAnchor(anchor)
                annotationAnchors.removeValue(forKey: id)
            }
        }

        private func placeAnnotationWithRaycast(_ annotation: ARTrackedAnnotation, normalizedPoint: AnnotationPoint, in arView: ARView) {
            // Convert normalized coordinates to screen coordinates
            let screenX = normalizedPoint.x * arView.bounds.width
            let screenY = normalizedPoint.y * arView.bounds.height
            let screenPoint = CGPoint(x: screenX, y: screenY)

            // Try raycasting to find a real surface
            if let worldPosition = performRaycast(from: screenPoint, in: arView) {
                // Found a surface - anchor to it
                createAnchorAtPosition(annotation, worldPosition: worldPosition, in: arView)
                print("[AR] Placed annotation on detected surface at: \(worldPosition)")
            } else {
                // No surface found - place at fixed distance
                if let fallbackPosition = placeAtFixedDistance(normalizedPoint: normalizedPoint, in: arView) {
                    createAnchorAtPosition(annotation, worldPosition: fallbackPosition, in: arView)
                    print("[AR] Placed annotation at fixed distance: \(fallbackPosition)")
                }
            }
        }

        private func performRaycast(from screenPoint: CGPoint, in arView: ARView) -> SIMD3<Float>? {
            // First try: raycast against detected planes
            if let query = arView.makeRaycastQuery(from: screenPoint, allowing: .existingPlaneGeometry, alignment: .any) {
                let results = arView.session.raycast(query)
                if let firstResult = results.first {
                    return SIMD3<Float>(
                        firstResult.worldTransform.columns.3.x,
                        firstResult.worldTransform.columns.3.y,
                        firstResult.worldTransform.columns.3.z
                    )
                }
            }

            // Second try: raycast against estimated planes
            if let query = arView.makeRaycastQuery(from: screenPoint, allowing: .estimatedPlane, alignment: .any) {
                let results = arView.session.raycast(query)
                if let firstResult = results.first {
                    return SIMD3<Float>(
                        firstResult.worldTransform.columns.3.x,
                        firstResult.worldTransform.columns.3.y,
                        firstResult.worldTransform.columns.3.z
                    )
                }
            }

            return nil
        }

        private func placeAtFixedDistance(normalizedPoint: AnnotationPoint, in arView: ARView) -> SIMD3<Float>? {
            guard let currentFrame = arView.session.currentFrame else { return nil }

            let cameraTransform = currentFrame.camera.transform
            let cameraPosition = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )

            // Calculate direction from normalized screen position
            let normalizedX = Float(normalizedPoint.x) * 2.0 - 1.0
            let normalizedY = -(Float(normalizedPoint.y) * 2.0 - 1.0)

            let fovSpread: Float = 0.5
            let localDirection = simd_normalize(SIMD3<Float>(
                normalizedX * fovSpread,
                normalizedY * fovSpread,
                -1.0
            ))

            let rotationMatrix = simd_float3x3(
                SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z),
                SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z),
                SIMD3<Float>(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
            )
            let worldDirection = rotationMatrix * localDirection

            let distance: Float = 0.5
            return cameraPosition + worldDirection * distance
        }

        private func createAnchorAtPosition(_ annotation: ARTrackedAnnotation, worldPosition: SIMD3<Float>, in arView: ARView) {
            let anchor = AnchorEntity(world: worldPosition)
            let entity = createMarkerEntity(color: UIColor(Color(hex: annotation.color) ?? .red))
            anchor.addChild(entity)

            arView.scene.addAnchor(anchor)
            annotationAnchors[annotation.id] = anchor
            annotationManager?.setWorldPosition(for: annotation.id, position: worldPosition)

            // Send annotation update back to iPad with AR world position
            Task { @MainActor in
                // Create updated annotation with world position
                var updatedAnnotation = Annotation(
                    id: annotation.id,
                    type: annotation.type,
                    points: annotation.points,
                    color: annotation.color,
                    strokeWidth: annotation.strokeWidth,
                    text: annotation.text,
                    animationType: annotation.animationType,
                    isComplete: true,  // AR-tracked annotations are complete
                    worldPosition: worldPosition
                )

                // Send back to iPad so it has the AR coordinates
                MultipeerService.shared.sendAnnotationUpdate(updatedAnnotation)
                print("[AR] ✅ Sent annotation update to iPad with world position: \(worldPosition)")
            }
        }

        private func createMarkerEntity(color: UIColor) -> Entity {
            // Create a 3D marker with enhanced visual effects
            let containerEntity = Entity()

            // Inner sphere - solid core with metallic finish
            let innerSphere = MeshResource.generateSphere(radius: 0.015)
            var innerMaterial = SimpleMaterial(color: color, isMetallic: true)
            innerMaterial.roughness = 0.2
            let innerEntity = ModelEntity(mesh: innerSphere, materials: [innerMaterial])
            containerEntity.addChild(innerEntity)

            // Middle ring - translucent layer
            let middleSphere = MeshResource.generateSphere(radius: 0.025)
            let middleMaterial = SimpleMaterial(color: color.withAlphaComponent(0.5), isMetallic: false)
            let middleEntity = ModelEntity(mesh: middleSphere, materials: [middleMaterial])
            containerEntity.addChild(middleEntity)

            // Outer glow - large transparent sphere
            let outerSphere = MeshResource.generateSphere(radius: 0.04)
            let outerMaterial = SimpleMaterial(color: color.withAlphaComponent(0.2), isMetallic: false)
            let outerEntity = ModelEntity(mesh: outerSphere, materials: [outerMaterial])
            containerEntity.addChild(outerEntity)

            return containerEntity
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    detectedPlanes[anchor.identifier] = planeAnchor
                    print("[AR] Detected plane: \(planeAnchor.classification.description)")
                }
            }
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    detectedPlanes[anchor.identifier] = planeAnchor
                }
            }
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            for anchor in anchors {
                detectedPlanes.removeValue(forKey: anchor.identifier)
            }
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            if frame.camera.trackingState == .normal && !isSessionReady {
                isSessionReady = true
                print("[AR] Tracking ready - planes detected: \(detectedPlanes.count)")
                DispatchQueue.main.async { [weak self] in
                    self?.processNewAnnotations()
                }
            }

            // ULTRA-LOW LATENCY: Capture video frame directly from ARSession callback
            // This gives us true 30 FPS synchronized with camera frames
            captureAndSendFrame(from: frame)

            // AR RECONSTRUCTION: Send depth map and plane data to iPad (Zoho Lens / Chalk style)
            let now = Date()

            // Send depth map periodically (if available)
            if now.timeIntervalSince(lastDepthMapTime) >= depthMapInterval {
                sendDepthMapIfAvailable(from: frame)
                lastDepthMapTime = now
            }

            // Send detected planes periodically
            if now.timeIntervalSince(lastPlaneUpdateTime) >= planeUpdateInterval {
                sendDetectedPlanes()
                lastPlaneUpdateTime = now
            }

            // Update screen positions for 2D overlay AND send 3D anchor data to iPad
            guard let manager = annotationManager, let arView = arView else { return }

            // LATENCY OPTIMIZATION: Throttle annotation updates to 10 FPS (was 30 FPS)
            let shouldSendUpdate = now.timeIntervalSince(lastAnnotationUpdateTime) >= minAnnotationUpdateInterval

            for (id, anchor) in annotationAnchors {
                let worldPos = anchor.position(relativeTo: nil)
                let worldOrientation = anchor.orientation(relativeTo: nil)

                // Update 2D screen position for local display
                if let screenPoint = arView.project(worldPos) {
                    let bounds = arView.bounds
                    let isOnScreen = screenPoint.x >= 0 && screenPoint.x <= bounds.width &&
                                    screenPoint.y >= 0 && screenPoint.y <= bounds.height

                    let normalized = AnnotationPoint.normalized(from: screenPoint, in: bounds.size)
                    manager.updateScreenPosition(for: id, point: normalized)
                    manager.setVisibility(for: id, visible: isOnScreen)
                } else {
                    manager.setVisibility(for: id, visible: false)
                }

                // Send 3D anchor data to iPad for AR reconstruction (throttled to 10 FPS)
                if shouldSendUpdate {
                    send3DAnchorData(annotationId: id, position: worldPos, orientation: worldOrientation)
                }
            }

            if shouldSendUpdate {
                lastAnnotationUpdateTime = now
            }
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            switch camera.trackingState {
            case .normal:
                isSessionReady = true
                print("[AR] Tracking: normal")
            case .limited(let reason):
                print("[AR] Tracking limited: \(reason)")
            case .notAvailable:
                print("[AR] Tracking not available")
            }
        }

        // MARK: - AR Reconstruction Methods (Zoho Lens / Chalk style)

        private func sendDepthMapIfAvailable(from frame: ARFrame) {
            // Extract scene depth if available (LiDAR or ARKit depth estimation)
            guard let sceneDepth = frame.sceneDepth else {
                // Depth not available on this device
                return
            }

            let depthMap = sceneDepth.depthMap
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)

            // Lock the pixel buffer to access depth data
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let bufferSize = bytesPerRow * height
            let depthData = Data(bytes: baseAddress, count: bufferSize)

            // Extract camera intrinsics and transform
            let intrinsics = frame.camera.intrinsics
            let intrinsicsArray: [Float] = [
                intrinsics[0, 0], intrinsics[0, 1], intrinsics[0, 2],
                intrinsics[1, 0], intrinsics[1, 1], intrinsics[1, 2],
                intrinsics[2, 0], intrinsics[2, 1], intrinsics[2, 2]
            ]

            let transform = frame.camera.transform
            let transformArray: [Float] = [
                transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w,
                transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w,
                transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w,
                transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w
            ]

            let depthMapData = DepthMapData(
                width: width,
                height: height,
                depthData: depthData,
                cameraIntrinsics: intrinsicsArray,
                cameraTransform: transformArray,
                timestamp: Date()
            )

            Task { @MainActor in
                MultipeerService.shared.sendDepthMap(depthMapData)
            }
        }

        private func sendDetectedPlanes() {
            guard !detectedPlanes.isEmpty else { return }

            let planes = detectedPlanes.values.map { planeAnchor -> DetectedPlaneData.Plane in
                let transform = planeAnchor.transform
                let transformArray: [Float] = [
                    transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w,
                    transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w,
                    transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w,
                    transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w
                ]

                return DetectedPlaneData.Plane(
                    identifier: planeAnchor.identifier.uuidString,
                    center: [planeAnchor.center.x, planeAnchor.center.y, planeAnchor.center.z],
                    extent: [planeAnchor.planeExtent.width, planeAnchor.planeExtent.height],
                    transform: transformArray,
                    classification: planeAnchor.classification.description,
                    alignment: planeAnchor.alignment == .horizontal ? "horizontal" : "vertical"
                )
            }

            let planesData = DetectedPlaneData(planes: planes, timestamp: Date())

            Task { @MainActor in
                MultipeerService.shared.sendDetectedPlanes(planesData)
            }
        }

        private func send3DAnchorData(annotationId: String, position: SIMD3<Float>, orientation: simd_quatf) {
            let anchorData = AnnotationAnchorData(
                annotationId: annotationId,
                worldPosition: [position.x, position.y, position.z],
                worldOrientation: [orientation.vector.x, orientation.vector.y, orientation.vector.z, orientation.vector.w],
                anchoredToPlaneId: nil,  // TODO: Track which plane annotation is anchored to
                timestamp: Date()
            )

            Task { @MainActor in
                MultipeerService.shared.sendAnnotationAnchorData(anchorData)
            }
        }

        func cleanup() {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            arView?.session.pause()
        }

        deinit {
            cleanup()
        }
    }
}

// MARK: - AR Annotation Manager

class ARAnnotationManager: ObservableObject {
    @Published var annotations: [ARTrackedAnnotation] = []

    func addAnnotation(_ annotation: Annotation) {
        let tracked = ARTrackedAnnotation(from: annotation)
        annotations.append(tracked)
        print("[AR Manager] Added annotation: \(annotation.id)")
    }

    func setWorldPosition(for id: String, position: SIMD3<Float>) {
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            annotations[index].worldPosition = position
        }
    }

    func updateScreenPosition(for id: String, point: AnnotationPoint) {
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            annotations[index].currentScreenPosition = point
        }
    }

    func setVisibility(for id: String, visible: Bool) {
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            annotations[index].isVisible = visible
        }
    }

    func clearAll() {
        annotations.removeAll()
    }
}

// MARK: - AR Tracked Annotation

struct ARTrackedAnnotation: Identifiable {
    let id: String
    let type: AnnotationType
    var points: [AnnotationPoint]
    let color: String
    let strokeWidth: CGFloat
    var text: String?
    var animationType: AnimationType?
    var worldPosition: SIMD3<Float>?
    var currentScreenPosition: AnnotationPoint?
    var isVisible: Bool = true

    init(from annotation: Annotation) {
        self.id = annotation.id
        self.type = annotation.type
        self.points = annotation.points
        self.color = annotation.color
        self.strokeWidth = annotation.strokeWidth
        self.text = annotation.text
        self.animationType = annotation.animationType
    }

    var swiftUIColor: Color {
        Color(hex: color) ?? .red
    }
}

// MARK: - AR Annotation Overlay View

struct ARAnnotationOverlayView: View {
    let annotations: [ARTrackedAnnotation]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(annotations) { annotation in
                    if annotation.isVisible, let screenPos = annotation.currentScreenPosition {
                        ARAnnotationMarker(
                            annotation: annotation,
                            position: screenPos.toAbsolute(in: geometry.size)
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - AR Annotation Marker

struct ARAnnotationMarker: View {
    let annotation: ARTrackedAnnotation
    let position: CGPoint
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(annotation.swiftUIColor.opacity(0.2))
                .frame(width: 70, height: 70)
                .blur(radius: 10)

            // Pulsing ring
            Circle()
                .stroke(annotation.swiftUIColor.opacity(0.8), lineWidth: 3)
                .frame(width: 50, height: 50)
                .scaleEffect(isAnimating ? 1.8 : 1.0)
                .opacity(isAnimating ? 0 : 0.7)

            // Middle ring with gradient
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [annotation.swiftUIColor, annotation.swiftUIColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 35, height: 35)
                .shadow(color: annotation.swiftUIColor.opacity(0.6), radius: 8, x: 0, y: 4)

            // Center dot with radial gradient for 3D depth
            Circle()
                .fill(
                    RadialGradient(
                        colors: [annotation.swiftUIColor.opacity(0.8), annotation.swiftUIColor],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 12
                    )
                )
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
        }
        .position(position)
        .shadow(color: annotation.swiftUIColor.opacity(0.7), radius: 15, x: 0, y: 7)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - ARPlaneAnchor Classification Extension

extension ARPlaneAnchor.Classification {
    var description: String {
        switch self {
        case .wall: return "wall"
        case .floor: return "floor"
        case .ceiling: return "ceiling"
        case .table: return "table"
        case .seat: return "seat"
        case .door: return "door"
        case .window: return "window"
        case .none: return "none"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - ARCamera TrackingState Extension

extension ARCamera.TrackingState {
    var description: String {
        switch self {
        case .normal:
            return "normal"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "limited_initializing"
            case .excessiveMotion:
                return "limited_excessive_motion"
            case .insufficientFeatures:
                return "limited_insufficient_features"
            case .relocalizing:
                return "limited_relocalizing"
            @unknown default:
                return "limited_unknown"
            }
        case .notAvailable:
            return "not_available"
        }
    }
}
