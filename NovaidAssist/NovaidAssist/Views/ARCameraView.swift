import SwiftUI
import ARKit
import RealityKit

/// AR Camera view for the User side that enables world tracking for annotations
struct ARCameraView: UIViewRepresentable {
    @ObservedObject var annotationManager: ARAnnotationManager

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        context.coordinator.annotationManager = annotationManager

        // Configure AR session for world tracking
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic

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
        // Update annotations when they change
        context.coordinator.updateAnnotations()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        // Re-enable idle timer when AR view is removed
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

        func startFrameStreaming() {
            // Stream frames at ~15 FPS
            frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
                self?.captureAndSendFrame()
            }
        }

        private func captureAndSendFrame() {
            guard let arView = arView,
                  let currentFrame = arView.session.currentFrame else { return }

            frameQueue.async {
                // Convert AR frame to UIImage
                let ciImage = CIImage(cvPixelBuffer: currentFrame.capturedImage)
                let context = CIContext()
                guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

                // Rotate and resize for landscape transmission
                let originalImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

                // Resize for efficient transmission (landscape: 640x480)
                let targetSize = CGSize(width: 640, height: 480)
                UIGraphicsBeginImageContextWithOptions(targetSize, true, 1.0)
                originalImage.draw(in: CGRect(origin: .zero, size: targetSize))
                let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()

                if let image = resizedImage {
                    Task { @MainActor in
                        MultipeerService.shared.sendVideoFrame(image)
                    }
                }
            }
        }

        func updateAnnotations() {
            guard let arView = arView,
                  let manager = annotationManager,
                  isSessionReady else { return }

            // Process each annotation that needs to be placed
            for annotation in manager.annotations {
                // Skip if already placed in AR
                if annotationAnchors[annotation.id] != nil { continue }

                // Place annotation in world space
                if let firstPoint = annotation.points.first {
                    placeAnnotationInWorld(annotation, normalizedPoint: firstPoint, in: arView)
                }
            }

            // Remove anchors for deleted annotations
            let currentIds = Set(manager.annotations.map { $0.id })
            for (id, anchor) in annotationAnchors {
                if !currentIds.contains(id) {
                    arView.scene.removeAnchor(anchor)
                    annotationAnchors.removeValue(forKey: id)
                    print("[AR] Removed annotation anchor: \(id)")
                }
            }
        }

        private func placeAnnotationInWorld(_ annotation: ARTrackedAnnotation, normalizedPoint: AnnotationPoint, in arView: ARView) {
            guard let currentFrame = arView.session.currentFrame else {
                print("[AR] No current frame available")
                return
            }

            // Get camera transform
            let cameraTransform = currentFrame.camera.transform

            // Convert normalized 2D position to a direction in camera space
            // Normalized coordinates: (0,0) = top-left, (1,1) = bottom-right
            // We need to map this to camera ray direction

            // Get the intrinsics to properly calculate ray direction
            let intrinsics = currentFrame.camera.intrinsics
            let imageResolution = currentFrame.camera.imageResolution

            // Convert normalized to pixel coordinates
            let pixelX = normalizedPoint.x * CGFloat(imageResolution.width)
            let pixelY = normalizedPoint.y * CGFloat(imageResolution.height)

            // Calculate ray direction in camera space using intrinsics
            let fx = intrinsics[0, 0]
            let fy = intrinsics[1, 1]
            let cx = intrinsics[2, 0]
            let cy = intrinsics[2, 1]

            // Direction in camera space (camera looks down -Z)
            let dirX = (Float(pixelX) - cx) / fx
            let dirY = (Float(pixelY) - cy) / fy
            let directionInCamera = simd_normalize(SIMD3<Float>(dirX, -dirY, -1.0))

            // Transform direction to world space
            let rotationMatrix = simd_float3x3(
                SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z),
                SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z),
                SIMD3<Float>(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
            )
            let directionInWorld = rotationMatrix * directionInCamera

            // Camera position in world space
            let cameraPosition = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )

            // Place annotation at fixed distance (0.5 meters) from camera along ray
            let distance: Float = 0.5
            let worldPosition = cameraPosition + directionInWorld * distance

            // Create anchor at world position
            let anchor = AnchorEntity(world: worldPosition)

            // Create visual marker
            let entity = createAnnotationEntity(for: annotation)
            anchor.addChild(entity)

            arView.scene.addAnchor(anchor)
            annotationAnchors[annotation.id] = anchor

            // Store world position in annotation
            annotationManager?.setWorldPosition(for: annotation.id, position: worldPosition)

            print("[AR] Placed annotation at world position: \(worldPosition)")
        }

        private func createAnnotationEntity(for annotation: ARTrackedAnnotation) -> Entity {
            let color = UIColor(Color(hex: annotation.color) ?? .red)

            // Create a visible 3D marker - sphere with glow effect
            let sphere = MeshResource.generateSphere(radius: 0.025)
            let material = SimpleMaterial(color: color, isMetallic: false)
            let entity = ModelEntity(mesh: sphere, materials: [material])

            // Add a larger transparent sphere for visibility
            let outerSphere = MeshResource.generateSphere(radius: 0.04)
            let outerMaterial = SimpleMaterial(color: color.withAlphaComponent(0.3), isMetallic: false)
            let outerEntity = ModelEntity(mesh: outerSphere, materials: [outerMaterial])
            entity.addChild(outerEntity)

            return entity
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Mark session as ready once we have tracking
            if frame.camera.trackingState == .normal && !isSessionReady {
                isSessionReady = true
                print("[AR] Session tracking is ready")

                // Process any pending annotations
                DispatchQueue.main.async { [weak self] in
                    self?.updateAnnotations()
                }
            }

            // Update 2D overlay positions for annotations based on current camera
            guard let manager = annotationManager, let arView = arView else { return }

            for (id, anchor) in annotationAnchors {
                let worldPosition = anchor.position(relativeTo: nil)

                // Project 3D world position to 2D screen coordinates
                if let screenPoint = arView.project(worldPosition) {
                    // Check if point is in front of camera and on screen
                    if screenPoint.x >= 0 && screenPoint.x <= arView.bounds.width &&
                       screenPoint.y >= 0 && screenPoint.y <= arView.bounds.height {
                        let normalizedPoint = AnnotationPoint.normalized(
                            from: screenPoint,
                            in: arView.bounds.size
                        )
                        manager.updateScreenPosition(for: id, point: normalizedPoint)
                        manager.setVisibility(for: id, visible: true)
                    } else {
                        // Annotation is off-screen
                        manager.setVisibility(for: id, visible: false)
                    }
                } else {
                    // Behind camera
                    manager.setVisibility(for: id, visible: false)
                }
            }
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            switch camera.trackingState {
            case .notAvailable:
                print("[AR] Tracking not available")
            case .limited(let reason):
                print("[AR] Tracking limited: \(reason)")
            case .normal:
                print("[AR] Tracking normal")
                isSessionReady = true
            }
        }

        func cleanup() {
            frameTimer?.invalidate()
            frameTimer = nil
            arView?.session.pause()
            print("[AR] Session cleaned up")
        }

        deinit {
            cleanup()
        }
    }
}

