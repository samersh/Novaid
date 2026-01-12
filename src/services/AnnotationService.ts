import { v4 as uuidv4 } from 'uuid';
import { Annotation, AnnotationType, Point, AnnotationFrame } from '../types';

type AnnotationCallback = (annotations: Annotation[]) => void;
type FrameCallback = (frame: AnnotationFrame | null) => void;

const DEFAULT_COLORS = [
  '#FF0000', // Red
  '#00FF00', // Green
  '#0000FF', // Blue
  '#FFFF00', // Yellow
  '#FF00FF', // Magenta
  '#00FFFF', // Cyan
  '#FFA500', // Orange
  '#FFFFFF', // White
];

const DEFAULT_STROKE_WIDTHS = [2, 4, 6, 8, 10];

export class AnnotationService {
  private annotations: Annotation[] = [];
  private frozenFrame: AnnotationFrame | null = null;
  private annotationCallbacks: Set<AnnotationCallback> = new Set();
  private frameCallbacks: Set<FrameCallback> = new Set();
  private currentTool: AnnotationType = 'freehand';
  private currentColor: string = DEFAULT_COLORS[0];
  private currentStrokeWidth: number = DEFAULT_STROKE_WIDTHS[1];
  private isDrawing: boolean = false;
  private currentPath: Point[] = [];

  /**
   * Start drawing
   */
  startDrawing(point: Point): void {
    this.isDrawing = true;
    this.currentPath = [point];
  }

  /**
   * Continue drawing
   */
  continueDrawing(point: Point): void {
    if (!this.isDrawing) return;
    this.currentPath.push(point);
  }

  /**
   * End drawing and create annotation
   */
  endDrawing(): Annotation | null {
    if (!this.isDrawing || this.currentPath.length === 0) {
      this.isDrawing = false;
      this.currentPath = [];
      return null;
    }

    const annotation = this.createAnnotation(this.currentTool, this.currentPath);
    this.isDrawing = false;
    this.currentPath = [];

    this.addAnnotation(annotation);
    return annotation;
  }

  /**
   * Create an annotation object
   */
  createAnnotation(
    type: AnnotationType,
    points: Point[],
    options?: {
      color?: string;
      strokeWidth?: number;
      text?: string;
      duration?: number;
    }
  ): Annotation {
    return {
      id: uuidv4(),
      type,
      points: this.processPoints(type, points),
      color: options?.color || this.currentColor,
      strokeWidth: options?.strokeWidth || this.currentStrokeWidth,
      text: options?.text,
      timestamp: Date.now(),
      duration: options?.duration,
    };
  }

  /**
   * Process points based on annotation type
   */
  private processPoints(type: AnnotationType, points: Point[]): Point[] {
    if (points.length === 0) return points;

    switch (type) {
      case 'line':
      case 'arrow':
        // Keep only first and last points
        return points.length >= 2
          ? [points[0], points[points.length - 1]]
          : points;

      case 'circle':
      case 'rectangle':
        // Keep only two corner points
        return points.length >= 2
          ? [points[0], points[points.length - 1]]
          : points;

      case 'pointer':
        // Single point
        return [points[points.length - 1]];

      case 'freehand':
      case 'text':
      default:
        // Keep all points, but simplify if too many
        return this.simplifyPath(points, 2);
    }
  }

  /**
   * Simplify path using Ramer-Douglas-Peucker algorithm
   */
  private simplifyPath(points: Point[], epsilon: number): Point[] {
    if (points.length <= 2) return points;

    // Find the point with maximum distance from the line between first and last
    let maxDistance = 0;
    let maxIndex = 0;

    const start = points[0];
    const end = points[points.length - 1];

    for (let i = 1; i < points.length - 1; i++) {
      const distance = this.perpendicularDistance(points[i], start, end);
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    if (maxDistance > epsilon) {
      // Recursive simplification
      const left = this.simplifyPath(points.slice(0, maxIndex + 1), epsilon);
      const right = this.simplifyPath(points.slice(maxIndex), epsilon);

      return [...left.slice(0, -1), ...right];
    }

    return [start, end];
  }

  /**
   * Calculate perpendicular distance from point to line
   */
  private perpendicularDistance(point: Point, lineStart: Point, lineEnd: Point): number {
    const dx = lineEnd.x - lineStart.x;
    const dy = lineEnd.y - lineStart.y;

    if (dx === 0 && dy === 0) {
      return Math.sqrt(
        Math.pow(point.x - lineStart.x, 2) + Math.pow(point.y - lineStart.y, 2)
      );
    }

    const t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) /
              (dx * dx + dy * dy);

    const nearestX = lineStart.x + t * dx;
    const nearestY = lineStart.y + t * dy;

    return Math.sqrt(
      Math.pow(point.x - nearestX, 2) + Math.pow(point.y - nearestY, 2)
    );
  }

