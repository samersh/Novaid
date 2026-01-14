import SwiftUI
import ARKit
import RealityKit

/// AR Camera view for the User side with proper landscape video streaming
struct ARCameraView: UIViewRepresentable {
    @ObservedObject var annotationManager: ARAnnotationManager

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        context.coordinator.annotationManager = annotationManager

        // Configure AR session for world tracking
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]

        arView.session.delegate = context.coordinator
        arView.session.run(configuration)

        // Keep screen awake during AR session
        UIApplication.shared.isIdleTimerDisabled = true

        // Start frame streaming
        context.coordinator.startFrameStreaming()

        print("[AR] ARKit session started")
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
        private let minFrameInterval: TimeInterval = 1.0 / 15.0 // 15 FPS

        func startFrameStreaming() {
            frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                self?.captureAndSendFrame()
            }
        }

        private func captureAndSendFrame() {
            // Rate limiting
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

            // Get the image dimensions
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            // Create CIImage and rotate for landscape right orientation
            var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            // The camera captures in portrait orientation by default
            // We need to rotate 90° clockwise for landscape right
            // This is done by applying a transform

            // Rotate 90° clockwise (for landscape right when device is in landscape)
            let rotateTransform = CGAffineTransform(rotationAngle: -.pi / 2)
            let translateTransform = CGAffineTransform(translationX: 0, y: CGFloat(width))
            ciImage = ciImage.transformed(by: rotateTransform.concatenating(translateTransform))

            // Now the image is in landscape orientation (height x width becomes width x height)
            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

            // Create UIImage (already rotated, so use .up orientation)
            let rotatedImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)

            // Resize for efficient transmission - landscape dimensions
            let targetSize = CGSize(width: 854, height: 480) // 16:9 landscape
            UIGraphicsBeginImageContextWithOptions(targetSize, true, 1.0)
            rotatedImage.draw(in: CGRect(origin: .zero, size: targetSize))
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

            // Place new annotations
            for annotation in manager.annotations {
                if annotationAnchors[annotation.id] != nil { continue }

                if let firstPoint = annotation.points.first {
                    placeAnnotationInWorld(annotation, normalizedPoint: firstPoint, in: arView)
                }
            }

            // Remove deleted annotations
            let currentIds = Set(manager.annotations.map { $0.id })
            for (id, anchor) in annotationAnchors where !currentIds.contains(id) {
                arView.scene.removeAnchor(anchor)
                annotationAnchors.removeValue(forKey: id)
            }
        }

        private func placeAnnotationInWorld(_ annotation: ARTrackedAnnotation, normalizedPoint: AnnotationPoint, in arView: ARView) {
            guard let currentFrame = arView.session.currentFrame else { return }

            // Get camera position and orientation
            let cameraTransform = currentFrame.camera.transform
            let cameraPosition = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )

            // Calculate direction based on normalized screen position
            // Map from (0,0)-(1,1) to (-1,1)-(1,-1) in camera space
            let normalizedX = Float(normalizedPoint.x) * 2.0 - 1.0  // -1 to 1 (left to right)
            let normalizedY = -(Float(normalizedPoint.y) * 2.0 - 1.0)  // 1 to -1 (top to bottom)

            // Create direction in camera local space
            // Spread based on approximate FOV
            let fovSpread: Float = 0.6
            let localDirection = simd_normalize(SIMD3<Float>(
                normalizedX * fovSpread,
                normalizedY * fovSpread,
                -1.0  // Forward in camera space
            ))

            // Transform to world space
            let rotationMatrix = simd_float3x3(
                SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z),
                SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z),
                SIMD3<Float>(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
            )
            let worldDirection = rotationMatrix * localDirection

            // Place at 0.4 meters distance
            let distance: Float = 0.4
            let worldPosition = cameraPosition + worldDirection * distance

            // Create anchor
            let anchor = AnchorEntity(world: worldPosition)
            let entity = createMarkerEntity(color: UIColor(Color(hex: annotation.color) ?? .red))
            anchor.addChild(entity)

            arView.scene.addAnchor(anchor)
            annotationAnchors[annotation.id] = anchor
            annotationManager?.setWorldPosition(for: annotation.id, position: worldPosition)

            print("[AR] Placed annotation at: \(worldPosition)")
        }

        private func createMarkerEntity(color: UIColor) -> Entity {
            let sphere = MeshResource.generateSphere(radius: 0.015)
            let material = SimpleMaterial(color: color, isMetallic: false)
            let entity = ModelEntity(mesh: sphere, materials: [material])

            // Add glow sphere
            let outerSphere = MeshResource.generateSphere(radius: 0.025)
            let outerMaterial = SimpleMaterial(color: color.withAlphaComponent(0.4), isMetallic: false)
            let outerEntity = ModelEntity(mesh: outerSphere, materials: [outerMaterial])
            entity.addChild(outerEntity)

            return entity
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            if frame.camera.trackingState == .normal && !isSessionReady {
                isSessionReady = true
                print("[AR] Tracking ready")
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
            // Pulsing outer ring
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
