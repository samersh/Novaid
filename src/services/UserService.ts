import AsyncStorage from '@react-native-async-storage/async-storage';
import { v4 as uuidv4 } from 'uuid';
import { User } from '../types';

const USER_STORAGE_KEY = '@novaid_user';
const USER_CODE_LENGTH = 6;

export class UserService {
  private currentUser: User | null = null;

  /**
   * Generate a unique user code (6 alphanumeric characters)
   */
  private generateUniqueCode(): string {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed ambiguous chars (0, O, I, 1)
    let code = '';
    for (let i = 0; i < USER_CODE_LENGTH; i++) {
      code += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return code;
  }

  /**
   * Initialize or retrieve the user
   */
  async initializeUser(role: 'user' | 'professional'): Promise<User> {
    try {
      // Try to load existing user
      const storedUser = await AsyncStorage.getItem(USER_STORAGE_KEY);

      if (storedUser) {
        const user = JSON.parse(storedUser) as User;
        // Update role if different
        if (user.role !== role) {
          user.role = role;
          await this.saveUser(user);
        }
        this.currentUser = user;
        return user;
      }

      // Create new user
      const newUser: User = {
        id: uuidv4(),
        uniqueCode: this.generateUniqueCode(),
        role,
        createdAt: new Date(),
      };

      await this.saveUser(newUser);
      this.currentUser = newUser;

      return newUser;
    } catch (error) {
      console.error('Error initializing user:', error);
      throw error;
    }
  }

  /**
   * Save user to storage
   */
  private async saveUser(user: User): Promise<void> {
    try {
      await AsyncStorage.setItem(USER_STORAGE_KEY, JSON.stringify(user));
    } catch (error) {
      console.error('Error saving user:', error);
      throw error;
    }
  }

  /**
   * Get current user
   */
  getCurrentUser(): User | null {
    return this.currentUser;
  }

  /**
   * Get user ID
   */
  getUserId(): string | null {
    return this.currentUser?.id || null;
  }

  /**
   * Get user unique code
   */
  getUniqueCode(): string | null {
    return this.currentUser?.uniqueCode || null;
  }

  /**
   * Regenerate unique code
   */
  async regenerateCode(): Promise<string> {
    if (!this.currentUser) {
      throw new Error('No user initialized');
    }

    this.currentUser.uniqueCode = this.generateUniqueCode();
    await this.saveUser(this.currentUser);

    return this.currentUser.uniqueCode;
  }

  /**
   * Update user role
   */
  async updateRole(role: 'user' | 'professional'): Promise<void> {
    if (!this.currentUser) {
      throw new Error('No user initialized');
    }

    this.currentUser.role = role;
    await this.saveUser(this.currentUser);
  }

  /**
   * Clear user data
   */
  async clearUser(): Promise<void> {
    try {
      await AsyncStorage.removeItem(USER_STORAGE_KEY);
      this.currentUser = null;
    } catch (error) {
      console.error('Error clearing user:', error);
      throw error;
    }
  }

  /**
   * Validate a user code format
   */
  isValidCode(code: string): boolean {
    if (code.length !== USER_CODE_LENGTH) return false;
    return /^[A-Z2-9]+$/.test(code);
  }

  /**
   * Format code for display (e.g., "ABC-123")
   */
  formatCodeForDisplay(code: string): string {
    if (code.length !== USER_CODE_LENGTH) return code;
    return `${code.substring(0, 3)}-${code.substring(3)}`;
  }

  /**
   * Parse formatted code
   */
  parseFormattedCode(formattedCode: string): string {
    return formattedCode.replace(/-/g, '').toUpperCase();
  }
}

export const userService = new UserService();
