import SwiftUI
import AVFoundation

struct UserVideoCallView: View {
    @StateObject private var multipeerService = MultipeerService.shared
    @EnvironmentObject var callManager: CallManager
    @Environment(\.dismiss) private var dismiss

    @State private var showControls = true
    @State private var isAudioEnabled = true
    @State private var isVideoEnabled = true
    @State private var showEndCallAlert = false
    @State private var controlsTimer: Timer?

    var body: some View {
        ZStack {
            // Video background
            Color.black.ignoresSafeArea()

            // Camera preview - using REAR camera and sending frames
            CameraPreviewView(useRearCamera: true, sendFrames: true)
                .ignoresSafeArea()

            // AR Annotations overlay
            AnnotationOverlayView(annotations: callManager.annotations)
                .ignoresSafeArea()

            // Frozen video indicator
            if callManager.isVideoFrozen {
                frozenVideoOverlay
            }

            // Controls overlay
            if showControls {
                controlsOverlay
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: true)
        .onTapGesture {
            toggleControls()
        }
        .onAppear {
            startControlsTimer()
            setupAnnotationCallbacks()
        }
        .onDisappear {
            controlsTimer?.invalidate()
        }
        .alert("End Call", isPresented: $showEndCallAlert) {
            Button("Cancel", role: .cancel) { }
            Button("End Call", role: .destructive) {
                endCall()
            }
        } message: {
            Text("Are you sure you want to end this call?")
        }
        .onChange(of: multipeerService.isConnected) { newValue in
            if !newValue && callManager.callState == .connected {
                dismiss()
            }
        }
    }

    // MARK: - Frozen Video Overlay
    private var frozenVideoOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white)

                Text("Video Paused")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Expert is adding annotations")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Controls Overlay
    private var controlsOverlay: some View {
        VStack {
            // Top bar
            topBar
                .padding(.top, 50)
                .padding(.horizontal, 20)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.6), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )

            Spacer()

            // Bottom controls
            bottomControls
                .padding(.bottom, 40)
                .padding(.horizontal, 20)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
        }
        .transition(.opacity)
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            // Call status
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)

                Text(callStatusText)
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Spacer()
        }
    }

    private var callStatusText: String {
        switch callManager.callState {
        case .calling:
            return "Calling..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return callManager.formattedDuration
        default:
            return ""
        }
    }

    // MARK: - Bottom Controls
    private var bottomControls: some View {
        HStack(spacing: 30) {
            // Mute button
            ControlButton(
                icon: isAudioEnabled ? "mic.fill" : "mic.slash.fill",
                isActive: !isAudioEnabled,
                action: toggleAudio
            )

            // End call button
            Button(action: { showEndCallAlert = true }) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)

                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
            }

            // Video toggle button
            ControlButton(
                icon: isVideoEnabled ? "video.fill" : "video.slash.fill",
                isActive: !isVideoEnabled,
                action: toggleVideo
            )
        }
    }

    // MARK: - Actions
    private func setupAnnotationCallbacks() {
        // Receive annotations from professional
        multipeerService.onAnnotationReceived = { [self] annotation in
            callManager.annotations.append(annotation)
            print("[User] Received annotation from professional")
        }

        // Handle video freeze command
        multipeerService.onVideoFrozen = { [self] in
            callManager.isVideoFrozen = true
            print("[User] Video frozen by professional")
        }

        // Handle video resume command with annotations
        multipeerService.onVideoResumed = { [self] annotations in
            callManager.isVideoFrozen = false
            callManager.annotations = annotations
            print("[User] Video resumed with \(annotations.count) annotations")
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showControls.toggle()
        }
        if showControls {
            startControlsTimer()
        }
    }

    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            withAnimation {
                showControls = false
            }
        }
    }

    private func toggleAudio() {
        isAudioEnabled.toggle()
    }

    private func toggleVideo() {
        isVideoEnabled.toggle()
    }

    private func endCall() {
        if multipeerService.isConnected {
            multipeerService.sendCallEnded()
            multipeerService.disconnect()
        }
        callManager.endCall()
        dismiss()
    }
}

// MARK: - Control Button
struct ControlButton: View {
    let icon: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.red.opacity(0.3) : Color.white.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    UserVideoCallView()
        .environmentObject(CallManager.shared)
}
