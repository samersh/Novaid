import Foundation
import RealityKit
import ARKit
import Combine

/// iPad-side AR scene reconstruction from iPhone depth/plane data
/// Reconstructs the 3D scene on iPad using data transmitted from iPhone
/// Based on Vuforia Chalk and Zoho Lens remote AR assistance architecture
@MainActor
class iPadARReconstruction: ObservableObject {

    // MARK: - Scene State
    @Published var reconstructedPlanes: [String: DetectedPlaneData.Plane] = [:]
    @Published var annotationAnchors: [String: AnchorEntity] = [:]

    // Latest depth map data
    private var latestDepthMap: DepthMapData?
    private var latestCameraTransform: simd_float4x4?

    // RealityKit anchor for the AR scene
    private var sceneAnchor: AnchorEntity?

    // Statistics
    private var depthMapsReceived: Int = 0
    private var planesReceived: Int = 0
    private var anchorsUpdated: Int = 0
    private var lastStatsLog: Date = Date()

    init() {
        print("[iPadAR] 🎬 iPad AR reconstruction initialized")
    }

    // MARK: - Depth Map Processing

    /// Process received depth map from iPhone
    func processDepthMap(_ depthMap: DepthMapData) {
        latestDepthMap = depthMap
        depthMapsReceived += 1

        // Extract camera transform (4x4 matrix)
        if depthMap.cameraTransform.count == 16 {
            latestCameraTransform = simd_float4x4(
                SIMD4<Float>(depthMap.cameraTransform[0], depthMap.cameraTransform[1], depthMap.cameraTransform[2], depthMap.cameraTransform[3]),
                SIMD4<Float>(depthMap.cameraTransform[4], depthMap.cameraTransform[5], depthMap.cameraTransform[6], depthMap.cameraTransform[7]),
                SIMD4<Float>(depthMap.cameraTransform[8], depthMap.cameraTransform[9], depthMap.cameraTransform[10], depthMap.cameraTransform[11]),
                SIMD4<Float>(depthMap.cameraTransform[12], depthMap.cameraTransform[13], depthMap.cameraTransform[14], depthMap.cameraTransform[15])
            )
        }

        logStatsIfNeeded()

        // Depth map can be used for occlusion or more advanced reconstruction
        // For now, we rely primarily on plane data for annotation anchoring
        print("[iPadAR] 🗺️ Processed depth map: \(depthMap.width)x\(depthMap.height)")
    }

    // MARK: - Plane Processing

    /// Process received planes from iPhone
    func processDetectedPlanes(_ planesData: DetectedPlaneData) {
        planesReceived += 1

        // Update our plane database
        for plane in planesData.planes {
            reconstructedPlanes[plane.identifier] = plane
            print("[iPadAR] 🏗️ Plane '\(plane.identifier)': \(plane.classification) (\(plane.alignment))")
        }

        // Remove planes that are no longer detected
        let receivedIds = Set(planesData.planes.map { $0.identifier })
        let currentIds = Set(reconstructedPlanes.keys)
        let removedIds = currentIds.subtracting(receivedIds)

        for id in removedIds {
            reconstructedPlanes.removeValue(forKey: id)
            print("[iPadAR] 🗑️ Removed plane: \(id)")
        }

        logStatsIfNeeded()
    }

    // MARK: - Annotation Anchor Processing

