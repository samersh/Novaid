import React from 'react';
import {
  View,
  StyleSheet,
  TouchableOpacity,
  Text,
} from 'react-native';
import Animated, {
  useAnimatedStyle,
  withRepeat,
  withSequence,
  withTiming,
  useSharedValue,
  withSpring,
} from 'react-native-reanimated';
import { useEffect } from 'react';

interface CallControlsProps {
  onEndCall: () => void;
  onToggleMute: () => void;
  onToggleVideo: () => void;
  onSwitchCamera?: () => void;
  isMuted: boolean;
  isVideoEnabled: boolean;
  isConnected: boolean;
  isConnecting?: boolean;
  showSwitchCamera?: boolean;
}

export const CallControls: React.FC<CallControlsProps> = ({
  onEndCall,
  onToggleMute,
  onToggleVideo,
  onSwitchCamera,
  isMuted,
  isVideoEnabled,
  isConnected,
  isConnecting = false,
  showSwitchCamera = true,
}) => {
  return (
    <View style={styles.container}>
      {/* Connection status */}
      <View style={styles.statusBar}>
        <View
          style={[
            styles.statusIndicator,
            isConnected ? styles.statusConnected : isConnecting ? styles.statusConnecting : styles.statusDisconnected,
          ]}
        />
        <Text style={styles.statusText}>
          {isConnected ? 'Connected' : isConnecting ? 'Connecting...' : 'Disconnected'}
        </Text>
      </View>

      {/* Main controls */}
      <View style={styles.controlsRow}>
        {/* Mute button */}
        <TouchableOpacity
          style={[styles.controlButton, isMuted && styles.controlButtonActive]}
          onPress={onToggleMute}
        >
          <Text style={styles.controlIcon}>{isMuted ? '🔇' : '🔊'}</Text>
          <Text style={styles.controlLabel}>{isMuted ? 'Unmute' : 'Mute'}</Text>
        </TouchableOpacity>

        {/* Video toggle */}
        <TouchableOpacity
          style={[styles.controlButton, !isVideoEnabled && styles.controlButtonActive]}
          onPress={onToggleVideo}
        >
          <Text style={styles.controlIcon}>{isVideoEnabled ? '📹' : '📷'}</Text>
          <Text style={styles.controlLabel}>{isVideoEnabled ? 'Stop Video' : 'Start Video'}</Text>
        </TouchableOpacity>

        {/* Switch camera */}
        {showSwitchCamera && (
          <TouchableOpacity style={styles.controlButton} onPress={onSwitchCamera}>
            <Text style={styles.controlIcon}>🔄</Text>
            <Text style={styles.controlLabel}>Switch</Text>
          </TouchableOpacity>
        )}

        {/* End call button */}
        <TouchableOpacity style={styles.endCallButton} onPress={onEndCall}>
          <Text style={styles.endCallIcon}>📞</Text>
          <Text style={styles.endCallLabel}>End</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

// One-click call button component
interface CallButtonProps {
  onPress: () => void;
  isLoading?: boolean;
  isActive?: boolean;
  size?: number;
  label?: string;
}

export const CallButton: React.FC<CallButtonProps> = ({
  onPress,
  isLoading = false,
  isActive = false,
  size = 100,
  label = 'Call for Help',
}) => {
  const scale = useSharedValue(1);
  const pulse = useSharedValue(1);

  useEffect(() => {
    if (isLoading) {
      pulse.value = withRepeat(
        withSequence(
          withTiming(1.2, { duration: 500 }),
          withTiming(1, { duration: 500 })
        ),
        -1,
        false
      );
    } else {
      pulse.value = withSpring(1);
    }
  }, [isLoading, pulse]);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value * pulse.value }],
  }));

  const handlePressIn = () => {
    scale.value = withSpring(0.95);
  };

  const handlePressOut = () => {
    scale.value = withSpring(1);
  };

  return (
    <View style={styles.callButtonContainer}>
      <Animated.View style={[styles.callButtonWrapper, animatedStyle]}>
        <TouchableOpacity
          style={[
            styles.callButton,
            { width: size, height: size, borderRadius: size / 2 },
            isActive && styles.callButtonActive,
          ]}
          onPress={onPress}
          onPressIn={handlePressIn}
          onPressOut={handlePressOut}
          disabled={isLoading}
          activeOpacity={0.8}
        >
          <Text style={[styles.callButtonIcon, { fontSize: size * 0.4 }]}>
            {isLoading ? '⏳' : isActive ? '📞' : '🆘'}
          </Text>
        </TouchableOpacity>
      </Animated.View>
      <Text style={styles.callButtonLabel}>
        {isLoading ? 'Connecting...' : isActive ? 'In Call' : label}
      </Text>
    </View>
  );
};

