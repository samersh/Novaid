import React, { useState, useRef, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Animated,
  StatusBar,
  Alert,
  ActivityIndicator,
} from 'react-native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { UserStackParamList } from '../../types';
import { useApp } from '../../context/AppContext';
import { userIdService } from '../../services/UserIdService';

type HomeScreenNavigationProp = NativeStackNavigationProp<UserStackParamList, 'UserHome'>;

interface Props {
  navigation: HomeScreenNavigationProp;
}

export const UserHomeScreen: React.FC<Props> = ({ navigation }) => {
  const { state, startCall, clearError, signalingService } = useApp();
  const [isConnecting, setIsConnecting] = useState(false);
  const pulseAnim = useRef(new Animated.Value(1)).current;
  const fadeAnim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    // Fade in animation
    Animated.timing(fadeAnim, {
      toValue: 1,
      duration: 500,
      useNativeDriver: true,
    }).start();

    // Pulse animation for call button
    const pulseAnimation = Animated.loop(
      Animated.sequence([
        Animated.timing(pulseAnim, {
          toValue: 1.05,
          duration: 1000,
          useNativeDriver: true,
        }),
        Animated.timing(pulseAnim, {
          toValue: 1,
          duration: 1000,
          useNativeDriver: true,
        }),
      ])
    );
    pulseAnimation.start();

    return () => {
      pulseAnimation.stop();
    };
  }, [fadeAnim, pulseAnim]);

  useEffect(() => {
    // Listen for call state changes
    if (state.currentSession?.state === 'connecting' || state.currentSession?.state === 'connected') {
      navigation.navigate('UserVideoCall', { sessionId: state.currentSession.id });
    }
  }, [state.currentSession?.state, navigation, state.currentSession?.id]);

  useEffect(() => {
    // Handle errors
    if (state.error) {
      Alert.alert('Error', state.error, [
        { text: 'OK', onPress: () => clearError() },
      ]);
      setIsConnecting(false);
    }
  }, [state.error, clearError]);

  const handleStartCall = async () => {
    if (isConnecting) return;

    setIsConnecting(true);
    try {
      await startCall();
    } catch (error) {
      console.error('Failed to start call:', error);
      setIsConnecting(false);
    }
  };

  const handleDemoCall = () => {
    // Navigate to video call in demo mode
    navigation.navigate('UserVideoCall', { sessionId: 'demo' });
  };

  const userId = userIdService.getShortId();

  return (
    <View style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#1a1a2e" />

      <Animated.View style={[styles.content, { opacity: fadeAnim }]}>
        {/* Header */}
        <View style={styles.header}>
          <Text style={styles.title}>Novaid</Text>
          <Text style={styles.subtitle}>Remote Assistance</Text>
          <View style={styles.statusContainer}>
            <View
              style={[
                styles.statusDot,
                state.isConnectedToServer ? styles.statusOnline : styles.statusOffline,
              ]}
            />
            <Text style={styles.statusText}>
              {state.isConnectedToServer ? 'Connected' : 'Offline'}
            </Text>
          </View>
        </View>

        {/* User ID Display */}
        <View style={styles.userIdContainer}>
          <Text style={styles.userIdLabel}>Your ID</Text>
          <Text style={styles.userIdValue}>{userId}</Text>
        </View>

        {/* Call Button */}
        <View style={styles.callButtonContainer}>
          <Animated.View style={{ transform: [{ scale: pulseAnim }] }}>
            <TouchableOpacity
              style={[
                styles.callButton,
                isConnecting && styles.callButtonDisabled,
              ]}
              onPress={handleStartCall}
              disabled={isConnecting || !state.isConnectedToServer}
              activeOpacity={0.8}
            >
              {isConnecting ? (
                <ActivityIndicator size="large" color="#ffffff" />
              ) : (
                <>
                  <Text style={styles.callButtonIcon}>📞</Text>
                  <Text style={styles.callButtonText}>Start Call</Text>
                </>
              )}
            </TouchableOpacity>
          </Animated.View>
          <Text style={styles.callButtonHint}>
            {isConnecting
              ? 'Connecting to a professional...'
              : 'Tap to connect with a professional'}
          </Text>
        </View>

        {/* Demo Button */}
        <TouchableOpacity style={styles.demoButton} onPress={handleDemoCall}>
          <Text style={styles.demoButtonText}>Try Demo</Text>
        </TouchableOpacity>

        {/* Info Section */}
        <View style={styles.infoSection}>
          <View style={styles.infoItem}>
            <Text style={styles.infoIcon}>📹</Text>
            <Text style={styles.infoText}>Share your view with rear camera</Text>
          </View>
          <View style={styles.infoItem}>
            <Text style={styles.infoIcon}>✍️</Text>
            <Text style={styles.infoText}>Receive AR guidance from experts</Text>
          </View>
          <View style={styles.infoItem}>
            <Text style={styles.infoIcon}>🔒</Text>
            <Text style={styles.infoText}>Secure peer-to-peer connection</Text>
          </View>
        </View>
      </Animated.View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#1a1a2e',
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
  userIdContainer: {
    backgroundColor: 'rgba(67, 97, 238, 0.2)',
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    marginBottom: 30,
  },
  userIdLabel: {
    fontSize: 12,
    color: '#a0a0a0',
    marginBottom: 4,
  },
  userIdValue: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#4361ee',
    letterSpacing: 2,
  },
  callButtonContainer: {
    alignItems: 'center',
    marginBottom: 20,
  },
  callButton: {
    width: 180,
    height: 180,
    borderRadius: 90,
    backgroundColor: '#4361ee',
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#4361ee',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.5,
    shadowRadius: 20,
    elevation: 10,
  },
  callButtonDisabled: {
    backgroundColor: '#3a3a5a',
  },
  callButtonIcon: {
    fontSize: 48,
    marginBottom: 8,
  },
  callButtonText: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#ffffff',
  },
  callButtonHint: {
    marginTop: 16,
    fontSize: 14,
    color: '#666666',
  },
  demoButton: {
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    borderRadius: 8,
    paddingVertical: 12,
    paddingHorizontal: 24,
    alignSelf: 'center',
    marginBottom: 30,
  },
  demoButtonText: {
    fontSize: 14,
    color: '#a0a0a0',
  },
  infoSection: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    borderRadius: 12,
    padding: 16,
  },
  infoItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  infoIcon: {
    fontSize: 20,
    marginRight: 12,
  },
  infoText: {
    fontSize: 14,
    color: '#a0a0a0',
    flex: 1,
  },
});

export default UserHomeScreen;