/// Manager for AR annotations with world tracking
class ARAnnotationManager: ObservableObject {
    @Published var annotations: [ARTrackedAnnotation] = []

    /// Add a new annotation
    func addAnnotation(_ annotation: Annotation) {
        let tracked = ARTrackedAnnotation(from: annotation)
        annotations.append(tracked)
        print("[AR Manager] Added annotation: \(annotation.id)")
    }

    /// Set world position for an annotation
    func setWorldPosition(for id: String, position: SIMD3<Float>) {
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            annotations[index].worldPosition = position
        }
    }

    /// Update screen position (for 2D overlay)
    func updateScreenPosition(for id: String, point: AnnotationPoint) {
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            annotations[index].currentScreenPosition = point
        }
    }

    /// Set visibility for annotation
    func setVisibility(for id: String, visible: Bool) {
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            annotations[index].isVisible = visible
        }
    }

    /// Clear all annotations
    func clearAll() {
        annotations.removeAll()
        print("[AR Manager] Cleared all annotations")
    }
}

/// Annotation with AR world tracking data
struct ARTrackedAnnotation: Identifiable {
    let id: String
    let type: AnnotationType
    var points: [AnnotationPoint]
    let color: String
    let strokeWidth: CGFloat
    var text: String?
    var animationType: AnimationType?

    // AR tracking data
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

/// Overlay for AR-tracked annotations (uses projected screen positions)
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

/// Visual marker for AR annotation (2D overlay that follows 3D position)
struct ARAnnotationMarker: View {
    let annotation: ARTrackedAnnotation
    let position: CGPoint

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Outer pulsing ring
            Circle()
                .stroke(annotation.swiftUIColor, lineWidth: 3)
                .frame(width: 50, height: 50)
                .scaleEffect(isAnimating ? 1.8 : 1.0)
                .opacity(isAnimating ? 0 : 0.8)

            // Middle ring
            Circle()
                .stroke(annotation.swiftUIColor, lineWidth: 2)
                .frame(width: 35, height: 35)

            // Center filled dot
            Circle()
                .fill(annotation.swiftUIColor)
                .frame(width: 20, height: 20)

            // Icon based on type
            annotationIcon
                .foregroundColor(.white)
                .font(.system(size: 10, weight: .bold))
        }
        .position(position)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }

    @ViewBuilder
    private var annotationIcon: some View {
        switch annotation.type {
        case .pointer:
            Image(systemName: "hand.point.up.fill")
        case .arrow:
            Image(systemName: "arrow.right")
        case .circle:
            Image(systemName: "circle")
        case .drawing:
            Image(systemName: "pencil")
        case .text:
            Image(systemName: "text.cursor")
        case .animation:
            Image(systemName: "sparkles")
        }
    }
}
