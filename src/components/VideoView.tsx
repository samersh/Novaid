import React, { useRef, useEffect, useState } from 'react';
import { View, StyleSheet, Dimensions, Platform } from 'react-native';
import { RTCView, MediaStream } from 'react-native-webrtc';
import { VideoStabilizer } from '../services/VideoStabilizer';

interface VideoViewProps {
  stream: MediaStream | null;
  isLocal?: boolean;
  isMirrored?: boolean;
  stabilizer?: VideoStabilizer;
  style?: any;
}

export const VideoView: React.FC<VideoViewProps> = ({
  stream,
  isLocal = false,
  isMirrored = false,
  stabilizer,
  style,
}) => {
  const [dimensions, setDimensions] = useState({
    width: Dimensions.get('window').width,
    height: Dimensions.get('window').height,
  });

  const [transform, setTransform] = useState({
    translateX: 0,
    translateY: 0,
    scale: 1,
    rotation: 0,
  });

  // Apply stabilization if enabled
  useEffect(() => {
    if (!stabilizer || isLocal) return;

    // Subscribe to accelerometer/gyroscope updates
    // In a real implementation, you would use react-native-sensors
    // This is a simulation for demonstration
    const interval = setInterval(() => {
      // Simulate sensor data (in real app, this comes from device sensors)
      const mockAccelerometer = {
        x: (Math.random() - 0.5) * 0.1,
        y: (Math.random() - 0.5) * 0.1,
        z: 9.8,
      };

      const newTransform = stabilizer.processMotionData(mockAccelerometer);
      setTransform(newTransform);
    }, 33); // ~30fps

    return () => clearInterval(interval);
  }, [stabilizer, isLocal]);

  useEffect(() => {
    const subscription = Dimensions.addEventListener('change', ({ window }) => {
      setDimensions({ width: window.width, height: window.height });
    });

    return () => subscription?.remove();
  }, []);

  if (!stream) {
    return <View style={[styles.container, styles.placeholder, style]} />;
  }

  const streamURL = stream.toURL();

  return (
    <View style={[styles.container, style]}>
      <RTCView
        streamURL={streamURL}
        style={[
          styles.video,
          {
            transform: [
              { translateX: transform.translateX },
              { translateY: transform.translateY },
              { scale: 1.1 }, // Slight zoom to hide stabilization edges
              { scaleX: isMirrored ? -1 : 1 },
            ],
          },
        ]}
        objectFit="cover"
        mirror={isMirrored}
        zOrder={isLocal ? 1 : 0}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000000',
    overflow: 'hidden',
  },
  video: {
    flex: 1,
    backgroundColor: '#000000',
  },
  placeholder: {
    justifyContent: 'center',
    alignItems: 'center',
  },
});

export default VideoView;
