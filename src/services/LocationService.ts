import Geolocation, {
  GeoPosition,
  GeoError,
  GeoOptions,
} from 'react-native-geolocation-service';
import { Platform, PermissionsAndroid } from 'react-native';
import { GPSLocation } from '../types';

type LocationCallback = (location: GPSLocation) => void;
type ErrorCallback = (error: string) => void;

const DEFAULT_OPTIONS: GeoOptions = {
  enableHighAccuracy: true,
  timeout: 15000,
  maximumAge: 10000,
  distanceFilter: 0,
  forceRequestLocation: true,
  forceLocationManager: false,
  showLocationDialog: true,
};

export class LocationService {
  private watchId: number | null = null;
  private locationCallbacks: Set<LocationCallback> = new Set();
  private errorCallbacks: Set<ErrorCallback> = new Set();
  private lastLocation: GPSLocation | null = null;
  private isTracking: boolean = false;

  /**
   * Request location permissions from the user
   */
  async requestPermissions(): Promise<boolean> {
    if (Platform.OS === 'ios') {
      const status = await Geolocation.requestAuthorization('whenInUse');
      return status === 'granted';
    }

    if (Platform.OS === 'android') {
      try {
        const granted = await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION,
          {
            title: 'Location Permission',
            message:
              'This app needs access to your location to help professionals locate you during assistance.',
            buttonNeutral: 'Ask Me Later',
            buttonNegative: 'Cancel',
            buttonPositive: 'OK',
          }
        );

        if (granted === PermissionsAndroid.RESULTS.GRANTED) {
          // Also request background location for Android 10+
          if (Platform.Version >= 29) {
            await PermissionsAndroid.request(
              PermissionsAndroid.PERMISSIONS.ACCESS_BACKGROUND_LOCATION,
              {
                title: 'Background Location Permission',
                message:
                  'This app needs access to your location in the background for continuous tracking during assistance.',
                buttonNeutral: 'Ask Me Later',
                buttonNegative: 'Cancel',
                buttonPositive: 'OK',
              }
            );
          }
          return true;
        }
        return false;
      } catch (err) {
        console.error('Location permission error:', err);
        return false;
      }
    }

    return false;
  }

  /**
   * Get the current location once
   */
  async getCurrentLocation(options?: Partial<GeoOptions>): Promise<GPSLocation> {
    const hasPermission = await this.requestPermissions();
    if (!hasPermission) {
      throw new Error('Location permission denied');
    }

    return new Promise((resolve, reject) => {
      Geolocation.getCurrentPosition(
        (position: GeoPosition) => {
          const location = this.positionToGPSLocation(position);
          this.lastLocation = location;
          resolve(location);
        },
        (error: GeoError) => {
          reject(new Error(this.getErrorMessage(error)));
        },
        { ...DEFAULT_OPTIONS, ...options }
      );
    });
  }

  /**
   * Start continuous location tracking
   */
  async startTracking(
    options?: Partial<GeoOptions>,
    intervalMs: number = 5000
  ): Promise<void> {
    if (this.isTracking) {
      console.warn('Location tracking already active');
      return;
    }

    const hasPermission = await this.requestPermissions();
    if (!hasPermission) {
      throw new Error('Location permission denied');
    }

    this.isTracking = true;

    this.watchId = Geolocation.watchPosition(
      (position: GeoPosition) => {
        const location = this.positionToGPSLocation(position);
        this.lastLocation = location;
        this.notifyLocationCallbacks(location);
      },
      (error: GeoError) => {
        this.notifyErrorCallbacks(this.getErrorMessage(error));
      },
      {
        ...DEFAULT_OPTIONS,
        ...options,
        interval: intervalMs,
        fastestInterval: Math.floor(intervalMs / 2),
      }
    );
  }

  /**
   * Stop location tracking
   */
  stopTracking(): void {
    if (this.watchId !== null) {
      Geolocation.clearWatch(this.watchId);
      this.watchId = null;
    }
    this.isTracking = false;
  }

  /**
   * Register a callback for location updates
   */
  onLocationUpdate(callback: LocationCallback): () => void {
    this.locationCallbacks.add(callback);
    return () => this.locationCallbacks.delete(callback);
  }

  /**
   * Register a callback for errors
   */
  onError(callback: ErrorCallback): () => void {
    this.errorCallbacks.add(callback);
    return () => this.errorCallbacks.delete(callback);
  }

  /**
   * Get the last known location
   */
  getLastLocation(): GPSLocation | null {
    return this.lastLocation;
  }

  /**
   * Check if location tracking is active
   */
  isActive(): boolean {
    return this.isTracking;
  }

  /**
   * Calculate distance between two GPS coordinates (Haversine formula)
   */
  calculateDistance(loc1: GPSLocation, loc2: GPSLocation): number {
    const R = 6371e3; // Earth's radius in meters
    const lat1Rad = (loc1.latitude * Math.PI) / 180;
    const lat2Rad = (loc2.latitude * Math.PI) / 180;
    const deltaLat = ((loc2.latitude - loc1.latitude) * Math.PI) / 180;
    const deltaLon = ((loc2.longitude - loc1.longitude) * Math.PI) / 180;

    const a =
      Math.sin(deltaLat / 2) * Math.sin(deltaLat / 2) +
      Math.cos(lat1Rad) *
        Math.cos(lat2Rad) *
        Math.sin(deltaLon / 2) *
        Math.sin(deltaLon / 2);

    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

    return R * c; // Distance in meters
  }

  /**
   * Calculate bearing between two GPS coordinates
   */
  calculateBearing(from: GPSLocation, to: GPSLocation): number {
    const lat1 = (from.latitude * Math.PI) / 180;
    const lat2 = (to.latitude * Math.PI) / 180;
    const deltaLon = ((to.longitude - from.longitude) * Math.PI) / 180;

    const y = Math.sin(deltaLon) * Math.cos(lat2);
    const x =
      Math.cos(lat1) * Math.sin(lat2) -
      Math.sin(lat1) * Math.cos(lat2) * Math.cos(deltaLon);

    const bearing = (Math.atan2(y, x) * 180) / Math.PI;
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  private positionToGPSLocation(position: GeoPosition): GPSLocation {
    return {
      latitude: position.coords.latitude,
      longitude: position.coords.longitude,
      altitude: position.coords.altitude ?? undefined,
      accuracy: position.coords.accuracy,
      heading: position.coords.heading ?? undefined,
      speed: position.coords.speed ?? undefined,
      timestamp: position.timestamp,
    };
  }

  private notifyLocationCallbacks(location: GPSLocation): void {
    this.locationCallbacks.forEach((callback) => callback(location));
  }

  private notifyErrorCallbacks(error: string): void {
    this.errorCallbacks.forEach((callback) => callback(error));
  }

  private getErrorMessage(error: GeoError): string {
    switch (error.code) {
      case 1:
        return 'Location permission denied';
      case 2:
        return 'Location unavailable';
      case 3:
        return 'Location request timed out';
      case 4:
        return 'Google Play Services not available';
      case 5:
        return 'Location settings not satisfied';
      default:
        return `Location error: ${error.message}`;
    }
  }
}

export const locationService = new LocationService();
