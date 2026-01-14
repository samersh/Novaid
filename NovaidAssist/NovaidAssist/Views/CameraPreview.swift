import SwiftUI
import AVFoundation

/// Camera preview view for displaying local camera feed
struct CameraPreviewView: UIViewRepresentable {
    var useRearCamera: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(useRearCamera: useRearCamera)
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

    class Coordinator: NSObject {
        var captureSession: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var isRunning = false
        let useRearCamera: Bool

        init(useRearCamera: Bool) {
            self.useRearCamera = useRearCamera
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
            session.sessionPreset = .high

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
                    print("[Camera] Session started running")
                }
            }
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

/// Camera preview with stabilization overlay
struct StabilizedCameraPreview: View {
    @ObservedObject var stabilizer: VideoStabilizer
    var useRearCamera: Bool = true

    var body: some View {
        GeometryReader { geometry in
            CameraPreviewView(useRearCamera: useRearCamera)
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
