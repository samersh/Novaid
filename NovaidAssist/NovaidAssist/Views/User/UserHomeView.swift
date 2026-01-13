import SwiftUI

struct UserHomeView: View {
    @EnvironmentObject var callManager: CallManager
    @EnvironmentObject var userManager: UserManager
    @State private var isConnecting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var navigateToCall = false
    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "#1a1a2e")!, Color(hex: "#16213e")!],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                headerSection

                // User ID
                userIdSection

                Spacer()

                // Call Button
                callButtonSection

                // Demo Button
                demoButtonSection

                Spacer()

                // Info Section
                infoSection
            }
            .padding()
        }
        .navigationBarHidden(true)
        .onAppear {
            connectToServer()
            startPulseAnimation()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: callManager.callState) { oldValue, newValue in
            if newValue == .connecting || newValue == .connected {
                navigateToCall = true
            }
        }
        .navigationDestination(isPresented: $navigateToCall) {
            UserVideoCallView()
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Novaid")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            Text("Remote Assistance")
                .font(.subheadline)
                .foregroundColor(.gray)

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(callManager.isConnectedToServer ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(callManager.isConnectedToServer ? "Connected" : "Offline")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.top, 40)
    }

    // MARK: - User ID
    private var userIdSection: some View {
        VStack(spacing: 8) {
            Text("Your ID")
                .font(.caption)
                .foregroundColor(.gray)

            Text(userManager.shortId)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#4361ee")!)
                .tracking(4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#4361ee")!.opacity(0.15))
        )
    }

    // MARK: - Call Button
    private var callButtonSection: some View {
        VStack(spacing: 16) {
            Button(action: startCall) {
                ZStack {
                    // Pulse effect
                    Circle()
                        .fill(Color(hex: "#4361ee")!.opacity(0.3))
                        .frame(width: 200, height: 200)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.5)

                    // Main button
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#4361ee")!, Color(hex: "#3a0ca3")!],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 180, height: 180)
                        .shadow(color: Color(hex: "#4361ee")!.opacity(0.5), radius: 20)

                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(2)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white)

                            Text("Start Call")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .disabled(isConnecting || !callManager.isConnectedToServer)
            .opacity(callManager.isConnectedToServer ? 1 : 0.5)

            Text(isConnecting ? "Connecting to a professional..." : "Tap to connect with a professional")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Demo Button
    private var demoButtonSection: some View {
        Button(action: startDemoCall) {
            Text("Try Demo")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                )
        }
    }

    // MARK: - Info Section
    private var infoSection: some View {
        VStack(spacing: 12) {
            InfoRow(icon: "video.fill", text: "Share your view with rear camera")
            InfoRow(icon: "hand.draw.fill", text: "Receive AR guidance from experts")
            InfoRow(icon: "lock.fill", text: "Secure peer-to-peer connection")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Actions
    private func connectToServer() {
        Task {
            do {
                try await callManager.connect()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func startCall() {
        isConnecting = true
        Task {
            do {
                try await callManager.startCall()
            } catch {
                await MainActor.run {
                    isConnecting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func startDemoCall() {
        Task {
            do {
                try await callManager.startDemoCall()
                await MainActor.run {
                    navigateToCall = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: "#4361ee")!)
                .frame(width: 30)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.gray)

            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        UserHomeView()
            .environmentObject(CallManager.shared)
            .environmentObject(UserManager.shared)
    }
}
