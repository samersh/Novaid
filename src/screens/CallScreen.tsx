import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  StyleSheet,
  SafeAreaView,
  StatusBar,
  Dimensions,
  Alert,
  BackHandler,
} from 'react-native';
import { RouteProp, useNavigation, useRoute } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList, Annotation, AnnotationType } from '../types';
import { useApp } from '../context/AppContext';
import { VideoStream, PictureInPicture } from '../components/VideoStream';
import { AnnotationCanvas } from '../components/AnnotationCanvas';
import { AnnotationToolbar, FloatingAnnotationToolbar } from '../components/AnnotationToolbar';
import { CallControls } from '../components/CallControls';
import { LocationMap, MiniMap } from '../components/LocationMap';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

type CallScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'CallScreen'>;
type CallScreenRouteProp = RouteProp<RootStackParamList, 'CallScreen'>;

export const CallScreen: React.FC = () => {
  const navigation = useNavigation<CallScreenNavigationProp>();
  const route = useRoute<CallScreenRouteProp>();
  const { role } = route.params;

  const {
    state,
    endCall,
    toggleMute,
    toggleVideo,
    switchCamera,
    sendAnnotation,
    clearAnnotations,
    freezeFrame,
    resumeFrame,
  } = useApp();

  const [isMuted, setIsMuted] = useState(false);
  const [isVideoEnabled, setIsVideoEnabled] = useState(true);
  const [currentTool, setCurrentTool] = useState<AnnotationType>('freehand');
  const [currentColor, setCurrentColor] = useState('#FF0000');
  const [currentStrokeWidth, setCurrentStrokeWidth] = useState(4);
  const [showMap, setShowMap] = useState(false);

  const isUser = role === 'user';
  const isProfessional = role === 'professional';

  // Handle back button
  useEffect(() => {
    const backHandler = BackHandler.addEventListener('hardwareBackPress', () => {
      handleEndCall();
      return true;
    });

    return () => backHandler.remove();
  }, []);

  // Navigate away when call ends
  useEffect(() => {
    if (!state.callState.isConnected && !state.callState.isConnecting) {
      navigation.goBack();
    }
  }, [state.callState.isConnected, state.callState.isConnecting, navigation]);

  const handleEndCall = useCallback(() => {
    Alert.alert(
      'End Call',
      'Are you sure you want to end this call?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'End Call',
          style: 'destructive',
          onPress: () => {
            endCall();
            navigation.goBack();
          },
        },
      ]
    );
  }, [endCall, navigation]);

  const handleToggleMute = useCallback(() => {
    const newMuteState = toggleMute();
    setIsMuted(!newMuteState);
  }, [toggleMute]);

  const handleToggleVideo = useCallback(() => {
    const newVideoState = toggleVideo();
    setIsVideoEnabled(newVideoState);
  }, [toggleVideo]);

  const handleAnnotationAdd = useCallback(
    (annotation: Annotation) => {
      sendAnnotation(annotation);
    },
    [sendAnnotation]
  );

  const handleClearAnnotations = useCallback(() => {
    clearAnnotations();
  }, [clearAnnotations]);

  const handleFreeze = useCallback(() => {
    freezeFrame();
  }, [freezeFrame]);

  const handleResume = useCallback(() => {
    resumeFrame();
  }, [resumeFrame]);

  const handleToggleMap = useCallback(() => {
    setShowMap(!showMap);
  }, [showMap]);

  // User view: Shows own rear camera feed with annotations overlay
  if (isUser) {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar barStyle="light-content" backgroundColor="#000" />

        {/* Main video (rear camera) */}
        <View style={styles.videoContainer}>
          <VideoStream
            stream={state.callState.localStream}
            stabilized={true}
            objectFit="cover"
          />

          {/* Annotation overlay (received from professional) */}
          <AnnotationCanvas
            annotations={state.annotations}
            isDrawing={false}
            currentTool={currentTool}
            currentColor={currentColor}
            strokeWidth={currentStrokeWidth}
            onAnnotationAdd={handleAnnotationAdd}
            isFrozen={state.isFrozen}
            editable={false}
            width={SCREEN_WIDTH}
            height={SCREEN_HEIGHT - 150}
          />

          {/* Frozen indicator */}
          {state.isFrozen && (
            <View style={styles.frozenIndicator}>
              <View style={styles.frozenBadge}>
                <View style={styles.frozenDot} />
              </View>
            </View>
          )}
        </View>

        {/* Call controls */}
        <CallControls
          onEndCall={handleEndCall}
          onToggleMute={handleToggleMute}
          onToggleVideo={handleToggleVideo}
          onSwitchCamera={switchCamera}
          isMuted={isMuted}
          isVideoEnabled={isVideoEnabled}
          isConnected={state.callState.isConnected}
          isConnecting={state.callState.isConnecting}
          showSwitchCamera={true}
        />
      </SafeAreaView>
    );
  }

  // Professional view: Shows remote video with annotation tools and map
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#000" />

      {/* Main content */}
      <View style={styles.professionalContainer}>
        {/* Remote video (user's rear camera) */}
        <View style={styles.remoteVideoContainer}>
          <VideoStream
            stream={state.callState.remoteStream}
            objectFit="contain"
          />

          {/* Annotation canvas (professional draws here) */}
          <AnnotationCanvas
            annotations={state.annotations}
            isDrawing={true}
            currentTool={currentTool}
            currentColor={currentColor}
            strokeWidth={currentStrokeWidth}
            onAnnotationAdd={handleAnnotationAdd}
            isFrozen={state.isFrozen}
            editable={true}
            width={SCREEN_WIDTH}
            height={SCREEN_HEIGHT - 280}
          />
        </View>

        {/* Mini map */}
        {state.remoteLocation && (
          <View style={styles.miniMapContainer}>
            <MiniMap
              location={state.remoteLocation}
              size={120}
              onPress={handleToggleMap}
            />
          </View>
        )}

        {/* Full map overlay */}
        {showMap && state.remoteLocation && (
          <View style={styles.fullMapOverlay}>
            <LocationMap
              location={state.remoteLocation}
              showUserMarker={true}
              showAccuracyCircle={true}
              onPress={handleToggleMap}
            />
          </View>
        )}
      </View>

      {/* Annotation toolbar */}
      <AnnotationToolbar
        currentTool={currentTool}
        currentColor={currentColor}
        currentStrokeWidth={currentStrokeWidth}
        onToolChange={setCurrentTool}
        onColorChange={setCurrentColor}
        onStrokeWidthChange={setCurrentStrokeWidth}
        onClear={handleClearAnnotations}
        onFreeze={handleFreeze}
        onResume={handleResume}
        isFrozen={state.isFrozen}
      />

      {/* Call controls */}
      <CallControls
        onEndCall={handleEndCall}
        onToggleMute={handleToggleMute}
        onToggleVideo={handleToggleVideo}
        isMuted={isMuted}
        isVideoEnabled={isVideoEnabled}
        isConnected={state.callState.isConnected}
        isConnecting={state.callState.isConnecting}
        showSwitchCamera={false}
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  videoContainer: {
    flex: 1,
    position: 'relative',
  },
  frozenIndicator: {
    position: 'absolute',
    top: 20,
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  frozenBadge: {
    backgroundColor: 'rgba(255, 0, 0, 0.8)',
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 20,
    flexDirection: 'row',
    alignItems: 'center',
  },
  frozenDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: '#fff',
    marginRight: 8,
  },
  professionalContainer: {
    flex: 1,
    position: 'relative',
  },
  remoteVideoContainer: {
    flex: 1,
    position: 'relative',
  },
  miniMapContainer: {
    position: 'absolute',
    bottom: 20,
    right: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 5,
  },
  fullMapOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.9)',
  },
});

export default CallScreen;
