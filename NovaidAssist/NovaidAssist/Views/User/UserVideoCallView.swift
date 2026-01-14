import SwiftUI
import AVFoundation

struct UserVideoCallView: View {
    @StateObject private var multipeerService = MultipeerService.shared
    @StateObject private var arAnnotationManager = ARAnnotationManager()
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

            // AR Camera with world tracking (replaces regular camera)
            ARCameraView(annotationManager: arAnnotationManager)
                .ignoresSafeArea()

            // AR Annotations overlay (world-tracked positions)
            ARAnnotationOverlayView(annotations: arAnnotationManager.annotations)
                .ignoresSafeArea()

            // Frozen video indicator
            if callManager.isVideoFrozen {
                frozenVideoOverlay
            }

            // Controls overlay (landscape-optimized)
            if showControls {
                landscapeControlsOverlay
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: true)
        .landscapeLock()  // Lock to landscape orientation
        .onTapGesture {
            toggleControls()
        }
        .onAppear {
            startControlsTimer()
            setupAnnotationCallbacks()
        }
        .onDisappear {
            controlsTimer?.invalidate()
            OrientationManager.shared.unlock()
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

    // MARK: - Landscape Controls Overlay
    private var landscapeControlsOverlay: some View {
        HStack {
            // Left side - Status
            VStack(alignment: .leading) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)

                    Text(callStatusText)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.5))
                .cornerRadius(20)

                Spacer()
            }
            .padding(.leading, 40)
            .padding(.top, 20)

            Spacer()

            // Right side - Controls (vertical stack for landscape)
            VStack(spacing: 20) {
                Spacer()

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

                Spacer()
            }
            .padding(.trailing, 40)
            .padding(.vertical, 20)
            .background(
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.4)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 120)
                .ignoresSafeArea()
            )
        }
        .transition(.opacity)
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

    // MARK: - Actions
    private func setupAnnotationCallbacks() {
        // Receive annotations from professional and add to AR manager
        multipeerService.onAnnotationReceived = { [self] annotation in
            arAnnotationManager.addAnnotation(annotation)
            print("[User] Received annotation from professional - will track in AR")
        }

        // Handle video freeze command
        multipeerService.onVideoFrozen = { [self] in
            callManager.isVideoFrozen = true
            print("[User] Video frozen by professional")
        }

        // Handle video resume command with annotations
        multipeerService.onVideoResumed = { [self] annotations in
            callManager.isVideoFrozen = false
            // Add all annotations to AR manager
            for annotation in annotations {
                arAnnotationManager.addAnnotation(annotation)
            }
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
        arAnnotationManager.clearAll()
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
