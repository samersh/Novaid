import Foundation
import SwiftUI
import Combine
import AVFoundation

/// Manages call state and coordinates between services
class CallManager: ObservableObject {
    static let shared = CallManager()

    // MARK: - Published Properties
    @Published var callState: CallState = .idle
    @Published var currentSession: CallSession?
    @Published var incomingCall: IncomingCall?
    @Published var isConnectedToServer: Bool = false
    @Published var error: String?
    @Published var annotations: [Annotation] = []
    @Published var isVideoFrozen: Bool = false
    @Published var callDuration: Int = 0

    // MARK: - Services
    private var signalingService: SignalingService?
    private var webRTCService: WebRTCService?
    let annotationService = AnnotationService()
    let videoStabilizer = VideoStabilizer()

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var callTimer: Timer?
    private let userManager = UserManager.shared

    private init() {
        setupAnnotationObserver()
    }

    // MARK: - Connection Management

    /// Connect to signaling server
    func connect() async throws {
        guard let userId = userManager.userId else {
            throw CallError.userNotInitialized
        }

        signalingService = SignalingService(userId: userId)

        // Setup signaling callbacks
        signalingService?.onConnected = { [weak self] in
            DispatchQueue.main.async {
                self?.isConnectedToServer = true
            }
        }

        signalingService?.onDisconnected = { [weak self] in
            DispatchQueue.main.async {
                self?.isConnectedToServer = false
            }
        }

        signalingService?.onCallRequest = { [weak self] callerId in
            DispatchQueue.main.async {
                self?.handleIncomingCall(from: callerId)
            }
        }

        signalingService?.onCallAccepted = { [weak self] professionalId in
            DispatchQueue.main.async {
                self?.handleCallAccepted(by: professionalId)
            }
        }

        signalingService?.onCallRejected = { [weak self] in
            DispatchQueue.main.async {
                self?.handleCallRejected()
            }
        }

        signalingService?.onCallEnded = { [weak self] in
            DispatchQueue.main.async {
                self?.endCall()
            }
        }

        signalingService?.onAnnotation = { [weak self] annotation in
            DispatchQueue.main.async {
                self?.handleRemoteAnnotation(annotation)
            }
        }

        signalingService?.onVideoFreeze = { [weak self] in
            DispatchQueue.main.async {
                self?.isVideoFrozen = true
            }
        }

        signalingService?.onVideoResume = { [weak self] annotations in
            DispatchQueue.main.async {
                self?.isVideoFrozen = false
                annotations.forEach { self?.annotations.append($0) }
            }
        }

        signalingService?.onNoProfessionalAvailable = { [weak self] in
            DispatchQueue.main.async {
                self?.callState = .failed
                self?.error = "No professional available at the moment"
            }
        }

        try await signalingService?.connect()

        // Register as professional if needed
        if userManager.currentUser?.role == .professional {
            signalingService?.registerAsProfessional()
        }
    }

    // MARK: - Call Initiation (User)

    /// Start a call (for users)
    func startCall() async throws {
        guard let userId = userManager.userId else {
            throw CallError.userNotInitialized
        }

        // Create session
        let session = CallSession(userId: userId, state: .calling)
        await MainActor.run {
            currentSession = session
            callState = .calling
        }

        // Initialize WebRTC with rear camera
        webRTCService = WebRTCService()
        try await webRTCService?.initialize(useRearCamera: true)

        // Request call from signaling server
        signalingService?.requestCall()
    }

    /// Start demo mode
    func startDemoCall() async throws {
        guard let userId = userManager.userId else {
            throw CallError.userNotInitialized
        }

        let session = CallSession(userId: userId, state: .connected)
        await MainActor.run {
            currentSession = session
            callState = .connected
        }

        // Initialize WebRTC in demo mode
        webRTCService = WebRTCService()
        try await webRTCService?.initialize(useRearCamera: true)

        startCallTimer()
    }

    // MARK: - Call Handling (Professional)

    /// Handle incoming call
    private func handleIncomingCall(from callerId: String) {
        incomingCall = IncomingCall(callerId: callerId)
        callState = .receiving

        // Vibrate to alert
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    /// Accept incoming call
    func acceptCall() async throws {
        guard let incoming = incomingCall,
              let userId = userManager.userId else {
            throw CallError.noIncomingCall
        }

        // Create session
        let session = CallSession(
            userId: incoming.callerId,
            professionalId: userId,
            state: .connecting
        )

        await MainActor.run {
            currentSession = session
            callState = .connecting
            incomingCall = nil
        }

        // Initialize WebRTC (professionals don't need rear camera)
        webRTCService = WebRTCService()
        try await webRTCService?.initialize(useRearCamera: false)

        // Accept via signaling
        signalingService?.acceptCall(callerId: incoming.callerId)
    }

    /// Reject incoming call
    func rejectCall() {
        guard let incoming = incomingCall else { return }

        signalingService?.rejectCall(callerId: incoming.callerId)
        incomingCall = nil
        callState = .idle
    }

    /// Handle call accepted by professional
    private func handleCallAccepted(by professionalId: String) {
        currentSession?.professionalId = professionalId
        callState = .connecting

        // Start WebRTC connection
        Task {
            try? await webRTCService?.createOffer()
        }
    }

    /// Handle call rejected
    private func handleCallRejected() {
        callState = .failed
        error = "Call was rejected"
        cleanup()
    }

    // MARK: - Call End

    /// End the current call
    func endCall() {
        signalingService?.endCall()
        cleanup()
    }

    /// Cleanup call resources
    private func cleanup() {
        callTimer?.invalidate()
        callTimer = nil

        webRTCService?.cleanup()
        webRTCService = nil

        annotations.removeAll()
        annotationService.clearAll()

        callState = .idle
        currentSession = nil
        incomingCall = nil
        isVideoFrozen = false
        callDuration = 0
    }

    // MARK: - Annotations

    private func setupAnnotationObserver() {
        annotationService.onAnnotationCreated = { [weak self] annotation in
            self?.sendAnnotation(annotation)
        }
    }

    /// Send annotation to remote peer
    func sendAnnotation(_ annotation: Annotation) {
        annotations.append(annotation)
        signalingService?.sendAnnotation(annotation)
    }

    /// Handle annotation from remote peer
    private func handleRemoteAnnotation(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    /// Clear all annotations
    func clearAnnotations() {
        annotations.removeAll()
        annotationService.clearAll()
    }

    // MARK: - Video Control

    /// Freeze video (professional only)
    func freezeVideo() {
        isVideoFrozen = true
        signalingService?.freezeVideo()
    }

    /// Resume video with annotations
    func resumeVideo() {
        let currentAnnotations = annotations
        isVideoFrozen = false
        signalingService?.resumeVideo(with: currentAnnotations)
    }

    // MARK: - Timer

    private func startCallTimer() {
        callTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.callDuration += 1
            }
        }
    }

    /// Format duration as mm:ss
    var formattedDuration: String {
        let minutes = callDuration / 60
        let seconds = callDuration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Call Error
enum CallError: LocalizedError {
    case userNotInitialized
    case connectionFailed
    case noIncomingCall
    case webRTCError(String)

    var errorDescription: String? {
        switch self {
        case .userNotInitialized:
            return "User not initialized"
        case .connectionFailed:
            return "Failed to connect to server"
        case .noIncomingCall:
            return "No incoming call to accept"
        case .webRTCError(let message):
            return "WebRTC error: \(message)"
        }
    }
}
