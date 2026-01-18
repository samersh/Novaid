import SwiftUI
import RealityKit
import ARKit

/// 3D annotation view for iPad that displays AR annotations with depth and perspective
/// Uses RealityKit to render 3D shapes overlaid on the 2D video stream
struct AR3DAnnotationView: UIViewRepresentable {
    let annotations: [Annotation]
    let containerSize: CGSize

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView

        // Configure for overlay mode (no camera, just 3D overlay)
        arView.environment.background = .color(.clear)
        arView.backgroundColor = .clear

        // Create camera anchor for perspective rendering
        context.coordinator.setupCameraAnchor()

        print("[AR3D] ✅ AR 3D annotation view initialized")
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.updateAnnotations(annotations, containerSize: containerSize)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var arView: ARView?
        private var annotationEntities: [String: AnchorEntity] = [:]
        private var cameraAnchor: AnchorEntity?

        func setupCameraAnchor() {
            guard let arView = arView else { return }

            // Create a camera anchor at fixed distance for overlay
            let anchor = AnchorEntity()
            anchor.position = [0, 0, -1.5]  // 1.5 meters in front
            arView.scene.addAnchor(anchor)
            cameraAnchor = anchor
        }

        func updateAnnotations(_ annotations: [Annotation], containerSize: CGSize) {
            guard let arView = arView, let cameraAnchor = cameraAnchor else { return }

            // Track which annotations we've seen
            var activeIds = Set<String>()

            // Update or create entities for each annotation
            for annotation in annotations {
                activeIds.insert(annotation.id)

                if let existingEntity = annotationEntities[annotation.id] {
                    // Update existing annotation position
                    updateAnnotationPosition(existingEntity, annotation: annotation, containerSize: containerSize)
                } else {
                    // Create new 3D annotation
                    let entity = create3DAnnotation(for: annotation, containerSize: containerSize)
                    cameraAnchor.addChild(entity)
                    annotationEntities[annotation.id] = entity
                }
            }

            // Remove annotations that no longer exist
            for (id, entity) in annotationEntities where !activeIds.contains(id) {
                entity.removeFromParent()
                annotationEntities.removeValue(forKey: id)
            }
        }

        private func create3DAnnotation(for annotation: Annotation, containerSize: CGSize) -> AnchorEntity {
            let anchor = AnchorEntity()

            // Convert normalized coordinates to 3D position
            if let firstPoint = annotation.points.first {
                let position = normalizedToView3DPosition(firstPoint, containerSize: containerSize)
                anchor.position = position
            }

            // Create 3D entity based on annotation type
            let entity: Entity

            switch annotation.type {
            case .pointer, .animation:
                entity = create3DPointer(color: UIColor(Color(hex: annotation.color) ?? .red))

            case .circle:
                if annotation.points.count >= 2 {
                    let radiusNormalized = annotation.points[1].x
                    let radius = Float(radiusNormalized * containerSize.width * 0.001)  // Scale down for 3D
                    entity = create3DCircle(radius: radius, color: UIColor(Color(hex: annotation.color) ?? .red))
                } else {
                    entity = create3DPointer(color: UIColor(Color(hex: annotation.color) ?? .red))
                }

            case .arrow:
                if annotation.points.count >= 2 {
                    entity = create3DArrow(
                        from: annotation.points[0],
                        to: annotation.points[1],
                        containerSize: containerSize,
                        color: UIColor(Color(hex: annotation.color) ?? .red)
                    )
                } else {
                    entity = create3DPointer(color: UIColor(Color(hex: annotation.color) ?? .red))
                }

            case .drawing:
                // For drawings, create a series of small spheres along the path
                entity = create3DPath(points: annotation.points, containerSize: containerSize, color: UIColor(Color(hex: annotation.color) ?? .red))

            case .text:
                if let text = annotation.text {
                    entity = create3DText(text: text, color: UIColor(Color(hex: annotation.color) ?? .red))
                } else {
                    entity = create3DPointer(color: UIColor(Color(hex: annotation.color) ?? .red))
                }
            }

            anchor.addChild(entity)
            return anchor
        }

        // MARK: - 3D Shape Creators

        private func create3DPointer(color: UIColor) -> ModelEntity {
            // Multi-layered sphere for 3D depth effect
            let container = Entity()

            // Core sphere - bright metallic
            let coreMesh = MeshResource.generateSphere(radius: 0.015)
            var coreMaterial = SimpleMaterial(color: color, isMetallic: true)
            coreMaterial.roughness = 0.2
            let coreEntity = ModelEntity(mesh: coreMesh, materials: [coreMaterial])
            container.addChild(coreEntity)

            // Middle layer - translucent glow
            let middleMesh = MeshResource.generateSphere(radius: 0.025)
            let middleMaterial = SimpleMaterial(color: color.withAlphaComponent(0.6), isMetallic: false)
            let middleEntity = ModelEntity(mesh: middleMesh, materials: [middleMaterial])
            container.addChild(middleEntity)

            // Outer glow - large soft halo
            let outerMesh = MeshResource.generateSphere(radius: 0.04)
            let outerMaterial = SimpleMaterial(color: color.withAlphaComponent(0.3), isMetallic: false)
            let outerEntity = ModelEntity(mesh: outerMesh, materials: [outerMaterial])
            container.addChild(outerEntity)

            // Add pulse animation
            let animation = AnimationResource.makePulse(duration: 1.0, scale: SIMD3<Float>(1.2, 1.2, 1.2))
            coreEntity.playAnimation(animation.repeat())

            return ModelEntity(mesh: coreMesh, materials: [])  // Return container as ModelEntity
        }

