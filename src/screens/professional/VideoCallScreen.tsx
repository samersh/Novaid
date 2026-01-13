import React, { useEffect, useState, useRef, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  StatusBar,
  Dimensions,
  Alert,
  Animated,
} from 'react-native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RouteProp } from '@react-navigation/native';
import { ProfessionalStackParamList, Annotation, Point } from '../../types';
import { useApp } from '../../context/AppContext';
import VideoView from '../../components/VideoView';
import AnnotationOverlay from '../../components/AnnotationOverlay';
import DrawingCanvas from '../../components/DrawingCanvas';

type VideoCallScreenNavigationProp = NativeStackNavigationProp<ProfessionalStackParamList, 'ProfessionalVideoCall'>;
type VideoCallScreenRouteProp = RouteProp<ProfessionalStackParamList, 'ProfessionalVideoCall'>;

interface Props {
  navigation: VideoCallScreenNavigationProp;
  route: VideoCallScreenRouteProp;
}

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

export const ProfessionalVideoCallScreen: React.FC<Props> = ({ navigation, route }) => {
  const {
    state,
    localStream,
    remoteStream,
    endCall,
    sendAnnotation,
    freezeVideo,
    resumeVideo,
    annotationService,
  } = useApp();

  const [isAudioEnabled, setIsAudioEnabled] = useState(true);
  const [showControls, setShowControls] = useState(true);
  const [annotations, setAnnotations] = useState<Annotation[]>([]);
  const [callDuration, setCallDuration] = useState(0);
  const [isDrawingMode, setIsDrawingMode] = useState(false);
  const [isVideoFrozen, setIsVideoFrozen] = useState(false);

  const controlsTimeout = useRef<NodeJS.Timeout | null>(null);
  const durationInterval = useRef<NodeJS.Timeout | null>(null);
  const fadeAnim = useRef(new Animated.Value(1)).current;

  // Demo mode flag
  const isDemo = route.params.sessionId === 'demo';

  // Call duration timer
  useEffect(() => {
    if (state.currentSession?.state === 'connected' || isDemo) {
      durationInterval.current = setInterval(() => {
        setCallDuration((prev) => prev + 1);
      }, 1000);
    }

    return () => {
      if (durationInterval.current) {
        clearInterval(durationInterval.current);
      }
    };
  }, [state.currentSession?.state, isDemo]);

  // Auto-hide controls (but not when in drawing mode)
  useEffect(() => {
    if (showControls && !isDrawingMode) {
      if (controlsTimeout.current) {
        clearTimeout(controlsTimeout.current);
      }

      controlsTimeout.current = setTimeout(() => {
        Animated.timing(fadeAnim, {
          toValue: 0,
          duration: 300,
          useNativeDriver: true,
        }).start(() => {
          setShowControls(false);
        });
      }, 5000);
    }

    return () => {
      if (controlsTimeout.current) {
        clearTimeout(controlsTimeout.current);
      }
    };
  }, [showControls, isDrawingMode, fadeAnim]);

  // Handle call ended
  useEffect(() => {
    if (state.currentSession?.state === 'disconnected' || state.currentSession?.state === 'failed') {
      Alert.alert('Call Ended', 'The call has been disconnected.', [
        { text: 'OK', onPress: () => navigation.goBack() },
      ]);
    }
  }, [state.currentSession?.state, navigation]);

  const toggleControls = () => {
    if (!showControls) {
      setShowControls(true);
      Animated.timing(fadeAnim, {
        toValue: 1,
        duration: 300,
        useNativeDriver: true,
      }).start();
    }
  };

  const formatDuration = (seconds: number): string => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  };

  const handleToggleAudio = () => {
    setIsAudioEnabled(!isAudioEnabled);
  };

  const handleToggleDrawingMode = () => {
    setIsDrawingMode(!isDrawingMode);
  };

  const handleFreezeVideo = () => {
    if (isVideoFrozen) {
      // Resume video and send annotations
      resumeVideo();
      setIsVideoFrozen(false);
    } else {
      // Freeze video
      freezeVideo();
      setIsVideoFrozen(true);
    }
  };

  const handleAnnotationComplete = useCallback(
    (annotation: Annotation) => {
      setAnnotations((prev) => [...prev, annotation]);
      sendAnnotation(annotation);
    },
    [sendAnnotation]
  );

  const handleClearAnnotations = () => {
    setAnnotations([]);
    annotationService.clearAllAnnotations();
  };

  const handleEndCall = () => {
    Alert.alert('End Call', 'Are you sure you want to end this call?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'End Call',
        style: 'destructive',
        onPress: () => {
          endCall();
          navigation.goBack();
        },
      },
    ]);
  };

  const getCallStatusText = (): string => {
    if (isDemo) return 'Demo Mode';

    switch (state.currentSession?.state) {
      case 'connecting':
        return 'Connecting...';
      case 'connected':
        return formatDuration(callDuration);
      default:
        return '';
    }
  };

  return (
    <View style={styles.container}>
      <StatusBar hidden />

      {/* Main video view - shows remote stream (user's camera) */}
      <TouchableOpacity
        style={styles.videoContainer}
        activeOpacity={1}
        onPress={toggleControls}
      >
        <VideoView
          stream={remoteStream}
          isLocal={false}
          style={styles.mainVideo}
        />

        {/* Existing annotations overlay (read-only) */}
        <AnnotationOverlay
          annotations={annotations}
          width={SCREEN_WIDTH}
          height={SCREEN_HEIGHT}
        />

        {/* Drawing canvas (when in drawing mode) */}
        {isDrawingMode && (
          <DrawingCanvas
            width={SCREEN_WIDTH}
            height={SCREEN_HEIGHT}
            onAnnotationComplete={handleAnnotationComplete}
            isEnabled={isDrawingMode}
          />
        )}

        {/* Frozen video indicator */}
        {isVideoFrozen && (
          <View style={styles.frozenBadge}>
            <Text style={styles.frozenBadgeText}>VIDEO FROZEN</Text>
          </View>
        )}
      </TouchableOpacity>

      {/* Controls overlay */}
      {showControls && (
        <Animated.View style={[styles.controlsOverlay, { opacity: fadeAnim }]}>
          {/* Top bar */}
          <View style={styles.topBar}>
            <View style={styles.callInfo}>
              <View style={styles.callStatusDot} />
              <Text style={styles.callStatusText}>{getCallStatusText()}</Text>
            </View>

            {/* Drawing mode indicator */}
            {isDrawingMode && (
              <View style={styles.drawingModeIndicator}>
                <Text style={styles.drawingModeText}>Drawing Mode</Text>
              </View>
            )}
          </View>

          {/* Annotation toolbar */}
          {isDrawingMode && (
            <View style={styles.annotationToolbar}>
              <TouchableOpacity
                style={styles.clearButton}
                onPress={handleClearAnnotations}
              >
                <Text style={styles.clearButtonText}>Clear All</Text>
              </TouchableOpacity>
            </View>
          )}

          {/* Bottom controls */}
          <View style={styles.bottomBar}>
            <TouchableOpacity
              style={[styles.controlButton, !isAudioEnabled && styles.controlButtonDisabled]}
              onPress={handleToggleAudio}
            >
              <Text style={styles.controlIcon}>{isAudioEnabled ? '🎤' : '🔇'}</Text>
              <Text style={styles.controlLabel}>{isAudioEnabled ? 'Mute' : 'Unmute'}</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.controlButton, isVideoFrozen && styles.controlButtonActive]}
              onPress={handleFreezeVideo}
            >
              <Text style={styles.controlIcon}>{isVideoFrozen ? '▶️' : '⏸️'}</Text>
              <Text style={styles.controlLabel}>{isVideoFrozen ? 'Resume' : 'Freeze'}</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.controlButton, isDrawingMode && styles.controlButtonActive]}
              onPress={handleToggleDrawingMode}
            >
              <Text style={styles.controlIcon}>✏️</Text>
              <Text style={styles.controlLabel}>{isDrawingMode ? 'Exit Draw' : 'Draw'}</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.controlButton, styles.endCallButton]}
              onPress={handleEndCall}
            >
              <Text style={styles.controlIcon}>📞</Text>
              <Text style={styles.controlLabel}>End</Text>
            </TouchableOpacity>
          </View>
        </Animated.View>
      )}

      {/* Small local video preview */}
      {localStream && (
        <View style={styles.localVideoContainer}>
          <VideoView
            stream={localStream}
            isLocal={true}
            isMirrored={true}
            style={styles.localVideo}
          />
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000000',
  },
  videoContainer: {
    flex: 1,
  },
  mainVideo: {
    flex: 1,
  },
  frozenBadge: {
    position: 'absolute',
    top: 100,
    alignSelf: 'center',
    backgroundColor: 'rgba(239, 68, 68, 0.9)',
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 20,
  },
  frozenBadgeText: {
    color: '#ffffff',
    fontWeight: 'bold',
    fontSize: 12,
  },
  controlsOverlay: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'space-between',
  },
  topBar: {
    paddingTop: 50,
    paddingHorizontal: 20,
    paddingBottom: 20,
    backgroundColor: 'rgba(0, 0, 0, 0.4)',
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  callInfo: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  callStatusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#4ade80',
    marginRight: 8,
  },
  callStatusText: {
    fontSize: 16,
    color: '#ffffff',
    fontWeight: '600',
  },
  drawingModeIndicator: {
    backgroundColor: '#e94560',
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderRadius: 16,
  },
  drawingModeText: {
    color: '#ffffff',
    fontSize: 12,
    fontWeight: 'bold',
  },
  annotationToolbar: {
    position: 'absolute',
    top: 100,
    left: 20,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    borderRadius: 8,
    padding: 8,
  },
  clearButton: {
    paddingVertical: 8,
    paddingHorizontal: 16,
  },
  clearButtonText: {
    color: '#ef4444',
    fontWeight: '600',
  },
  bottomBar: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingBottom: 40,
    paddingHorizontal: 20,
    backgroundColor: 'rgba(0, 0, 0, 0.4)',
    gap: 20,
  },
  controlButton: {
    width: 65,
    height: 65,
    borderRadius: 32,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  controlButtonDisabled: {
    backgroundColor: 'rgba(239, 68, 68, 0.3)',
  },
  controlButtonActive: {
    backgroundColor: 'rgba(233, 69, 96, 0.6)',
    borderWidth: 2,
    borderColor: '#e94560',
  },
  endCallButton: {
    backgroundColor: '#ef4444',
    width: 70,
    height: 70,
    borderRadius: 35,
  },
  controlIcon: {
    fontSize: 22,
  },
  controlLabel: {
    fontSize: 9,
    color: '#ffffff',
    marginTop: 4,
  },
  localVideoContainer: {
    position: 'absolute',
    bottom: 140,
    right: 20,
    width: 100,
    height: 130,
    borderRadius: 12,
    overflow: 'hidden',
    borderWidth: 2,
    borderColor: '#ffffff',
  },
  localVideo: {
    flex: 1,
  },
});

export default ProfessionalVideoCallScreen;
