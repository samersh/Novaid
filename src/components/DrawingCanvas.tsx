import React, { useState, useRef, useCallback } from 'react';
import {
  View,
  StyleSheet,
  PanResponder,
  GestureResponderEvent,
  PanResponderGestureState,
  TouchableOpacity,
  Text,
} from 'react-native';
import Svg, { Path, Circle, Line, Polygon } from 'react-native-svg';
import { Point, Annotation, AnnotationType } from '../types';

interface DrawingCanvasProps {
  width: number;
  height: number;
  onAnnotationComplete: (annotation: Annotation) => void;
  isEnabled: boolean;
}

type DrawingTool = 'pen' | 'arrow' | 'circle' | 'pointer';

const COLORS = ['#FF0000', '#00FF00', '#0000FF', '#FFFF00', '#FF00FF', '#00FFFF', '#FFFFFF'];
const STROKE_WIDTHS = [2, 4, 6, 8];

export const DrawingCanvas: React.FC<DrawingCanvasProps> = ({
  width,
  height,
  onAnnotationComplete,
  isEnabled,
}) => {
  const [currentTool, setCurrentTool] = useState<DrawingTool>('pen');
  const [currentColor, setCurrentColor] = useState('#FF0000');
  const [strokeWidth, setStrokeWidth] = useState(4);
  const [currentPath, setCurrentPath] = useState<Point[]>([]);
  const [startPoint, setStartPoint] = useState<Point | null>(null);
  const [showToolbar, setShowToolbar] = useState(true);

  const generateId = (): string => {
    return `ann_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  };

  const handleTouchStart = useCallback(
    (event: GestureResponderEvent) => {
      if (!isEnabled) return;

      const { locationX, locationY } = event.nativeEvent;
      const point: Point = { x: locationX, y: locationY };

      if (currentTool === 'pen') {
        setCurrentPath([point]);
      } else if (currentTool === 'pointer') {
        // Create pointer annotation immediately
        const annotation: Annotation = {
          id: generateId(),
          type: 'pointer',
          points: [point],
          color: currentColor,
          strokeWidth: strokeWidth,
          animationType: 'pulse',
          timestamp: Date.now(),
          isComplete: true,
        };
        onAnnotationComplete(annotation);
      } else {
        setStartPoint(point);
      }
    },
    [isEnabled, currentTool, currentColor, strokeWidth, onAnnotationComplete]
  );

  const handleTouchMove = useCallback(
    (event: GestureResponderEvent) => {
      if (!isEnabled) return;

      const { locationX, locationY } = event.nativeEvent;
      const point: Point = { x: locationX, y: locationY };

      if (currentTool === 'pen') {
        setCurrentPath((prev) => [...prev, point]);
      }
    },
    [isEnabled, currentTool]
  );

  const handleTouchEnd = useCallback(
    (event: GestureResponderEvent) => {
      if (!isEnabled) return;

      const { locationX, locationY } = event.nativeEvent;
      const endPoint: Point = { x: locationX, y: locationY };

      if (currentTool === 'pen' && currentPath.length > 0) {
        const annotation: Annotation = {
          id: generateId(),
          type: 'drawing',
          points: [...currentPath, endPoint],
          color: currentColor,
          strokeWidth: strokeWidth,
          timestamp: Date.now(),
          isComplete: true,
        };
        onAnnotationComplete(annotation);
        setCurrentPath([]);
      } else if (currentTool === 'arrow' && startPoint) {
        const annotation: Annotation = {
          id: generateId(),
          type: 'arrow',
          points: [startPoint, endPoint],
          color: currentColor,
          strokeWidth: strokeWidth,
          timestamp: Date.now(),
          isComplete: true,
        };
        onAnnotationComplete(annotation);
        setStartPoint(null);
      } else if (currentTool === 'circle' && startPoint) {
        const radius = Math.sqrt(
          Math.pow(endPoint.x - startPoint.x, 2) + Math.pow(endPoint.y - startPoint.y, 2)
        );
        const annotation: Annotation = {
          id: generateId(),
          type: 'circle',
          points: [startPoint, { x: radius, y: radius }],
          color: currentColor,
          strokeWidth: strokeWidth,
          timestamp: Date.now(),
          isComplete: true,
        };
        onAnnotationComplete(annotation);
        setStartPoint(null);
      }
    },
    [isEnabled, currentTool, currentPath, startPoint, currentColor, strokeWidth, onAnnotationComplete]
  );

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => isEnabled,
      onMoveShouldSetPanResponder: () => isEnabled,
      onPanResponderGrant: handleTouchStart,
      onPanResponderMove: handleTouchMove,
      onPanResponderRelease: handleTouchEnd,
    })
  ).current;

  // Update panResponder when callbacks change
  React.useEffect(() => {
    panResponder.panHandlers.onStartShouldSetResponder = () => isEnabled;
    panResponder.panHandlers.onMoveShouldSetResponder = () => isEnabled;
  }, [isEnabled, panResponder]);

  const pointsToPath = (points: Point[]): string => {
    if (points.length === 0) return '';
    let path = `M ${points[0].x} ${points[0].y}`;
    for (let i = 1; i < points.length; i++) {
      path += ` L ${points[i].x} ${points[i].y}`;
    }
    return path;
  };

  const getArrowHead = (start: Point, end: Point, headLength: number = 15): string => {
    const angle = Math.atan2(end.y - start.y, end.x - start.x);
    const x1 = end.x - headLength * Math.cos(angle - Math.PI / 6);
    const y1 = end.y - headLength * Math.sin(angle - Math.PI / 6);
    const x2 = end.x - headLength * Math.cos(angle + Math.PI / 6);
    const y2 = end.y - headLength * Math.sin(angle + Math.PI / 6);
    return `${end.x},${end.y} ${x1},${y1} ${x2},${y2}`;
  };

  return (
    <View style={[styles.container, { width, height }]}>
      {/* Drawing area */}
      <View
        style={styles.drawingArea}
        {...panResponder.panHandlers}
      >
        <Svg width={width} height={height}>
          {/* Current drawing preview */}
          {currentTool === 'pen' && currentPath.length > 0 && (
            <Path
              d={pointsToPath(currentPath)}
              stroke={currentColor}
              strokeWidth={strokeWidth}
              fill="none"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          )}
        </Svg>
      </View>

      {/* Toolbar */}
      {showToolbar && (
        <View style={styles.toolbar}>
          {/* Tool selection */}
          <View style={styles.toolSection}>
            <TouchableOpacity
              style={[styles.toolButton, currentTool === 'pen' && styles.activeButton]}
              onPress={() => setCurrentTool('pen')}
            >
              <Text style={styles.toolIcon}>✏️</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.toolButton, currentTool === 'arrow' && styles.activeButton]}
              onPress={() => setCurrentTool('arrow')}
            >
              <Text style={styles.toolIcon}>➡️</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.toolButton, currentTool === 'circle' && styles.activeButton]}
              onPress={() => setCurrentTool('circle')}
            >
              <Text style={styles.toolIcon}>⭕</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.toolButton, currentTool === 'pointer' && styles.activeButton]}
              onPress={() => setCurrentTool('pointer')}
            >
              <Text style={styles.toolIcon}>👆</Text>
            </TouchableOpacity>
          </View>

          {/* Color selection */}
          <View style={styles.colorSection}>
            {COLORS.map((color) => (
              <TouchableOpacity
                key={color}
                style={[
                  styles.colorButton,
                  { backgroundColor: color },
                  currentColor === color && styles.activeColorButton,
                ]}
                onPress={() => setCurrentColor(color)}
              />
            ))}
          </View>

          {/* Stroke width selection */}
          <View style={styles.strokeSection}>
            {STROKE_WIDTHS.map((width) => (
              <TouchableOpacity
                key={width}
                style={[styles.strokeButton, strokeWidth === width && styles.activeButton]}
                onPress={() => setStrokeWidth(width)}
              >
                <View
                  style={[
                    styles.strokePreview,
                    { height: width, backgroundColor: currentColor },
                  ]}
                />
              </TouchableOpacity>
            ))}
          </View>
        </View>
      )}

      {/* Toggle toolbar button */}
      <TouchableOpacity
        style={styles.toggleToolbar}
        onPress={() => setShowToolbar(!showToolbar)}
      >
        <Text style={styles.toggleIcon}>{showToolbar ? '▼' : '▲'}</Text>
      </TouchableOpacity>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 0,
    left: 0,
  },
  drawingArea: {
    flex: 1,
  },
  toolbar: {
    position: 'absolute',
    bottom: 80,
    left: 10,
    right: 10,
    backgroundColor: 'rgba(0, 0, 0, 0.8)',
    borderRadius: 12,
    padding: 10,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  toolSection: {
    flexDirection: 'row',
    gap: 5,
  },
  toolButton: {
    width: 40,
    height: 40,
    borderRadius: 8,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  activeButton: {
    backgroundColor: 'rgba(255, 255, 255, 0.5)',
    borderWidth: 2,
    borderColor: '#FFFFFF',
  },
  toolIcon: {
    fontSize: 20,
  },
  colorSection: {
    flexDirection: 'row',
    gap: 5,
  },
  colorButton: {
    width: 30,
    height: 30,
    borderRadius: 15,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  activeColorButton: {
    borderColor: '#FFFFFF',
  },
  strokeSection: {
    flexDirection: 'row',
    gap: 5,
  },
  strokeButton: {
    width: 30,
    height: 30,
    borderRadius: 6,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  strokePreview: {
    width: 20,
    borderRadius: 2,
  },
  toggleToolbar: {
    position: 'absolute',
    bottom: 40,
    right: 20,
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0, 0, 0, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  toggleIcon: {
    color: '#FFFFFF',
    fontSize: 16,
  },
});

export default DrawingCanvas;
