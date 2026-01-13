import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, StatusBar } from 'react-native';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import {
  UserStackParamList,
  ProfessionalStackParamList,
  RootStackParamList,
} from '../types';
import {
  UserSplashScreen,
  UserHomeScreen,
  UserVideoCallScreen,
  ProfessionalSplashScreen,
  ProfessionalHomeScreen,
  ProfessionalVideoCallScreen,
} from '../screens';

// Create stack navigators
const UserStack = createNativeStackNavigator<UserStackParamList>();
const ProfessionalStack = createNativeStackNavigator<ProfessionalStackParamList>();
const RootStack = createNativeStackNavigator<RootStackParamList>();

// User Navigator
function UserNavigator() {
  return (
    <UserStack.Navigator
      screenOptions={{
        headerShown: false,
        animation: 'fade',
      }}
    >
      <UserStack.Screen name="UserSplash" component={UserSplashScreen} />
      <UserStack.Screen name="UserHome" component={UserHomeScreen} />
      <UserStack.Screen name="UserVideoCall" component={UserVideoCallScreen} />
    </UserStack.Navigator>
  );
}

// Professional Navigator
function ProfessionalNavigator() {
  return (
    <ProfessionalStack.Navigator
      screenOptions={{
        headerShown: false,
        animation: 'fade',
      }}
    >
      <ProfessionalStack.Screen name="ProfessionalSplash" component={ProfessionalSplashScreen} />
      <ProfessionalStack.Screen name="ProfessionalHome" component={ProfessionalHomeScreen} />
      <ProfessionalStack.Screen name="ProfessionalVideoCall" component={ProfessionalVideoCallScreen} />
    </ProfessionalStack.Navigator>
  );
}

// Role Selection Screen
interface RoleSelectionScreenProps {
  navigation: any;
}

function RoleSelectionScreen({ navigation }: RoleSelectionScreenProps) {
  return (
    <View style={styles.roleContainer}>
      <StatusBar barStyle="light-content" backgroundColor="#0f0f23" />

      <View style={styles.logoSection}>
        <View style={styles.logo}>
          <Text style={styles.logoText}>N</Text>
        </View>
        <Text style={styles.title}>Novaid</Text>
        <Text style={styles.subtitle}>Remote Assistance Platform</Text>
      </View>

      <Text style={styles.selectText}>Select your role</Text>

      <View style={styles.roleButtons}>
        <TouchableOpacity
          style={[styles.roleButton, styles.userButton]}
          onPress={() => navigation.navigate('UserStack')}
          activeOpacity={0.8}
        >
          <Text style={styles.roleIcon}>👤</Text>
          <Text style={styles.roleName}>User</Text>
          <Text style={styles.roleDescription}>Get remote assistance from a professional</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.roleButton, styles.professionalButton]}
          onPress={() => navigation.navigate('ProfessionalStack')}
          activeOpacity={0.8}
        >
          <Text style={styles.roleIcon}>👨‍💼</Text>
          <Text style={styles.roleName}>Professional</Text>
          <Text style={styles.roleDescription}>Provide remote assistance to users</Text>
        </TouchableOpacity>
      </View>

      <Text style={styles.versionText}>Version 1.0.0</Text>
    </View>
  );
}

// Main App Navigator
export function AppNavigator() {
  return (
    <NavigationContainer>
      <RootStack.Navigator
        screenOptions={{
          headerShown: false,
          animation: 'fade',
        }}
      >
        <RootStack.Screen name="RoleSelection" component={RoleSelectionScreen} />
        <RootStack.Screen name="UserStack" component={UserNavigator} />
        <RootStack.Screen name="ProfessionalStack" component={ProfessionalNavigator} />
      </RootStack.Navigator>
    </NavigationContainer>
  );
}

const styles = StyleSheet.create({
  roleContainer: {
    flex: 1,
    backgroundColor: '#0f0f23',
    padding: 20,
    justifyContent: 'center',
  },
  logoSection: {
    alignItems: 'center',
    marginBottom: 40,
  },
  logo: {
    width: 100,
    height: 100,
    borderRadius: 50,
    backgroundColor: '#4361ee',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 16,
    shadowColor: '#4361ee',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.5,
    shadowRadius: 20,
    elevation: 10,
  },
  logoText: {
    fontSize: 48,
    fontWeight: 'bold',
    color: '#ffffff',
  },
  title: {
    fontSize: 36,
    fontWeight: 'bold',
    color: '#ffffff',
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 16,
    color: '#666666',
  },
  selectText: {
    fontSize: 18,
    color: '#a0a0a0',
    textAlign: 'center',
    marginBottom: 24,
  },
  roleButtons: {
    gap: 16,
  },
  roleButton: {
    padding: 24,
    borderRadius: 16,
    alignItems: 'center',
  },
  userButton: {
    backgroundColor: 'rgba(67, 97, 238, 0.15)',
    borderWidth: 2,
    borderColor: '#4361ee',
  },
  professionalButton: {
    backgroundColor: 'rgba(233, 69, 96, 0.15)',
    borderWidth: 2,
    borderColor: '#e94560',
  },
  roleIcon: {
    fontSize: 40,
    marginBottom: 8,
  },
  roleName: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#ffffff',
    marginBottom: 4,
  },
  roleDescription: {
    fontSize: 14,
    color: '#666666',
    textAlign: 'center',
  },
  versionText: {
    textAlign: 'center',
    color: '#444444',
    marginTop: 40,
    fontSize: 12,
  },
});

export default AppNavigator;
