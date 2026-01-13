import { io, Socket } from 'socket.io-client';
import { SignalMessage, SignalType, User } from '../types';
import { EventEmitter } from '../utils/EventEmitter';

// Default signaling server URL - can be configured
const DEFAULT_SERVER_URL = 'wss://novaid-signaling.herokuapp.com';

export class SignalingService extends EventEmitter {
  private socket: Socket | null = null;
  private userId: string;
  private serverUrl: string;
  private reconnectAttempts: number = 0;
  private maxReconnectAttempts: number = 5;
  private isConnected: boolean = false;

  constructor(userId: string, serverUrl?: string) {
    super();
    this.userId = userId;
    this.serverUrl = serverUrl || DEFAULT_SERVER_URL;
  }

  public connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      try {
        this.socket = io(this.serverUrl, {
          transports: ['websocket'],
          autoConnect: true,
          reconnection: true,
          reconnectionAttempts: this.maxReconnectAttempts,
          reconnectionDelay: 1000,
          reconnectionDelayMax: 5000,
          query: {
            userId: this.userId,
          },
        });

        this.socket.on('connect', () => {
          console.log('Connected to signaling server');
          this.isConnected = true;
          this.reconnectAttempts = 0;
          this.emit('connected');
          resolve();
        });

        this.socket.on('disconnect', (reason: string) => {
          console.log('Disconnected from signaling server:', reason);
          this.isConnected = false;
          this.emit('disconnected', reason);
        });

        this.socket.on('connect_error', (error: Error) => {
          console.error('Connection error:', error);
          this.reconnectAttempts++;
          this.emit('error', error);

          if (this.reconnectAttempts >= this.maxReconnectAttempts) {
            reject(error);
          }
        });

        // Handle incoming messages
        this.socket.on('message', (message: SignalMessage) => {
          this.handleMessage(message);
        });

        // Handle call requests
        this.socket.on('call-request', (message: SignalMessage) => {
          this.emit('callRequest', message);
        });

        // Handle call accepted
        this.socket.on('call-accepted', (message: SignalMessage) => {
          this.emit('callAccepted', message);
        });

        // Handle call rejected
        this.socket.on('call-rejected', (message: SignalMessage) => {
          this.emit('callRejected', message);
        });

        // Handle professional availability
        this.socket.on('professional-available', (data: { professionalId: string }) => {
          this.emit('professionalAvailable', data);
        });

        // Handle no professional available
        this.socket.on('no-professional-available', () => {
          this.emit('noProfessionalAvailable');
        });

      } catch (error) {
        reject(error);
      }
    });
  }

  private handleMessage(message: SignalMessage): void {
    // Route message to appropriate handler based on type
    switch (message.type) {
      case 'offer':
        this.emit('offer', message);
        break;
      case 'answer':
        this.emit('answer', message);
        break;
      case 'ice-candidate':
        this.emit('ice-candidate', message);
        break;
      case 'call-ended':
        this.emit('call-ended', message);
        break;
      case 'annotation':
        this.emit('annotation', message);
        break;
      case 'freeze-video':
        this.emit('freeze-video', message);
        break;
      case 'resume-video':
        this.emit('resume-video', message);
        break;
      default:
        console.warn('Unknown message type:', message.type);
    }
  }

  public send(message: SignalMessage): void {
    if (this.socket && this.isConnected) {
      this.socket.emit('message', message);
    } else {
      console.error('Cannot send message: not connected to signaling server');
    }
  }

  public registerAsProfessional(): void {
    if (this.socket && this.isConnected) {
      this.socket.emit('register-professional', { userId: this.userId });
    }
  }

  public requestCall(): void {
    if (this.socket && this.isConnected) {
      this.socket.emit('request-call', { userId: this.userId });
    }
  }

  public acceptCall(callerId: string): void {
    if (this.socket && this.isConnected) {
      this.socket.emit('accept-call', {
        userId: this.userId,
        callerId: callerId
      });
    }
  }

  public rejectCall(callerId: string): void {
    if (this.socket && this.isConnected) {
      this.socket.emit('reject-call', {
        userId: this.userId,
        callerId: callerId
      });
    }
  }

  public disconnect(): void {
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
      this.isConnected = false;
    }
  }

  public getConnectionStatus(): boolean {
    return this.isConnected;
  }

  public getUserId(): string {
    return this.userId;
  }
}

export default SignalingService;
