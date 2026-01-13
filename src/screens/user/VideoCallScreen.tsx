import React, { useEffect, useState, useRef } from 'react';
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
import { UserStackParamList, Annotation } from '../../types';
import { useApp } from '../../context/AppContext';
import VideoView from '../../components/VideoView';
import AnnotationOverlay from '../../components/AnnotationOverlay';

type VideoCallScreenNavigationProp = NativeStackNavigationProp<UserStackParamList, 'UserVideoCall'>;
type VideoCallScreenRouteProp = RouteProp<UserStackParamList, 'UserVideoCall'>;

interface Props {
  navigation: VideoCallScreenNavigationProp;
  route: VideoCallScreenRouteProp;
}

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

export const UserVideoCallScreen: React.FC<Props> = ({ navigation, route }) => {
  const {
    state,
    localStream,
    remoteStream,
    endCall,
    videoStabilizer,
    annotationService,
  } = useApp();

  const [isAudioEnabled, setIsAudioEnabled] = useState(true);
  const [isVideoEnabled, setIsVideoEnabled] = useState(true);
  const [showControls, setShowControls] = useState(true);
  const [annotations, setAnnotations] = useState<Annotation[]>([]);
  const [callDuration, setCallDuration] = useState(0);

  const controlsTimeout = useRef<NodeJS.Timeout | null>(null);
  const durationInterval = useRef<NodeJS.Timeout | null>(null);
  const fadeAnim = useRef(new Animated.Value(1)).current;

  // Demo mode flag
  const isDemo = route.params.sessionId === 'demo';

  // Setup annotations listener
  useEffect(() => {
    const handleAnnotation = (annotation: Annotation) => {
      setAnnotations((prev) => [...prev, annotation]);
    };

    annotationService.on('remoteAnnotationReceived', handleAnnotation);

    return () => {
      annotationService.off('remoteAnnotationReceived', handleAnnotation);
    };
  }, [annotationService]);

  // Update annotations from state
  useEffect(() => {
    if (state.currentSession?.annotations) {
      setAnnotations(state.currentSession.annotations);
    }
  }, [state.currentSession?.annotations]);

  // Call duration timer
  useEffect(() => {
    if (state.currentSession?.state === 'connected') {
      durationInterval.current = setInterval(() => {
        setCallDuration((prev) => prev + 1);
      }, 1000);
    }

    return () => {
      if (durationInterval.current) {
        clearInterval(durationInterval.current);
      }
    };
  }, [state.currentSession?.state]);

  // Auto-hide controls
  useEffect(() => {
    if (showControls) {
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
  }, [showControls, fadeAnim]);

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
    // In real implementation, toggle track
  };

  const handleToggleVideo = () => {
    setIsVideoEnabled(!isVideoEnabled);
    // In real implementation, toggle track
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
      case 'calling':
        return 'Calling...';
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

      {/* Main video view - shows local camera (rear camera) */}
      <TouchableOpacity
        style={styles.videoContainer}
        activeOpacity={1}
        onPress={toggleControls}
      >
        <VideoView
          stream={localStream}
          isLocal={true}
          stabilizer={videoStabilizer}
          style={styles.mainVideo}
        />

        {/* AR Annotations Overlay */}
        <AnnotationOverlay
          annotations={annotations}
          width={SCREEN_WIDTH}
          height={SCREEN_HEIGHT}
        />

        {/* Frozen video indicator */}
        {state.currentSession?.isVideoFrozen && (
          <View style={styles.frozenOverlay}>
            <Text style={styles.frozenText}>Video Paused</Text>
            <Text style={styles.frozenSubtext}>Expert is adding annotations</Text>
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
          </View>

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
              style={[styles.controlButton, styles.endCallButton]}
              onPress={handleEndCall}
            >
              <Text style={styles.controlIcon}>📞</Text>
              <Text style={styles.controlLabel}>End</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.controlButton, !isVideoEnabled && styles.controlButtonDisabled]}
              onPress={handleToggleVideo}
            >
              <Text style={styles.controlIcon}>{isVideoEnabled ? '📹' : '🚫'}</Text>
              <Text style={styles.controlLabel}>{isVideoEnabled ? 'Camera' : 'Camera Off'}</Text>
            </TouchableOpacity>
          </View>
        </Animated.View>
      )}

      {/* Small remote video (professional's video if any) */}
      {remoteStream && (
        <View style={styles.remoteVideoContainer}>
          <VideoView
            stream={remoteStream}
            isLocal={false}
            style={styles.remoteVideo}
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
  frozenOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  frozenText: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#ffffff',
    marginBottom: 8,
  },
  frozenSubtext: {
    fontSize: 16,
    color: '#a0a0a0',
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
  },
  callInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
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
  bottomBar: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingBottom: 40,
    paddingHorizontal: 20,
    backgroundColor: 'rgba(0, 0, 0, 0.4)',
    gap: 30,
  },
  controlButton: {
    width: 70,
    height: 70,
    borderRadius: 35,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  controlButtonDisabled: {
    backgroundColor: 'rgba(239, 68, 68, 0.3)',
  },
  endCallButton: {
    backgroundColor: '#ef4444',
    width: 80,
    height: 80,
    borderRadius: 40,
  },
  controlIcon: {
    fontSize: 24,
  },
  controlLabel: {
    fontSize: 10,
    color: '#ffffff',
    marginTop: 4,
  },
  remoteVideoContainer: {
    position: 'absolute',
    top: 100,
    right: 20,
    width: 120,
    height: 160,
    borderRadius: 12,
    overflow: 'hidden',
    borderWidth: 2,
    borderColor: '#ffffff',
  },
  remoteVideo: {
    flex: 1,
  },
});

export default UserVideoCallScreen;
