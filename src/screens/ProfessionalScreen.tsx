import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  StatusBar,
  Alert,
  ActivityIndicator,
  FlatList,
  TouchableOpacity,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../types';
import { useApp } from '../context/AppContext';
import { IncomingCall } from '../components/CallControls';
import { userService } from '../services/UserService';

type ProfessionalScreenNavigationProp = NativeStackNavigationProp<
  RootStackParamList,
  'ProfessionalScreen'
>;

export const ProfessionalScreen: React.FC = () => {
  const navigation = useNavigation<ProfessionalScreenNavigationProp>();
  const { state, initializeApp, acceptCall, rejectCall } = useApp();
  const [isInitializing, setIsInitializing] = useState(true);
  const [isAvailable, setIsAvailable] = useState(true);

  useEffect(() => {
    const init = async () => {
      try {
        await initializeApp('professional');
      } catch (error) {
        Alert.alert('Error', 'Failed to initialize. Please try again.');
      } finally {
        setIsInitializing(false);
      }
    };

    init();
  }, [initializeApp]);

  useEffect(() => {
    // Navigate to call screen when call is connected
    if (state.callState.isConnected) {
      navigation.navigate('CallScreen', { role: 'professional' });
    }
  }, [state.callState.isConnected, navigation]);

  const handleAcceptCall = async () => {
    if (state.incomingCall) {
      await acceptCall(state.incomingCall.callerId);
    }
  };

  const handleRejectCall = () => {
    if (state.incomingCall) {
      rejectCall(state.incomingCall.callerId);
    }
  };

  const toggleAvailability = () => {
    setIsAvailable(!isAvailable);
    // In production, this would update the server status
  };

  if (isInitializing) {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar barStyle="light-content" backgroundColor="#1a1a1a" />
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color="#007AFF" />
          <Text style={styles.loadingText}>Initializing...</Text>
        </View>
      </SafeAreaView>
    );
  }

  // Show incoming call UI
  if (state.incomingCall) {
    return (
      <IncomingCall
        callerCode={state.incomingCall.callerCode}
        onAccept={handleAcceptCall}
        onReject={handleRejectCall}
      />
    );
  }

  const professionalCode = state.user?.uniqueCode
    ? userService.formatCodeForDisplay(state.user.uniqueCode)
    : '------';

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#1a1a1a" />

      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>Professional Dashboard</Text>
        <View style={styles.statusBadge}>
          <View style={[styles.statusDot, isAvailable ? styles.available : styles.unavailable]} />
          <Text style={styles.statusLabel}>{isAvailable ? 'Available' : 'Busy'}</Text>
        </View>
      </View>

      {/* Professional Info */}
      <View style={styles.infoCard}>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Your Code</Text>
          <Text style={styles.infoValue}>{professionalCode}</Text>
        </View>
        <View style={styles.divider} />
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Server Status</Text>
          <View style={styles.serverStatus}>
            <View
              style={[
                styles.serverDot,
                state.isConnectedToServer ? styles.serverConnected : styles.serverDisconnected,
              ]}
            />
            <Text style={styles.serverText}>
              {state.isConnectedToServer ? 'Connected' : 'Disconnected'}
            </Text>
          </View>
        </View>
      </View>

      {/* Availability Toggle */}
      <TouchableOpacity
        style={[styles.availabilityButton, !isAvailable && styles.unavailableButton]}
        onPress={toggleAvailability}
      >
        <Text style={styles.availabilityText}>
          {isAvailable ? 'Go Offline' : 'Go Online'}
        </Text>
      </TouchableOpacity>

      {/* Waiting State */}
      <View style={styles.waitingContainer}>
        {isAvailable ? (
          <>
            <View style={styles.pulseContainer}>
              <View style={styles.pulse} />
              <View style={[styles.pulse, styles.pulse2]} />
              <View style={styles.pulseCenter}>
                <Text style={styles.pulseIcon}>📱</Text>
              </View>
            </View>
            <Text style={styles.waitingTitle}>Waiting for calls...</Text>
            <Text style={styles.waitingSubtitle}>
              You'll be notified when a user needs assistance
            </Text>
          </>
        ) : (
          <>
            <Text style={styles.offlineIcon}>🔕</Text>
            <Text style={styles.offlineTitle}>You're Offline</Text>
            <Text style={styles.offlineSubtitle}>
              Toggle availability to receive calls
            </Text>
          </>
        )}
      </View>

      {/* Stats (placeholder) */}
      <View style={styles.statsContainer}>
        <View style={styles.statItem}>
          <Text style={styles.statValue}>0</Text>
          <Text style={styles.statLabel}>Today's Calls</Text>
        </View>
        <View style={styles.statDivider} />
        <View style={styles.statItem}>
          <Text style={styles.statValue}>0m</Text>
          <Text style={styles.statLabel}>Total Time</Text>
        </View>
        <View style={styles.statDivider} />
        <View style={styles.statItem}>
          <Text style={styles.statValue}>-</Text>
          <Text style={styles.statLabel}>Rating</Text>
        </View>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#1a1a1a',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    color: '#888',
    marginTop: 16,
    fontSize: 16,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingTop: 20,
    paddingBottom: 16,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#fff',
  },
  statusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#2a2a2a',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 20,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 6,
  },
  available: {
    backgroundColor: '#00FF00',
  },
  unavailable: {
    backgroundColor: '#FF3B30',
  },
  statusLabel: {
    fontSize: 12,
    color: '#888',
  },
  infoCard: {
    marginHorizontal: 24,
    backgroundColor: '#2a2a2a',
    borderRadius: 16,
    padding: 20,
    marginTop: 16,
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  infoLabel: {
    fontSize: 14,
    color: '#888',
  },
  infoValue: {
    fontSize: 18,
    fontWeight: '600',
    color: '#007AFF',
    fontFamily: 'monospace',
  },
  divider: {
    height: 1,
    backgroundColor: '#333',
    marginVertical: 16,
  },
  serverStatus: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  serverDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 6,
  },
  serverConnected: {
    backgroundColor: '#00FF00',
  },
  serverDisconnected: {
    backgroundColor: '#FF3B30',
  },
  serverText: {
    fontSize: 14,
    color: '#888',
  },
  availabilityButton: {
    marginHorizontal: 24,
    marginTop: 16,
    backgroundColor: '#FF3B3020',
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#FF3B3050',
  },
  unavailableButton: {
    backgroundColor: '#00C85320',
    borderColor: '#00C85350',
  },
  availabilityText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#fff',
  },
  waitingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 24,
  },
  pulseContainer: {
    width: 120,
    height: 120,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 24,
  },
  pulse: {
    position: 'absolute',
    width: 120,
    height: 120,
    borderRadius: 60,
    backgroundColor: 'rgba(0, 122, 255, 0.2)',
  },
  pulse2: {
    width: 90,
    height: 90,
    borderRadius: 45,
    backgroundColor: 'rgba(0, 122, 255, 0.3)',
  },
  pulseCenter: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: '#007AFF',
    justifyContent: 'center',
    alignItems: 'center',
  },
  pulseIcon: {
    fontSize: 24,
  },
  waitingTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: '#fff',
    marginBottom: 8,
  },
  waitingSubtitle: {
    fontSize: 14,
    color: '#888',
    textAlign: 'center',
  },
  offlineIcon: {
    fontSize: 48,
    marginBottom: 16,
  },
  offlineTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: '#666',
    marginBottom: 8,
  },
  offlineSubtitle: {
    fontSize: 14,
    color: '#555',
    textAlign: 'center',
  },
  statsContainer: {
    flexDirection: 'row',
    marginHorizontal: 24,
    marginBottom: 24,
    backgroundColor: '#2a2a2a',
    borderRadius: 16,
    padding: 20,
  },
  statItem: {
    flex: 1,
    alignItems: 'center',
  },
  statValue: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#fff',
  },
  statLabel: {
    fontSize: 12,
    color: '#888',
    marginTop: 4,
  },
  statDivider: {
    width: 1,
    backgroundColor: '#333',
    marginHorizontal: 16,
  },
});

export default ProfessionalScreen;