    /// Process received 3D anchor data for annotation
    func processAnnotationAnchor(_ anchorData: AnnotationAnchorData, in arView: ARView) {
        anchorsUpdated += 1

        // Extract position and orientation
        let position = SIMD3<Float>(
            anchorData.worldPosition[0],
            anchorData.worldPosition[1],
            anchorData.worldPosition[2]
        )

        let orientation = simd_quatf(
            ix: anchorData.worldOrientation[0],
            iy: anchorData.worldOrientation[1],
            iz: anchorData.worldOrientation[2],
            r: anchorData.worldOrientation[3]
        )

        // Check if annotation is anchored to a specific plane
        var finalPosition = position
        var finalOrientation = orientation

        if let planeId = anchorData.anchoredToPlaneId,
           let plane = reconstructedPlanes[planeId] {
            // Annotation is anchored to a plane - use plane's transform
            print("[iPadAR] 📍 Annotation \(anchorData.annotationId) anchored to plane: \(plane.classification)")

            // Apply plane transform to annotation position (make it stick!)
            if plane.transform.count == 16 {
                let planeTransform = simd_float4x4(
                    SIMD4<Float>(plane.transform[0], plane.transform[1], plane.transform[2], plane.transform[3]),
                    SIMD4<Float>(plane.transform[4], plane.transform[5], plane.transform[6], plane.transform[7]),
                    SIMD4<Float>(plane.transform[8], plane.transform[9], plane.transform[10], plane.transform[11]),
                    SIMD4<Float>(plane.transform[12], plane.transform[13], plane.transform[14], plane.transform[15])
                )

                // Transform annotation position by plane transform
                let positionInPlane = SIMD4<Float>(position.x, position.y, position.z, 1.0)
                let transformedPosition = planeTransform * positionInPlane
                finalPosition = SIMD3<Float>(transformedPosition.x, transformedPosition.y, transformedPosition.z)
            }
        }

        // Update or create anchor entity
        if let existingAnchor = annotationAnchors[anchorData.annotationId] {
            // Update existing anchor
            existingAnchor.position = finalPosition
            existingAnchor.orientation = finalOrientation
        } else {
            // Create new anchor entity
            let anchorEntity = AnchorEntity()
            anchorEntity.position = finalPosition
            anchorEntity.orientation = finalOrientation

            arView.scene.addAnchor(anchorEntity)
            annotationAnchors[anchorData.annotationId] = anchorEntity

            print("[iPadAR] ➕ Created anchor for annotation: \(anchorData.annotationId)")
        }

        logStatsIfNeeded()
    }

    // MARK: - Anchor Management

    /// Get world position for annotation (for rendering overlay)
    func getAnnotationWorldPosition(annotationId: String) -> SIMD3<Float>? {
        return annotationAnchors[annotationId]?.position
    }

    /// Get anchor entity for annotation (for attaching 3D models)
    func getAnnotationAnchor(annotationId: String) -> AnchorEntity? {
        return annotationAnchors[annotationId]
    }

    /// Remove anchor for deleted annotation
    func removeAnnotationAnchor(annotationId: String) {
        if let anchor = annotationAnchors[annotationId] {
            anchor.removeFromParent()
            annotationAnchors.removeValue(forKey: annotationId)
            print("[iPadAR] 🗑️ Removed anchor: \(annotationId)")
        }
    }

    /// Clear all anchors
    func clearAllAnchors() {
        for anchor in annotationAnchors.values {
            anchor.removeFromParent()
        }
        annotationAnchors.removeAll()
        print("[iPadAR] 🧹 Cleared all anchors")
    }

    // MARK: - Scene Utilities

    /// Find nearest plane to a world position
    func findNearestPlane(to position: SIMD3<Float>) -> DetectedPlaneData.Plane? {
        var nearestPlane: DetectedPlaneData.Plane?
        var minDistance: Float = .infinity

        for plane in reconstructedPlanes.values {
            let planeCenter = SIMD3<Float>(plane.center[0], plane.center[1], plane.center[2])
            let distance = simd_distance(position, planeCenter)

            if distance < minDistance {
                minDistance = distance
                nearestPlane = plane
            }
        }

        return nearestPlane
    }

    /// Project point onto nearest plane (snap to surface)
    func projectToNearestPlane(position: SIMD3<Float>) -> SIMD3<Float>? {
        guard let plane = findNearestPlane(to: position) else { return nil }

        // For now, return the plane center
        // More sophisticated projection can be added using plane normal
        return SIMD3<Float>(plane.center[0], plane.center[1], plane.center[2])
    }

    // MARK: - Statistics

    private func logStatsIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(lastStatsLog) >= 5.0 {
            print("╔═══════════════════════════════════════════╗")
            print("║  📊 iPAD AR RECONSTRUCTION STATS          ║")
            print("╠═══════════════════════════════════════════╣")
            print("║ Depth maps received:  \(String(format: "%4d", depthMapsReceived))               ║")
            print("║ Planes received:      \(String(format: "%4d", planesReceived))               ║")
            print("║ Active planes:        \(String(format: "%4d", reconstructedPlanes.count))               ║")
            print("║ Anchors updated:      \(String(format: "%4d", anchorsUpdated))               ║")
            print("║ Active anchors:       \(String(format: "%4d", annotationAnchors.count))               ║")
            print("╚═══════════════════════════════════════════╝")

            lastStatsLog = now

            // Reset counters
            depthMapsReceived = 0
            planesReceived = 0
            anchorsUpdated = 0
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        clearAllAnchors()
        reconstructedPlanes.removeAll()
        latestDepthMap = nil
        latestCameraTransform = nil
        print("[iPadAR] 🧹 iPad AR reconstruction cleaned up")
    }
}
