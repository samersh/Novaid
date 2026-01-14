import Foundation
import MultipeerConnectivity
import Combine

/// Service for peer-to-peer connection using MultipeerConnectivity
/// Allows iPhone and iPad to connect directly via WiFi/Bluetooth without a server
@MainActor
class MultipeerService: NSObject, ObservableObject {
    // MARK: - Singleton
    static let shared = MultipeerService()

    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectedPeerId: String?
    @Published var availablePeers: [MCPeerID] = []
    @Published var sessionCode: String = ""
    @Published var isHosting = false
    @Published var isBrowsing = false
    @Published var connectionStatus: String = "Disconnected"
    @Published var incomingInvitation: (from: MCPeerID, handler: (Bool, MCSession?) -> Void)?

    // MARK: - Callbacks
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onDataReceived: ((Data, MCPeerID) -> Void)?
    var onIncomingCall: ((String) -> Void)?
    var onCallAccepted: (() -> Void)?
    var onCallRejected: (() -> Void)?
    var onAnnotationReceived: ((Annotation) -> Void)?
    var onVideoFrozen: (() -> Void)?
    var onVideoResumed: (([Annotation]) -> Void)?

    // MARK: - Private Properties
    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private let serviceType = "novaid-assist"

    // MARK: - Initialization
    private override init() {
        super.init()
        setupPeerID()
    }

    private func setupPeerID() {
        let deviceName = UIDevice.current.name
        peerID = MCPeerID(displayName: deviceName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    // MARK: - Session Code Management

    /// Generate a random 6-digit session code
    func generateSessionCode() -> String {
        let code = String(format: "%06d", Int.random(in: 0...999999))
        sessionCode = code
        return code
    }

    /// Set session code for joining
    func setSessionCode(_ code: String) {
        sessionCode = code
    }

    // MARK: - Hosting (Professional waits for User)

    /// Start hosting a session (Professional mode)
    func startHosting(withCode code: String) {
        sessionCode = code
        stopAll()

        // Create advertiser with session code in discovery info
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["code": code, "role": "professional"],
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        isHosting = true
        connectionStatus = "Waiting for connection..."
        print("[Multipeer] Started hosting with code: \(code)")
    }

    // MARK: - Browsing (User looks for Professional)

    /// Start browsing for hosts (User mode)
    func startBrowsing(forCode code: String) {
        sessionCode = code
        stopAll()

        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        isBrowsing = true
        connectionStatus = "Searching for professional..."
        print("[Multipeer] Started browsing for code: \(code)")
    }

    // MARK: - Connection

    /// Invite a peer to connect
    func invitePeer(_ peer: MCPeerID) {
        let context = sessionCode.data(using: .utf8)
        browser?.invitePeer(peer, to: session, withContext: context, timeout: 30)
        connectionStatus = "Connecting..."
        print("[Multipeer] Invited peer: \(peer.displayName)")
    }

    /// Accept incoming invitation
    func acceptInvitation() {
        guard let invitation = incomingInvitation else { return }
        invitation.handler(true, session)
        incomingInvitation = nil
        connectionStatus = "Connecting..."
        print("[Multipeer] Accepted invitation from: \(invitation.from.displayName)")
    }

    /// Reject incoming invitation
    func rejectInvitation() {
        guard let invitation = incomingInvitation else { return }
        invitation.handler(false, nil)
        incomingInvitation = nil
        print("[Multipeer] Rejected invitation")
    }

    // MARK: - Data Transmission

    /// Send data to connected peer
    func sendData(_ data: Data) {
        guard !session.connectedPeers.isEmpty else {
            print("[Multipeer] No connected peers to send data to")
            return
        }

        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("[Multipeer] Failed to send data: \(error)")
        }
    }

    /// Send a message
    func sendMessage(_ message: MultipeerMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        sendData(data)
    }

    /// Send call request
    func sendCallRequest() {
        let message = MultipeerMessage(type: .callRequest, payload: nil)
        sendMessage(message)
    }

    /// Send call accepted
    func sendCallAccepted() {
        let message = MultipeerMessage(type: .callAccepted, payload: nil)
        sendMessage(message)
        onCallAccepted?()
    }

    /// Send call rejected
    func sendCallRejected() {
        let message = MultipeerMessage(type: .callRejected, payload: nil)
        sendMessage(message)
    }

    /// Send call ended
    func sendCallEnded() {
        let message = MultipeerMessage(type: .callEnded, payload: nil)
        sendMessage(message)
    }

    /// Send annotation
    func sendAnnotation(_ annotation: Annotation) {
        guard let data = try? JSONEncoder().encode(annotation) else { return }
        let message = MultipeerMessage(type: .annotation, payload: data)
        sendMessage(message)
    }

    /// Send freeze video command
    func sendFreezeVideo() {
        let message = MultipeerMessage(type: .freezeVideo, payload: nil)
        sendMessage(message)
    }

    /// Send resume video command with annotations
    func sendResumeVideo(annotations: [Annotation]) {
        guard let data = try? JSONEncoder().encode(annotations) else { return }
        let message = MultipeerMessage(type: .resumeVideo, payload: data)
        sendMessage(message)
    }

    // MARK: - Cleanup

    func stopAll() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        isHosting = false
        isBrowsing = false
    }