  /**
   * Add an annotation
   */
  addAnnotation(annotation: Annotation): void {
    this.annotations.push(annotation);
    this.notifyAnnotationCallbacks();
  }

  /**
   * Remove an annotation by ID
   */
  removeAnnotation(id: string): void {
    this.annotations = this.annotations.filter((a) => a.id !== id);
    this.notifyAnnotationCallbacks();
  }

  /**
   * Clear all annotations
   */
  clearAnnotations(): void {
    this.annotations = [];
    this.notifyAnnotationCallbacks();
  }

  /**
   * Get all annotations
   */
  getAnnotations(): Annotation[] {
    return [...this.annotations];
  }

  /**
   * Freeze frame with current annotations
   */
  freezeFrame(frameData?: string): AnnotationFrame {
    this.frozenFrame = {
      id: uuidv4(),
      frameTimestamp: Date.now(),
      annotations: [...this.annotations],
      isFrozen: true,
    };

    this.notifyFrameCallbacks();
    return this.frozenFrame;
  }

  /**
   * Resume from frozen frame
   */
  resumeFrame(): void {
    if (this.frozenFrame) {
      // Annotations from frozen frame are preserved
      this.annotations = [...this.frozenFrame.annotations];
    }
    this.frozenFrame = null;
    this.notifyFrameCallbacks();
  }

  /**
   * Check if frame is frozen
   */
  isFrozen(): boolean {
    return this.frozenFrame !== null;
  }

  /**
   * Get frozen frame
   */
  getFrozenFrame(): AnnotationFrame | null {
    return this.frozenFrame;
  }

  /**
   * Set current drawing tool
   */
  setTool(tool: AnnotationType): void {
    this.currentTool = tool;
  }

  /**
   * Get current drawing tool
   */
  getTool(): AnnotationType {
    return this.currentTool;
  }

  /**
   * Set current color
   */
  setColor(color: string): void {
    this.currentColor = color;
  }

  /**
   * Get current color
   */
  getColor(): string {
    return this.currentColor;
  }

  /**
   * Set stroke width
   */
  setStrokeWidth(width: number): void {
    this.currentStrokeWidth = width;
  }

  /**
   * Get stroke width
   */
  getStrokeWidth(): number {
    return this.currentStrokeWidth;
  }

  /**
   * Get available colors
   */
  getAvailableColors(): string[] {
    return [...DEFAULT_COLORS];
  }

  /**
   * Get available stroke widths
   */
  getAvailableStrokeWidths(): number[] {
    return [...DEFAULT_STROKE_WIDTHS];
  }

  /**
   * Register callback for annotation updates
   */
  onAnnotationsChange(callback: AnnotationCallback): () => void {
    this.annotationCallbacks.add(callback);
    return () => this.annotationCallbacks.delete(callback);
  }

  /**
   * Register callback for frame updates
   */
  onFrameChange(callback: FrameCallback): () => void {
    this.frameCallbacks.add(callback);
    return () => this.frameCallbacks.delete(callback);
  }

  private notifyAnnotationCallbacks(): void {
    const annotations = this.getAnnotations();
    this.annotationCallbacks.forEach((callback) => callback(annotations));
  }

  private notifyFrameCallbacks(): void {
    this.frameCallbacks.forEach((callback) => callback(this.frozenFrame));
  }

  /**
   * Create a pointer annotation that expires after duration
   */
  createPointer(point: Point, duration: number = 3000): Annotation {
    const pointer = this.createAnnotation('pointer', [point], {
      duration,
      color: '#FF0000',
      strokeWidth: 20,
    });

    this.addAnnotation(pointer);

    // Auto-remove after duration
    setTimeout(() => {
      this.removeAnnotation(pointer.id);
    }, duration);

    return pointer;
  }

  /**
   * Create animated arrow sequence
   */
  createAnimatedArrow(
    from: Point,
    to: Point,
    duration: number = 1000
  ): Annotation {
    const arrow = this.createAnnotation('arrow', [from, to], {
      duration,
    });

    this.addAnnotation(arrow);

    // Auto-remove after duration (optional)
    // setTimeout(() => this.removeAnnotation(arrow.id), duration);

    return arrow;
  }

  /**
   * Serialize annotations for transmission
   */
  serialize(): string {
    return JSON.stringify({
      annotations: this.annotations,
      frozenFrame: this.frozenFrame,
    });
  }

  /**
   * Deserialize received annotations
   */
  deserialize(data: string): void {
    try {
      const parsed = JSON.parse(data);
      if (parsed.annotations) {
        this.annotations = parsed.annotations;
        this.notifyAnnotationCallbacks();
      }
      if (parsed.frozenFrame !== undefined) {
        this.frozenFrame = parsed.frozenFrame;
        this.notifyFrameCallbacks();
      }
    } catch (error) {
      console.error('Failed to deserialize annotations:', error);
    }
  }
}

export const annotationService = new AnnotationService();