// Incoming call UI
interface IncomingCallProps {
  callerCode: string;
  onAccept: () => void;
  onReject: () => void;
}

export const IncomingCall: React.FC<IncomingCallProps> = ({
  callerCode,
  onAccept,
  onReject,
}) => {
  const ringScale = useSharedValue(1);

  useEffect(() => {
    ringScale.value = withRepeat(
      withSequence(
        withTiming(1.1, { duration: 300 }),
        withTiming(1, { duration: 300 })
      ),
      -1,
      false
    );
  }, [ringScale]);

  const ringStyle = useAnimatedStyle(() => ({
    transform: [{ scale: ringScale.value }],
  }));

  return (
    <View style={styles.incomingContainer}>
      <Animated.View style={[styles.incomingRing, ringStyle]}>
        <Text style={styles.incomingIcon}>📱</Text>
      </Animated.View>
      <Text style={styles.incomingTitle}>Incoming Call</Text>
      <Text style={styles.incomingCode}>User: {callerCode}</Text>

      <View style={styles.incomingActions}>
        <TouchableOpacity style={styles.rejectButton} onPress={onReject}>
          <Text style={styles.actionIcon}>✖</Text>
          <Text style={styles.rejectLabel}>Decline</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.acceptButton} onPress={onAccept}>
          <Text style={styles.actionIcon}>✓</Text>
          <Text style={styles.acceptLabel}>Accept</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    backgroundColor: 'rgba(0, 0, 0, 0.8)',
    paddingVertical: 16,
    paddingHorizontal: 20,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
  },
  statusBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 16,
  },
  statusIndicator: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 8,
  },
  statusConnected: {
    backgroundColor: '#00FF00',
  },
  statusConnecting: {
    backgroundColor: '#FFA500',
  },
  statusDisconnected: {
    backgroundColor: '#FF0000',
  },
  statusText: {
    color: '#fff',
    fontSize: 14,
  },
  controlsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    alignItems: 'center',
  },
  controlButton: {
    alignItems: 'center',
    padding: 12,
    borderRadius: 16,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    minWidth: 70,
  },
  controlButtonActive: {
    backgroundColor: 'rgba(255, 59, 48, 0.3)',
  },
  controlIcon: {
    fontSize: 24,
    marginBottom: 4,
  },
  controlLabel: {
    color: '#fff',
    fontSize: 10,
  },
  endCallButton: {
    alignItems: 'center',
    padding: 12,
    borderRadius: 16,
    backgroundColor: '#FF3B30',
    minWidth: 70,
  },
  endCallIcon: {
    fontSize: 24,
    marginBottom: 4,
    transform: [{ rotate: '135deg' }],
  },
  endCallLabel: {
    color: '#fff',
    fontSize: 10,
    fontWeight: 'bold',
  },
  // Call button styles
  callButtonContainer: {
    alignItems: 'center',
  },
  callButtonWrapper: {
    shadowColor: '#FF0000',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.5,
    shadowRadius: 20,
    elevation: 10,
  },
  callButton: {
    backgroundColor: '#FF3B30',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 4,
    borderColor: 'rgba(255, 255, 255, 0.3)',
  },
  callButtonActive: {
    backgroundColor: '#00C853',
  },
  callButtonIcon: {
    color: '#fff',
  },
  callButtonLabel: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
    marginTop: 16,
  },
  // Incoming call styles
  incomingContainer: {
    flex: 1,
    backgroundColor: '#1a1a1a',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  incomingRing: {
    width: 120,
    height: 120,
    borderRadius: 60,
    backgroundColor: 'rgba(0, 200, 83, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 30,
  },
  incomingIcon: {
    fontSize: 50,
  },
  incomingTitle: {
    color: '#fff',
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 10,
  },
  incomingCode: {
    color: '#888',
    fontSize: 18,
    marginBottom: 40,
  },
  incomingActions: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 40,
  },
  rejectButton: {
    width: 70,
    height: 70,
    borderRadius: 35,
    backgroundColor: '#FF3B30',
    justifyContent: 'center',
    alignItems: 'center',
  },
  acceptButton: {
    width: 70,
    height: 70,
    borderRadius: 35,
    backgroundColor: '#00C853',
    justifyContent: 'center',
    alignItems: 'center',
  },
  actionIcon: {
    color: '#fff',
    fontSize: 28,
    fontWeight: 'bold',
  },
  rejectLabel: {
    color: '#FF3B30',
    fontSize: 12,
    marginTop: 8,
    position: 'absolute',
    bottom: -24,
  },
  acceptLabel: {
    color: '#00C853',
    fontSize: 12,
    marginTop: 8,
    position: 'absolute',
    bottom: -24,
  },
});

export default CallControls;
