import SwiftUI
import ARKit
import RealityKit

/// AR Camera view for the User side with proper landscape video streaming and world tracking
struct ARCameraView: UIViewRepresentable {
    @ObservedObject var annotationManager: ARAnnotationManager

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
        private let minFrameInterval: TimeInterval = 1.0 / 15.0
        private var detectedPlanes: [UUID: ARPlaneAnchor] = [:]

        func startFrameStreaming() {
            frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                self?.captureAndSendFrame()
            }
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

            // Create CIImage from pixel buffer
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            // Get device orientation to determine correct rotation
            // ARKit camera always captures in native sensor orientation
            // For landscape right: rotate 90° counter-clockwise
            let rotatedImage = ciImage.oriented(.right)

            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let cgImage = context.createCGImage(rotatedImage, from: rotatedImage.extent) else { return }

            // Create UIImage
            let uiImage = UIImage(cgImage: cgImage)

            // Resize to landscape dimensions (16:9)
            let targetSize = CGSize(width: 854, height: 480)
            UIGraphicsBeginImageContextWithOptions(targetSize, true, 1.0)
            uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            if let image = resizedImage {
                Task { @MainActor in
                    MultipeerService.shared.sendVideoFrame(image)
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
        }

        private func createMarkerEntity(color: UIColor) -> Entity {
            // Create a visible 3D marker
            let sphere = MeshResource.generateSphere(radius: 0.02)
            let material = SimpleMaterial(color: color, isMetallic: false)
            let entity = ModelEntity(mesh: sphere, materials: [material])

            // Add outer glow
            let outerSphere = MeshResource.generateSphere(radius: 0.035)
            let outerMaterial = SimpleMaterial(color: color.withAlphaComponent(0.3), isMetallic: false)
            let outerEntity = ModelEntity(mesh: outerSphere, materials: [outerMaterial])
            entity.addChild(outerEntity)

            return entity
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
                    if annotation.isVisible {
                        ARAnnotationShapeView(
                            annotation: annotation,
                            containerSize: geometry.size
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - AR Annotation Shape View (renders full annotation shapes)

struct ARAnnotationShapeView: View {
    let annotation: ARTrackedAnnotation
    let containerSize: CGSize

    var body: some View {
        // Use current tracked screen position if available, otherwise use original points
        let baseOffset = calculateBaseOffset()

        switch annotation.type {
        case .drawing:
            ARDrawingPath(annotation: annotation, containerSize: containerSize, offset: baseOffset)
                .stroke(
                    annotation.swiftUIColor,
                    style: StrokeStyle(
                        lineWidth: annotation.strokeWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

        case .arrow:
            if annotation.points.count >= 2 {
                let start = annotation.points[0].toAbsolute(in: containerSize).offset(by: baseOffset)
                let end = annotation.points[1].toAbsolute(in: containerSize).offset(by: baseOffset)
                ARArrowShape(start: start, end: end)
                    .stroke(annotation.swiftUIColor, lineWidth: annotation.strokeWidth)
            }

        case .circle:
            if annotation.points.count >= 2 {
                let center = annotation.points[0].toAbsolute(in: containerSize).offset(by: baseOffset)
                let radiusNormalized = annotation.points[1].x
                let radius = radiusNormalized * containerSize.width

                Circle()
                    .stroke(annotation.swiftUIColor, lineWidth: annotation.strokeWidth)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
            }

        case .pointer, .animation:
            if let screenPos = annotation.currentScreenPosition {
                let position = screenPos.toAbsolute(in: containerSize)
                ARAnnotationMarker(
                    annotation: annotation,
                    position: position
                )
            } else if let point = annotation.points.first {
                let position = point.toAbsolute(in: containerSize).offset(by: baseOffset)
                ARAnnotationMarker(
                    annotation: annotation,
                    position: position
                )
            }

        case .text:
            if let point = annotation.points.first,
               let text = annotation.text {
                let position = point.toAbsolute(in: containerSize).offset(by: baseOffset)
                Text(text)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(annotation.swiftUIColor)
                    .position(position)
            }
        }
    }

    private func calculateBaseOffset() -> CGPoint {
        // Calculate offset from original first point to current tracked position
        guard let currentPos = annotation.currentScreenPosition,
              let originalFirst = annotation.points.first else {
            return .zero
        }

        let currentAbsolute = currentPos.toAbsolute(in: containerSize)
        let originalAbsolute = originalFirst.toAbsolute(in: containerSize)

        return CGPoint(
            x: currentAbsolute.x - originalAbsolute.x,
            y: currentAbsolute.y - originalAbsolute.y
        )
    }
}

// MARK: - AR Drawing Path

struct ARDrawingPath: Shape {
    let annotation: ARTrackedAnnotation
    let containerSize: CGSize
    let offset: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard let first = annotation.points.first else { return path }

        let firstAbsolute = first.toAbsolute(in: containerSize).offset(by: offset)
        path.move(to: firstAbsolute)

        for point in annotation.points.dropFirst() {
            let absolutePoint = point.toAbsolute(in: containerSize).offset(by: offset)
            path.addLine(to: absolutePoint)
        }

        return path
    }
}

// MARK: - AR Arrow Shape

struct ARArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let headLength: CGFloat = 20
    let headAngle: CGFloat = .pi / 6

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)

        let arrowPoint1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )

        let arrowPoint2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        path.move(to: end)
        path.addLine(to: arrowPoint1)
        path.move(to: end)
        path.addLine(to: arrowPoint2)

        return path
    }
}

// MARK: - CGPoint Extension for Offset

extension CGPoint {
    func offset(by point: CGPoint) -> CGPoint {
        return CGPoint(x: self.x + point.x, y: self.y + point.y)
    }
}

// MARK: - AR Annotation Marker

struct ARAnnotationMarker: View {
    let annotation: ARTrackedAnnotation
    let position: CGPoint
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Pulsing ring
            Circle()
                .stroke(annotation.swiftUIColor, lineWidth: 3)
                .frame(width: 50, height: 50)
                .scaleEffect(isAnimating ? 1.8 : 1.0)
                .opacity(isAnimating ? 0 : 0.7)

            // Middle ring
            Circle()
                .stroke(annotation.swiftUIColor, lineWidth: 2)
                .frame(width: 30, height: 30)

            // Center dot
            Circle()
                .fill(annotation.swiftUIColor)
                .frame(width: 16, height: 16)
        }
        .position(position)
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
