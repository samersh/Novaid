import React, { useEffect, useRef, useState } from 'react';
import {
  View,
  StyleSheet,
  Dimensions,
  TouchableOpacity,
  Text,
} from 'react-native';
import { RTCView, MediaStream } from 'react-native-webrtc';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withSpring,
} from 'react-native-reanimated';
import { VideoStabilizer, FrameTransform } from '../utils/VideoStabilizer';

interface VideoStreamProps {
  stream: MediaStream | null;
  muted?: boolean;
  mirror?: boolean;
  stabilized?: boolean;
  objectFit?: 'contain' | 'cover';
  zOrder?: number;
  style?: object;
  onPress?: () => void;
}

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

export const VideoStream: React.FC<VideoStreamProps> = ({
  stream,
  muted = false,
  mirror = false,
  stabilized = false,
  objectFit = 'cover',
  zOrder = 0,
  style,
  onPress,
}) => {
  const stabilizer = useRef(new VideoStabilizer()).current;
  const [transform, setTransform] = useState<FrameTransform>({
    translateX: 0,
    translateY: 0,
    rotation: 0,
    scale: 1,
  });

  // Animated values for smooth stabilization
  const translateX = useSharedValue(0);
  const translateY = useSharedValue(0);
  const rotation = useSharedValue(0);
  const scale = useSharedValue(1);

  useEffect(() => {
    if (stabilized) {
      // Simulate frame processing with stabilization
      const interval = setInterval(() => {
        // In a real implementation, this would process actual frame data
        const motion = stabilizer.estimateMotion(null, null);
        const newTransform = stabilizer.calculateStabilizationTransform(motion);

        translateX.value = withSpring(newTransform.translateX, { damping: 15 });
        translateY.value = withSpring(newTransform.translateY, { damping: 15 });
        rotation.value = withSpring(newTransform.rotation, { damping: 15 });
        scale.value = withSpring(newTransform.scale, { damping: 15 });

        setTransform(newTransform);
      }, 33); // ~30fps

      return () => clearInterval(interval);
    }
  }, [stabilized, stabilizer, translateX, translateY, rotation, scale]);

  const animatedStyle = useAnimatedStyle(() => {
    if (!stabilized) {
      return {};
    }

    return {
      transform: [
        { translateX: translateX.value },
        { translateY: translateY.value },
        { rotate: `${rotation.value}deg` },
        { scale: scale.value },
      ],
    };
  });

  if (!stream) {
    return (
      <View style={[styles.placeholder, style]}>
        <Text style={styles.placeholderText}>No video stream</Text>
      </View>
    );
  }

  const streamURL = stream.toURL();

  const videoContent = (
    <Animated.View style={[styles.videoWrapper, animatedStyle]}>
      <RTCView
        streamURL={streamURL}
        style={styles.video}
        objectFit={objectFit}
        mirror={mirror}
        zOrder={zOrder}
      />
    </Animated.View>
  );

  if (onPress) {
    return (
      <TouchableOpacity
        style={[styles.container, style]}
        onPress={onPress}
        activeOpacity={0.9}
      >
        {videoContent}
      </TouchableOpacity>
    );
  }

  return <View style={[styles.container, style]}>{videoContent}</View>;
};

interface PictureInPictureProps {
  mainStream: MediaStream | null;
  pipStream: MediaStream | null;
  mainMuted?: boolean;
  pipMuted?: boolean;
  mainMirror?: boolean;
  pipMirror?: boolean;
  onPipPress?: () => void;
  stabilizeMain?: boolean;
}

export const PictureInPicture: React.FC<PictureInPictureProps> = ({
  mainStream,
  pipStream,
  mainMuted = false,
  pipMuted = true,
  mainMirror = false,
  pipMirror = true,
  onPipPress,
  stabilizeMain = false,
}) => {
  return (
    <View style={styles.pipContainer}>
      <VideoStream
        stream={mainStream}
        muted={mainMuted}
        mirror={mainMirror}
        stabilized={stabilizeMain}
        style={styles.mainVideo}
        zOrder={0}
      />
      {pipStream && (
        <VideoStream
          stream={pipStream}
          muted={pipMuted}
          mirror={pipMirror}
          style={styles.pipVideo}
          objectFit="cover"
          zOrder={1}
          onPress={onPipPress}
        />
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
    overflow: 'hidden',
  },
  videoWrapper: {
    flex: 1,
  },
  video: {
    flex: 1,
    width: '100%',
    height: '100%',
  },
  placeholder: {
    flex: 1,
    backgroundColor: '#1a1a1a',
    justifyContent: 'center',
    alignItems: 'center',
  },
  placeholderText: {
    color: '#666',
    fontSize: 16,
  },
  pipContainer: {
    flex: 1,
    position: 'relative',
  },
  mainVideo: {
    flex: 1,
  },
  pipVideo: {
    position: 'absolute',
    top: 40,
    right: 20,
    width: 120,
    height: 160,
    borderRadius: 10,
    overflow: 'hidden',
    borderWidth: 2,
    borderColor: '#fff',
    elevation: 5,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
  },
});

export default VideoStream;
