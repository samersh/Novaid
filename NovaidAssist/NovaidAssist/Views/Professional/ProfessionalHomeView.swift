import SwiftUI

struct ProfessionalHomeView: View {
    @StateObject private var multipeerService = MultipeerService.shared
    @EnvironmentObject var callManager: CallManager
    @EnvironmentObject var userManager: UserManager

    @State private var sessionCode = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var navigateToCall = false
    @State private var ringAnimation = false
    @State private var hasGeneratedCode = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "#16213e")!, Color(hex: "#1a1a2e")!],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Session Code Section
                    sessionCodeSection

                    // Connection Status
                    connectionStatusSection

                    Spacer().frame(height: 20)

                    // Main content - connected or waiting
                    if multipeerService.isConnected {
                        connectedSection
                    } else if multipeerService.isHosting {
                        waitingSection
                    } else {
                        startHostingSection
                    }

                    Spacer().frame(height: 20)

                    // Features section
                    featuresSection
                }
                .padding()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            setupMultipeerCallbacks()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: multipeerService.isConnected) { newValue in
            if newValue {
                navigateToCall = true
            }
        }
        .navigationDestination(isPresented: $navigateToCall) {
            ProfessionalVideoCallView()
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Novaid Pro")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            Text("Professional Dashboard")
                .font(.subheadline)
                .foregroundColor(.gray)

            // Professional ID
            HStack(spacing: 6) {
                Text("Professional ID:")
                    .font(.caption)
                    .foregroundColor(.gray)

                Text(userManager.shortId)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#e94560")!)
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Session Code Section
    private var sessionCodeSection: some View {
        VStack(spacing: 16) {
            Text("Session Code")
                .font(.headline)
                .foregroundColor(.white)

            if hasGeneratedCode {
                VStack(spacing: 8) {
                    Text(sessionCode)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#e94560")!)
                        .tracking(8)

                    Text("Share this code with the user")
                        .font(.caption)
                        .foregroundColor(.gray)

                    // Copy button
                    Button(action: copyCode) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Code")
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color(hex: "#e94560")!.opacity(0.3))
                        )
                    }
                }
            } else {
                Button(action: generateCode) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 24))

                        Text("Generate Session Code")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#e94560")!)
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#e94560")!.opacity(0.15))
        )
    }

    // MARK: - Connection Status
    private var connectionStatusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(multipeerService.connectionStatus)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
        )
    }

    private var statusColor: Color {
        if multipeerService.isConnected {
            return .green
        } else if multipeerService.isHosting {
            return .yellow
        } else {
            return .gray
        }
    }

    // MARK: - Connected Section
    private var connectedSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text("User Connected!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                if let peerId = multipeerService.connectedPeerId {
                    Text("Device: \(peerId)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }

            Button(action: { navigateToCall = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "video.fill")
                    Text("Start Video Call")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green)
                )
            }
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }

    // MARK: - Waiting Section
    private var waitingSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.2))
                    .frame(width: 100, height: 100)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                    .scaleEffect(2)
            }

            Text("Waiting for User...")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("Make sure the user enters the session code\nand both devices are on the same WiFi network")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Button(action: stopHosting) {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.5), lineWidth: 1)
                    )
            }
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Start Hosting Section
    private var startHostingSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 40))
                    .foregroundColor(.gray)
            }

            Text("Ready to Connect")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("Generate a session code and share it\nwith the user to start a connection")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Features Section
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Tools")
                .font(.headline)
                .foregroundColor(.white)

            FeatureRow(
                icon: "pencil.tip",
                title: "Draw Annotations",
                description: "Guide users with real-time drawings"
            )

            FeatureRow(
                icon: "pause.circle",
                title: "Freeze Video",
                description: "Pause video for precise annotations"
            )

            FeatureRow(
                icon: "hand.point.up.fill",
                title: "Point & Highlight",
                description: "Draw attention with animated markers"
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Actions
    private func setupMultipeerCallbacks() {
        multipeerService.onConnected = {
            // Connection established
        }

        multipeerService.onDisconnected = {
            Task { @MainActor in
                navigateToCall = false
            }
        }

        multipeerService.onIncomingCall = { callerId in
            // User connected
            print("[Professional] User connected: \(callerId)")
        }
    }

    private func generateCode() {
        sessionCode = multipeerService.generateSessionCode()
        hasGeneratedCode = true

        // Start hosting with the generated code
        multipeerService.startHosting(withCode: sessionCode)
    }

    private func copyCode() {
        UIPasteboard.general.string = sessionCode
    }

    private func stopHosting() {
        multipeerService.stopAll()
        hasGeneratedCode = false
        sessionCode = ""
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "#e94560")!)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        ProfessionalHomeView()
            .environmentObject(CallManager.shared)
            .environmentObject(UserManager.shared)
    }
}
