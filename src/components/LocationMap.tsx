import React from 'react';
import {
  View,
  StyleSheet,
  Text,
  TouchableOpacity,
} from 'react-native';
import { GPSLocation } from '../types';

// Note: react-native-maps temporarily disabled due to incompatibility with RN 0.73.4
// Will be re-enabled when upgrading to RN 0.74+

interface LocationMapProps {
  location: GPSLocation | null;
  showUserMarker?: boolean;
  showAccuracyCircle?: boolean;
  showPath?: boolean;
  pathHistory?: GPSLocation[];
  style?: object;
  compact?: boolean;
  onPress?: () => void;
}

export const LocationMap: React.FC<LocationMapProps> = ({
  location,
  style,
  compact = false,
  onPress,
}) => {
  return (
    <TouchableOpacity
      style={[styles.container, compact && styles.compactContainer, style]}
      onPress={onPress}
      activeOpacity={onPress ? 0.9 : 1}
      disabled={!onPress}
    >
      <View style={styles.placeholder}>
        <Text style={styles.placeholderTitle}>Map View</Text>
        {location ? (
          <>
            <Text style={styles.coordsText}>
              {location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}
            </Text>
            {location.accuracy && (
              <Text style={styles.accuracyText}>
                Accuracy: ±{location.accuracy.toFixed(0)}m
              </Text>
            )}
            {location.speed !== undefined && location.speed > 0 && (
              <Text style={styles.speedText}>
                Speed: {(location.speed * 3.6).toFixed(1)} km/h
              </Text>
            )}
          </>
        ) : (
          <Text style={styles.placeholderText}>Location unavailable</Text>
        )}
      </View>

      {/* Compact location badge */}
      {compact && location && (
        <View style={styles.compactBadge}>
          <Text style={styles.compactBadgeText}>LIVE</Text>
        </View>
      )}
    </TouchableOpacity>
  );
};

// Mini map component for PiP display
export const MiniMap: React.FC<{
  location: GPSLocation | null;
  size?: number;
  onPress?: () => void;
}> = ({ location, size = 120, onPress }) => {
  return (
    <LocationMap
      location={location}
      compact
      showAccuracyCircle={false}
      style={{ width: size, height: size, borderRadius: 10 }}
      onPress={onPress}
    />
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    overflow: 'hidden',
    borderRadius: 0,
  },
  compactContainer: {
    borderRadius: 10,
    borderWidth: 2,
    borderColor: '#333',
  },
  placeholder: {
    flex: 1,
    backgroundColor: '#1a1a1a',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 16,
  },
  placeholderTitle: {
    color: '#007AFF',
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  placeholderText: {
    color: '#666',
    fontSize: 14,
  },
  coordsText: {
    color: '#fff',
    fontSize: 14,
    fontFamily: 'monospace',
    marginBottom: 4,
  },
  accuracyText: {
    color: '#007AFF',
    fontSize: 12,
    marginTop: 4,
  },
  speedText: {
    color: '#00FF00',
    fontSize: 12,
    marginTop: 4,
  },
  compactBadge: {
    position: 'absolute',
    top: 4,
    right: 4,
    backgroundColor: '#FF0000',
    borderRadius: 4,
    paddingHorizontal: 4,
    paddingVertical: 2,
  },
  compactBadgeText: {
    color: '#fff',
    fontSize: 8,
    fontWeight: 'bold',
  },
});

export default LocationMap;
