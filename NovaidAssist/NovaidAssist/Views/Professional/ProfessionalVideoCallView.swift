import SwiftUI

struct ProfessionalVideoCallView: View {
    @EnvironmentObject var callManager: CallManager
    @Environment(\.dismiss) private var dismiss

    @State private var showControls = true
    @State private var isDrawingMode = false
    @State private var isAudioEnabled = true
    @State private var showEndCallAlert = false
    @State private var controlsTimer: Timer?

    var body: some View {
        ZStack {
            // Video background
            Color.black.ignoresSafeArea()

            // Remote video (user's camera)
            RemoteVideoView()
                .ignoresSafeArea()

            // Annotations overlay
            AnnotationOverlayView(annotations: callManager.annotations)
                .ignoresSafeArea()

            // Drawing canvas (when in drawing mode)
            if isDrawingMode {
                DrawingCanvasView(annotationService: callManager.annotationService)
                    .ignoresSafeArea()
            }

            // Frozen badge
            if callManager.isVideoFrozen {
                VStack {
                    frozenBadge
                        .padding(.top, 100)
                    Spacer()
                }
            }

            // Controls overlay
            if showControls {
                controlsOverlay
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: true)
        .onTapGesture {
            if !isDrawingMode {
                toggleControls()
            }
        }
        .onAppear {
            startControlsTimer()
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
        .onChange(of: callManager.callState) { newValue in
            if newValue == .disconnected || newValue == .failed || newValue == .idle {
                dismiss()
            }
        }
    }

    // MARK: - Frozen Badge
    private var frozenBadge: some View {
        Text("VIDEO FROZEN")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.9))
            )
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

            // Annotation toolbar (when in drawing mode)
            if isDrawingMode {
                annotationToolbar
            }

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

                Text(callManager.formattedDuration)
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Spacer()

            // Drawing mode indicator
            if isDrawingMode {
                Text("Drawing Mode")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(hex: "#e94560")!)
                    )
            }
        }
    }

    // MARK: - Annotation Toolbar
    private var annotationToolbar: some View {
        VStack(spacing: 12) {
            // Tool selection
            HStack(spacing: 16) {
                ForEach(AnnotationService.AnnotationTool.allCases, id: \.self) { tool in
                    ToolButton(
                        icon: tool.icon,
                        isSelected: callManager.annotationService.selectedTool == tool
                    ) {
                        callManager.annotationService.selectedTool = tool
                    }
                }
            }

            // Color selection
            HStack(spacing: 12) {
                ForEach(AnnotationService.availableColors, id: \.self) { color in
                    ColorButton(
                        color: color,
                        isSelected: callManager.annotationService.selectedColor == color
                    ) {
                        callManager.annotationService.selectedColor = color
                    }
                }
            }

            // Actions
            HStack(spacing: 20) {
                Button(action: { callManager.clearAnnotations() }) {
                    Text("Clear All")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                        )
                }

                Button(action: { callManager.annotationService.undo() }) {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.2))
                        )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.8))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: - Bottom Controls
    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Mute button
            ControlButton(
                icon: isAudioEnabled ? "mic.fill" : "mic.slash.fill",
                isActive: !isAudioEnabled,
                action: toggleAudio
            )

            // Freeze button
            ControlButton(
                icon: callManager.isVideoFrozen ? "play.fill" : "pause.fill",
                isActive: callManager.isVideoFrozen,
                action: toggleFreeze
            )

            // Draw button
            ControlButton(
                icon: "pencil.tip",
                isActive: isDrawingMode,
                action: toggleDrawingMode
            )

            // End call button
            Button(action: { showEndCallAlert = true }) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 60, height: 60)

                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Actions
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
        guard !isDrawingMode else { return }

        controlsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            withAnimation {
                showControls = false
            }
        }
    }

    private func toggleAudio() {
        isAudioEnabled.toggle()
    }

    private func toggleFreeze() {
        if callManager.isVideoFrozen {
            callManager.resumeVideo()
        } else {
            callManager.freezeVideo()
        }
    }

    private func toggleDrawingMode() {
        withAnimation {
            isDrawingMode.toggle()
        }
        if isDrawingMode {
            controlsTimer?.invalidate()
            showControls = true
        } else {
            startControlsTimer()
        }
    }

    private func endCall() {
        callManager.endCall()
        dismiss()
    }
}

// MARK: - Tool Button
struct ToolButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isSelected ? .white : .gray)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isSelected ? Color(hex: "#e94560")! : Color.white.opacity(0.2))
                )
        }
    }
}

// MARK: - Color Button
struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 3 : 0)
                )
        }
    }
}

// MARK: - Remote Video View (Placeholder)
struct RemoteVideoView: View {
    var body: some View {
        // In production, this would display the remote WebRTC video stream
        ZStack {
            Color.black

            // Placeholder content
            VStack(spacing: 16) {
                Image(systemName: "video.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray.opacity(0.5))

                Text("Remote Video")
                    .font(.headline)
                    .foregroundColor(.gray.opacity(0.5))
            }
        }
    }
}

#Preview {
    ProfessionalVideoCallView()
        .environmentObject(CallManager.shared)
}
