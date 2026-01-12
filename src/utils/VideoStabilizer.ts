import { StabilizationConfig, FrameTransform, Point } from '../types';

interface MotionVector {
  dx: number;
  dy: number;
  confidence: number;
}

interface StabilizationState {
  smoothedTransform: FrameTransform;
  previousTransform: FrameTransform;
  motionHistory: MotionVector[];
  frameCount: number;
}

const DEFAULT_CONFIG: StabilizationConfig = {
  enabled: true,
  smoothingFactor: 0.9, // Higher = smoother but more latency
  maxCorrection: 50, // Maximum pixels to correct
};

export class VideoStabilizer {
  private config: StabilizationConfig;
  private state: StabilizationState;
  private readonly historySize: number = 30;

  constructor(config: Partial<StabilizationConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.state = this.initializeState();
  }

  private initializeState(): StabilizationState {
    return {
      smoothedTransform: { translateX: 0, translateY: 0, rotation: 0, scale: 1 },
      previousTransform: { translateX: 0, translateY: 0, rotation: 0, scale: 1 },
      motionHistory: [],
      frameCount: 0,
    };
  }

  /**
   * Estimates motion between frames using optical flow approximation
   * In a real implementation, this would use native CV libraries
   * This is a simplified version for demonstration
   */
  estimateMotion(
    currentFrame: ImageData | null,
    previousFrame: ImageData | null
  ): MotionVector {
    // Simplified motion estimation
    // In production, use react-native-opencv or similar for proper optical flow
    if (!currentFrame || !previousFrame) {
      return { dx: 0, dy: 0, confidence: 0 };
    }

    // Placeholder for actual motion estimation
    // This would typically use:
    // 1. Feature detection (FAST, ORB, etc.)
    // 2. Feature matching between frames
    // 3. Motion model fitting (affine, homography)
    return {
      dx: 0,
      dy: 0,
      confidence: 1,
    };
  }

  /**
   * Applies low-pass filter to smooth motion
   */
  private smoothMotion(motion: MotionVector): MotionVector {
    this.state.motionHistory.push(motion);

    if (this.state.motionHistory.length > this.historySize) {
      this.state.motionHistory.shift();
    }

    // Calculate weighted average of motion history
    let totalWeight = 0;
    let smoothedDx = 0;
    let smoothedDy = 0;

    this.state.motionHistory.forEach((m, index) => {
      const weight = (index + 1) * m.confidence;
      smoothedDx += m.dx * weight;
      smoothedDy += m.dy * weight;
      totalWeight += weight;
    });

    if (totalWeight > 0) {
      smoothedDx /= totalWeight;
      smoothedDy /= totalWeight;
    }

    return {
      dx: smoothedDx,
      dy: smoothedDy,
      confidence: motion.confidence,
    };
  }

  /**
   * Calculates the stabilization transform for the current frame
   */
  calculateStabilizationTransform(motion: MotionVector): FrameTransform {
    if (!this.config.enabled) {
      return { translateX: 0, translateY: 0, rotation: 0, scale: 1 };
    }

    const smoothedMotion = this.smoothMotion(motion);

    // Calculate correction (opposite of motion to stabilize)
    let correctionX = -smoothedMotion.dx * this.config.smoothingFactor;
    let correctionY = -smoothedMotion.dy * this.config.smoothingFactor;

    // Clamp correction to max values
    correctionX = Math.max(
      -this.config.maxCorrection,
      Math.min(this.config.maxCorrection, correctionX)
    );
    correctionY = Math.max(
      -this.config.maxCorrection,
      Math.min(this.config.maxCorrection, correctionY)
    );

    // Apply exponential smoothing
    const alpha = 1 - this.config.smoothingFactor;
    const newTransform: FrameTransform = {
      translateX:
        alpha * correctionX +
        (1 - alpha) * this.state.smoothedTransform.translateX,
      translateY:
        alpha * correctionY +
        (1 - alpha) * this.state.smoothedTransform.translateY,
      rotation: 0, // Can be extended for rotation stabilization
      scale: 1, // Can be extended for zoom stabilization
    };

    this.state.previousTransform = this.state.smoothedTransform;
    this.state.smoothedTransform = newTransform;
    this.state.frameCount++;

    return newTransform;
  }

