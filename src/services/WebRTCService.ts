import {
  RTCPeerConnection,
  RTCIceCandidate,
  RTCSessionDescription,
  mediaDevices,
  MediaStream,
  MediaStreamTrack,
} from 'react-native-webrtc';
import { SignalMessage, WebRTCConfig, Annotation } from '../types';
import { SignalingService } from './SignalingService';
import { EventEmitter } from '../utils/EventEmitter';

// Default ICE servers including public STUN servers
const DEFAULT_ICE_SERVERS: RTCIceServer[] = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
  { urls: 'stun:stun2.l.google.com:19302' },
  { urls: 'stun:stun3.l.google.com:19302' },
  { urls: 'stun:stun4.l.google.com:19302' },
];

export class WebRTCService extends EventEmitter {
  private peerConnection: RTCPeerConnection | null = null;
  private localStream: MediaStream | null = null;
  private remoteStream: MediaStream | null = null;
  private signalingService: SignalingService;
  private userId: string;
  private remoteUserId: string | null = null;
  private config: WebRTCConfig;
  private iceCandidatesQueue: RTCIceCandidate[] = [];
  private isNegotiating: boolean = false;

  constructor(signalingService: SignalingService, userId: string, config?: Partial<WebRTCConfig>) {
    super();
    this.signalingService = signalingService;
    this.userId = userId;
    this.config = {
      iceServers: config?.iceServers || DEFAULT_ICE_SERVERS,
      videoConstraints: config?.videoConstraints || {
        facingMode: 'environment', // Use rear camera
        width: { ideal: 1280 },
        height: { ideal: 720 },
        frameRate: { ideal: 30 },
      },
      audioConstraints: config?.audioConstraints || {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    };

    this.setupSignalingListeners();
  }

  private setupSignalingListeners(): void {
    this.signalingService.on('offer', this.handleOffer.bind(this));
    this.signalingService.on('answer', this.handleAnswer.bind(this));
    this.signalingService.on('ice-candidate', this.handleIceCandidate.bind(this));
    this.signalingService.on('call-ended', this.handleCallEnded.bind(this));
    this.signalingService.on('annotation', this.handleAnnotation.bind(this));
    this.signalingService.on('freeze-video', this.handleFreezeVideo.bind(this));
    this.signalingService.on('resume-video', this.handleResumeVideo.bind(this));
  }

  public async initializeLocalStream(useRearCamera: boolean = true): Promise<MediaStream> {
    try {
      const constraints = {
        audio: this.config.audioConstraints,
        video: {
          ...this.config.videoConstraints,
          facingMode: useRearCamera ? 'environment' : 'user',
        },
      };

      this.localStream = await mediaDevices.getUserMedia(constraints);
      this.emit('localStream', this.localStream);
      return this.localStream;
    } catch (error) {
      console.error('Error getting user media:', error);
      throw error;
    }
  }

  public async createPeerConnection(): Promise<RTCPeerConnection> {
    const configuration = {
      iceServers: this.config.iceServers,
      iceCandidatePoolSize: 10,
    };

    this.peerConnection = new RTCPeerConnection(configuration);

    // Add local tracks to peer connection
    if (this.localStream) {
      this.localStream.getTracks().forEach((track: MediaStreamTrack) => {
        if (this.peerConnection && this.localStream) {
          this.peerConnection.addTrack(track, this.localStream);
        }
      });
    }

    // Handle remote tracks
    this.peerConnection.ontrack = (event: any) => {
      if (event.streams && event.streams[0]) {
        this.remoteStream = event.streams[0];
        this.emit('remoteStream', this.remoteStream);
      }
    };

    // Handle ICE candidates
    this.peerConnection.onicecandidate = (event: any) => {
      if (event.candidate && this.remoteUserId) {
        this.signalingService.send({
          type: 'ice-candidate',
          from: this.userId,
          to: this.remoteUserId,
          payload: event.candidate.toJSON(),
          timestamp: Date.now(),
        });
      }
    };

    // Handle connection state changes
    this.peerConnection.onconnectionstatechange = () => {
      const state = this.peerConnection?.connectionState;
      this.emit('connectionStateChange', state);

      if (state === 'connected') {
        this.emit('connected');
        this.processIceCandidatesQueue();
      } else if (state === 'disconnected' || state === 'failed') {
        this.emit('disconnected', state);
      }
    };

    // Handle ICE connection state
    this.peerConnection.oniceconnectionstatechange = () => {
      const state = this.peerConnection?.iceConnectionState;
      this.emit('iceConnectionStateChange', state);
    };

    // Handle negotiation needed
    this.peerConnection.onnegotiationneeded = async () => {
      if (this.isNegotiating) return;
      this.isNegotiating = true;

      try {
        if (this.remoteUserId) {
          await this.createAndSendOffer();
        }
      } finally {
        this.isNegotiating = false;
      }
    };

    return this.peerConnection;
  }

  public async initiateCall(targetUserId: string): Promise<void> {
    this.remoteUserId = targetUserId;

    // Request call
    this.signalingService.send({
      type: 'call-request',
      from: this.userId,
      to: targetUserId,
      timestamp: Date.now(),
    });

    this.emit('callStateChange', 'calling');
  }

  public async acceptCall(callerUserId: string): Promise<void> {
    this.remoteUserId = callerUserId;

    // Initialize streams and peer connection
    await this.initializeLocalStream(false); // Professional uses front camera for their view
    await this.createPeerConnection();

    // Accept the call
    this.signalingService.send({
      type: 'call-accepted',
      from: this.userId,
      to: callerUserId,
      timestamp: Date.now(),
    });

    this.emit('callStateChange', 'connecting');
  }

  public rejectCall(callerUserId: string): void {
    this.signalingService.send({
      type: 'call-rejected',
      from: this.userId,
      to: callerUserId,
      timestamp: Date.now(),
    });
  }

  public async createAndSendOffer(): Promise<void> {
    if (!this.peerConnection || !this.remoteUserId) return;

    try {
      const offer = await this.peerConnection.createOffer({
        offerToReceiveAudio: true,
        offerToReceiveVideo: true,
      });

      await this.peerConnection.setLocalDescription(offer);

      this.signalingService.send({
        type: 'offer',
        from: this.userId,
        to: this.remoteUserId,
        payload: offer,
        timestamp: Date.now(),
      });
    } catch (error) {
      console.error('Error creating offer:', error);
      throw error;
    }
  }

  private async handleOffer(message: SignalMessage): Promise<void> {
    if (!this.peerConnection) {
      await this.createPeerConnection();
    }

    try {
      this.remoteUserId = message.from;
      const remoteDesc = new RTCSessionDescription(message.payload);
      await this.peerConnection!.setRemoteDescription(remoteDesc);

      const answer = await this.peerConnection!.createAnswer();
      await this.peerConnection!.setLocalDescription(answer);

      this.signalingService.send({
        type: 'answer',
        from: this.userId,
        to: message.from,
        payload: answer,
        timestamp: Date.now(),
      });

      this.processIceCandidatesQueue();
    } catch (error) {
      console.error('Error handling offer:', error);
    }
  }

  private async handleAnswer(message: SignalMessage): Promise<void> {
    if (!this.peerConnection) return;

    try {
      const remoteDesc = new RTCSessionDescription(message.payload);
      await this.peerConnection.setRemoteDescription(remoteDesc);
      this.processIceCandidatesQueue();
    } catch (error) {
      console.error('Error handling answer:', error);
    }
  }

  private async handleIceCandidate(message: SignalMessage): Promise<void> {
    const candidate = new RTCIceCandidate(message.payload);

    if (this.peerConnection?.remoteDescription) {
      try {
        await this.peerConnection.addIceCandidate(candidate);
      } catch (error) {
        console.error('Error adding ICE candidate:', error);
      }
    } else {
      // Queue the candidate for later
      this.iceCandidatesQueue.push(candidate);
    }
  }

  private async processIceCandidatesQueue(): Promise<void> {
    if (!this.peerConnection?.remoteDescription) return;

    while (this.iceCandidatesQueue.length > 0) {
      const candidate = this.iceCandidatesQueue.shift();
      if (candidate) {
        try {
          await this.peerConnection.addIceCandidate(candidate);
        } catch (error) {
          console.error('Error adding queued ICE candidate:', error);
        }
      }
    }
  }

  private handleCallEnded(message: SignalMessage): void {
    this.emit('callEnded', message);
    this.cleanup();
  }

  private handleAnnotation(message: SignalMessage): void {
    const annotation: Annotation = message.payload;
    this.emit('annotation', annotation);
  }

  private handleFreezeVideo(message: SignalMessage): void {
    this.emit('freezeVideo', message.payload);
  }

  private handleResumeVideo(message: SignalMessage): void {
    this.emit('resumeVideo', message.payload);
  }

  public sendAnnotation(annotation: Annotation): void {
    if (!this.remoteUserId) return;

    this.signalingService.send({
      type: 'annotation',
      from: this.userId,
      to: this.remoteUserId,
      payload: annotation,
      timestamp: Date.now(),
    });
  }

  public freezeVideo(frameData?: string): void {
    if (!this.remoteUserId) return;

    this.signalingService.send({
      type: 'freeze-video',
      from: this.userId,
      to: this.remoteUserId,
      payload: { frameData },
      timestamp: Date.now(),
    });
  }

  public resumeVideo(annotations: Annotation[]): void {
    if (!this.remoteUserId) return;

    this.signalingService.send({
      type: 'resume-video',
      from: this.userId,
      to: this.remoteUserId,
      payload: { annotations },
      timestamp: Date.now(),
    });
  }

  public endCall(): void {
    if (this.remoteUserId) {
      this.signalingService.send({
        type: 'call-ended',
        from: this.userId,
        to: this.remoteUserId,
        timestamp: Date.now(),
      });
    }
    this.cleanup();
  }

  public cleanup(): void {
    // Stop local tracks
    if (this.localStream) {
      this.localStream.getTracks().forEach((track: MediaStreamTrack) => track.stop());
      this.localStream = null;
    }

    // Close peer connection
    if (this.peerConnection) {
      this.peerConnection.close();
      this.peerConnection = null;
    }

    this.remoteStream = null;
    this.remoteUserId = null;
    this.iceCandidatesQueue = [];
    this.isNegotiating = false;

    this.emit('callStateChange', 'idle');
  }

  public getLocalStream(): MediaStream | null {
    return this.localStream;
  }

  public getRemoteStream(): MediaStream | null {
    return this.remoteStream;
  }

  public toggleAudio(enabled: boolean): void {
    if (this.localStream) {
      this.localStream.getAudioTracks().forEach((track: MediaStreamTrack) => {
        track.enabled = enabled;
      });
    }
  }

  public toggleVideo(enabled: boolean): void {
    if (this.localStream) {
      this.localStream.getVideoTracks().forEach((track: MediaStreamTrack) => {
        track.enabled = enabled;
      });
    }
  }

  public async switchCamera(): Promise<void> {
    if (this.localStream) {
      const videoTrack = this.localStream.getVideoTracks()[0];
      if (videoTrack) {
        await (videoTrack as any)._switchCamera();
      }
    }
  }
}

export default WebRTCService;
