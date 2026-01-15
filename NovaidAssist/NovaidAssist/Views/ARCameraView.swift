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
        private var frameTimer: Timer?
        private var annotationAnchors: [String: AnchorEntity] = [:]
        private let frameQueue = DispatchQueue(label: "com.novaid.arFrameQueue")
        private var isSessionReady = false
        private var lastFrameTime: Date = Date()
        private let minFrameInterval: TimeInterval = 1.0 / 30.0  // 30 FPS for smoother video
        private var detectedPlanes: [UUID: ARPlaneAnchor] = [:]
        private var currentOrientation = DeviceOrientation()
        var isVideoFrozen = false
        private var lastCapturedFrame: UIImage?

        func startFrameStreaming() {
            frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.captureAndSendFrame()
            }

            // Enable device orientation notifications
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            print("[AR] Device orientation tracking started")
        }

        func freezeVideo() {
            frameTimer?.invalidate()
            frameTimer = nil

            // Capture and send the current frozen frame
            if let lastFrame = lastCapturedFrame {
                Task { @MainActor in
                    MultipeerService.shared.sendFrozenFrame(lastFrame)
                    print("[AR] Sent frozen frame to iPad")
                }
            }
            print("[AR] Video frozen - stopped frame capture")
        }

        func resumeVideo() {
            // Restart frame streaming
            startFrameStreaming()
            print("[AR] Video resumed - restarted frame capture")
        }

        private func captureAndSendFrame() {
            let now = Date()
            guard now.timeIntervalSince(lastFrameTime) >= minFrameInterval else { return }

            guard let arView = arView,
                  let currentFrame = arView.session.currentFrame else { return }

            lastFrameTime = now

            frameQueue.async { [weak self] in
                self?.processAndSendFrame(currentFrame)
            }
        }

        private func processAndSendFrame(_ frame: ARFrame) {
            let pixelBuffer = frame.capturedImage

            // Capture current device orientation state
            let deviceOrientation = UIDevice.current.orientation
            let orientationState: DeviceOrientation.OrientationState

            switch deviceOrientation {
            case .portrait:
                orientationState = .portrait
            case .portraitUpsideDown:
                orientationState = .portraitUpsideDown
            case .landscapeLeft:
                orientationState = .landscapeLeft
            case .landscapeRight:
                orientationState = .landscapeRight
            default:
                // If orientation is unknown/faceUp/faceDown, keep the last known orientation
                orientationState = currentOrientation.state
            }

            currentOrientation = DeviceOrientation(state: orientationState)

            // Create CIImage from pixel buffer
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            // Create CGImage
            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

            // Determine UIImage orientation based on device orientation
            // This embeds rotation info in the image metadata (EXIF orientation)
            let imageOrientation: UIImage.Orientation
            switch orientationState {
            case .portrait:
                imageOrientation = .right  // ARKit captures landscape, rotate for portrait display
            case .portraitUpsideDown:
                imageOrientation = .left
            case .landscapeLeft:
                imageOrientation = .up
            case .landscapeRight:
                imageOrientation = .down
            case .unknown:
                imageOrientation = .right  // Default
            }

            // Create UIImage with embedded orientation metadata
            // This is the key: orientation is in the image, not applied as transform
            let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation)

            // Lower resolution optimized for minimal latency
            // 540x960 provides good quality with fast transmission
            let targetSize = CGSize(width: 540, height: 960)
            UIGraphicsBeginImageContextWithOptions(targetSize, true, 1.0)
            uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            if let image = resizedImage {
                // Store last frame for freeze functionality
                lastCapturedFrame = image

                Task { @MainActor in
                    MultipeerService.shared.sendVideoFrame(image, orientation: self.currentOrientation)
                }
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

            // Update screen positions for 2D overlay
            guard let manager = annotationManager, let arView = arView else { return }

            for (id, anchor) in annotationAnchors {
                let worldPos = anchor.position(relativeTo: nil)
                if let screenPoint = arView.project(worldPos) {
                    let bounds = arView.bounds
                    let isOnScreen = screenPoint.x >= 0 && screenPoint.x <= bounds.width &&
                                    screenPoint.y >= 0 && screenPoint.y <= bounds.height

                    let normalized = AnnotationPoint.normalized(from: screenPoint, in: bounds.size)
                    manager.updateScreenPosition(for: id, point: normalized)
                    manager.setVisibility(for: id, visible: isOnScreen)

                    // Send position update to iPad for AR tracking
                    Task { @MainActor in
                        MultipeerService.shared.sendAnnotationPositionUpdate(
                            id: id,
                            normalizedX: normalized.x,
                            normalizedY: normalized.y
                        )
                    }
                } else {
                    manager.setVisibility(for: id, visible: false)
                }
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

        func cleanup() {
            frameTimer?.invalidate()
            frameTimer = nil
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
