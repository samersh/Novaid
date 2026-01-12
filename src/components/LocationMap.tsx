import React, { useRef, useEffect, useState } from 'react';
import {
  View,
  StyleSheet,
  Text,
  TouchableOpacity,
  Dimensions,
} from 'react-native';
import MapView, {
  Marker,
  PROVIDER_GOOGLE,
  Circle,
  Polyline,
  Region,
  MapStyleElement,
} from 'react-native-maps';
import { GPSLocation } from '../types';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

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

const DARK_MAP_STYLE: MapStyleElement[] = [
  { elementType: 'geometry', stylers: [{ color: '#242f3e' }] },
  { elementType: 'labels.text.stroke', stylers: [{ color: '#242f3e' }] },
  { elementType: 'labels.text.fill', stylers: [{ color: '#746855' }] },
  {
    featureType: 'administrative.locality',
    elementType: 'labels.text.fill',
    stylers: [{ color: '#d59563' }],
  },
  {
    featureType: 'poi',
    elementType: 'labels.text.fill',
    stylers: [{ color: '#d59563' }],
  },
  {
    featureType: 'poi.park',
    elementType: 'geometry',
    stylers: [{ color: '#263c3f' }],
  },
  {
    featureType: 'poi.park',
    elementType: 'labels.text.fill',
    stylers: [{ color: '#6b9a76' }],
  },
  {
    featureType: 'road',
    elementType: 'geometry',
    stylers: [{ color: '#38414e' }],
  },
  {
    featureType: 'road',
    elementType: 'geometry.stroke',
    stylers: [{ color: '#212a37' }],
  },
  {
    featureType: 'road',
    elementType: 'labels.text.fill',
    stylers: [{ color: '#9ca5b3' }],
  },
  {
    featureType: 'road.highway',
    elementType: 'geometry',
    stylers: [{ color: '#746855' }],
  },
  {
    featureType: 'road.highway',
    elementType: 'geometry.stroke',
    stylers: [{ color: '#1f2835' }],
  },
  {
    featureType: 'road.highway',
    elementType: 'labels.text.fill',
    stylers: [{ color: '#f3d19c' }],
  },
  {
    featureType: 'transit',
    elementType: 'geometry',
    stylers: [{ color: '#2f3948' }],
  },
  {
    featureType: 'transit.station',
    elementType: 'labels.text.fill',
    stylers: [{ color: '#d59563' }],
  },
  {
    featureType: 'water',
    elementType: 'geometry',
    stylers: [{ color: '#17263c' }],
  },
  {
    featureType: 'water',
    elementType: 'labels.text.fill',
    stylers: [{ color: '#515c6d' }],
  },
  {
    featureType: 'water',
    elementType: 'labels.text.stroke',
    stylers: [{ color: '#17263c' }],
  },
];

