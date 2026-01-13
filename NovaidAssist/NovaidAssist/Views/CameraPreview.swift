import SwiftUI
import AVFoundation

/// Camera preview view for displaying local camera feed
struct CameraPreviewView: UIViewRepresentable {
    @StateObject private var cameraManager = CameraManager()

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        cameraManager.setupCamera(in: view)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update if needed
    }
}

/// Camera manager for handling camera setup and preview
class CameraManager: NSObject, ObservableObject {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    @Published var isRunning = false
    @Published var error: String?

    func setupCamera(in view: UIView) {
        checkPermissions { [weak self] granted in
            guard granted else {
                self?.error = "Camera permission denied"
                return
            }

            DispatchQueue.main.async {
                self?.configureSession(in: view)
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

        // Get rear camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            error = "Rear camera not available"
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            self.error = "Could not configure camera input"
            return
        }

        // Create preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds

        view.layer.addSublayer(previewLayer)

        self.previewLayer = previewLayer
        self.captureSession = session

        // Start session on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.startRunning()
            DispatchQueue.main.async {
                self?.isRunning = true
            }
        }

        // Update preview layer frame when view resizes
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.previewLayer?.frame = view.bounds
        }
    }

    func stopCamera() {
        captureSession?.stopRunning()
        isRunning = false
    }

    deinit {
        stopCamera()
    }
}

/// Camera preview with stabilization overlay
struct StabilizedCameraPreview: View {
    @ObservedObject var stabilizer: VideoStabilizer

    var body: some View {
        GeometryReader { geometry in
            CameraPreviewView()
                .offset(x: stabilizer.currentOffset.x, y: stabilizer.currentOffset.y)
                .scaleEffect(1.05) // Slight zoom to hide edges
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
