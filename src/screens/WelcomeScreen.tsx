import React, { useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  SafeAreaView,
  StatusBar,
  Animated,
  Dimensions,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../types';

type WelcomeScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'Welcome'>;

const { width } = Dimensions.get('window');

export const WelcomeScreen: React.FC = () => {
  const navigation = useNavigation<WelcomeScreenNavigationProp>();
  const pulseAnim = useRef(new Animated.Value(1)).current;
  const fadeAnim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    // Fade in animation
    Animated.timing(fadeAnim, {
      toValue: 1,
      duration: 800,
      useNativeDriver: true,
    }).start();

    // Pulse animation for call button
    const pulse = Animated.loop(
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
    pulse.start();

    return () => pulse.stop();
  }, []);

  const handleCallPress = () => {
    navigation.navigate('UserScreen');
  };

  const handleProfessionalPress = () => {
    navigation.navigate('Home');
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#0a0a0a" />

      <Animated.View style={[styles.content, { opacity: fadeAnim }]}>
        <View style={styles.header}>
          <Text style={styles.logo}>NOVAID</Text>
          <Text style={styles.tagline}>Emergency Remote Assistance</Text>
        </View>

        <View style={styles.callSection}>
          <Text style={styles.helpText}>Need immediate help?</Text>

          <Animated.View style={{ transform: [{ scale: pulseAnim }] }}>
            <TouchableOpacity
              style={styles.callButton}
              onPress={handleCallPress}
              activeOpacity={0.8}
            >
              <View style={styles.callButtonInner}>
                <Text style={styles.phoneIcon}>📞</Text>
                <Text style={styles.callButtonText}>START CALL</Text>
              </View>
            </TouchableOpacity>
          </Animated.View>

          <Text style={styles.callDescription}>
            Tap to connect with a professional who can see your camera and guide you remotely
          </Text>
        </View>

        <View style={styles.divider}>
          <View style={styles.dividerLine} />
          <Text style={styles.dividerText}>OR</Text>
          <View style={styles.dividerLine} />
        </View>

        <TouchableOpacity
          style={styles.professionalButton}
          onPress={handleProfessionalPress}
          activeOpacity={0.8}
        >
          <Text style={styles.professionalIcon}>👨‍💼</Text>
          <Text style={styles.professionalText}>I'm a Professional</Text>
          <Text style={styles.arrow}>→</Text>
        </TouchableOpacity>
      </Animated.View>

      <View style={styles.footer}>
        <Text style={styles.footerText}>Secure • Real-time • Easy to use</Text>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0a0a0a',
  },
  content: {
    flex: 1,
    paddingHorizontal: 24,
    justifyContent: 'center',
  },
  header: {
    alignItems: 'center',
    marginBottom: 60,
  },
  logo: {
    fontSize: 48,
    fontWeight: 'bold',
    color: '#007AFF',
    letterSpacing: 6,
  },
  tagline: {
    fontSize: 16,
    color: '#666',
    marginTop: 12,
    letterSpacing: 1,
  },
  callSection: {
    alignItems: 'center',
  },
  helpText: {
    fontSize: 22,
    fontWeight: '600',
    color: '#fff',
    marginBottom: 30,
  },
  callButton: {
    width: width * 0.55,
    height: width * 0.55,
    borderRadius: width * 0.275,
    backgroundColor: '#FF3B30',
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#FF3B30',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.5,
    shadowRadius: 30,
    elevation: 20,
  },
  callButtonInner: {
    alignItems: 'center',
  },
  phoneIcon: {
    fontSize: 60,
    marginBottom: 12,
  },
  callButtonText: {
    fontSize: 22,
    fontWeight: 'bold',
    color: '#fff',
    letterSpacing: 2,
  },
  callDescription: {
    fontSize: 14,
    color: '#888',
    textAlign: 'center',
    marginTop: 30,
    paddingHorizontal: 20,
    lineHeight: 22,
  },
  divider: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 40,
  },
  dividerLine: {
    flex: 1,
    height: 1,
    backgroundColor: '#333',
  },
  dividerText: {
    color: '#666',
    paddingHorizontal: 16,
    fontSize: 14,
  },
  professionalButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1a1a1a',
    borderRadius: 16,
    padding: 20,
    borderWidth: 1,
    borderColor: '#333',
  },
  professionalIcon: {
    fontSize: 28,
    marginRight: 16,
  },
  professionalText: {
    flex: 1,
    fontSize: 18,
    fontWeight: '500',
    color: '#fff',
  },
  arrow: {
    fontSize: 24,
    color: '#666',
  },
  footer: {
    alignItems: 'center',
    paddingVertical: 24,
  },
  footerText: {
    fontSize: 12,
    color: '#444',
  },
});

export default WelcomeScreen;