  /**
   * Generates transform style for React Native
   */
  getTransformStyle(transform: FrameTransform): object {
    return {
      transform: [
        { translateX: transform.translateX },
        { translateY: transform.translateY },
        { rotate: `${transform.rotation}deg` },
        { scale: transform.scale },
      ],
    };
  }

  /**
   * Applies stabilization to a point (for annotation mapping)
   */
  stabilizePoint(point: Point, transform: FrameTransform): Point {
    return {
      x: point.x + transform.translateX,
      y: point.y + transform.translateY,
    };
  }

  /**
   * Inverse stabilization for mapping screen points to video coordinates
   */
  destabilizePoint(point: Point, transform: FrameTransform): Point {
    return {
      x: point.x - transform.translateX,
      y: point.y - transform.translateY,
    };
  }

  /**
   * Resets the stabilizer state
   */
  reset(): void {
    this.state = this.initializeState();
  }

  /**
   * Updates stabilizer configuration
   */
  updateConfig(config: Partial<StabilizationConfig>): void {
    this.config = { ...this.config, ...config };
  }

  /**
   * Gets current configuration
   */
  getConfig(): StabilizationConfig {
    return { ...this.config };
  }

  /**
   * Gets stabilization statistics
   */
  getStats(): {
    frameCount: number;
    averageCorrection: Point;
    isStable: boolean;
  } {
    const avgCorrection: Point = { x: 0, y: 0 };

    if (this.state.motionHistory.length > 0) {
      this.state.motionHistory.forEach((m) => {
        avgCorrection.x += Math.abs(m.dx);
        avgCorrection.y += Math.abs(m.dy);
      });
      avgCorrection.x /= this.state.motionHistory.length;
      avgCorrection.y /= this.state.motionHistory.length;
    }

    const isStable =
      avgCorrection.x < this.config.maxCorrection * 0.1 &&
      avgCorrection.y < this.config.maxCorrection * 0.1;

    return {
      frameCount: this.state.frameCount,
      averageCorrection: avgCorrection,
      isStable,
    };
  }
}

// Singleton instance
export const videoStabilizer = new VideoStabilizer();

// Software-based stabilization using gyroscope data
export class GyroStabilizer {
  private gyroData: { x: number; y: number; z: number; timestamp: number }[] = [];
  private readonly maxHistory = 30;
  private accumulatedRotation = { x: 0, y: 0, z: 0 };

  /**
   * Process gyroscope reading
   */
  processGyroReading(x: number, y: number, z: number, timestamp: number): void {
    const reading = { x, y, z, timestamp };
    this.gyroData.push(reading);

    if (this.gyroData.length > this.maxHistory) {
      this.gyroData.shift();
    }

    // Integrate angular velocity to get rotation
    if (this.gyroData.length > 1) {
      const prev = this.gyroData[this.gyroData.length - 2];
      const dt = (timestamp - prev.timestamp) / 1000; // Convert to seconds

      this.accumulatedRotation.x += x * dt;
      this.accumulatedRotation.y += y * dt;
      this.accumulatedRotation.z += z * dt;
    }
  }

  /**
   * Get compensation transform based on gyro data
   */
  getCompensationTransform(): FrameTransform {
    // Convert accumulated rotation to screen translation
    // This is simplified - real implementation would use proper camera model
    const sensitivity = 10; // Pixels per radian

    return {
      translateX: -this.accumulatedRotation.y * sensitivity,
      translateY: this.accumulatedRotation.x * sensitivity,
      rotation: -this.accumulatedRotation.z * (180 / Math.PI),
      scale: 1,
    };
  }

  /**
   * Reset accumulated rotation
   */
  reset(): void {
    this.gyroData = [];
    this.accumulatedRotation = { x: 0, y: 0, z: 0 };
  }
}

export const gyroStabilizer = new GyroStabilizer();