        private func create3DCircle(radius: Float, color: UIColor) -> ModelEntity {
            // Create a torus (ring) for the circle
            let mesh = MeshResource.generateBox(size: [radius * 2, radius * 2, 0.01], cornerRadius: radius)
            var material = SimpleMaterial(color: color.withAlphaComponent(0.8), isMetallic: true)
            material.roughness = 0.3

            let entity = ModelEntity(mesh: mesh, materials: [material])
            return entity
        }

        private func create3DArrow(from start: AnnotationPoint, to end: AnnotationPoint, containerSize: CGSize, color: UIColor) -> ModelEntity {
            let container = Entity()

            // Calculate arrow shaft
            let startPos = normalizedToView3DPosition(start, containerSize: containerSize)
            let endPos = normalizedToView3DPosition(end, containerSize: containerSize)

            let direction = endPos - startPos
            let length = simd_length(direction)

            // Shaft
            let shaftMesh = MeshResource.generateBox(size: [0.01, length, 0.01])
            var shaftMaterial = SimpleMaterial(color: color, isMetallic: true)
            shaftMaterial.roughness = 0.2
            let shaft = ModelEntity(mesh: shaftMesh, materials: [shaftMaterial])

            // Position and rotate shaft
            shaft.position = (startPos + endPos) / 2
            container.addChild(shaft)

            // Arrowhead (cone)
            let headMesh = MeshResource.generateCone(height: 0.05, radius: 0.02)
            let head = ModelEntity(mesh: headMesh, materials: [shaftMaterial])
            head.position = endPos
            container.addChild(head)

            return ModelEntity(mesh: shaftMesh, materials: [])
        }

        private func create3DPath(points: [AnnotationPoint], containerSize: CGSize, color: UIColor) -> ModelEntity {
            let container = Entity()

            // Create small spheres along the path
            for point in points {
                let position = normalizedToView3DPosition(point, containerSize: containerSize)

                let sphereMesh = MeshResource.generateSphere(radius: 0.01)
                var material = SimpleMaterial(color: color, isMetallic: true)
                material.roughness = 0.3

                let sphere = ModelEntity(mesh: sphereMesh, materials: [material])
                sphere.position = position
                container.addChild(sphere)
            }

            return ModelEntity(mesh: MeshResource.generateSphere(radius: 0.01), materials: [])
        }

        private func create3DText(text: String, color: UIColor) -> ModelEntity {
            // Create a text mesh (simplified - would use MeshResource.generateText in production)
            let mesh = MeshResource.generateBox(size: [0.1, 0.05, 0.01])
            var material = SimpleMaterial(color: color, isMetallic: false)
            material.roughness = 0.5

            let entity = ModelEntity(mesh: mesh, materials: [material])
            return entity
        }

        // MARK: - Position Conversion

        private func normalizedToView3DPosition(_ point: AnnotationPoint, containerSize: CGSize) -> SIMD3<Float> {
            // Convert normalized 2D coordinates to 3D position in view space
            // Map 0-1 normalized coords to -1 to +1 view space
            let x = Float((point.x * 2.0) - 1.0) * 0.8  // Scale down slightly to fit in view
            let y = -Float((point.y * 2.0) - 1.0) * 0.6  // Flip Y, scale for aspect ratio
            let z: Float = 0.0  // Keep on same plane

            return SIMD3<Float>(x, y, z)
        }

        private func updateAnnotationPosition(_ entity: AnchorEntity, annotation: Annotation, containerSize: CGSize) {
            // Update position based on first point
            if let firstPoint = annotation.points.first {
                let position = normalizedToView3DPosition(firstPoint, containerSize: containerSize)
                entity.position = position
            }
        }
    }
}

// MARK: - Animation Extensions

extension AnimationResource {
    static func makePulse(duration: TimeInterval, scale: SIMD3<Float>) -> AnimationResource {
        // Create a simple transform animation (pulse effect)
        // In production, would use proper AnimationResource API
        return AnimationResource.makeTransform(
            fromTransform: Transform(scale: SIMD3<Float>(1, 1, 1), rotation: simd_quatf(), translation: SIMD3<Float>(0, 0, 0)),
            toTransform: Transform(scale: scale, rotation: simd_quatf(), translation: SIMD3<Float>(0, 0, 0)),
            duration: duration,
            timingFunction: .linear
        )
    }
}
