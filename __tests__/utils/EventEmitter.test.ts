import { EventEmitter } from '../../src/utils/EventEmitter';

describe('EventEmitter', () => {
  let emitter: EventEmitter;

  beforeEach(() => {
    emitter = new EventEmitter();
  });

  afterEach(() => {
    emitter.removeAllListeners();
  });

  describe('on', () => {
    it('should register event listener', () => {
      const callback = jest.fn();
      emitter.on('test', callback);
      emitter.emit('test');

      expect(callback).toHaveBeenCalled();
    });

    it('should pass arguments to callback', () => {
      const callback = jest.fn();
      emitter.on('test', callback);
      emitter.emit('test', 'arg1', 'arg2');

      expect(callback).toHaveBeenCalledWith('arg1', 'arg2');
    });

    it('should return unsubscribe function', () => {
      const callback = jest.fn();
      const unsubscribe = emitter.on('test', callback);

      unsubscribe();
      emitter.emit('test');

      expect(callback).not.toHaveBeenCalled();
    });

    it('should allow multiple listeners for same event', () => {
      const callback1 = jest.fn();
      const callback2 = jest.fn();

      emitter.on('test', callback1);
      emitter.on('test', callback2);
      emitter.emit('test');

      expect(callback1).toHaveBeenCalled();
      expect(callback2).toHaveBeenCalled();
    });
  });

  describe('off', () => {
    it('should remove specific listener', () => {
      const callback = jest.fn();
      emitter.on('test', callback);
      emitter.off('test', callback);
      emitter.emit('test');

      expect(callback).not.toHaveBeenCalled();
    });

    it('should not affect other listeners', () => {
      const callback1 = jest.fn();
      const callback2 = jest.fn();

      emitter.on('test', callback1);
      emitter.on('test', callback2);
      emitter.off('test', callback1);
      emitter.emit('test');

      expect(callback1).not.toHaveBeenCalled();
      expect(callback2).toHaveBeenCalled();
    });

    it('should handle removing non-existent listener', () => {
      const callback = jest.fn();
      emitter.off('test', callback);
      // Should not throw
      expect(true).toBe(true);
    });
  });

  describe('emit', () => {
    it('should not throw when no listeners', () => {
      emitter.emit('non-existent');
      // Should not throw
      expect(true).toBe(true);
    });

    it('should handle callback errors gracefully', () => {
      const errorCallback = jest.fn(() => {
        throw new Error('Callback error');
      });
      const normalCallback = jest.fn();

      emitter.on('test', errorCallback);
      emitter.on('test', normalCallback);

      emitter.emit('test');

      expect(errorCallback).toHaveBeenCalled();
      expect(normalCallback).toHaveBeenCalled();
    });
  });

  describe('once', () => {
    it('should only call listener once', () => {
      const callback = jest.fn();
      emitter.once('test', callback);

      emitter.emit('test');
      emitter.emit('test');
      emitter.emit('test');

      expect(callback).toHaveBeenCalledTimes(1);
    });

    it('should return unsubscribe function', () => {
      const callback = jest.fn();
      const unsubscribe = emitter.once('test', callback);

      unsubscribe();
      emitter.emit('test');

      expect(callback).not.toHaveBeenCalled();
    });
  });

  describe('removeAllListeners', () => {
    it('should remove all listeners for specific event', () => {
      const callback1 = jest.fn();
      const callback2 = jest.fn();

      emitter.on('test', callback1);
      emitter.on('test', callback2);
      emitter.removeAllListeners('test');
      emitter.emit('test');

      expect(callback1).not.toHaveBeenCalled();
      expect(callback2).not.toHaveBeenCalled();
    });

    it('should remove all listeners when no event specified', () => {
      const callback1 = jest.fn();
      const callback2 = jest.fn();

      emitter.on('test1', callback1);
      emitter.on('test2', callback2);
      emitter.removeAllListeners();

      emitter.emit('test1');
      emitter.emit('test2');

      expect(callback1).not.toHaveBeenCalled();
      expect(callback2).not.toHaveBeenCalled();
    });
  });
});
