import SwiftUI

struct ProfessionalVideoCallView: View {
    @StateObject private var multipeerService = MultipeerService.shared
    @EnvironmentObject var callManager: CallManager
    @Environment(\.dismiss) private var dismiss

    @State private var showControls = true
    @State private var isDrawingMode = false
    @State private var isAudioEnabled = true
    @State private var showEndCallAlert = false
    @State private var controlsTimer: Timer?
    @State private var videoRotation: Double = 0  // 0, 90, 180, 270 degrees

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video background
                Color.black.ignoresSafeArea()

                // Calculate video frame based on rotation
                let isRotated90or270 = (Int(videoRotation) % 180) != 0
                let baseAspectRatio: CGFloat = 16.0 / 9.0
                let effectiveAspectRatio = isRotated90or270 ? (1.0 / baseAspectRatio) : baseAspectRatio
                let videoFrame = VideoFrameHelper.calculateVideoFrame(
                    containerSize: geometry.size,
                    aspectRatio: effectiveAspectRatio
                )

                // Video + Annotations + Drawing container (rotated together)
                ZStack {
                    // Remote video from User's iPhone camera
                    RemoteVideoView(videoAspectRatio: baseAspectRatio)

                    // Annotations overlay - constrained to video area
                    AnnotationOverlayView(annotations: callManager.annotations)

                    // Drawing canvas (when in drawing mode) - constrained to video area
                    if isDrawingMode {
                        DrawingCanvasView(
                            annotationService: callManager.annotationService,
                            onAnnotationCreated: { annotation in
                                callManager.annotations.append(annotation)
                                // Send via multipeer if connected
                                if multipeerService.isConnected {
                                    multipeerService.sendAnnotation(annotation)
                                    print("[Professional] Sent annotation to user")
                                }
                            }
                        )
                    }
                }
                .frame(width: videoFrame.width, height: videoFrame.height)
                .rotationEffect(.degrees(videoRotation))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Frozen badge
                if callManager.isVideoFrozen {
                    VStack {
                        frozenBadge
                            .padding(.top, 100)
                        Spacer()
                    }
                }

                // Connection status
                if !multipeerService.isConnected {
                    VStack {
                        Spacer()
                        connectionBanner
                            .padding(.bottom, 150)
                    }
                }

                // Controls overlay
                if showControls {
                    controlsOverlay
                }
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: true)
        .landscapeLock()  // Lock to landscape orientation
        .onTapGesture {
            if !isDrawingMode {
                toggleControls()
            }
        }
        .onAppear {
            // Keep screen awake during call
            UIApplication.shared.isIdleTimerDisabled = true
            startControlsTimer()
            setupAnnotationCallback()
        }
        .onDisappear {
            // Re-enable screen sleep
            UIApplication.shared.isIdleTimerDisabled = false
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
            if !newValue {
                dismiss()
            }
        }
    }

    // MARK: - Connection Banner
    private var connectionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundColor(.yellow)
            Text("Demo Mode - No user connected")
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
        )
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
                    .fill(multipeerService.isConnected ? Color.green : Color.yellow)
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

            // Rotate video button
            ControlButton(
                icon: "rotate.right",
                isActive: videoRotation != 0,
                action: rotateVideo
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
    private func setupAnnotationCallback() {
        // Setup is now done via onAnnotationCreated callback in DrawingCanvasView
        // This method remains for any additional setup if needed
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
            callManager.isVideoFrozen = false
            if multipeerService.isConnected {
                multipeerService.sendResumeVideo(annotations: callManager.annotations)
            }
        } else {
            callManager.isVideoFrozen = true
            if multipeerService.isConnected {
                multipeerService.sendFreezeVideo()
            }
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

    private func rotateVideo() {
        withAnimation(.easeInOut(duration: 0.3)) {
            videoRotation = (videoRotation + 90).truncatingRemainder(dividingBy: 360)
        }
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

#Preview {
    ProfessionalVideoCallView()
        .environmentObject(CallManager.shared)
}
