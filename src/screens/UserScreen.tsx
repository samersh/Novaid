import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  StatusBar,
  Alert,
  ActivityIndicator,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../types';
import { useApp } from '../context/AppContext';
import { CallButton } from '../components/CallControls';
import { userService } from '../services/UserService';

type UserScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'UserScreen'>;

export const UserScreen: React.FC = () => {
  const navigation = useNavigation<UserScreenNavigationProp>();
  const { state, initializeApp, initiateCall } = useApp();
  const [isInitializing, setIsInitializing] = useState(true);

  useEffect(() => {
    const init = async () => {
      try {
        await initializeApp('user');
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
      navigation.navigate('CallScreen', { role: 'user' });
    }
  }, [state.callState.isConnected, navigation]);

  const handleCallPress = async () => {
    if (!state.isConnectedToServer) {
      Alert.alert('Not Connected', 'Please wait while connecting to server...');
      return;
    }

    try {
      await initiateCall();
    } catch (error) {
      Alert.alert('Call Failed', 'Unable to connect. Please try again.');
    }
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

  const userCode = state.user?.uniqueCode
    ? userService.formatCodeForDisplay(state.user.uniqueCode)
    : '------';

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#1a1a1a" />

      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>Need Help?</Text>
        <Text style={styles.subtitle}>
          Tap the button below to connect with a professional instantly
        </Text>
      </View>

      {/* User ID Display */}
      <View style={styles.idContainer}>
        <Text style={styles.idLabel}>Your ID</Text>
        <Text style={styles.idCode}>{userCode}</Text>
        <View style={styles.connectionStatus}>
          <View
            style={[
              styles.statusDot,
              state.isConnectedToServer ? styles.statusConnected : styles.statusDisconnected,
            ]}
          />
          <Text style={styles.statusText}>
            {state.isConnectedToServer ? 'Connected' : 'Connecting...'}
          </Text>
        </View>
      </View>

      {/* Call Button */}
      <View style={styles.callContainer}>
        <CallButton
          onPress={handleCallPress}
          isLoading={state.callState.isConnecting}
          isActive={state.callState.isConnected}
          size={140}
          label="Call for Help"
        />
      </View>

      {/* Instructions */}
      <View style={styles.instructions}>
        <View style={styles.instructionItem}>
          <Text style={styles.instructionNumber}>1</Text>
          <Text style={styles.instructionText}>Tap the call button</Text>
        </View>
        <View style={styles.instructionItem}>
          <Text style={styles.instructionNumber}>2</Text>
          <Text style={styles.instructionText}>Point your camera at the issue</Text>
        </View>
        <View style={styles.instructionItem}>
          <Text style={styles.instructionNumber}>3</Text>
          <Text style={styles.instructionText}>Follow the AR guidance</Text>
        </View>
      </View>

      {/* Error display */}
      {state.error && (
        <View style={styles.errorContainer}>
          <Text style={styles.errorText}>{state.error}</Text>
        </View>
      )}
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
    paddingHorizontal: 24,
    paddingTop: 40,
    alignItems: 'center',
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#fff',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 16,
    color: '#888',
    textAlign: 'center',
    lineHeight: 24,
  },
  idContainer: {
    alignItems: 'center',
    marginTop: 30,
    paddingVertical: 20,
    marginHorizontal: 24,
    backgroundColor: '#2a2a2a',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#333',
  },
  idLabel: {
    fontSize: 12,
    color: '#888',
    textTransform: 'uppercase',
    letterSpacing: 2,
  },
  idCode: {
    fontSize: 36,
    fontWeight: 'bold',
    color: '#007AFF',
    marginTop: 8,
    fontFamily: 'monospace',
    letterSpacing: 4,
  },
  connectionStatus: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 12,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 8,
  },
  statusConnected: {
    backgroundColor: '#00FF00',
  },
  statusDisconnected: {
    backgroundColor: '#FF3B30',
  },
  statusText: {
    fontSize: 12,
    color: '#888',
  },
  callContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  instructions: {
    paddingHorizontal: 24,
    paddingBottom: 40,
  },
  instructionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  instructionNumber: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: '#333',
    color: '#007AFF',
    fontSize: 14,
    fontWeight: 'bold',
    textAlign: 'center',
    lineHeight: 28,
    marginRight: 12,
  },
  instructionText: {
    fontSize: 14,
    color: '#888',
  },
  errorContainer: {
    position: 'absolute',
    bottom: 100,
    left: 24,
    right: 24,
    backgroundColor: 'rgba(255, 59, 48, 0.2)',
    borderRadius: 8,
    padding: 12,
    borderWidth: 1,
    borderColor: '#FF3B30',
  },
  errorText: {
    color: '#FF3B30',
    fontSize: 14,
    textAlign: 'center',
  },
});

export default UserScreen;
