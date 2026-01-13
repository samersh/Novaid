import AsyncStorage from '@react-native-async-storage/async-storage';
import { User, UserRole } from '../types';

const USER_STORAGE_KEY = '@novaid_user';

/**
 * User ID Service
 *
 * Manages unique user identification without requiring manual input.
 * Uses a combination of:
 * 1. Stored persistent ID (first priority)
 * 2. Generated UUID for new users
 */

export class UserIdService {
  private currentUser: User | null = null;

  /**
   * Generate a unique user ID
   * Uses a combination of timestamp and random values for uniqueness
   */
  private generateUniqueId(): string {
    const timestamp = Date.now().toString(36);
    const randomPart1 = Math.random().toString(36).substring(2, 8);
    const randomPart2 = Math.random().toString(36).substring(2, 8);
    return `${timestamp}-${randomPart1}-${randomPart2}`;
  }

  /**
   * Initialize or retrieve user
   * Automatically creates a new user if none exists
   */
  public async initializeUser(role: UserRole): Promise<User> {
    try {
      // Try to load existing user
      const storedUser = await this.loadStoredUser();

      if (storedUser && storedUser.role === role) {
        this.currentUser = storedUser;
        return storedUser;
      }

      // Create new user if none exists or role changed
      const newUser: User = {
        id: this.generateUniqueId(),
        role: role,
        createdAt: Date.now(),
      };

      await this.saveUser(newUser);
      this.currentUser = newUser;

      return newUser;
    } catch (error) {
      console.error('Error initializing user:', error);
      // Fallback to new user creation
      const fallbackUser: User = {
        id: this.generateUniqueId(),
        role: role,
        createdAt: Date.now(),
      };
      this.currentUser = fallbackUser;
      return fallbackUser;
    }
  }

  /**
   * Load stored user from AsyncStorage
   */
  private async loadStoredUser(): Promise<User | null> {
    try {
      const userData = await AsyncStorage.getItem(USER_STORAGE_KEY);
      if (userData) {
        return JSON.parse(userData) as User;
      }
      return null;
    } catch (error) {
      console.error('Error loading stored user:', error);
      return null;
    }
  }

  /**
   * Save user to AsyncStorage
   */
  private async saveUser(user: User): Promise<void> {
    try {
      await AsyncStorage.setItem(USER_STORAGE_KEY, JSON.stringify(user));
    } catch (error) {
      console.error('Error saving user:', error);
    }
  }

  /**
   * Get current user
   */
  public getCurrentUser(): User | null {
    return this.currentUser;
  }

  /**
   * Get current user ID
   */
  public getUserId(): string | null {
    return this.currentUser?.id || null;
  }

  /**
   * Clear user data (for logout or reset)
   */
  public async clearUser(): Promise<void> {
    try {
      await AsyncStorage.removeItem(USER_STORAGE_KEY);
      this.currentUser = null;
    } catch (error) {
      console.error('Error clearing user:', error);
    }
  }

  /**
   * Update user data
   */
  public async updateUser(updates: Partial<User>): Promise<User | null> {
    if (!this.currentUser) {
      return null;
    }

    const updatedUser: User = {
      ...this.currentUser,
      ...updates,
      id: this.currentUser.id, // ID should never change
    };

    await this.saveUser(updatedUser);
    this.currentUser = updatedUser;

    return updatedUser;
  }

  /**
   * Generate a display-friendly short ID
   */
  public getShortId(): string {
    if (!this.currentUser) {
      return 'Unknown';
    }
    // Return last 6 characters of ID for display
    return this.currentUser.id.slice(-6).toUpperCase();
  }

  /**
   * Check if user is initialized
   */
  public isInitialized(): boolean {
    return this.currentUser !== null;
  }
}

// Singleton instance for app-wide use
export const userIdService = new UserIdService();

export default UserIdService;
