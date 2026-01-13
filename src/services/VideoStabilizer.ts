import { StabilizationConfig, Point } from '../types';

/**
 * Video Stabilization Service
 *
 * Implements a software-based video stabilization algorithm using:
 * 1. Motion vector estimation
 * 2. Low-pass filtering for smooth motion
 * 3. Frame transformation based on accumulated motion
 *
 * This service processes frame data to reduce shakiness from handheld camera usage.
 */

interface MotionVector {
  x: number;
  y: number;
  timestamp: number;
}

interface TransformMatrix {
  translateX: number;
  translateY: number;
  scale: number;
  rotation: number;
}

export class VideoStabilizer {
  private config: StabilizationConfig;
  private motionHistory: MotionVector[] = [];
  private smoothedMotion: MotionVector = { x: 0, y: 0, timestamp: 0 };
  private accumulatedTransform: TransformMatrix = {
    translateX: 0,
    translateY: 0,
    scale: 1,
    rotation: 0,
  };

  // Kalman filter state for smooth motion estimation
  private kalmanState = {
    x: { estimate: 0, errorCovariance: 1 },
    y: { estimate: 0, errorCovariance: 1 },
  };

  // Kalman filter parameters
  private kalmanParams = {
    processNoise: 0.01,      // Q - process noise covariance
    measurementNoise: 0.1,   // R - measurement noise covariance
  };

  constructor(config?: Partial<StabilizationConfig>) {
    this.config = {
      enabled: config?.enabled ?? true,
      smoothingFactor: config?.smoothingFactor ?? 0.95,
      maxOffset: config?.maxOffset ?? 50,
    };
  }

  /**
   * Process accelerometer/gyroscope data for motion estimation
   */
  public processMotionData(
    accelerometerData: { x: number; y: number; z: number },
    gyroscopeData?: { x: number; y: number; z: number }
  ): TransformMatrix {
    if (!this.config.enabled) {
      return this.getIdentityTransform();
    }

    const currentTime = Date.now();

    // Calculate motion vector from sensor data
    const rawMotion: MotionVector = {
      x: accelerometerData.x * 10, // Scale factor for pixel displacement
      y: accelerometerData.y * 10,
      timestamp: currentTime,
    };

    // Apply Kalman filter for noise reduction
    const filteredMotion = this.applyKalmanFilter(rawMotion);

    // Add to motion history
    this.motionHistory.push(filteredMotion);

    // Keep only recent motion history (last 500ms)
    const historyWindow = 500;
    this.motionHistory = this.motionHistory.filter(
      (m) => currentTime - m.timestamp < historyWindow
    );

    // Calculate smoothed motion using exponential moving average
    this.smoothedMotion = this.calculateSmoothedMotion();

    // Calculate compensation transform
    return this.calculateCompensationTransform();
  }

  /**
   * Apply Kalman filter for single axis
   */
  private kalmanFilterUpdate(
    axis: 'x' | 'y',
    measurement: number
  ): number {
    const state = this.kalmanState[axis];
    const { processNoise, measurementNoise } = this.kalmanParams;

    // Prediction step
    const predictedEstimate = state.estimate;
    const predictedErrorCovariance = state.errorCovariance + processNoise;

    // Update step
    const kalmanGain = predictedErrorCovariance / (predictedErrorCovariance + measurementNoise);
    state.estimate = predictedEstimate + kalmanGain * (measurement - predictedEstimate);
    state.errorCovariance = (1 - kalmanGain) * predictedErrorCovariance;

    return state.estimate;
  }

  /**
   * Apply Kalman filter to motion vector
   */
  private applyKalmanFilter(motion: MotionVector): MotionVector {
    return {
      x: this.kalmanFilterUpdate('x', motion.x),
      y: this.kalmanFilterUpdate('y', motion.y),
      timestamp: motion.timestamp,
    };
  }

  /**
   * Calculate smoothed motion using exponential moving average
   */
  private calculateSmoothedMotion(): MotionVector {
    if (this.motionHistory.length === 0) {
      return { x: 0, y: 0, timestamp: Date.now() };
    }

    const alpha = 1 - this.config.smoothingFactor;
    let smoothedX = this.smoothedMotion.x;
    let smoothedY = this.smoothedMotion.y;

    // Apply EMA
    for (const motion of this.motionHistory) {
      smoothedX = alpha * motion.x + (1 - alpha) * smoothedX;
      smoothedY = alpha * motion.y + (1 - alpha) * smoothedY;
    }

    return {
      x: smoothedX,
      y: smoothedY,
      timestamp: Date.now(),
    };
  }

