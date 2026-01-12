import React, { useState } from 'react';
import {
  View,
  StyleSheet,
  TouchableOpacity,
  Text,
  ScrollView,
  Dimensions,
} from 'react-native';
import Animated, {
  useAnimatedStyle,
  withSpring,
  useSharedValue,
} from 'react-native-reanimated';
import Svg, { Path, Circle, Rect, Line, G } from 'react-native-svg';
import { AnnotationType } from '../types';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

interface AnnotationToolbarProps {
  currentTool: AnnotationType;
  currentColor: string;
  currentStrokeWidth: number;
  onToolChange: (tool: AnnotationType) => void;
  onColorChange: (color: string) => void;
  onStrokeWidthChange: (width: number) => void;
  onClear: () => void;
  onFreeze: () => void;
  onResume: () => void;
  isFrozen: boolean;
  isExpanded?: boolean;
  onToggleExpand?: () => void;
}

const TOOLS: { type: AnnotationType; icon: React.ReactNode; label: string }[] = [
  {
    type: 'freehand',
    icon: (
      <Svg width={24} height={24} viewBox="0 0 24 24">
        <Path
          d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM5.92 19H5v-.92l9.06-9.06.92.92L5.92 19z"
          fill="currentColor"
        />
      </Svg>
    ),
    label: 'Draw',
  },
  {
    type: 'arrow',
    icon: (
      <Svg width={24} height={24} viewBox="0 0 24 24">
        <Path d="M4 12l1.41 1.41L11 7.83V20h2V7.83l5.58 5.59L20 12l-8-8-8 8z" fill="currentColor" />
      </Svg>
    ),
    label: 'Arrow',
  },
  {
    type: 'circle',
    icon: (
      <Svg width={24} height={24} viewBox="0 0 24 24">
        <Circle cx={12} cy={12} r={9} stroke="currentColor" strokeWidth={2} fill="none" />
      </Svg>
    ),
    label: 'Circle',
  },
  {
    type: 'rectangle',
    icon: (
      <Svg width={24} height={24} viewBox="0 0 24 24">
        <Rect x={3} y={5} width={18} height={14} stroke="currentColor" strokeWidth={2} fill="none" rx={2} />
      </Svg>
    ),
    label: 'Rectangle',
  },
  {
    type: 'pointer',
    icon: (
      <Svg width={24} height={24} viewBox="0 0 24 24">
        <Circle cx={12} cy={12} r={4} fill="currentColor" />
        <Circle cx={12} cy={12} r={8} stroke="currentColor" strokeWidth={2} fill="none" />
      </Svg>
    ),
    label: 'Pointer',
  },
];

const COLORS = [
  '#FF0000',
  '#FF6600',
  '#FFFF00',
  '#00FF00',
  '#00FFFF',
  '#0000FF',
  '#FF00FF',
  '#FFFFFF',
];

const STROKE_WIDTHS = [2, 4, 6, 8, 10];

