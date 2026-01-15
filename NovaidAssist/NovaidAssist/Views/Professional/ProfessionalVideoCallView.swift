import SwiftUI

struct ProfessionalVideoCallView: View {
    @StateObject private var multipeerService = MultipeerService.shared
    @StateObject private var audioService = AudioService.shared
    @EnvironmentObject var callManager: CallManager
    @Environment(\.dismiss) private var dismiss

    @State private var showControls = true
    @State private var isDrawingMode = false
    @State private var isAudioEnabled = true
    @State private var isFlashlightOn = false
    @State private var showEndCallAlert = false
    @State private var controlsTimer: Timer?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video background
                Color.black.ignoresSafeArea()

                // Calculate video frame bounds
                let videoFrame = VideoFrameHelper.calculateVideoFrame(containerSize: geometry.size)

                // Remote video from User's iPhone camera
                RemoteVideoView()
                    .ignoresSafeArea()

                // Annotations overlay - constrained to video area
                AnnotationOverlayView(annotations: callManager.annotations)
                    .frame(width: videoFrame.width, height: videoFrame.height)
                    .position(x: videoFrame.midX, y: videoFrame.midY)

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
                    .frame(width: videoFrame.width, height: videoFrame.height)
                    .position(x: videoFrame.midX, y: videoFrame.midY)
                }

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
            setupAudioCallbacks()
            // Start audio capture
            audioService.startAudioCapture()
        }
        .onDisappear {
            // Re-enable screen sleep
            UIApplication.shared.isIdleTimerDisabled = false
            controlsTimer?.invalidate()
            OrientationManager.shared.unlock()
            // Stop audio capture
            audioService.stopAudioCapture()
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
                Button(action: {
                    callManager.clearAnnotations()
                    // Also send clear command to iPhone
                    if multipeerService.isConnected {
                        multipeerService.sendClearAnnotations()
                    }
                }) {
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

            // Flashlight button
            ControlButton(
                icon: isFlashlightOn ? "flashlight.on.fill" : "flashlight.off.fill",
                isActive: isFlashlightOn,
                action: toggleFlashlight
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

    private func setupAudioCallbacks() {
        // Handle incoming audio data from user
        multipeerService.onAudioDataReceived = { [self] audioData in
            audioService.playAudioData(audioData)
        }

        // Handle annotation updates with AR world positions from iPhone
        multipeerService.onAnnotationUpdated = { [self] updatedAnnotation in
            // Find and update the existing annotation with world position
            if let index = callManager.annotations.firstIndex(where: { $0.id == updatedAnnotation.id }) {
                callManager.annotations[index] = updatedAnnotation
                print("[Professional] ✅ Updated annotation \(updatedAnnotation.id) with world position: \(updatedAnnotation.worldPosition?.debugDescription ?? "none")")
            }
        }

        // Handle continuous annotation position updates for AR tracking
        multipeerService.onAnnotationPositionUpdated = { [self] id, normalizedX, normalizedY in
            // Update the annotation's position based on AR tracking from iPhone
            if let index = callManager.annotations.firstIndex(where: { $0.id == id }) {
                // Update the first point which represents the annotation's position
                if !callManager.annotations[index].points.isEmpty {
                    callManager.annotations[index].points[0] = AnnotationPoint(x: normalizedX, y: normalizedY)
                }
            }
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
        guard !isDrawingMode else { return }

        controlsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            withAnimation {
                showControls = false
            }
        }
    }

    private func toggleAudio() {
        isAudioEnabled.toggle()
        audioService.setMuted(!isAudioEnabled)
    }

    private func toggleFreeze() {
        if callManager.isVideoFrozen {
            callManager.isVideoFrozen = false
            // Clear frozen frame to resume live video
            multipeerService.frozenFrame = nil
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

    private func toggleFlashlight() {
        isFlashlightOn.toggle()
        if multipeerService.isConnected {
            multipeerService.sendToggleFlashlight(on: isFlashlightOn)
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
