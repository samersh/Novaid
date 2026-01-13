import AsyncStorage from '@react-native-async-storage/async-storage';
import { UserIdService } from '../../src/services/UserIdService';

describe('UserIdService', () => {
  let userIdService: UserIdService;

  beforeEach(() => {
    userIdService = new UserIdService();
    jest.clearAllMocks();
  });

  afterEach(async () => {
    await userIdService.clearUser();
  });

  describe('initializeUser', () => {
    it('should create a new user when none exists', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      const user = await userIdService.initializeUser('user');

      expect(user).toBeDefined();
      expect(user.id).toBeDefined();
      expect(user.role).toBe('user');
      expect(user.createdAt).toBeDefined();
    });

    it('should create user with professional role', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      const user = await userIdService.initializeUser('professional');

      expect(user.role).toBe('professional');
    });

    it('should return existing user with same role', async () => {
      const existingUser = {
        id: 'existing-user-id',
        role: 'user',
        createdAt: Date.now() - 1000,
      };
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(JSON.stringify(existingUser));

      const user = await userIdService.initializeUser('user');

      expect(user.id).toBe('existing-user-id');
    });

    it('should create new user when role changes', async () => {
      const existingUser = {
        id: 'existing-user-id',
        role: 'user',
        createdAt: Date.now() - 1000,
      };
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(JSON.stringify(existingUser));

      const user = await userIdService.initializeUser('professional');

      expect(user.id).not.toBe('existing-user-id');
      expect(user.role).toBe('professional');
    });

    it('should save user to AsyncStorage', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      await userIdService.initializeUser('user');

      expect(AsyncStorage.setItem).toHaveBeenCalled();
    });

    it('should handle AsyncStorage errors gracefully', async () => {
      (AsyncStorage.getItem as jest.Mock).mockRejectedValue(new Error('Storage error'));

      const user = await userIdService.initializeUser('user');

      expect(user).toBeDefined();
      expect(user.role).toBe('user');
    });
  });

  describe('getCurrentUser', () => {
    it('should return null when not initialized', () => {
      const user = userIdService.getCurrentUser();
      expect(user).toBeNull();
    });

    it('should return current user after initialization', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      await userIdService.initializeUser('user');
      const user = userIdService.getCurrentUser();

      expect(user).toBeDefined();
    });
  });

  describe('getUserId', () => {
    it('should return null when not initialized', () => {
      const userId = userIdService.getUserId();
      expect(userId).toBeNull();
    });

    it('should return user ID after initialization', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      await userIdService.initializeUser('user');
      const userId = userIdService.getUserId();

      expect(userId).toBeDefined();
      expect(typeof userId).toBe('string');
    });
  });

  describe('getShortId', () => {
    it('should return Unknown when not initialized', () => {
      const shortId = userIdService.getShortId();
      expect(shortId).toBe('Unknown');
    });

    it('should return last 6 characters uppercased', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      await userIdService.initializeUser('user');
      const shortId = userIdService.getShortId();

      expect(shortId).toBeDefined();
      expect(shortId.length).toBe(6);
      expect(shortId).toBe(shortId.toUpperCase());
    });
  });

  describe('clearUser', () => {
    it('should clear user from memory', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      await userIdService.initializeUser('user');
      await userIdService.clearUser();

      expect(userIdService.getCurrentUser()).toBeNull();
    });

    it('should remove user from AsyncStorage', async () => {
      await userIdService.clearUser();

      expect(AsyncStorage.removeItem).toHaveBeenCalled();
    });
  });

  describe('updateUser', () => {
    it('should return null when not initialized', async () => {
      const result = await userIdService.updateUser({ name: 'Test' });
      expect(result).toBeNull();
    });

    it('should update user properties', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      await userIdService.initializeUser('user');
      const updated = await userIdService.updateUser({ name: 'Test User' });

      expect(updated?.name).toBe('Test User');
    });

    it('should not change user ID', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      await userIdService.initializeUser('user');
      const originalId = userIdService.getUserId();
      await userIdService.updateUser({ name: 'Test' });

      expect(userIdService.getUserId()).toBe(originalId);
    });

    it('should save updated user to AsyncStorage', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      await userIdService.initializeUser('user');
      jest.clearAllMocks();
      await userIdService.updateUser({ name: 'Test' });

      expect(AsyncStorage.setItem).toHaveBeenCalled();
    });
  });

  describe('isInitialized', () => {
    it('should return false when not initialized', () => {
      expect(userIdService.isInitialized()).toBe(false);
    });

    it('should return true after initialization', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      await userIdService.initializeUser('user');

      expect(userIdService.isInitialized()).toBe(true);
    });
  });
});
