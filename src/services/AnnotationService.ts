import { Annotation, AnnotationType, Point } from '../types';
import { EventEmitter } from '../utils/EventEmitter';

/**
 * Annotation Service
 *
 * Manages AR annotations for remote assistance including:
 * - Drawing paths
 * - Pointers/markers
 * - Arrows
 * - Circles/highlights
 * - Text annotations
 * - Animated elements (pulse, bounce, highlight)
 */

export class AnnotationService extends EventEmitter {
  private annotations: Map<string, Annotation> = new Map();
  private currentAnnotation: Annotation | null = null;
  private defaultColor: string = '#FF0000';
  private defaultStrokeWidth: number = 4;

  /**
   * Generate unique annotation ID
   */
  private generateId(): string {
    return `ann_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Start a new drawing annotation
   */
  public startDrawing(point: Point, color?: string, strokeWidth?: number): Annotation {
    const annotation: Annotation = {
      id: this.generateId(),
      type: 'drawing',
      points: [point],
      color: color || this.defaultColor,
      strokeWidth: strokeWidth || this.defaultStrokeWidth,
      timestamp: Date.now(),
      isComplete: false,
    };

    this.currentAnnotation = annotation;
    this.annotations.set(annotation.id, annotation);
    this.emit('annotationStarted', annotation);

    return annotation;
  }

  /**
   * Add point to current drawing
   */
  public addDrawingPoint(point: Point): Annotation | null {
    if (!this.currentAnnotation || this.currentAnnotation.type !== 'drawing') {
      return null;
    }

    this.currentAnnotation.points.push(point);
    this.annotations.set(this.currentAnnotation.id, this.currentAnnotation);
    this.emit('annotationUpdated', this.currentAnnotation);

    return this.currentAnnotation;
  }

  /**
   * End current drawing
   */
  public endDrawing(): Annotation | null {
    if (!this.currentAnnotation) {
      return null;
    }

    this.currentAnnotation.isComplete = true;
    this.annotations.set(this.currentAnnotation.id, this.currentAnnotation);
    this.emit('annotationCompleted', this.currentAnnotation);

    const completed = this.currentAnnotation;
    this.currentAnnotation = null;

    return completed;
  }

  /**
   * Create a pointer annotation
   */
  public createPointer(point: Point, color?: string): Annotation {
    const annotation: Annotation = {
      id: this.generateId(),
      type: 'pointer',
      points: [point],
      color: color || this.defaultColor,
      strokeWidth: this.defaultStrokeWidth,
      animationType: 'pulse',
      timestamp: Date.now(),
      isComplete: true,
    };

    this.annotations.set(annotation.id, annotation);
    this.emit('annotationCreated', annotation);

    return annotation;
  }

  /**
   * Create an arrow annotation
   */
  public createArrow(startPoint: Point, endPoint: Point, color?: string, strokeWidth?: number): Annotation {
    const annotation: Annotation = {
      id: this.generateId(),
      type: 'arrow',
      points: [startPoint, endPoint],
      color: color || this.defaultColor,
      strokeWidth: strokeWidth || this.defaultStrokeWidth,
      timestamp: Date.now(),
      isComplete: true,
    };

    this.annotations.set(annotation.id, annotation);
    this.emit('annotationCreated', annotation);

    return annotation;
  }

  /**
   * Create a circle/highlight annotation
   */
  public createCircle(center: Point, radius: number, color?: string, strokeWidth?: number): Annotation {
    // Store circle as center point with radius encoded in a second point
    const annotation: Annotation = {
      id: this.generateId(),
      type: 'circle',
      points: [center, { x: radius, y: radius }], // Using second point to store radius
      color: color || this.defaultColor,
      strokeWidth: strokeWidth || this.defaultStrokeWidth,
      timestamp: Date.now(),
      isComplete: true,
    };

    this.annotations.set(annotation.id, annotation);
    this.emit('annotationCreated', annotation);

    return annotation;
  }

  /**
   * Create a text annotation
   */
  public createText(position: Point, text: string, color?: string): Annotation {
    const annotation: Annotation = {
      id: this.generateId(),
      type: 'text',
      points: [position],
      color: color || this.defaultColor,
      strokeWidth: this.defaultStrokeWidth,
      text: text,
      timestamp: Date.now(),
      isComplete: true,
    };

    this.annotations.set(annotation.id, annotation);
    this.emit('annotationCreated', annotation);

    return annotation;
  }

  /**
   * Create an animated annotation (pulse, bounce, or highlight)
   */
  public createAnimation(
    point: Point,
    animationType: 'pulse' | 'bounce' | 'highlight',
    color?: string
  ): Annotation {
    const annotation: Annotation = {
      id: this.generateId(),
      type: 'animation',
      points: [point],
      color: color || this.defaultColor,
      strokeWidth: this.defaultStrokeWidth,
      animationType: animationType,
      timestamp: Date.now(),
      isComplete: true,
    };

    this.annotations.set(annotation.id, annotation);
    this.emit('annotationCreated', annotation);

    return annotation;
  }

  /**
   * Add annotation from remote (received via WebRTC)
   */
  public addRemoteAnnotation(annotation: Annotation): void {
    this.annotations.set(annotation.id, annotation);
    this.emit('remoteAnnotationReceived', annotation);
  }

  /**
   * Remove annotation by ID
   */
  public removeAnnotation(annotationId: string): boolean {
    if (this.annotations.has(annotationId)) {
      this.annotations.delete(annotationId);
      this.emit('annotationRemoved', annotationId);
      return true;
    }
    return false;
  }

  /**
   * Clear all annotations
   */
  public clearAllAnnotations(): void {
    this.annotations.clear();
    this.currentAnnotation = null;
    this.emit('annotationsCleared');
  }

  /**
   * Get all annotations
   */
  public getAllAnnotations(): Annotation[] {
    return Array.from(this.annotations.values());
  }

  /**
   * Get annotation by ID
   */
  public getAnnotation(annotationId: string): Annotation | undefined {
    return this.annotations.get(annotationId);
  }

  /**
   * Get annotations since timestamp
   */
  public getAnnotationsSince(timestamp: number): Annotation[] {
    return this.getAllAnnotations().filter((ann) => ann.timestamp >= timestamp);
  }

  /**
   * Set default drawing color
   */
  public setDefaultColor(color: string): void {
    this.defaultColor = color;
  }

  /**
   * Set default stroke width
   */
  public setDefaultStrokeWidth(width: number): void {
    this.defaultStrokeWidth = width;
  }

  /**
   * Get current annotation being drawn
   */
  public getCurrentAnnotation(): Annotation | null {
    return this.currentAnnotation;
  }

  /**
   * Export annotations as JSON
   */
  public exportAnnotations(): string {
    return JSON.stringify(this.getAllAnnotations());
  }

  /**
   * Import annotations from JSON
   */
  public importAnnotations(json: string): void {
    try {
      const annotations: Annotation[] = JSON.parse(json);
      annotations.forEach((ann) => {
        this.annotations.set(ann.id, ann);
      });
      this.emit('annotationsImported', annotations);
    } catch (error) {
      console.error('Error importing annotations:', error);
    }
  }
}

// Singleton instance
export const annotationService = new AnnotationService();

export default AnnotationService;
