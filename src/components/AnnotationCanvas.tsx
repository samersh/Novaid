import React, { useCallback, useRef, useState, useEffect } from 'react';
import {
  View,
  StyleSheet,
  Dimensions,
  PanResponder,
  GestureResponderEvent,
  PanResponderGestureState,
} from 'react-native';
import Svg, {
  Path,
  Circle,
  Rect,
  Line,
  G,
  Defs,
  Marker,
  Text as SvgText,
} from 'react-native-svg';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withRepeat,
  withSequence,
  withTiming,
  Easing,
} from 'react-native-reanimated';
import { Annotation, Point, AnnotationType } from '../types';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

interface AnnotationCanvasProps {
  annotations: Annotation[];
  isDrawing: boolean;
  currentTool: AnnotationType;
  currentColor: string;
  strokeWidth: number;
  onAnnotationAdd: (annotation: Annotation) => void;
  onDrawStart?: () => void;
  onDrawEnd?: () => void;
  isFrozen?: boolean;
  editable?: boolean;
  width?: number;
  height?: number;
}

export const AnnotationCanvas: React.FC<AnnotationCanvasProps> = ({
  annotations,
  isDrawing,
  currentTool,
  currentColor,
  strokeWidth,
  onAnnotationAdd,
  onDrawStart,
  onDrawEnd,
  isFrozen = false,
  editable = true,
  width = SCREEN_WIDTH,
  height = SCREEN_HEIGHT,
}) => {
  const [currentPath, setCurrentPath] = useState<Point[]>([]);
  const [isActive, setIsActive] = useState(false);
  const pathRef = useRef<Point[]>([]);

  const handleTouchStart = useCallback(
    (event: GestureResponderEvent) => {
      if (!editable) return;

      const { locationX, locationY } = event.nativeEvent;
      const point: Point = { x: locationX, y: locationY };

      setIsActive(true);
      pathRef.current = [point];
      setCurrentPath([point]);
      onDrawStart?.();
    },
    [editable, onDrawStart]
  );

  const handleTouchMove = useCallback(
    (event: GestureResponderEvent, state: PanResponderGestureState) => {
      if (!editable || !isActive) return;

      const { locationX, locationY } = event.nativeEvent;
      const point: Point = { x: locationX, y: locationY };

      pathRef.current.push(point);
      setCurrentPath([...pathRef.current]);
    },
    [editable, isActive]
  );

  const handleTouchEnd = useCallback(() => {
    if (!editable || !isActive) return;

    setIsActive(false);

    if (pathRef.current.length > 0) {
      const annotation: Annotation = {
        id: `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
        type: currentTool,
        points: [...pathRef.current],
        color: currentColor,
        strokeWidth,
        timestamp: Date.now(),
      };

      onAnnotationAdd(annotation);
    }

    pathRef.current = [];
    setCurrentPath([]);
    onDrawEnd?.();
  }, [editable, isActive, currentTool, currentColor, strokeWidth, onAnnotationAdd, onDrawEnd]);

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => editable,
      onMoveShouldSetPanResponder: () => editable,
      onPanResponderGrant: handleTouchStart,
      onPanResponderMove: handleTouchMove,
      onPanResponderRelease: handleTouchEnd,
      onPanResponderTerminate: handleTouchEnd,
    })
  ).current;

  const renderAnnotation = useCallback((annotation: Annotation) => {
    const { id, type, points, color, strokeWidth: sw, text } = annotation;

    switch (type) {
      case 'freehand':
        return renderFreehand(id, points, color, sw);
      case 'line':
        return renderLine(id, points, color, sw);
      case 'arrow':
        return renderArrow(id, points, color, sw);
      case 'circle':
        return renderCircle(id, points, color, sw);
      case 'rectangle':
        return renderRectangle(id, points, color, sw);
      case 'pointer':
        return renderPointer(id, points, color, sw, annotation.duration);
      case 'text':
        return renderText(id, points, color, text);
      default:
        return null;
    }
  }, []);

  const renderFreehand = (
    id: string,
    points: Point[],
    color: string,
    sw: number
  ) => {
    if (points.length < 2) return null;

    let pathData = `M ${points[0].x} ${points[0].y}`;

    for (let i = 1; i < points.length; i++) {
      const prev = points[i - 1];
      const curr = points[i];
      // Use quadratic bezier for smooth curves
      const midX = (prev.x + curr.x) / 2;
      const midY = (prev.y + curr.y) / 2;
      pathData += ` Q ${prev.x} ${prev.y} ${midX} ${midY}`;
    }

    return (
      <Path
        key={id}
        d={pathData}
        stroke={color}
        strokeWidth={sw}
        fill="none"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    );
  };

  const renderLine = (
    id: string,
    points: Point[],
    color: string,
    sw: number
  ) => {
    if (points.length < 2) return null;
    const start = points[0];
    const end = points[points.length - 1];

    return (
      <Line
        key={id}
        x1={start.x}
        y1={start.y}
        x2={end.x}
        y2={end.y}
        stroke={color}
        strokeWidth={sw}
        strokeLinecap="round"
      />
    );
  };

  const renderArrow = (
    id: string,
    points: Point[],
    color: string,
    sw: number
  ) => {
    if (points.length < 2) return null;
    const start = points[0];
    const end = points[points.length - 1];

    // Calculate arrow head
    const angle = Math.atan2(end.y - start.y, end.x - start.x);
    const headLength = sw * 4;
    const headAngle = Math.PI / 6;

    const head1 = {
      x: end.x - headLength * Math.cos(angle - headAngle),
      y: end.y - headLength * Math.sin(angle - headAngle),
    };
    const head2 = {
      x: end.x - headLength * Math.cos(angle + headAngle),
      y: end.y - headLength * Math.sin(angle + headAngle),
    };

    return (
      <G key={id}>
        <Line
          x1={start.x}
          y1={start.y}
          x2={end.x}
          y2={end.y}
          stroke={color}
          strokeWidth={sw}
          strokeLinecap="round"
        />
        <Path
          d={`M ${head1.x} ${head1.y} L ${end.x} ${end.y} L ${head2.x} ${head2.y}`}
          stroke={color}
          strokeWidth={sw}
          fill="none"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </G>
    );
  };

  const renderCircle = (
    id: string,
    points: Point[],
    color: string,
    sw: number
  ) => {
    if (points.length < 2) return null;
    const start = points[0];
    const end = points[points.length - 1];

    const cx = (start.x + end.x) / 2;
    const cy = (start.y + end.y) / 2;
    const rx = Math.abs(end.x - start.x) / 2;
    const ry = Math.abs(end.y - start.y) / 2;

    return (
      <Circle
        key={id}
        cx={cx}
        cy={cy}
        r={Math.max(rx, ry)}
        stroke={color}
        strokeWidth={sw}
        fill="none"
      />
    );
  };

  const renderRectangle = (
    id: string,
    points: Point[],
    color: string,
    sw: number
  ) => {
    if (points.length < 2) return null;
    const start = points[0];
    const end = points[points.length - 1];

    const x = Math.min(start.x, end.x);
    const y = Math.min(start.y, end.y);
    const rectWidth = Math.abs(end.x - start.x);
    const rectHeight = Math.abs(end.y - start.y);

    return (
      <Rect
        key={id}
        x={x}
        y={y}
        width={rectWidth}
        height={rectHeight}
        stroke={color}
        strokeWidth={sw}
        fill="none"
        rx={4}
        ry={4}
      />
    );
  };

  const renderPointer = (
    id: string,
    points: Point[],
    color: string,
    sw: number,
    duration?: number
  ) => {
    if (points.length === 0) return null;
    const point = points[points.length - 1];

    return (
      <G key={id}>
        <Circle
          cx={point.x}
          cy={point.y}
          r={sw / 2}
          fill={color}
          opacity={0.8}
        />
        <Circle
          cx={point.x}
          cy={point.y}
          r={sw}
          stroke={color}
          strokeWidth={2}
          fill="none"
          opacity={0.5}
        />
        <Circle
          cx={point.x}
          cy={point.y}
          r={sw * 1.5}
          stroke={color}
          strokeWidth={1}
          fill="none"
          opacity={0.3}
        />
      </G>
    );
  };

  const renderText = (
    id: string,
    points: Point[],
    color: string,
    text?: string
  ) => {
    if (points.length === 0 || !text) return null;
    const point = points[0];

    return (
      <SvgText
        key={id}
        x={point.x}
        y={point.y}
        fill={color}
        fontSize={16}
        fontWeight="bold"
      >
        {text}
      </SvgText>
    );
  };

  return (
    <View
      style={[styles.container, { width, height }]}
      {...panResponder.panHandlers}
    >
      <Svg width={width} height={height} style={styles.svg}>
        {/* Render existing annotations */}
        {annotations.map(renderAnnotation)}

        {/* Render current drawing */}
        {isActive && currentPath.length > 0 && (
          renderFreehand(
            'current',
            currentPath,
            currentColor,
            strokeWidth
          )
        )}
      </Svg>

      {/* Frozen frame overlay */}
      {isFrozen && (
        <View style={styles.frozenOverlay}>
          <View style={styles.frozenBadge}>
            <SvgText>FROZEN</SvgText>
          </View>
        </View>
      )}
    </View>
  );
};

// Animated pointer component for pulsing effect
export const AnimatedPointer: React.FC<{
  x: number;
  y: number;
  color: string;
  size: number;
}> = ({ x, y, color, size }) => {
  const scale = useSharedValue(1);
  const opacity = useSharedValue(1);

  useEffect(() => {
    scale.value = withRepeat(
      withSequence(
        withTiming(1.5, { duration: 500, easing: Easing.ease }),
        withTiming(1, { duration: 500, easing: Easing.ease })
      ),
      -1,
      false
    );

    opacity.value = withRepeat(
      withSequence(
        withTiming(0.5, { duration: 500 }),
        withTiming(1, { duration: 500 })
      ),
      -1,
      false
    );
  }, [scale, opacity]);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
    opacity: opacity.value,
  }));

  return (
    <Animated.View
      style={[
        styles.animatedPointer,
        animatedStyle,
        {
          left: x - size / 2,
          top: y - size / 2,
          width: size,
          height: size,
          borderRadius: size / 2,
          backgroundColor: color,
        },
      ]}
    />
  );
};

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 0,
    left: 0,
    backgroundColor: 'transparent',
  },
  svg: {
    backgroundColor: 'transparent',
  },
  frozenOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.1)',
    justifyContent: 'flex-start',
    alignItems: 'center',
    paddingTop: 60,
  },
  frozenBadge: {
    backgroundColor: 'rgba(255, 0, 0, 0.8)',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
  },
  animatedPointer: {
    position: 'absolute',
  },
});

export default AnnotationCanvas;
