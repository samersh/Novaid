import React, { useEffect, useRef } from 'react';
import { View, StyleSheet, Animated, Easing, Text } from 'react-native';
import Svg, {
  Path,
  Circle,
  Line,
  Polygon,
  G,
  Text as SvgText,
} from 'react-native-svg';
import { Annotation, Point } from '../types';

interface AnnotationOverlayProps {
  annotations: Annotation[];
  width: number;
  height: number;
}

interface AnimatedPointerProps {
  point: Point;
  color: string;
  animationType?: 'pulse' | 'bounce' | 'highlight';
}

// Animated pointer component
const AnimatedPointer: React.FC<AnimatedPointerProps> = ({
  point,
  color,
  animationType = 'pulse',
}) => {
  const scaleAnim = useRef(new Animated.Value(1)).current;
  const opacityAnim = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    let animation: Animated.CompositeAnimation;

    switch (animationType) {
      case 'pulse':
        animation = Animated.loop(
          Animated.sequence([
            Animated.parallel([
              Animated.timing(scaleAnim, {
                toValue: 1.5,
                duration: 500,
                easing: Easing.ease,
                useNativeDriver: true,
              }),
              Animated.timing(opacityAnim, {
                toValue: 0.5,
                duration: 500,
                easing: Easing.ease,
                useNativeDriver: true,
              }),
            ]),
            Animated.parallel([
              Animated.timing(scaleAnim, {
                toValue: 1,
                duration: 500,
                easing: Easing.ease,
                useNativeDriver: true,
              }),
              Animated.timing(opacityAnim, {
                toValue: 1,
                duration: 500,
                easing: Easing.ease,
                useNativeDriver: true,
              }),
            ]),
          ])
        );
        break;

      case 'bounce':
        animation = Animated.loop(
          Animated.sequence([
            Animated.timing(scaleAnim, {
              toValue: 1.3,
              duration: 300,
              easing: Easing.bounce,
              useNativeDriver: true,
            }),
            Animated.timing(scaleAnim, {
              toValue: 1,
              duration: 300,
              easing: Easing.bounce,
              useNativeDriver: true,
            }),
          ])
        );
        break;

      case 'highlight':
        animation = Animated.loop(
          Animated.sequence([
            Animated.timing(opacityAnim, {
              toValue: 0.3,
              duration: 400,
              easing: Easing.linear,
              useNativeDriver: true,
            }),
            Animated.timing(opacityAnim, {
              toValue: 1,
              duration: 400,
              easing: Easing.linear,
              useNativeDriver: true,
            }),
          ])
        );
        break;
    }

    animation.start();

    return () => {
      animation.stop();
    };
  }, [animationType, scaleAnim, opacityAnim]);

  return (
    <Animated.View
      style={[
        styles.pointer,
        {
          left: point.x - 15,
          top: point.y - 15,
          backgroundColor: color,
          transform: [{ scale: scaleAnim }],
          opacity: opacityAnim,
        },
      ]}
    />
  );
};

// Convert points to SVG path
const pointsToPath = (points: Point[]): string => {
  if (points.length === 0) return '';

  let path = `M ${points[0].x} ${points[0].y}`;

  for (let i = 1; i < points.length; i++) {
    path += ` L ${points[i].x} ${points[i].y}`;
  }

  return path;
};

// Calculate arrow head points
const getArrowHead = (
  start: Point,
  end: Point,
  headLength: number = 15
): string => {
  const angle = Math.atan2(end.y - start.y, end.x - start.x);
  const angle1 = angle - Math.PI / 6;
  const angle2 = angle + Math.PI / 6;

  const x1 = end.x - headLength * Math.cos(angle1);
  const y1 = end.y - headLength * Math.sin(angle1);
  const x2 = end.x - headLength * Math.cos(angle2);
  const y2 = end.y - headLength * Math.sin(angle2);

  return `${end.x},${end.y} ${x1},${y1} ${x2},${y2}`;
};

export const AnnotationOverlay: React.FC<AnnotationOverlayProps> = ({
  annotations,
  width,
  height,
}) => {
  const renderAnnotation = (annotation: Annotation): React.ReactNode => {
    const { id, type, points, color, strokeWidth, text, animationType } = annotation;

    switch (type) {
      case 'drawing':
        return (
          <Path
            key={id}
            d={pointsToPath(points)}
            stroke={color}
            strokeWidth={strokeWidth}
            fill="none"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        );

      case 'pointer':
      case 'animation':
        return (
          <G key={id}>
            {/* Render in native view for animations */}
          </G>
        );

      case 'arrow':
        if (points.length < 2) return null;
        return (
          <G key={id}>
            <Line
              x1={points[0].x}
              y1={points[0].y}
              x2={points[1].x}
              y2={points[1].y}
              stroke={color}
              strokeWidth={strokeWidth}
            />
            <Polygon
              points={getArrowHead(points[0], points[1])}
              fill={color}
            />
          </G>
        );

      case 'circle':
        if (points.length < 2) return null;
        const center = points[0];
        const radius = points[1].x; // Radius stored in x of second point
        return (
          <Circle
            key={id}
            cx={center.x}
            cy={center.y}
            r={radius}
            stroke={color}
            strokeWidth={strokeWidth}
            fill="none"
          />
        );

      case 'text':
        return (
          <SvgText
            key={id}
            x={points[0].x}
            y={points[0].y}
            fill={color}
            fontSize={16}
            fontWeight="bold"
          >
            {text}
          </SvgText>
        );

      default:
        return null;
    }
  };

  // Separate animations from SVG annotations
  const svgAnnotations = annotations.filter(
    (a) => a.type !== 'pointer' && a.type !== 'animation'
  );
  const animatedAnnotations = annotations.filter(
    (a) => a.type === 'pointer' || a.type === 'animation'
  );

  return (
    <View style={[styles.container, { width, height }]} pointerEvents="none">
      {/* SVG layer for static annotations */}
      <Svg width={width} height={height} style={styles.svg}>
        {svgAnnotations.map(renderAnnotation)}
      </Svg>

      {/* Native layer for animated annotations */}
      {animatedAnnotations.map((annotation) => (
        <AnimatedPointer
          key={annotation.id}
          point={annotation.points[0]}
          color={annotation.color}
          animationType={annotation.animationType}
        />
      ))}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 0,
    left: 0,
  },
  svg: {
    position: 'absolute',
    top: 0,
    left: 0,
  },
  pointer: {
    position: 'absolute',
    width: 30,
    height: 30,
    borderRadius: 15,
  },
});

export default AnnotationOverlay;
