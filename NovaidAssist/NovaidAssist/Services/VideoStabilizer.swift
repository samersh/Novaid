import Foundation
import CoreMotion
import UIKit
import Accelerate

/// Video stabilization service using Kalman filtering and motion data
class VideoStabilizer: ObservableObject {
    // MARK: - Configuration
    struct Config {
        var enabled: Bool = true
        var smoothingFactor: Float = 0.95
        var maxOffset: Float = 50.0
        var kalmanProcessNoise: Float = 0.01
        var kalmanMeasurementNoise: Float = 0.1
    }

    // MARK: - Published Properties
    @Published var config = Config()
    @Published var currentOffset: CGPoint = .zero
    @Published var isStabilizing: Bool = false

    // MARK: - Private Properties
    private let motionManager = CMMotionManager()
    private var kalmanFilterX: KalmanFilter
    private var kalmanFilterY: KalmanFilter
    private var kalmanFilterRotation: KalmanFilter

    private var previousAcceleration: CMAcceleration?
    private var velocityX: Float = 0
    private var velocityY: Float = 0

    private var stabilizationQueue = DispatchQueue(label: "com.novaid.stabilization", qos: .userInteractive)

    // MARK: - Initialization

    init() {
        kalmanFilterX = KalmanFilter(processNoise: 0.01, measurementNoise: 0.1)
        kalmanFilterY = KalmanFilter(processNoise: 0.01, measurementNoise: 0.1)
        kalmanFilterRotation = KalmanFilter(processNoise: 0.005, measurementNoise: 0.05)
    }

    // MARK: - Start/Stop

    func startStabilization() {
        guard config.enabled, motionManager.isAccelerometerAvailable else {
            return
        }

        isStabilizing = true

        // Configure motion updates
        motionManager.accelerometerUpdateInterval = 1.0 / 60.0 // 60 Hz
        motionManager.gyroUpdateInterval = 1.0 / 60.0

        // Start accelerometer
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let acceleration = data?.acceleration else { return }
            self.processAccelerometerData(acceleration)
        }

        // Start gyroscope for rotation stabilization
        if motionManager.isGyroAvailable {
            motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
                guard let self = self, let rotation = data?.rotationRate else { return }
                self.processGyroData(rotation)
            }
        }
    }

    func stopStabilization() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        isStabilizing = false
        resetFilters()
    }

    // MARK: - Motion Processing

    private func processAccelerometerData(_ acceleration: CMAcceleration) {
        stabilizationQueue.async { [weak self] in
            guard let self = self else { return }

            // Apply Kalman filter to smooth acceleration
            let filteredX = self.kalmanFilterX.update(measurement: Float(acceleration.x))
            let filteredY = self.kalmanFilterY.update(measurement: Float(acceleration.y))

            // Calculate velocity (integration of acceleration)
            let dt: Float = 1.0 / 60.0
            self.velocityX += filteredX * dt
            self.velocityY += filteredY * dt

            // Apply damping to prevent drift
            let damping: Float = 0.95
            self.velocityX *= damping
            self.velocityY *= damping

            // Calculate compensation offset
            var offsetX = -self.velocityX * self.config.smoothingFactor * 100
            var offsetY = -self.velocityY * self.config.smoothingFactor * 100

            // Clamp to max offset
            offsetX = max(-self.config.maxOffset, min(self.config.maxOffset, offsetX))
            offsetY = max(-self.config.maxOffset, min(self.config.maxOffset, offsetY))

            DispatchQueue.main.async {
                self.currentOffset = CGPoint(x: CGFloat(offsetX), y: CGFloat(offsetY))
            }
        }
    }

    private func processGyroData(_ rotation: CMRotationRate) {
        // Process rotation for tilt compensation
        let filteredRotation = kalmanFilterRotation.update(measurement: Float(rotation.z))
        // Use for additional stabilization if needed
        _ = filteredRotation
    }

    // MARK: - Frame Processing

    /// Apply stabilization transform to a video frame
    func stabilizationTransform() -> CGAffineTransform {
        guard config.enabled else {
            return .identity
        }

        return CGAffineTransform(translationX: currentOffset.x, y: currentOffset.y)
    }

    /// Process a video frame with stabilization
    func processFrame(_ image: UIImage) -> UIImage {
        guard config.enabled else {
            return image
        }

        // Apply stabilization transform
        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let transform = stabilizationTransform()

            // Scale slightly to hide black edges from translation
            let scale: CGFloat = 1.05
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: -size.width / 2, y: -size.height / 2)

            context.cgContext.concatenate(transform)
            image.draw(at: .zero)
        }
    }

    // MARK: - Reset

    func resetFilters() {
        kalmanFilterX = KalmanFilter(processNoise: config.kalmanProcessNoise, measurementNoise: config.kalmanMeasurementNoise)
        kalmanFilterY = KalmanFilter(processNoise: config.kalmanProcessNoise, measurementNoise: config.kalmanMeasurementNoise)
        kalmanFilterRotation = KalmanFilter(processNoise: 0.005, measurementNoise: 0.05)
        velocityX = 0
        velocityY = 0
        currentOffset = .zero
    }

    // MARK: - Configuration

    func updateConfig(_ newConfig: Config) {
        config = newConfig
        kalmanFilterX = KalmanFilter(processNoise: newConfig.kalmanProcessNoise, measurementNoise: newConfig.kalmanMeasurementNoise)
        kalmanFilterY = KalmanFilter(processNoise: newConfig.kalmanProcessNoise, measurementNoise: newConfig.kalmanMeasurementNoise)
    }
}

// MARK: - Kalman Filter

/// Simple 1D Kalman filter for smoothing sensor data
class KalmanFilter {
    private var q: Float // Process noise
    private var r: Float // Measurement noise
    private var x: Float = 0 // Estimated value
    private var p: Float = 1 // Estimation error covariance
    private var k: Float = 0 // Kalman gain

    init(processNoise: Float = 0.01, measurementNoise: Float = 0.1) {
        self.q = processNoise
        self.r = measurementNoise
    }

    func update(measurement: Float) -> Float {
        // Prediction update
        p = p + q

        // Measurement update
        k = p / (p + r)
        x = x + k * (measurement - x)
        p = (1 - k) * p

        return x
    }

    func reset() {
        x = 0
        p = 1
        k = 0
    }
}

// MARK: - Motion Smoother

/// Additional motion smoothing using exponential moving average
class MotionSmoother {
    private var smoothedValue: Float = 0
    private let alpha: Float

    init(smoothingFactor: Float = 0.1) {
        self.alpha = smoothingFactor
    }

    func smooth(_ value: Float) -> Float {
        smoothedValue = alpha * value + (1 - alpha) * smoothedValue
        return smoothedValue
    }

    func reset() {
        smoothedValue = 0
    }
}