    func disconnect() {
        stopAll()
        session.disconnect()
        isConnected = false
        connectedPeerId = nil
        availablePeers = []
        connectionStatus = "Disconnected"
        onDisconnected?()
    }
}

// MARK: - MCSessionDelegate
extension MultipeerService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                print("[Multipeer] Connected to: \(peerID.displayName)")
                self.isConnected = true
                self.connectedPeerId = peerID.displayName
                self.connectionStatus = "Connected to \(peerID.displayName)"
                self.stopAll()
                self.onConnected?()

            case .connecting:
                print("[Multipeer] Connecting to: \(peerID.displayName)")
                self.connectionStatus = "Connecting..."

            case .notConnected:
                print("[Multipeer] Disconnected from: \(peerID.displayName)")
                self.isConnected = false
                self.connectedPeerId = nil
                self.connectionStatus = "Disconnected"
                self.onDisconnected?()

            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.onDataReceived?(data, peerID)

            // Parse message
            guard let message = try? JSONDecoder().decode(MultipeerMessage.self, from: data) else {
                return
            }

            switch message.type {
            case .callRequest:
                self.onIncomingCall?(peerID.displayName)

            case .callAccepted:
                self.onCallAccepted?()

            case .callRejected:
                self.onCallRejected?()

            case .callEnded:
                self.onDisconnected?()

            case .annotation:
                if let payload = message.payload,
                   let annotation = try? JSONDecoder().decode(Annotation.self, from: payload) {
                    self.onAnnotationReceived?(annotation)
                }

            case .freezeVideo:
                self.onVideoFrozen?()

            case .resumeVideo:
                if let payload = message.payload,
                   let annotations = try? JSONDecoder().decode([Annotation].self, from: payload) {
                    self.onVideoResumed?(annotations)
                }
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Handle incoming stream if needed
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Handle resource transfer
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Handle completed resource transfer
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // Check if the invitation has the matching session code
            if let contextData = context,
               let receivedCode = String(data: contextData, encoding: .utf8),
               receivedCode == self.sessionCode {
                // Auto-accept if codes match
                print("[Multipeer] Auto-accepting invitation from \(peerID.displayName) with matching code")
                invitationHandler(true, self.session)
                self.onIncomingCall?(peerID.displayName)
            } else {
                // Store invitation for manual handling
                self.incomingInvitation = (peerID, invitationHandler)
                self.onIncomingCall?(peerID.displayName)
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            print("[Multipeer] Failed to advertise: \(error)")
            self.connectionStatus = "Failed to start hosting"
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            print("[Multipeer] Found peer: \(peerID.displayName), info: \(String(describing: info))")

            // Check if the peer has our session code
            if let peerCode = info?["code"], peerCode == self.sessionCode {
                // Found matching peer, auto-connect
                print("[Multipeer] Found matching peer with code \(peerCode)")
                if !self.availablePeers.contains(where: { $0.displayName == peerID.displayName }) {
                    self.availablePeers.append(peerID)
                    // Auto-connect to matching peer
                    self.invitePeer(peerID)
                }
            } else {
                // Just add to list
                if !self.availablePeers.contains(where: { $0.displayName == peerID.displayName }) {
                    self.availablePeers.append(peerID)
                }
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            print("[Multipeer] Lost peer: \(peerID.displayName)")
            self.availablePeers.removeAll { $0.displayName == peerID.displayName }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            print("[Multipeer] Failed to browse: \(error)")
            self.connectionStatus = "Failed to search"
        }
    }
}

// MARK: - Message Types
struct MultipeerMessage: Codable {
    enum MessageType: String, Codable {
        case callRequest
        case callAccepted
        case callRejected
        case callEnded
        case annotation
        case freezeVideo
        case resumeVideo
    }

    let type: MessageType
    let payload: Data?
}