  /**
   * Calculate the compensation transform to stabilize video
   */
  private calculateCompensationTransform(): TransformMatrix {
    // Clamp values to prevent excessive compensation
    const clampedX = this.clamp(
      -this.smoothedMotion.x,
      -this.config.maxOffset,
      this.config.maxOffset
    );
    const clampedY = this.clamp(
      -this.smoothedMotion.y,
      -this.config.maxOffset,
      this.config.maxOffset
    );

    // Update accumulated transform with damping
    const dampingFactor = 0.1;
    this.accumulatedTransform.translateX =
      this.accumulatedTransform.translateX * (1 - dampingFactor) + clampedX * dampingFactor;
    this.accumulatedTransform.translateY =
      this.accumulatedTransform.translateY * (1 - dampingFactor) + clampedY * dampingFactor;

    return { ...this.accumulatedTransform };
  }

  /**
   * Get CSS-style transform string for applying stabilization
   */
  public getTransformStyle(): string {
    const { translateX, translateY, scale, rotation } = this.accumulatedTransform;
    return `translate(${translateX}px, ${translateY}px) scale(${scale}) rotate(${rotation}deg)`;
  }

  /**
   * Get transform values for React Native style
   */
  public getReactNativeTransform(): {
    transform: Array<{ translateX?: number; translateY?: number; scale?: number; rotate?: string }>;
  } {
    const { translateX, translateY, scale, rotation } = this.accumulatedTransform;
    return {
      transform: [
        { translateX },
        { translateY },
        { scale },
        { rotate: `${rotation}deg` },
      ],
    };
  }

  /**
   * Process frame-based motion estimation (optical flow alternative)
   * This is used when accelerometer data is not available
   */
  public estimateMotionFromFrames(
    previousFeaturePoints: Point[],
    currentFeaturePoints: Point[]
  ): TransformMatrix {
    if (!this.config.enabled || previousFeaturePoints.length === 0) {
      return this.getIdentityTransform();
    }

    // Calculate average displacement
    let totalDx = 0;
    let totalDy = 0;
    let validPoints = 0;

    const maxPoints = Math.min(previousFeaturePoints.length, currentFeaturePoints.length);

    for (let i = 0; i < maxPoints; i++) {
      const dx = currentFeaturePoints[i].x - previousFeaturePoints[i].x;
      const dy = currentFeaturePoints[i].y - previousFeaturePoints[i].y;

      // Filter out outliers (large motions are likely tracking errors)
      if (Math.abs(dx) < 100 && Math.abs(dy) < 100) {
        totalDx += dx;
        totalDy += dy;
        validPoints++;
      }
    }

    if (validPoints === 0) {
      return this.getIdentityTransform();
    }

    const avgDx = totalDx / validPoints;
    const avgDy = totalDy / validPoints;

    // Create motion vector and process it
    const motionVector: MotionVector = {
      x: avgDx,
      y: avgDy,
      timestamp: Date.now(),
    };

    // Apply filtering
    const filtered = this.applyKalmanFilter(motionVector);
    this.motionHistory.push(filtered);

    // Calculate smoothed motion
    this.smoothedMotion = this.calculateSmoothedMotion();

    return this.calculateCompensationTransform();
  }

  /**
   * Reset stabilization state
   */
  public reset(): void {
    this.motionHistory = [];
    this.smoothedMotion = { x: 0, y: 0, timestamp: 0 };
    this.accumulatedTransform = {
      translateX: 0,
      translateY: 0,
      scale: 1,
      rotation: 0,
    };
    this.kalmanState = {
      x: { estimate: 0, errorCovariance: 1 },
      y: { estimate: 0, errorCovariance: 1 },
    };
  }

  /**
   * Update configuration
   */
  public setConfig(config: Partial<StabilizationConfig>): void {
    this.config = { ...this.config, ...config };
  }

  /**
   * Enable or disable stabilization
   */
  public setEnabled(enabled: boolean): void {
    this.config.enabled = enabled;
    if (!enabled) {
      this.reset();
    }
  }

  /**
   * Get identity transform (no transformation)
   */
  private getIdentityTransform(): TransformMatrix {
    return {
      translateX: 0,
      translateY: 0,
      scale: 1,
      rotation: 0,
    };
  }

  /**
   * Clamp value between min and max
   */
  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  /**
   * Get current stabilization metrics for debugging
   */
  public getMetrics(): {
    motionHistoryLength: number;
    currentSmoothedMotion: MotionVector;
    currentTransform: TransformMatrix;
  } {
    return {
      motionHistoryLength: this.motionHistory.length,
      currentSmoothedMotion: { ...this.smoothedMotion },
      currentTransform: { ...this.accumulatedTransform },
    };
  }
}

export default VideoStabilizer;
