import React, { useState, useRef, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Animated,
  StatusBar,
  Vibration,
} from 'react-native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { ProfessionalStackParamList } from '../../types';
import { useApp } from '../../context/AppContext';
import { userIdService } from '../../services/UserIdService';

type HomeScreenNavigationProp = NativeStackNavigationProp<ProfessionalStackParamList, 'ProfessionalHome'>;

interface Props {
  navigation: HomeScreenNavigationProp;
}

export const ProfessionalHomeScreen: React.FC<Props> = ({ navigation }) => {
  const { state, acceptCall, rejectCall, signalingService, clearError } = useApp();
  const [incomingCallerId, setIncomingCallerId] = useState<string | null>(null);
  const [isAccepting, setIsAccepting] = useState(false);

  const ringAnim = useRef(new Animated.Value(0)).current;
  const pulseAnim = useRef(new Animated.Value(1)).current;
  const fadeAnim = useRef(new Animated.Value(0)).current;

  // Check for incoming calls
  useEffect(() => {
    if (state.currentSession?.state === 'receiving' && state.currentSession.userId) {
      setIncomingCallerId(state.currentSession.userId);
      Vibration.vibrate([0, 500, 200, 500], true);
    } else {
      setIncomingCallerId(null);
      Vibration.cancel();
    }

    return () => {
      Vibration.cancel();
    };
  }, [state.currentSession?.state, state.currentSession?.userId]);

  // Navigate when call is connected
  useEffect(() => {
    if (state.currentSession?.state === 'connecting' || state.currentSession?.state === 'connected') {
      navigation.navigate('ProfessionalVideoCall', { sessionId: state.currentSession.id });
    }
  }, [state.currentSession?.state, state.currentSession?.id, navigation]);

  // Animations
  useEffect(() => {
    Animated.timing(fadeAnim, {
      toValue: 1,
      duration: 500,
      useNativeDriver: true,
    }).start();

    // Ring animation when there's an incoming call
    if (incomingCallerId) {
      const ringAnimation = Animated.loop(
        Animated.sequence([
          Animated.timing(ringAnim, {
            toValue: 1,
            duration: 200,
            useNativeDriver: true,
          }),
          Animated.timing(ringAnim, {
            toValue: -1,
            duration: 200,
            useNativeDriver: true,
          }),
          Animated.timing(ringAnim, {
            toValue: 0,
            duration: 200,
            useNativeDriver: true,
          }),
        ])
      );

      const pulseAnimation = Animated.loop(
        Animated.sequence([
          Animated.timing(pulseAnim, {
            toValue: 1.3,
            duration: 400,
            useNativeDriver: true,
          }),
          Animated.timing(pulseAnim, {
            toValue: 1,
            duration: 400,
            useNativeDriver: true,
          }),
        ])
      );

      ringAnimation.start();
      pulseAnimation.start();

      return () => {
        ringAnimation.stop();
        pulseAnimation.stop();
      };
    }
  }, [incomingCallerId, ringAnim, pulseAnim, fadeAnim]);

  const handleAcceptCall = async () => {
    if (!incomingCallerId || isAccepting) return;

    setIsAccepting(true);
    Vibration.cancel();
    try {
      await acceptCall(incomingCallerId);
    } catch (error) {
      console.error('Failed to accept call:', error);
      setIsAccepting(false);
    }
  };

  const handleRejectCall = () => {
    if (!incomingCallerId) return;

    Vibration.cancel();
    rejectCall(incomingCallerId);
    setIncomingCallerId(null);
  };

  const userId = userIdService.getShortId();
  const ringRotate = ringAnim.interpolate({
    inputRange: [-1, 0, 1],
    outputRange: ['-15deg', '0deg', '15deg'],
  });

  return (
    <View style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#16213e" />

      <Animated.View style={[styles.content, { opacity: fadeAnim }]}>
        {/* Header */}
        <View style={styles.header}>
          <Text style={styles.title}>Novaid Pro</Text>
          <Text style={styles.subtitle}>Professional Dashboard</Text>
          <View style={styles.statusContainer}>
            <View
              style={[
                styles.statusDot,
                state.isConnectedToServer ? styles.statusOnline : styles.statusOffline,
              ]}
            />
            <Text style={styles.statusText}>
              {state.isConnectedToServer ? 'Online - Ready for calls' : 'Offline'}
            </Text>
          </View>
        </View>

        {/* Professional ID */}
        <View style={styles.professionalIdContainer}>
          <Text style={styles.idLabel}>Professional ID</Text>
          <Text style={styles.idValue}>{userId}</Text>
        </View>

        {/* Incoming call or waiting state */}
        {incomingCallerId ? (
          <View style={styles.incomingCallContainer}>
            <Animated.View
              style={[
                styles.callIconContainer,
                {
                  transform: [{ rotate: ringRotate }, { scale: pulseAnim }],
                },
              ]}
            >
              <Text style={styles.callIcon}>📞</Text>
            </Animated.View>

            <Text style={styles.incomingText}>Incoming Call</Text>
            <Text style={styles.callerIdText}>User ID: {incomingCallerId.slice(-6).toUpperCase()}</Text>

            <View style={styles.callActions}>
              <TouchableOpacity
                style={[styles.callActionButton, styles.rejectButton]}
                onPress={handleRejectCall}
              >
                <Text style={styles.actionIcon}>✕</Text>
                <Text style={styles.actionText}>Decline</Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={[styles.callActionButton, styles.acceptButton]}
                onPress={handleAcceptCall}
                disabled={isAccepting}
              >
                <Text style={styles.actionIcon}>✓</Text>
                <Text style={styles.actionText}>{isAccepting ? 'Connecting...' : 'Accept'}</Text>
              </TouchableOpacity>
            </View>
          </View>
        ) : (
          <View style={styles.waitingContainer}>
            <View style={styles.waitingIcon}>
              <Text style={styles.waitingEmoji}>📱</Text>
            </View>
            <Text style={styles.waitingText}>Waiting for calls...</Text>
            <Text style={styles.waitingSubtext}>
              You will receive a notification when a user requests assistance
            </Text>
          </View>
        )}

        {/* Features info */}
        <View style={styles.featuresSection}>
          <Text style={styles.featuresTitle}>Your Tools</Text>
          <View style={styles.featureItem}>
            <Text style={styles.featureIcon}>✏️</Text>
            <View style={styles.featureTextContainer}>
              <Text style={styles.featureText}>Draw Annotations</Text>
              <Text style={styles.featureSubtext}>Guide users with real-time drawings</Text>
            </View>
          </View>
          <View style={styles.featureItem}>
            <Text style={styles.featureIcon}>⏸️</Text>
            <View style={styles.featureTextContainer}>
              <Text style={styles.featureText}>Freeze Video</Text>
              <Text style={styles.featureSubtext}>Pause video for precise annotations</Text>
            </View>
          </View>
          <View style={styles.featureItem}>
            <Text style={styles.featureIcon}>👆</Text>
            <View style={styles.featureTextContainer}>
              <Text style={styles.featureText}>Point & Highlight</Text>
              <Text style={styles.featureSubtext}>Draw attention with animated markers</Text>
            </View>
          </View>
        </View>
      </Animated.View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#16213e',
  },
  content: {
    flex: 1,
    padding: 20,
  },
  header: {
    alignItems: 'center',
    marginTop: 40,
    marginBottom: 20,
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#ffffff',
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 16,
    color: '#a0a0a0',
    marginBottom: 12,
  },
  statusContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 6,
  },
  statusOnline: {
    backgroundColor: '#4ade80',
  },
  statusOffline: {
    backgroundColor: '#ef4444',
  },
  statusText: {
    fontSize: 12,
    color: '#a0a0a0',
  },
  professionalIdContainer: {
    backgroundColor: 'rgba(233, 69, 96, 0.2)',
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    marginBottom: 20,
  },
  idLabel: {
    fontSize: 12,
    color: '#a0a0a0',
    marginBottom: 4,
  },
  idValue: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#e94560',
    letterSpacing: 2,
  },
  incomingCallContainer: {
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    borderRadius: 16,
    padding: 30,
    alignItems: 'center',
    marginBottom: 20,
  },
  callIconContainer: {
    width: 100,
    height: 100,
    borderRadius: 50,
    backgroundColor: '#4ade80',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 20,
  },
  callIcon: {
    fontSize: 48,
  },
  incomingText: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#ffffff',
    marginBottom: 8,
  },
  callerIdText: {
    fontSize: 14,
    color: '#a0a0a0',
    marginBottom: 20,
  },
  callActions: {
    flexDirection: 'row',
    gap: 20,
  },
  callActionButton: {
    paddingVertical: 16,
    paddingHorizontal: 32,
    borderRadius: 30,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  rejectButton: {
    backgroundColor: '#ef4444',
  },
  acceptButton: {
    backgroundColor: '#4ade80',
  },
  actionIcon: {
    fontSize: 20,
    color: '#ffffff',
  },
  actionText: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#ffffff',
  },
  waitingContainer: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    borderRadius: 16,
    padding: 40,
    alignItems: 'center',
    marginBottom: 20,
  },
  waitingIcon: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 16,
  },
  waitingEmoji: {
    fontSize: 36,
  },
  waitingText: {
    fontSize: 18,
    fontWeight: '600',
    color: '#ffffff',
    marginBottom: 8,
  },
  waitingSubtext: {
    fontSize: 14,
    color: '#666666',
    textAlign: 'center',
  },
  featuresSection: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    borderRadius: 12,
    padding: 16,
  },
  featuresTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#ffffff',
    marginBottom: 16,
  },
  featureItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  featureIcon: {
    fontSize: 24,
    marginRight: 16,
  },
  featureTextContainer: {
    flex: 1,
  },
  featureText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#ffffff',
  },
  featureSubtext: {
    fontSize: 12,
    color: '#666666',
  },
});

export default ProfessionalHomeScreen;
