import SwiftUI
import AVFoundation

/// Camera preview view for displaying local camera feed and optionally sending frames
struct CameraPreviewView: UIViewRepresentable {
    var useRearCamera: Bool = true
    var sendFrames: Bool = false  // Whether to send frames via MultipeerService

    func makeCoordinator() -> Coordinator {
        Coordinator(useRearCamera: useRearCamera, sendFrames: sendFrames)
    }

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Start camera when view appears
        if !context.coordinator.isRunning {
            context.coordinator.startCamera(in: uiView)
        }
    }

    class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var captureSession: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var videoOutput: AVCaptureVideoDataOutput?
        var isRunning = false
        let useRearCamera: Bool
        let sendFrames: Bool
        private let videoQueue = DispatchQueue(label: "com.novaid.videoQueue")

        init(useRearCamera: Bool, sendFrames: Bool) {
            self.useRearCamera = useRearCamera
            self.sendFrames = sendFrames
            super.init()
        }

        func startCamera(in view: UIView) {
            guard !isRunning else { return }

            checkPermissions { [weak self] granted in
                guard granted, let self = self else {
                    print("[Camera] Permission denied")
                    return
                }

                DispatchQueue.main.async {
                    self.configureSession(in: view)
                }
            }
        }

        private func checkPermissions(completion: @escaping (Bool) -> Void) {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                completion(true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    completion(granted)
                }
            default:
                completion(false)
            }
        }

        private func configureSession(in view: UIView) {
            let session = AVCaptureSession()
            session.sessionPreset = .medium  // Lower resolution for faster transmission

            // Get camera based on preference
            let position: AVCaptureDevice.Position = useRearCamera ? .back : .front
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                    ?? AVCaptureDevice.default(for: .video) else {
                print("[Camera] No camera available")
                return
            }

            print("[Camera] Using camera: \(camera.localizedName), position: \(position == .back ? "rear" : "front")")

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
            } catch {
                print("[Camera] Could not configure camera input: \(error)")
                return
            }

            // Add video output for frame capture if needed
            if sendFrames {
                let output = AVCaptureVideoDataOutput()
                output.setSampleBufferDelegate(self, queue: videoQueue)
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                if session.canAddOutput(output) {
                    session.addOutput(output)
                }
                self.videoOutput = output
            }

            // Create preview layer
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.connection?.videoRotationAngle = 90

            // Important: Set frame to view bounds
            previewLayer.frame = view.layer.bounds

            view.layer.insertSublayer(previewLayer, at: 0)

            self.previewLayer = previewLayer
            self.captureSession = session

            // Start session on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                session.startRunning()
                DispatchQueue.main.async {
                    self?.isRunning = true
                    print("[Camera] Session started running, sendFrames: \(self?.sendFrames ?? false)")
                }
            }
        }

        // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard sendFrames else { return }

            // Convert sample buffer to UIImage
            guard let image = imageFromSampleBuffer(sampleBuffer) else { return }

            // Send frame via MultipeerService
            Task { @MainActor in
                MultipeerService.shared.sendVideoFrame(image)
            }
        }

        private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

            CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

            // Rotate image to correct orientation
            let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

            // Resize to reduce data size
            let targetSize = CGSize(width: 480, height: 640)
            UIGraphicsBeginImageContextWithOptions(targetSize, true, 1.0)
            image.draw(in: CGRect(origin: .zero, size: targetSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            return resizedImage
        }

        func stopCamera() {
            captureSession?.stopRunning()
            previewLayer?.removeFromSuperlayer()
            isRunning = false
        }
    }
}

/// Custom UIView that automatically updates preview layer frame
class CameraPreviewUIView: UIView {
    var coordinator: CameraPreviewView.Coordinator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update preview layer frame when view resizes
        coordinator?.previewLayer?.frame = bounds
    }

    deinit {
        coordinator?.stopCamera()
    }
}

/// View to display received video frames from remote peer
struct RemoteVideoView: View {
    @ObservedObject var multipeerService = MultipeerService.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                // Show frozen frame if available, otherwise show live frame
                if let frame = multipeerService.frozenFrame ?? multipeerService.receivedVideoFrame {
                    Image(uiImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(2)

                        Text("Waiting for video...")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }

    /// Determine content mode based on device orientation
    /// Landscape: fill screen without stretching
    /// Portrait: fit to show full frame
    private var contentMode: ContentMode {
        let orientation = multipeerService.receivedDeviceOrientation.state

        switch orientation {
        case .landscapeLeft, .landscapeRight:
            return .fill  // Full screen for landscape
        case .portrait, .portraitUpsideDown, .unknown:
            return .fit   // Show full frame for portrait
        }
    }

    private func calculateVideoFrame(containerSize: CGSize, aspectRatio: CGFloat) -> CGSize {
        let containerAspect = containerSize.width / containerSize.height

        if containerAspect > aspectRatio {
            // Container is wider - fit to height
            let height = containerSize.height
            let width = height * aspectRatio
            return CGSize(width: width, height: height)
        } else {
            // Container is taller - fit to width
            let width = containerSize.width
            let height = width / aspectRatio
            return CGSize(width: width, height: height)
        }
    }
}

/// Helper to get video frame bounds for annotation overlay
struct VideoFrameHelper {
    static func calculateVideoFrame(containerSize: CGSize, aspectRatio: CGFloat = 16.0 / 9.0) -> CGRect {
        let containerAspect = containerSize.width / containerSize.height

        var frameSize: CGSize
        if containerAspect > aspectRatio {
            let height = containerSize.height
            let width = height * aspectRatio
            frameSize = CGSize(width: width, height: height)
        } else {
            let width = containerSize.width
            let height = width / aspectRatio
            frameSize = CGSize(width: width, height: height)
        }

        let x = (containerSize.width - frameSize.width) / 2
        let y = (containerSize.height - frameSize.height) / 2

        return CGRect(origin: CGPoint(x: x, y: y), size: frameSize)
    }
}

/// Camera preview with stabilization overlay
struct StabilizedCameraPreview: View {
    @ObservedObject var stabilizer: VideoStabilizer
    var useRearCamera: Bool = true
    var sendFrames: Bool = false

    var body: some View {
        GeometryReader { geometry in
            CameraPreviewView(useRearCamera: useRearCamera, sendFrames: sendFrames)
                .offset(x: stabilizer.currentOffset.x, y: stabilizer.currentOffset.y)
                .scaleEffect(1.05) // Slight zoom to hide edges during stabilization
                .clipped()
        }
        .onAppear {
            stabilizer.startStabilization()
        }
        .onDisappear {
            stabilizer.stopStabilization()
        }
    }
}

#Preview {
    CameraPreviewView()
}
