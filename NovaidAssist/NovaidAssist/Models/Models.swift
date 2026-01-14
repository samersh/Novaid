import Foundation
import SwiftUI

// MARK: - User Role
enum UserRole: String, Codable {
    case user
    case professional
}

// MARK: - User Model
struct User: Codable, Identifiable {
    let id: String
    var role: UserRole
    var name: String?
    let createdAt: Date

    init(id: String = UUID().uuidString, role: UserRole, name: String? = nil) {
        self.id = id
        self.role = role
        self.name = name
        self.createdAt = Date()
    }

    var shortId: String {
        String(id.suffix(6)).uppercased()
    }
}

// MARK: - Call State
enum CallState: String {
    case idle
    case calling
    case receiving
    case connecting
    case connected
    case disconnected
    case failed
}

// MARK: - Signal Types
enum SignalType: String, Codable {
    case offer
    case answer
    case iceCandidate = "ice-candidate"
    case callRequest = "call-request"
    case callAccepted = "call-accepted"
    case callRejected = "call-rejected"
    case callEnded = "call-ended"
    case annotation
    case freezeVideo = "freeze-video"
    case resumeVideo = "resume-video"
}

// MARK: - Signal Message
struct SignalMessage: Codable {
    let type: SignalType
    let from: String
    let to: String
    var payload: [String: Any]?
    let timestamp: Date

    init(type: SignalType, from: String, to: String, payload: [String: Any]? = nil) {
        self.type = type
        self.from = from
        self.to = to
        self.payload = payload
        self.timestamp = Date()
    }

    enum CodingKeys: String, CodingKey {
        case type, from, to, payload, timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(SignalType.self, forKey: .type)
        from = try container.decode(String.self, forKey: .from)
        to = try container.decode(String.self, forKey: .to)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        payload = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

// MARK: - Annotation Types
enum AnnotationType: String, Codable {
    case drawing
    case pointer
    case arrow
    case circle
    case text
    case animation
}

// MARK: - Animation Type
enum AnimationType: String, Codable {
    case pulse
    case bounce
    case highlight
}

// MARK: - Point (Normalized 0-1 coordinates for cross-device compatibility)
struct AnnotationPoint: Codable, Hashable {
    let x: CGFloat
    let y: CGFloat

    // Whether coordinates are normalized (0-1 range) or absolute
    var isNormalized: Bool = true

    init(x: CGFloat, y: CGFloat, normalized: Bool = true) {
        self.x = x
        self.y = y
        self.isNormalized = normalized
    }

    init(_ point: CGPoint, normalized: Bool = true) {
        self.x = point.x
        self.y = point.y
        self.isNormalized = normalized
    }

    // Create from absolute coordinates, normalizing to 0-1 range
    static func normalized(from point: CGPoint, in size: CGSize) -> AnnotationPoint {
        return AnnotationPoint(
            x: point.x / size.width,
            y: point.y / size.height,
            normalized: true
        )
    }

    // Convert to absolute coordinates for a given screen size
    func toAbsolute(in size: CGSize) -> CGPoint {
        if isNormalized {
            return CGPoint(x: x * size.width, y: y * size.height)
        } else {
            return CGPoint(x: x, y: y)
        }
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    enum CodingKeys: String, CodingKey {
        case x, y, isNormalized
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(CGFloat.self, forKey: .x)
        y = try container.decode(CGFloat.self, forKey: .y)
        isNormalized = try container.decodeIfPresent(Bool.self, forKey: .isNormalized) ?? true
    }
}

// MARK: - World Position (for AR tracking)
struct WorldPosition: Codable, Hashable {
    let x: Float
    let y: Float
    let z: Float

    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(_ simd: SIMD3<Float>) {
        self.x = simd.x
        self.y = simd.y
        self.z = simd.z
    }

    var simd: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

// MARK: - Annotation
struct Annotation: Codable, Identifiable {
    let id: String
    let type: AnnotationType
    var points: [AnnotationPoint]
    let color: String
    let strokeWidth: CGFloat
    var text: String?
    var animationType: AnimationType?
    let timestamp: Date
    var isComplete: Bool

    // AR world tracking position (optional)
    var worldPosition: SIMD3<Float>?

    init(
        id: String = UUID().uuidString,
        type: AnnotationType,
        points: [AnnotationPoint] = [],
        color: String = "#FF0000",
        strokeWidth: CGFloat = 4,
        text: String? = nil,
        animationType: AnimationType? = nil,
        isComplete: Bool = false,
        worldPosition: SIMD3<Float>? = nil
    ) {
        self.id = id
        self.type = type
        self.points = points
        self.color = color
        self.strokeWidth = strokeWidth
        self.text = text
        self.animationType = animationType
        self.timestamp = Date()
        self.isComplete = isComplete
        self.worldPosition = worldPosition
    }

    var swiftUIColor: Color {
        Color(hex: color) ?? .red
    }

    // Custom Codable for SIMD3<Float>
    enum CodingKeys: String, CodingKey {
        case id, type, points, color, strokeWidth, text, animationType, timestamp, isComplete, worldPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(AnnotationType.self, forKey: .type)
        points = try container.decode([AnnotationPoint].self, forKey: .points)
        color = try container.decode(String.self, forKey: .color)
        strokeWidth = try container.decode(CGFloat.self, forKey: .strokeWidth)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        animationType = try container.decodeIfPresent(AnimationType.self, forKey: .animationType)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false

        if let worldPos = try container.decodeIfPresent(WorldPosition.self, forKey: .worldPosition) {
            worldPosition = worldPos.simd
        } else {
            worldPosition = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(points, forKey: .points)
        try container.encode(color, forKey: .color)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(animationType, forKey: .animationType)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isComplete, forKey: .isComplete)

        if let worldPos = worldPosition {
            try container.encode(WorldPosition(worldPos), forKey: .worldPosition)
        }
    }
}

// MARK: - Call Session
struct CallSession: Identifiable {
    let id: String
    let userId: String
    var professionalId: String?
    var state: CallState
    var startTime: Date?
    var endTime: Date?
    var annotations: [Annotation]
    var isVideoFrozen: Bool
    var frozenFrameData: Data?

    init(
        id: String = UUID().uuidString,
        userId: String,
        professionalId: String? = nil,
        state: CallState = .idle
    ) {
        self.id = id
        self.userId = userId
        self.professionalId = professionalId
        self.state = state
        self.annotations = []
        self.isVideoFrozen = false
    }
}

// MARK: - Video Stabilization Config
struct StabilizationConfig {
    var enabled: Bool = true
    var smoothingFactor: Float = 0.95
    var maxOffset: Float = 50.0
}

// MARK: - WebRTC Configuration
struct WebRTCConfiguration {
    let iceServers: [String]
    let useRearCamera: Bool

    static let `default` = WebRTCConfiguration(
        iceServers: [
            "stun:stun.l.google.com:19302",
            "stun:stun1.l.google.com:19302",
            "stun:stun2.l.google.com:19302"
        ],
        useRearCamera: true
    )
}

// MARK: - Incoming Call
struct IncomingCall: Identifiable {
    let id: String
    let callerId: String
    let callerShortId: String
    let timestamp: Date

    init(callerId: String) {
        self.id = UUID().uuidString
        self.callerId = callerId
        self.callerShortId = String(callerId.suffix(6)).uppercased()
        self.timestamp = Date()
    }
}