export const LocationMap: React.FC<LocationMapProps> = ({
  location,
  showUserMarker = true,
  showAccuracyCircle = true,
  showPath = false,
  pathHistory = [],
  style,
  compact = false,
  onPress,
}) => {
  const mapRef = useRef<MapView>(null);
  const [region, setRegion] = useState<Region>({
    latitude: location?.latitude ?? 0,
    longitude: location?.longitude ?? 0,
    latitudeDelta: compact ? 0.005 : 0.01,
    longitudeDelta: compact ? 0.005 : 0.01,
  });

  useEffect(() => {
    if (location && mapRef.current) {
      mapRef.current.animateToRegion(
        {
          latitude: location.latitude,
          longitude: location.longitude,
          latitudeDelta: region.latitudeDelta,
          longitudeDelta: region.longitudeDelta,
        },
        500
      );
    }
  }, [location, region.latitudeDelta, region.longitudeDelta]);

  const handleCenterOnUser = () => {
    if (location && mapRef.current) {
      mapRef.current.animateToRegion(
        {
          latitude: location.latitude,
          longitude: location.longitude,
          latitudeDelta: 0.005,
          longitudeDelta: 0.005,
        },
        300
      );
    }
  };

  if (!location) {
    return (
      <View style={[styles.container, compact && styles.compactContainer, style]}>
        <View style={styles.placeholder}>
          <Text style={styles.placeholderText}>Location unavailable</Text>
        </View>
      </View>
    );
  }

  const pathCoordinates = pathHistory.map((loc) => ({
    latitude: loc.latitude,
    longitude: loc.longitude,
  }));

  return (
    <TouchableOpacity
      style={[styles.container, compact && styles.compactContainer, style]}
      onPress={onPress}
      activeOpacity={onPress ? 0.9 : 1}
      disabled={!onPress}
    >
      <MapView
        ref={mapRef}
        style={styles.map}
        provider={PROVIDER_GOOGLE}
        customMapStyle={DARK_MAP_STYLE}
        initialRegion={region}
        onRegionChangeComplete={setRegion}
        showsUserLocation={false}
        showsMyLocationButton={false}
        showsCompass={!compact}
        showsScale={!compact}
        rotateEnabled={!compact}
        scrollEnabled={!compact}
        zoomEnabled={!compact}
        pitchEnabled={false}
      >
        {showUserMarker && (
          <Marker
            coordinate={{
              latitude: location.latitude,
              longitude: location.longitude,
            }}
            title="User Location"
            description={`Accuracy: ${location.accuracy?.toFixed(0) ?? 'N/A'}m`}
          >
            <View style={styles.markerContainer}>
              <View style={styles.markerOuter}>
                <View style={styles.markerInner} />
              </View>
              {location.heading !== undefined && (
                <View
                  style={[
                    styles.headingIndicator,
                    { transform: [{ rotate: `${location.heading}deg` }] },
                  ]}
                />
              )}
            </View>
          </Marker>
        )}

        {showAccuracyCircle && location.accuracy && (
          <Circle
            center={{
              latitude: location.latitude,
              longitude: location.longitude,
            }}
            radius={location.accuracy}
            strokeColor="rgba(0, 122, 255, 0.5)"
            fillColor="rgba(0, 122, 255, 0.1)"
            strokeWidth={1}
          />
        )}

        {showPath && pathCoordinates.length > 1 && (
          <Polyline
            coordinates={pathCoordinates}
            strokeColor="#007AFF"
            strokeWidth={3}
            lineDashPattern={[1]}
          />
        )}
      </MapView>

      {/* Location info overlay */}
      {!compact && (
        <View style={styles.infoOverlay}>
          <Text style={styles.infoText}>
            {location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}
          </Text>
          {location.accuracy && (
            <Text style={styles.accuracyText}>
              ±{location.accuracy.toFixed(0)}m
            </Text>
          )}
          {location.speed !== undefined && location.speed > 0 && (
            <Text style={styles.speedText}>
              {(location.speed * 3.6).toFixed(1)} km/h
            </Text>
          )}
        </View>
      )}

      {/* Center button */}
      {!compact && (
        <TouchableOpacity
          style={styles.centerButton}
          onPress={handleCenterOnUser}
        >
          <View style={styles.centerIcon} />
        </TouchableOpacity>
      )}

      {/* Compact location badge */}
      {compact && (
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
  map: {
    flex: 1,
  },
  placeholder: {
    flex: 1,
    backgroundColor: '#1a1a1a',
    justifyContent: 'center',
    alignItems: 'center',
  },
  placeholderText: {
    color: '#666',
    fontSize: 14,
  },
  markerContainer: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  markerOuter: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: 'rgba(0, 122, 255, 0.3)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  markerInner: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: '#007AFF',
    borderWidth: 2,
    borderColor: '#fff',
  },
  headingIndicator: {
    position: 'absolute',
    top: -8,
    width: 0,
    height: 0,
    borderLeftWidth: 6,
    borderRightWidth: 6,
    borderBottomWidth: 10,
    borderLeftColor: 'transparent',
    borderRightColor: 'transparent',
    borderBottomColor: '#007AFF',
  },
  infoOverlay: {
    position: 'absolute',
    bottom: 10,
    left: 10,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    borderRadius: 8,
    padding: 8,
  },
  infoText: {
    color: '#fff',
    fontSize: 12,
    fontFamily: 'monospace',
  },
  accuracyText: {
    color: '#007AFF',
    fontSize: 10,
    marginTop: 2,
  },
  speedText: {
    color: '#00FF00',
    fontSize: 10,
    marginTop: 2,
  },
  centerButton: {
    position: 'absolute',
    bottom: 10,
    right: 10,
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  centerIcon: {
    width: 16,
    height: 16,
    borderRadius: 8,
    borderWidth: 2,
    borderColor: '#007AFF',
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
