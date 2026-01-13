import SwiftUI

struct ProfessionalHomeView: View {
    @EnvironmentObject var callManager: CallManager
    @EnvironmentObject var userManager: UserManager
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var navigateToCall = false
    @State private var ringAnimation = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "#16213e")!, Color(hex: "#1a1a2e")!],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                headerSection

                // Professional ID
                professionalIdSection

                Spacer()

                // Main content - incoming call or waiting
                if let incomingCall = callManager.incomingCall {
                    incomingCallSection(call: incomingCall)
                } else {
                    waitingSection
                }

                Spacer()

                // Features section
                featuresSection
            }
            .padding()
        }
        .navigationBarHidden(true)
        .onAppear {
            connectToServer()
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

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(callManager.isConnectedToServer ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(callManager.isConnectedToServer ? "Online - Ready for calls" : "Offline")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Professional ID
    private var professionalIdSection: some View {
        VStack(spacing: 8) {
            Text("Professional ID")
                .font(.caption)
                .foregroundColor(.gray)

            Text(userManager.shortId)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#e94560")!)
                .tracking(4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#e94560")!.opacity(0.15))
        )
    }

    // MARK: - Incoming Call
    private func incomingCallSection(call: IncomingCall) -> some View {
        VStack(spacing: 24) {
            // Animated phone icon
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 100, height: 100)
                    .scaleEffect(ringAnimation ? 1.3 : 1.0)
                    .opacity(ringAnimation ? 0.5 : 1.0)

                Circle()
                    .fill(Color.green)
                    .frame(width: 100, height: 100)

                Image(systemName: "phone.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(ringAnimation ? 15 : -15))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                    ringAnimation = true
                }
            }

            VStack(spacing: 8) {
                Text("Incoming Call")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("User ID: \(call.callerShortId)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            // Action buttons
            HStack(spacing: 40) {
                // Reject button
                Button(action: rejectCall) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 70, height: 70)

                            Image(systemName: "xmark")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Text("Decline")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }

                // Accept button
                Button(action: acceptCall) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 70, height: 70)

                            Image(systemName: "checkmark")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Text("Accept")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
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
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "iphone")
                    .font(.system(size: 40))
                    .foregroundColor(.gray)
            }

            Text("Waiting for calls...")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("You will receive a notification when a user requests assistance")
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

    private func acceptCall() {
        Task {
            do {
                try await callManager.acceptCall()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func rejectCall() {
        callManager.rejectCall()
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
