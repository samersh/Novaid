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

        // Enable high resolution frame capture for streaming
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        arView.session.delegate = context.coordinator
        arView.session.run(configuration)

        // Start frame streaming
        context.coordinator.startFrameStreaming()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Update annotations when they change
        context.coordinator.updateAnnotations()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, ARSessionDelegate {
        var arView: ARView?
        var annotationManager: ARAnnotationManager?
        private var frameTimer: Timer?
        private var annotationAnchors: [String: AnchorEntity] = [:]
        private let frameQueue = DispatchQueue(label: "com.novaid.arFrameQueue")

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
                  let manager = annotationManager else { return }

            // Process each annotation
            for annotation in manager.annotations {
                // Skip if already placed
                if annotationAnchors[annotation.id] != nil { continue }

                // If annotation has a world position, create anchor
                if let worldPosition = annotation.worldPosition {
                    placeAnnotation(annotation, at: worldPosition, in: arView)
                } else if let normalizedPosition = annotation.points.first {
                    // Try to find world position from screen coordinates
                    let screenPoint = normalizedPosition.toAbsolute(in: arView.bounds.size)
                    if let worldPos = hitTest(at: screenPoint, in: arView) {
                        // Update annotation with world position
                        manager.setWorldPosition(for: annotation.id, position: worldPos)
                        placeAnnotation(annotation, at: worldPos, in: arView)
                    }
                }
            }

            // Remove anchors for deleted annotations
            let currentIds = Set(manager.annotations.map { $0.id })
            for (id, anchor) in annotationAnchors {
                if !currentIds.contains(id) {
                    arView.scene.removeAnchor(anchor)
                    annotationAnchors.removeValue(forKey: id)
                }
            }
        }

        private func placeAnnotation(_ annotation: Annotation, at worldPosition: SIMD3<Float>, in arView: ARView) {
            let anchor = AnchorEntity(world: worldPosition)

            // Create visual representation based on annotation type
            let entity = createAnnotationEntity(for: annotation)
            anchor.addChild(entity)

            arView.scene.addAnchor(anchor)
            annotationAnchors[annotation.id] = anchor
        }

        private func createAnnotationEntity(for annotation: Annotation) -> Entity {
            let color = UIColor(Color(hex: annotation.color) ?? .red)

            switch annotation.type {
            case .pointer, .animation:
                // Create a sphere for pointer
                let mesh = MeshResource.generateSphere(radius: 0.02)
                let material = SimpleMaterial(color: color, isMetallic: false)
                return ModelEntity(mesh: mesh, materials: [material])

            case .circle:
                // Create a ring/torus for circle
                let mesh = MeshResource.generateSphere(radius: 0.03)
                let material = SimpleMaterial(color: color.withAlphaComponent(0.7), isMetallic: false)
                return ModelEntity(mesh: mesh, materials: [material])

            case .arrow:
                // Create a cone for arrow
                let mesh = MeshResource.generateCone(height: 0.05, radius: 0.015)
                let material = SimpleMaterial(color: color, isMetallic: false)
                let entity = ModelEntity(mesh: mesh, materials: [material])
                // Point the arrow forward
                entity.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
                return entity

            case .drawing, .text:
                // Create a small box for drawing points
                let mesh = MeshResource.generateBox(size: 0.01)
                let material = SimpleMaterial(color: color, isMetallic: false)
                return ModelEntity(mesh: mesh, materials: [material])
            }
        }

        private func hitTest(at point: CGPoint, in arView: ARView) -> SIMD3<Float>? {
            // Perform raycast to find world position
            guard let query = arView.makeRaycastQuery(from: point, allowing: .estimatedPlane, alignment: .any) else {
                return nil
            }

            let results = arView.session.raycast(query)
            if let firstResult = results.first {
                return SIMD3<Float>(
                    firstResult.worldTransform.columns.3.x,
                    firstResult.worldTransform.columns.3.y,
                    firstResult.worldTransform.columns.3.z
                )
            }

            // Fallback: place at fixed distance from camera
            guard let currentFrame = arView.session.currentFrame else { return nil }

            let cameraTransform = currentFrame.camera.transform
            let cameraPosition = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )

            // Get camera forward direction
            let cameraForward = SIMD3<Float>(
                -cameraTransform.columns.2.x,
                -cameraTransform.columns.2.y,
                -cameraTransform.columns.2.z
            )

            // Place 1 meter in front of camera
            return cameraPosition + cameraForward * 1.0
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Update 2D overlay positions for annotations based on current camera
            guard let manager = annotationManager else { return }

            for (id, anchor) in annotationAnchors {
                let worldPosition = anchor.position(relativeTo: nil)

                // Project 3D world position to 2D screen coordinates
                guard let arView = arView else { continue }
                let screenPoint = arView.project(worldPosition)

                if let point = screenPoint {
                    // Update the annotation's screen position for overlay rendering
                    let normalizedPoint = AnnotationPoint.normalized(
                        from: point,
                        in: arView.bounds.size
                    )
                    manager.updateScreenPosition(for: id, point: normalizedPoint)
                }
            }
        }

        deinit {
            frameTimer?.invalidate()
            arView?.session.pause()
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

    /// Clear all annotations
    func clearAll() {
        annotations.removeAll()
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
                    if let screenPos = annotation.currentScreenPosition {
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

/// Visual marker for AR annotation
struct ARAnnotationMarker: View {
    let annotation: ARTrackedAnnotation
    let position: CGPoint

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Pulsing ring
            Circle()
                .stroke(annotation.swiftUIColor, lineWidth: 2)
                .frame(width: 40, height: 40)
                .scaleEffect(isAnimating ? 1.5 : 1.0)
                .opacity(isAnimating ? 0 : 0.8)

            // Center dot
            Circle()
                .fill(annotation.swiftUIColor)
                .frame(width: 16, height: 16)

            // Icon based on type
            annotationIcon
                .foregroundColor(.white)
                .font(.system(size: 10, weight: .bold))
        }
        .position(position)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
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
