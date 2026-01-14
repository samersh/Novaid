import SwiftUI

struct UserHomeView: View {
    @StateObject private var multipeerService = MultipeerService.shared
    @EnvironmentObject var callManager: CallManager
    @EnvironmentObject var userManager: UserManager

    @State private var sessionCode = ""
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

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Session Code Input
                    sessionCodeSection

                    // Connection Status
                    connectionStatusSection

                    Spacer().frame(height: 20)

                    // Call Button
                    callButtonSection

                    // Demo Button
                    demoButtonSection

                    Spacer().frame(height: 20)

                    // Info Section
                    infoSection
                }
                .padding()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            startPulseAnimation()
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

            // User ID
            HStack(spacing: 6) {
                Text("Your ID:")
                    .font(.caption)
                    .foregroundColor(.gray)

                Text(userManager.shortId)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#4361ee")!)
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Session Code Section
    private var sessionCodeSection: some View {
        VStack(spacing: 12) {
            Text("Enter Session Code")
                .font(.headline)
                .foregroundColor(.white)

            Text("Get this code from your professional")
                .font(.caption)
                .foregroundColor(.gray)

            HStack(spacing: 12) {
                TextField("000000", text: $sessionCode)
                    .keyboardType(.numberPad)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
                    .onChange(of: sessionCode) { newValue in
                        // Limit to 6 digits
                        if newValue.count > 6 {
                            sessionCode = String(newValue.prefix(6))
                        }
                        // Only allow numbers
                        sessionCode = newValue.filter { $0.isNumber }
                    }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#4361ee")!.opacity(0.15))
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
        } else if multipeerService.isBrowsing {
            return .yellow
        } else {
            return .gray
        }
    }

    // MARK: - Call Button
    private var callButtonSection: some View {
        VStack(spacing: 16) {
            Button(action: startCall) {
                ZStack {
                    // Pulse effect
                    if canConnect {
                        Circle()
                            .fill(Color(hex: "#4361ee")!.opacity(0.3))
                            .frame(width: 200, height: 200)
                            .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                            .opacity(pulseAnimation ? 0 : 0.5)
                    }

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

                    if isConnecting || multipeerService.isBrowsing {
                        VStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(2)

                            Text("Connecting...")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white)

                            Text("Connect")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .disabled(!canConnect || isConnecting)
            .opacity(canConnect ? 1 : 0.5)

            Text(buttonHelpText)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }

    private var canConnect: Bool {
        sessionCode.count == 6 && !multipeerService.isBrowsing && !multipeerService.isConnected
    }

    private var buttonHelpText: String {
        if sessionCode.count < 6 {
            return "Enter the 6-digit session code first"
        } else if multipeerService.isBrowsing {
            return "Searching for professional..."
        } else if multipeerService.isConnected {
            return "Connected!"
        } else {
            return "Tap to connect with the professional"
        }
    }

    // MARK: - Demo Button
    private var demoButtonSection: some View {
        Button(action: startDemoCall) {
            Text("Try Demo (No Connection)")
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
            InfoRow(icon: "video.fill", text: "Share your rear camera view")
            InfoRow(icon: "hand.draw.fill", text: "Receive AR guidance from experts")
            InfoRow(icon: "wifi", text: "Connect via WiFi or Bluetooth")
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
            Task { @MainActor in
                isConnecting = false
            }
        }

        multipeerService.onDisconnected = {
            Task { @MainActor in
                isConnecting = false
                navigateToCall = false
            }
        }

        multipeerService.onAnnotationReceived = { annotation in
            Task { @MainActor in
                callManager.annotations.append(annotation)
            }
        }

        multipeerService.onVideoFrozen = {
            Task { @MainActor in
                callManager.isVideoFrozen = true
            }
        }

        multipeerService.onVideoResumed = { annotations in
            Task { @MainActor in
                callManager.isVideoFrozen = false
                callManager.annotations.append(contentsOf: annotations)
            }
        }
    }

    private func startCall() {
        guard sessionCode.count == 6 else {
            errorMessage = "Please enter a valid 6-digit session code"
            showError = true
            return
        }

        isConnecting = true
        multipeerService.startBrowsing(forCode: sessionCode)
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
