import { io, Socket } from 'socket.io-client';
import { GPSLocation, Annotation, AnnotationFrame } from '../types';

type EventCallback = (...args: any[]) => void;

interface SocketEvents {
  // Connection events
  connect: () => void;
  disconnect: () => void;
  error: (error: string) => void;

  // Call events
  'call:incoming': (data: { callerId: string; callerCode: string }) => void;
  'call:accepted': (data: { sessionId: string; professionalId: string }) => void;
  'call:rejected': (data: { reason: string }) => void;
  'call:ended': () => void;

  // WebRTC signaling
  'signal:offer': (data: { offer: RTCSessionDescriptionInit; from: string }) => void;
  'signal:answer': (data: { answer: RTCSessionDescriptionInit; from: string }) => void;
  'signal:ice': (data: { candidate: RTCIceCandidateInit; from: string }) => void;

  // Location events
  'location:update': (data: { location: GPSLocation }) => void;

  // Annotation events
  'annotation:received': (data: { annotation: Annotation }) => void;
  'annotation:clear': () => void;
  'frame:frozen': (data: { frameData: string; timestamp: number }) => void;
  'frame:resumed': () => void;

  // User events
  'user:registered': (data: { uniqueCode: string }) => void;
  'user:status': (data: { isAvailable: boolean }) => void;
}

export class SocketService {
  private socket: Socket | null = null;
  private serverUrl: string;
  private userId: string = '';
  private eventHandlers: Map<string, Set<EventCallback>> = new Map();
  private reconnectAttempts: number = 0;
  private maxReconnectAttempts: number = 5;
  private reconnectDelay: number = 1000;

  constructor(serverUrl: string = 'http://localhost:3000') {
    this.serverUrl = serverUrl;
  }

  connect(userId: string, role: 'user' | 'professional'): Promise<void> {
    return new Promise((resolve, reject) => {
      this.userId = userId;

      this.socket = io(this.serverUrl, {
        transports: ['websocket'],
        auth: {
          userId,
          role,
        },
        reconnection: true,
        reconnectionAttempts: this.maxReconnectAttempts,
        reconnectionDelay: this.reconnectDelay,
      });

      this.socket.on('connect', () => {
        console.log('Socket connected:', this.socket?.id);
        this.reconnectAttempts = 0;
        this.emit('user:register', { userId, role });
        resolve();
      });

      this.socket.on('disconnect', (reason) => {
        console.log('Socket disconnected:', reason);
        this.notifyHandlers('disconnect', reason);
      });

      this.socket.on('connect_error', (error) => {
        console.error('Socket connection error:', error);
        this.reconnectAttempts++;
        if (this.reconnectAttempts >= this.maxReconnectAttempts) {
          reject(new Error('Failed to connect to server'));
        }
      });

      // Set up event forwarding
      this.setupEventForwarding();
    });
  }

  private setupEventForwarding(): void {
    const events = [
      'call:incoming',
      'call:accepted',
      'call:rejected',
      'call:ended',
      'signal:offer',
      'signal:answer',
      'signal:ice',
      'location:update',
      'annotation:received',
      'annotation:clear',
      'frame:frozen',
      'frame:resumed',
      'user:registered',
      'user:status',
      'error',
    ];

    events.forEach((event) => {
      this.socket?.on(event, (data: any) => {
        this.notifyHandlers(event, data);
      });
    });
  }

  private notifyHandlers(event: string, data?: any): void {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      handlers.forEach((handler) => handler(data));
    }
  }

  on<K extends keyof SocketEvents>(event: K, callback: SocketEvents[K]): () => void {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, new Set());
    }
    this.eventHandlers.get(event)!.add(callback as EventCallback);

    return () => {
      this.eventHandlers.get(event)?.delete(callback as EventCallback);
    };
  }

  off<K extends keyof SocketEvents>(event: K, callback?: SocketEvents[K]): void {
    if (callback) {
      this.eventHandlers.get(event)?.delete(callback as EventCallback);
    } else {
      this.eventHandlers.delete(event);
    }
  }

  emit(event: string, data?: any): void {
    if (this.socket?.connected) {
      this.socket.emit(event, data);
    } else {
      console.warn('Socket not connected, cannot emit:', event);
    }
  }

  // Call methods
  initiateCall(targetCode?: string): void {
    this.emit('call:initiate', {
      callerId: this.userId,
      targetCode,
    });
  }

  acceptCall(callerId: string): void {
    this.emit('call:accept', {
      callerId,
      professionalId: this.userId,
    });
  }

  rejectCall(callerId: string, reason: string = 'Busy'): void {
    this.emit('call:reject', {
      callerId,
      reason,
    });
  }

  endCall(): void {
    this.emit('call:end', { userId: this.userId });
  }

  // WebRTC signaling methods
  sendOffer(offer: RTCSessionDescriptionInit, targetId: string): void {
    this.emit('signal:offer', {
      offer,
      from: this.userId,
      to: targetId,
    });
  }

  sendAnswer(answer: RTCSessionDescriptionInit, targetId: string): void {
    this.emit('signal:answer', {
      answer,
      from: this.userId,
      to: targetId,
    });
  }

  sendIceCandidate(candidate: RTCIceCandidateInit, targetId: string): void {
    this.emit('signal:ice', {
      candidate,
      from: this.userId,
      to: targetId,
    });
  }

  // Location methods
  sendLocation(location: GPSLocation): void {
    this.emit('location:update', {
      userId: this.userId,
      location,
    });
  }

  // Annotation methods
  sendAnnotation(annotation: Annotation): void {
    this.emit('annotation:add', {
      userId: this.userId,
      annotation,
    });
  }

  clearAnnotations(): void {
    this.emit('annotation:clear', { userId: this.userId });
  }

  freezeFrame(frameData: string, timestamp: number): void {
    this.emit('frame:freeze', {
      userId: this.userId,
      frameData,
      timestamp,
    });
  }

  resumeFrame(): void {
    this.emit('frame:resume', { userId: this.userId });
  }

  // Utility methods
  disconnect(): void {
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
    }
    this.eventHandlers.clear();
  }

  isConnected(): boolean {
    return this.socket?.connected || false;
  }

  getSocketId(): string | null {
    return this.socket?.id || null;
  }

  getUserId(): string {
    return this.userId;
  }
}

export const socketService = new SocketService();
