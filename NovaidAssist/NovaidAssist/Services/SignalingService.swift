import Foundation

/// WebSocket-based signaling service for WebRTC connection establishment
class SignalingService {
    private let userId: String
    private let serverURL: URL
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    // MARK: - Callbacks
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onCallRequest: ((String) -> Void)?
    var onCallAccepted: ((String) -> Void)?
    var onCallRejected: (() -> Void)?
    var onCallEnded: (() -> Void)?
    var onAnnotation: ((Annotation) -> Void)?
    var onVideoFreeze: (() -> Void)?
    var onVideoResume: (([Annotation]) -> Void)?
    var onNoProfessionalAvailable: (() -> Void)?
    var onOffer: ((String) -> Void)?
    var onAnswer: ((String) -> Void)?
    var onIceCandidate: ((String) -> Void)?

    private var remoteUserId: String?

    init(userId: String, serverURL: String = "ws://localhost:3001") {
        self.userId = userId
        self.serverURL = URL(string: "\(serverURL)?userId=\(userId)")!
    }

    // MARK: - Connection

    func connect() async throws {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true

        urlSession = URLSession(configuration: configuration)
        webSocket = urlSession?.webSocketTask(with: serverURL)
        webSocket?.resume()

        isConnected = true
        reconnectAttempts = 0
        onConnected?()

        // Start receiving messages
        receiveMessage()
    }

    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        onDisconnected?()
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self?.receiveMessage()

            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self?.handleDisconnection()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeString = json["type"] as? String else {
            return
        }

        let from = json["from"] as? String
        let payload = json["payload"] as? [String: Any]

        switch typeString {
        case "call-request":
            if let callerId = from {
                remoteUserId = callerId
                onCallRequest?(callerId)
            }

        case "call-accepted":
            if let professionalId = from {
                remoteUserId = professionalId
                onCallAccepted?(professionalId)
            }

        case "call-rejected":
            onCallRejected?()

        case "call-ended":
            onCallEnded?()

        case "professional-available":
            if let professionalId = payload?["professionalId"] as? String {
                remoteUserId = professionalId
            }

        case "no-professional-available":
            onNoProfessionalAvailable?()

        case "offer":
            if let sdp = payload?["sdp"] as? String {
                remoteUserId = from
                onOffer?(sdp)
            }

        case "answer":
            if let sdp = payload?["sdp"] as? String {
                onAnswer?(sdp)
            }

        case "ice-candidate":
            if let candidate = payload?["candidate"] as? String {
                onIceCandidate?(candidate)
            }

        case "annotation":
            if let annotationData = try? JSONSerialization.data(withJSONObject: payload ?? [:]),
               let annotation = try? JSONDecoder().decode(Annotation.self, from: annotationData) {
                onAnnotation?(annotation)
            }

        case "freeze-video":
            onVideoFreeze?()

        case "resume-video":
            if let annotationsArray = payload?["annotations"] as? [[String: Any]],
               let data = try? JSONSerialization.data(withJSONObject: annotationsArray),
               let annotations = try? JSONDecoder().decode([Annotation].self, from: data) {
                onVideoResume?(annotations)
            } else {
                onVideoResume?([])
            }

        default:
            print("Unknown message type: \(typeString)")
        }
    }

    private func handleDisconnection() {
        isConnected = false
        onDisconnected?()

        // Attempt reconnection
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            let delay = pow(2.0, Double(reconnectAttempts))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                Task {
                    try? await self?.connect()
                }
            }
        }
    }

    // MARK: - Send Methods

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        webSocket?.send(.string(text)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    func registerAsProfessional() {
        send([
            "type": "register-professional",
            "userId": userId
        ])
    }

    func requestCall() {
        send([
            "type": "request-call",
            "userId": userId
        ])
    }

    func acceptCall(callerId: String) {
        remoteUserId = callerId
        send([
            "type": "accept-call",
            "userId": userId,
            "callerId": callerId
        ])
    }

    func rejectCall(callerId: String) {
        send([
            "type": "reject-call",
            "userId": userId,
            "callerId": callerId
        ])
    }

    func endCall() {
        guard let remoteId = remoteUserId else { return }
        send([
            "type": "message",
            "type": "call-ended",
            "from": userId,
            "to": remoteId,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ])
    }

    func sendOffer(sdp: String) {
        guard let remoteId = remoteUserId else { return }
        send([
            "type": "message",
            "from": userId,
            "to": remoteId,
            "payload": [
                "type": "offer",
                "sdp": sdp
            ],
            "timestamp": Date().timeIntervalSince1970 * 1000
        ])
    }

    func sendAnswer(sdp: String) {
        guard let remoteId = remoteUserId else { return }
        send([
            "type": "message",
            "from": userId,
            "to": remoteId,
            "payload": [
                "type": "answer",
                "sdp": sdp
            ],
            "timestamp": Date().timeIntervalSince1970 * 1000
        ])
    }

    func sendIceCandidate(_ candidate: String) {
        guard let remoteId = remoteUserId else { return }
        send([
            "type": "message",
            "from": userId,
            "to": remoteId,
            "payload": [
                "type": "ice-candidate",
                "candidate": candidate
            ],
            "timestamp": Date().timeIntervalSince1970 * 1000
        ])
    }

    func sendAnnotation(_ annotation: Annotation) {
        guard let remoteId = remoteUserId,
              let annotationData = try? JSONEncoder().encode(annotation),
              let annotationDict = try? JSONSerialization.jsonObject(with: annotationData) else {
            return
        }

        send([
            "type": "message",
            "from": userId,
            "to": remoteId,
            "payload": [
                "type": "annotation",
                "annotation": annotationDict
            ],
            "timestamp": Date().timeIntervalSince1970 * 1000
        ])
    }

    func freezeVideo() {
        guard let remoteId = remoteUserId else { return }
        send([
            "type": "message",
            "from": userId,
            "to": remoteId,
            "payload": ["type": "freeze-video"],
            "timestamp": Date().timeIntervalSince1970 * 1000
        ])
    }

    func resumeVideo(with annotations: [Annotation]) {
        guard let remoteId = remoteUserId,
              let annotationsData = try? JSONEncoder().encode(annotations),
              let annotationsArray = try? JSONSerialization.jsonObject(with: annotationsData) else {
            return
        }

        send([
            "type": "message",
            "from": userId,
            "to": remoteId,
            "payload": [
                "type": "resume-video",
                "annotations": annotationsArray
            ],
            "timestamp": Date().timeIntervalSince1970 * 1000
        ])
    }
}
