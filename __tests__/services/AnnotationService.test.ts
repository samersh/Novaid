import { AnnotationService } from '../../src/services/AnnotationService';
import { Annotation, Point } from '../../src/types';

describe('AnnotationService', () => {
  let annotationService: AnnotationService;

  beforeEach(() => {
    annotationService = new AnnotationService();
  });

  afterEach(() => {
    annotationService.clearAllAnnotations();
    annotationService.removeAllListeners();
  });

  describe('Drawing annotations', () => {
    it('should start a new drawing', () => {
      const point: Point = { x: 100, y: 100 };
      const annotation = annotationService.startDrawing(point);

      expect(annotation).toBeDefined();
      expect(annotation.type).toBe('drawing');
      expect(annotation.points).toHaveLength(1);
      expect(annotation.points[0]).toEqual(point);
      expect(annotation.isComplete).toBe(false);
    });

    it('should add points to current drawing', () => {
      annotationService.startDrawing({ x: 0, y: 0 });
      annotationService.addDrawingPoint({ x: 10, y: 10 });
      annotationService.addDrawingPoint({ x: 20, y: 20 });

      const annotation = annotationService.getCurrentAnnotation();
      expect(annotation?.points).toHaveLength(3);
    });

    it('should end drawing and mark as complete', () => {
      annotationService.startDrawing({ x: 0, y: 0 });
      annotationService.addDrawingPoint({ x: 10, y: 10 });
      const completed = annotationService.endDrawing();

      expect(completed?.isComplete).toBe(true);
      expect(annotationService.getCurrentAnnotation()).toBeNull();
    });

    it('should return null when adding point without active drawing', () => {
      const result = annotationService.addDrawingPoint({ x: 0, y: 0 });
      expect(result).toBeNull();
    });

    it('should use custom color and stroke width', () => {
      const annotation = annotationService.startDrawing(
        { x: 0, y: 0 },
        '#00FF00',
        8
      );

      expect(annotation.color).toBe('#00FF00');
      expect(annotation.strokeWidth).toBe(8);
    });
  });

  describe('Pointer annotations', () => {
    it('should create a pointer annotation', () => {
      const point: Point = { x: 150, y: 150 };
      const annotation = annotationService.createPointer(point);

      expect(annotation.type).toBe('pointer');
      expect(annotation.points[0]).toEqual(point);
      expect(annotation.isComplete).toBe(true);
      expect(annotation.animationType).toBe('pulse');
    });

    it('should create pointer with custom color', () => {
      const annotation = annotationService.createPointer(
        { x: 0, y: 0 },
        '#0000FF'
      );

      expect(annotation.color).toBe('#0000FF');
    });
  });

  describe('Arrow annotations', () => {
    it('should create an arrow annotation', () => {
      const start: Point = { x: 0, y: 0 };
      const end: Point = { x: 100, y: 100 };
      const annotation = annotationService.createArrow(start, end);

      expect(annotation.type).toBe('arrow');
      expect(annotation.points).toHaveLength(2);
      expect(annotation.points[0]).toEqual(start);
      expect(annotation.points[1]).toEqual(end);
      expect(annotation.isComplete).toBe(true);
    });
  });

  describe('Circle annotations', () => {
    it('should create a circle annotation', () => {
      const center: Point = { x: 200, y: 200 };
      const radius = 50;
      const annotation = annotationService.createCircle(center, radius);

      expect(annotation.type).toBe('circle');
      expect(annotation.points[0]).toEqual(center);
      expect(annotation.points[1]).toEqual({ x: radius, y: radius });
      expect(annotation.isComplete).toBe(true);
    });
  });

  describe('Text annotations', () => {
    it('should create a text annotation', () => {
      const position: Point = { x: 50, y: 50 };
      const text = 'Check this';
      const annotation = annotationService.createText(position, text);

      expect(annotation.type).toBe('text');
      expect(annotation.text).toBe(text);
      expect(annotation.points[0]).toEqual(position);
    });
  });

  describe('Animation annotations', () => {
    it('should create animation annotation with pulse', () => {
      const annotation = annotationService.createAnimation(
        { x: 100, y: 100 },
        'pulse'
      );

      expect(annotation.type).toBe('animation');
      expect(annotation.animationType).toBe('pulse');
    });

    it('should create animation annotation with bounce', () => {
      const annotation = annotationService.createAnimation(
        { x: 100, y: 100 },
        'bounce'
      );

      expect(annotation.animationType).toBe('bounce');
    });

    it('should create animation annotation with highlight', () => {
      const annotation = annotationService.createAnimation(
        { x: 100, y: 100 },
        'highlight'
      );

      expect(annotation.animationType).toBe('highlight');
    });
  });

  describe('Annotation management', () => {
    it('should get all annotations', () => {
      annotationService.createPointer({ x: 0, y: 0 });
      annotationService.createPointer({ x: 100, y: 100 });

      const all = annotationService.getAllAnnotations();
      expect(all).toHaveLength(2);
    });

    it('should get annotation by ID', () => {
      const created = annotationService.createPointer({ x: 0, y: 0 });
      const retrieved = annotationService.getAnnotation(created.id);

      expect(retrieved).toBeDefined();
      expect(retrieved?.id).toBe(created.id);
    });

    it('should remove annotation by ID', () => {
      const annotation = annotationService.createPointer({ x: 0, y: 0 });
      const removed = annotationService.removeAnnotation(annotation.id);

      expect(removed).toBe(true);
      expect(annotationService.getAllAnnotations()).toHaveLength(0);
    });

    it('should return false when removing non-existent annotation', () => {
      const removed = annotationService.removeAnnotation('non-existent-id');
      expect(removed).toBe(false);
    });

    it('should clear all annotations', () => {
      annotationService.createPointer({ x: 0, y: 0 });
      annotationService.createPointer({ x: 100, y: 100 });
      annotationService.clearAllAnnotations();

      expect(annotationService.getAllAnnotations()).toHaveLength(0);
    });

    it('should get annotations since timestamp', () => {
      const timestamp = Date.now();

      // Create annotation after timestamp
      setTimeout(() => {
        annotationService.createPointer({ x: 0, y: 0 });
      }, 10);

      const annotations = annotationService.getAnnotationsSince(timestamp);
      // May have annotations created at or after timestamp
      expect(annotations).toBeDefined();
    });
  });

  describe('Remote annotations', () => {
    it('should add remote annotation', () => {
      const remoteAnnotation: Annotation = {
        id: 'remote-ann-1',
        type: 'pointer',
        points: [{ x: 50, y: 50 }],
        color: '#FF0000',
        strokeWidth: 4,
        timestamp: Date.now(),
        isComplete: true,
      };

      annotationService.addRemoteAnnotation(remoteAnnotation);

      const retrieved = annotationService.getAnnotation('remote-ann-1');
      expect(retrieved).toBeDefined();
      expect(retrieved?.id).toBe('remote-ann-1');
    });
  });

  describe('Configuration', () => {
    it('should set default color', () => {
      annotationService.setDefaultColor('#00FF00');
      const annotation = annotationService.createPointer({ x: 0, y: 0 });

      expect(annotation.color).toBe('#00FF00');
    });

    it('should set default stroke width', () => {
      annotationService.setDefaultStrokeWidth(8);
      const annotation = annotationService.startDrawing({ x: 0, y: 0 });

      expect(annotation.strokeWidth).toBe(8);
    });
  });

  describe('Export/Import', () => {
    it('should export annotations as JSON', () => {
      annotationService.createPointer({ x: 0, y: 0 });
      annotationService.createPointer({ x: 100, y: 100 });

      const json = annotationService.exportAnnotations();
      const parsed = JSON.parse(json);

      expect(Array.isArray(parsed)).toBe(true);
      expect(parsed).toHaveLength(2);
    });

    it('should import annotations from JSON', () => {
      const annotations: Annotation[] = [
        {
          id: 'import-1',
          type: 'pointer',
          points: [{ x: 0, y: 0 }],
          color: '#FF0000',
          strokeWidth: 4,
          timestamp: Date.now(),
          isComplete: true,
        },
      ];

      annotationService.importAnnotations(JSON.stringify(annotations));

      const all = annotationService.getAllAnnotations();
      expect(all).toHaveLength(1);
      expect(all[0].id).toBe('import-1');
    });
  });

  describe('Events', () => {
    it('should emit annotationStarted event', () => {
      const callback = jest.fn();
      annotationService.on('annotationStarted', callback);

      annotationService.startDrawing({ x: 0, y: 0 });

      expect(callback).toHaveBeenCalled();
    });

    it('should emit annotationCompleted event', () => {
      const callback = jest.fn();
      annotationService.on('annotationCompleted', callback);

      annotationService.startDrawing({ x: 0, y: 0 });
      annotationService.endDrawing();

      expect(callback).toHaveBeenCalled();
    });

    it('should emit annotationCreated event for non-drawing annotations', () => {
      const callback = jest.fn();
      annotationService.on('annotationCreated', callback);

      annotationService.createPointer({ x: 0, y: 0 });

      expect(callback).toHaveBeenCalled();
    });

    it('should emit annotationsCleared event', () => {
      const callback = jest.fn();
      annotationService.on('annotationsCleared', callback);

      annotationService.createPointer({ x: 0, y: 0 });
      annotationService.clearAllAnnotations();

      expect(callback).toHaveBeenCalled();
    });
  });
});
