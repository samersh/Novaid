import { VideoStabilizer } from '../../src/services/VideoStabilizer';

describe('VideoStabilizer', () => {
  let stabilizer: VideoStabilizer;

  beforeEach(() => {
    stabilizer = new VideoStabilizer();
  });

  afterEach(() => {
    stabilizer.reset();
  });

  describe('initialization', () => {
    it('should create a new instance with default config', () => {
      expect(stabilizer).toBeDefined();
    });

    it('should create instance with custom config', () => {
      const customStabilizer = new VideoStabilizer({
        enabled: false,
        smoothingFactor: 0.8,
        maxOffset: 30,
      });
      expect(customStabilizer).toBeDefined();
    });
  });

  describe('processMotionData', () => {
    it('should return identity transform when disabled', () => {
      stabilizer.setEnabled(false);
      const result = stabilizer.processMotionData({ x: 1, y: 1, z: 1 });

      expect(result).toEqual({
        translateX: 0,
        translateY: 0,
        scale: 1,
        rotation: 0,
      });
    });

    it('should process accelerometer data and return transform', () => {
      const result = stabilizer.processMotionData({ x: 0.5, y: 0.3, z: 9.8 });

      expect(result).toHaveProperty('translateX');
      expect(result).toHaveProperty('translateY');
      expect(result).toHaveProperty('scale');
      expect(result).toHaveProperty('rotation');
    });

    it('should clamp transform values to max offset', () => {
      // Process multiple large motion values
      for (let i = 0; i < 100; i++) {
        stabilizer.processMotionData({ x: 10, y: 10, z: 9.8 });
      }

      const result = stabilizer.processMotionData({ x: 10, y: 10, z: 9.8 });

      expect(Math.abs(result.translateX)).toBeLessThanOrEqual(50);
      expect(Math.abs(result.translateY)).toBeLessThanOrEqual(50);
    });
  });

  describe('estimateMotionFromFrames', () => {
    it('should return identity transform when disabled', () => {
      stabilizer.setEnabled(false);
      const result = stabilizer.estimateMotionFromFrames(
        [{ x: 0, y: 0 }],
        [{ x: 10, y: 10 }]
      );

      expect(result).toEqual({
        translateX: 0,
        translateY: 0,
        scale: 1,
        rotation: 0,
      });
    });

    it('should return identity transform with empty previous points', () => {
      const result = stabilizer.estimateMotionFromFrames(
        [],
        [{ x: 10, y: 10 }]
      );

      expect(result).toEqual({
        translateX: 0,
        translateY: 0,
        scale: 1,
        rotation: 0,
      });
    });

    it('should estimate motion from feature points', () => {
      const prevPoints = [
        { x: 100, y: 100 },
        { x: 200, y: 200 },
        { x: 300, y: 300 },
      ];
      const currPoints = [
        { x: 105, y: 103 },
        { x: 205, y: 203 },
        { x: 305, y: 303 },
      ];

      const result = stabilizer.estimateMotionFromFrames(prevPoints, currPoints);

      expect(result).toHaveProperty('translateX');
      expect(result).toHaveProperty('translateY');
    });
  });

  describe('getTransformStyle', () => {
    it('should return CSS transform string', () => {
      stabilizer.processMotionData({ x: 0.1, y: 0.1, z: 9.8 });
      const style = stabilizer.getTransformStyle();

      expect(typeof style).toBe('string');
      expect(style).toContain('translate');
      expect(style).toContain('scale');
      expect(style).toContain('rotate');
    });
  });

  describe('getReactNativeTransform', () => {
    it('should return React Native transform array', () => {
      stabilizer.processMotionData({ x: 0.1, y: 0.1, z: 9.8 });
      const result = stabilizer.getReactNativeTransform();

      expect(result).toHaveProperty('transform');
      expect(Array.isArray(result.transform)).toBe(true);
      expect(result.transform.length).toBe(4);
    });
  });

  describe('reset', () => {
    it('should reset all state', () => {
      // Build up some state
      for (let i = 0; i < 10; i++) {
        stabilizer.processMotionData({ x: 1, y: 1, z: 9.8 });
      }

      stabilizer.reset();
      const metrics = stabilizer.getMetrics();

      expect(metrics.motionHistoryLength).toBe(0);
      expect(metrics.currentSmoothedMotion).toEqual({ x: 0, y: 0, timestamp: 0 });
    });
  });

  describe('setEnabled', () => {
    it('should enable stabilization', () => {
      stabilizer.setEnabled(true);
      const result = stabilizer.processMotionData({ x: 1, y: 1, z: 9.8 });

      // When enabled, transform should be calculated
      expect(result).toBeDefined();
    });

    it('should disable stabilization and reset state', () => {
      // Build up state
      stabilizer.processMotionData({ x: 1, y: 1, z: 9.8 });

      stabilizer.setEnabled(false);
      const result = stabilizer.processMotionData({ x: 1, y: 1, z: 9.8 });

      expect(result).toEqual({
        translateX: 0,
        translateY: 0,
        scale: 1,
        rotation: 0,
      });
    });
  });

  describe('getMetrics', () => {
    it('should return current stabilization metrics', () => {
      const metrics = stabilizer.getMetrics();

      expect(metrics).toHaveProperty('motionHistoryLength');
      expect(metrics).toHaveProperty('currentSmoothedMotion');
      expect(metrics).toHaveProperty('currentTransform');
    });
  });
});
