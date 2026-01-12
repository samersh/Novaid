import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  SafeAreaView,
  StatusBar,
  ActivityIndicator,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../types';

type HomeScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'Home'>;

export const HomeScreen: React.FC = () => {
  const navigation = useNavigation<HomeScreenNavigationProp>();
  const [isLoading, setIsLoading] = useState(false);

  const handleUserPress = () => {
    navigation.navigate('UserScreen');
  };

  const handleProfessionalPress = () => {
    navigation.navigate('ProfessionalScreen');
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#1a1a1a" />

      <View style={styles.header}>
        <Text style={styles.logo}>NOVAID</Text>
        <Text style={styles.tagline}>Remote Assistance Platform</Text>
      </View>

      <View style={styles.content}>
        <Text style={styles.title}>Welcome</Text>
        <Text style={styles.subtitle}>Choose your role to continue</Text>

        <TouchableOpacity
          style={styles.roleButton}
          onPress={handleUserPress}
          activeOpacity={0.8}
        >
          <View style={styles.roleIconContainer}>
            <Text style={styles.roleIcon}>🆘</Text>
          </View>
          <View style={styles.roleInfo}>
            <Text style={styles.roleTitle}>I Need Help</Text>
            <Text style={styles.roleDescription}>
              Connect with a professional for remote assistance
            </Text>
          </View>
          <Text style={styles.arrow}>→</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.roleButton, styles.professionalButton]}
          onPress={handleProfessionalPress}
          activeOpacity={0.8}
        >
          <View style={[styles.roleIconContainer, styles.professionalIcon]}>
            <Text style={styles.roleIcon}>👨‍💼</Text>
          </View>
          <View style={styles.roleInfo}>
            <Text style={styles.roleTitle}>I'm a Professional</Text>
            <Text style={styles.roleDescription}>
              Provide remote assistance to users
            </Text>
          </View>
          <Text style={styles.arrow}>→</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.footer}>
        <Text style={styles.footerText}>
          Secure • Real-time • Easy to use
        </Text>
        <Text style={styles.version}>v1.0.0</Text>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#1a1a1a',
  },
  header: {
    alignItems: 'center',
    paddingTop: 40,
    paddingBottom: 20,
  },
  logo: {
    fontSize: 42,
    fontWeight: 'bold',
    color: '#007AFF',
    letterSpacing: 4,
  },
  tagline: {
    fontSize: 14,
    color: '#888',
    marginTop: 8,
  },
  content: {
    flex: 1,
    paddingHorizontal: 24,
    paddingTop: 40,
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
    marginBottom: 40,
  },
  roleButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#2a2a2a',
    borderRadius: 16,
    padding: 20,
    marginBottom: 16,
    borderWidth: 2,
    borderColor: '#333',
  },
  professionalButton: {
    borderColor: '#007AFF30',
  },
  roleIconContainer: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: '#FF3B3020',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 16,
  },
  professionalIcon: {
    backgroundColor: '#007AFF20',
  },
  roleIcon: {
    fontSize: 28,
  },
  roleInfo: {
    flex: 1,
  },
  roleTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#fff',
    marginBottom: 4,
  },
  roleDescription: {
    fontSize: 14,
    color: '#888',
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
    color: '#666',
  },
  version: {
    fontSize: 10,
    color: '#444',
    marginTop: 4,
  },
});

export default HomeScreen;