export const AnnotationToolbar: React.FC<AnnotationToolbarProps> = ({
  currentTool,
  currentColor,
  currentStrokeWidth,
  onToolChange,
  onColorChange,
  onStrokeWidthChange,
  onClear,
  onFreeze,
  onResume,
  isFrozen,
  isExpanded = true,
  onToggleExpand,
}) => {
  const [showColors, setShowColors] = useState(false);
  const [showStrokes, setShowStrokes] = useState(false);

  const height = useSharedValue(isExpanded ? 120 : 50);

  const animatedStyle = useAnimatedStyle(() => ({
    height: withSpring(height.value, { damping: 15 }),
  }));

  const handleToolPress = (tool: AnnotationType) => {
    onToolChange(tool);
    setShowColors(false);
    setShowStrokes(false);
  };

  return (
    <Animated.View style={[styles.container, animatedStyle]}>
      {/* Main toolbar row */}
      <View style={styles.mainRow}>
        {/* Tools */}
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.toolsContainer}
        >
          {TOOLS.map(({ type, icon, label }) => (
            <TouchableOpacity
              key={type}
              style={[
                styles.toolButton,
                currentTool === type && styles.toolButtonActive,
              ]}
              onPress={() => handleToolPress(type)}
            >
              <View style={[styles.toolIcon, { color: currentTool === type ? '#007AFF' : '#fff' }]}>
                {icon}
              </View>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {/* Color picker button */}
        <TouchableOpacity
          style={[styles.toolButton, styles.colorButton]}
          onPress={() => {
            setShowColors(!showColors);
            setShowStrokes(false);
          }}
        >
          <View style={[styles.colorPreview, { backgroundColor: currentColor }]} />
        </TouchableOpacity>

        {/* Stroke width button */}
        <TouchableOpacity
          style={styles.toolButton}
          onPress={() => {
            setShowStrokes(!showStrokes);
            setShowColors(false);
          }}
        >
          <View style={[styles.strokePreview, { height: currentStrokeWidth }]} />
        </TouchableOpacity>

        {/* Freeze/Resume button */}
        <TouchableOpacity
          style={[styles.toolButton, isFrozen && styles.freezeButtonActive]}
          onPress={isFrozen ? onResume : onFreeze}
        >
          <Text style={[styles.buttonText, isFrozen && styles.buttonTextActive]}>
            {isFrozen ? 'PLAY' : 'PAUSE'}
          </Text>
        </TouchableOpacity>

        {/* Clear button */}
        <TouchableOpacity style={styles.clearButton} onPress={onClear}>
          <Text style={styles.clearButtonText}>CLEAR</Text>
        </TouchableOpacity>
      </View>

      {/* Color picker */}
      {showColors && (
        <View style={styles.pickerRow}>
          {COLORS.map((color) => (
            <TouchableOpacity
              key={color}
              style={[
                styles.colorOption,
                { backgroundColor: color },
                currentColor === color && styles.colorOptionSelected,
              ]}
              onPress={() => {
                onColorChange(color);
                setShowColors(false);
              }}
            />
          ))}
        </View>
      )}

      {/* Stroke width picker */}
      {showStrokes && (
        <View style={styles.pickerRow}>
          {STROKE_WIDTHS.map((width) => (
            <TouchableOpacity
              key={width}
              style={[
                styles.strokeOption,
                currentStrokeWidth === width && styles.strokeOptionSelected,
              ]}
              onPress={() => {
                onStrokeWidthChange(width);
                setShowStrokes(false);
              }}
            >
              <View style={[styles.strokeLine, { height: width }]} />
            </TouchableOpacity>
          ))}
        </View>
      )}
    </Animated.View>
  );
};

// Compact floating toolbar for mobile
export const FloatingAnnotationToolbar: React.FC<{
  currentTool: AnnotationType;
  currentColor: string;
  onToolChange: (tool: AnnotationType) => void;
  onColorChange: (color: string) => void;
  onFreeze: () => void;
  onResume: () => void;
  onClear: () => void;
  isFrozen: boolean;
}> = ({
  currentTool,
  currentColor,
  onToolChange,
  onColorChange,
  onFreeze,
  onResume,
  onClear,
  isFrozen,
}) => {
  const [expanded, setExpanded] = useState(false);

  return (
    <View style={styles.floatingContainer}>
      <TouchableOpacity
        style={styles.floatingToggle}
        onPress={() => setExpanded(!expanded)}
      >
        <Text style={styles.floatingToggleText}>{expanded ? '×' : '✏️'}</Text>
      </TouchableOpacity>

      {expanded && (
        <View style={styles.floatingTools}>
          {TOOLS.slice(0, 3).map(({ type, icon }) => (
            <TouchableOpacity
              key={type}
              style={[
                styles.floatingToolButton,
                currentTool === type && styles.floatingToolButtonActive,
              ]}
              onPress={() => onToolChange(type)}
            >
              <View style={styles.toolIcon}>{icon}</View>
            </TouchableOpacity>
          ))}

          <TouchableOpacity
            style={[styles.floatingToolButton, isFrozen && styles.floatingToolButtonActive]}
            onPress={isFrozen ? onResume : onFreeze}
          >
            <Text style={styles.floatingButtonText}>{isFrozen ? '▶' : '⏸'}</Text>
          </TouchableOpacity>

          <TouchableOpacity style={styles.floatingToolButton} onPress={onClear}>
            <Text style={styles.floatingButtonText}>🗑</Text>
          </TouchableOpacity>

          <View style={styles.floatingColorRow}>
            {COLORS.slice(0, 4).map((color) => (
              <TouchableOpacity
                key={color}
                style={[
                  styles.floatingColorOption,
                  { backgroundColor: color },
                  currentColor === color && styles.floatingColorSelected,
                ]}
                onPress={() => onColorChange(color)}
              />
            ))}
          </View>
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    backgroundColor: 'rgba(0, 0, 0, 0.85)',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingHorizontal: 10,
    paddingTop: 10,
    overflow: 'hidden',
  },
  mainRow: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 50,
  },
  toolsContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  toolButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    justifyContent: 'center',
    alignItems: 'center',
    marginHorizontal: 4,
  },
  toolButtonActive: {
    backgroundColor: 'rgba(0, 122, 255, 0.3)',
    borderWidth: 2,
    borderColor: '#007AFF',
  },
  toolIcon: {
    color: '#fff',
  },
  colorButton: {
    marginLeft: 'auto',
  },
  colorPreview: {
    width: 24,
    height: 24,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: '#fff',
  },
  strokePreview: {
    width: 24,
    backgroundColor: '#fff',
    borderRadius: 2,
  },
  freezeButtonActive: {
    backgroundColor: '#FF3B30',
  },
  buttonText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: 'bold',
  },
  buttonTextActive: {
    color: '#fff',
  },
  clearButton: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: 'rgba(255, 59, 48, 0.3)',
    borderRadius: 16,
    marginLeft: 8,
  },
  clearButtonText: {
    color: '#FF3B30',
    fontSize: 10,
    fontWeight: 'bold',
  },
  pickerRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 10,
    flexWrap: 'wrap',
  },
  colorOption: {
    width: 36,
    height: 36,
    borderRadius: 18,
    marginHorizontal: 6,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  colorOptionSelected: {
    borderColor: '#fff',
    transform: [{ scale: 1.2 }],
  },
  strokeOption: {
    width: 50,
    height: 40,
    justifyContent: 'center',
    alignItems: 'center',
    marginHorizontal: 4,
    borderRadius: 8,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
  },
  strokeOptionSelected: {
    backgroundColor: 'rgba(0, 122, 255, 0.3)',
    borderWidth: 1,
    borderColor: '#007AFF',
  },
  strokeLine: {
    width: 30,
    backgroundColor: '#fff',
    borderRadius: 2,
  },
  // Floating toolbar styles
  floatingContainer: {
    position: 'absolute',
    right: 10,
    bottom: 100,
  },
  floatingToggle: {
    width: 50,
    height: 50,
    borderRadius: 25,
    backgroundColor: 'rgba(0, 0, 0, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 10,
  },
  floatingToggleText: {
    color: '#fff',
    fontSize: 24,
  },
  floatingTools: {
    backgroundColor: 'rgba(0, 0, 0, 0.85)',
    borderRadius: 25,
    padding: 10,
    alignItems: 'center',
  },
  floatingToolButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    justifyContent: 'center',
    alignItems: 'center',
    marginVertical: 4,
  },
  floatingToolButtonActive: {
    backgroundColor: 'rgba(0, 122, 255, 0.5)',
  },
  floatingButtonText: {
    color: '#fff',
    fontSize: 18,
  },
  floatingColorRow: {
    flexDirection: 'row',
    marginTop: 8,
  },
  floatingColorOption: {
    width: 24,
    height: 24,
    borderRadius: 12,
    marginHorizontal: 2,
    borderWidth: 1,
    borderColor: '#333',
  },
  floatingColorSelected: {
    borderWidth: 2,
    borderColor: '#fff',
  },
});

export default AnnotationToolbar;
