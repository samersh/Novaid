import {
  RTCPeerConnection,
  RTCSessionDescription,
  RTCIceCandidate,
  mediaDevices,
  MediaStream,
  MediaStreamTrack,
} from 'react-native-webrtc';
import { RTCSignal, CallState } from '../types';

const ICE_SERVERS = {
  iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' },
    { urls: 'stun:stun2.l.google.com:19302' },
    {
      urls: 'turn:numb.viagenie.ca',
      username: 'webrtc@live.com',
      credential: 'muazkh',
    },
  ],
};

export type CallStateListener = (state: Partial<CallState>) => void;

export class WebRTCService {
  private peerConnection: RTCPeerConnection | null = null;
  private localStream: MediaStream | null = null;
  private remoteStream: MediaStream | null = null;
  private listeners: Set<CallStateListener> = new Set();
  private iceCandidatesQueue: RTCIceCandidateInit[] = [];
  private isNegotiating: boolean = false;

  constructor() {
    this.initializePeerConnection();
  }

  private initializePeerConnection(): void {
    this.peerConnection = new RTCPeerConnection(ICE_SERVERS);

    this.peerConnection.onicecandidate = (event) => {
      if (event.candidate) {
        this.emitIceCandidate(event.candidate);
      }
    };

    this.peerConnection.ontrack = (event) => {
      if (event.streams && event.streams[0]) {
        this.remoteStream = event.streams[0];
        this.notifyListeners({ remoteStream: this.remoteStream });
      }
    };

    this.peerConnection.oniceconnectionstatechange = () => {
      const state = this.peerConnection?.iceConnectionState;
      console.log('ICE Connection State:', state);

      switch (state) {
        case 'connected':
          this.notifyListeners({ isConnected: true, isConnecting: false });
          break;
        case 'disconnected':
        case 'failed':
          this.notifyListeners({ isConnected: false, error: 'Connection failed' });
          break;
        case 'closed':
          this.notifyListeners({ isConnected: false });
          break;
      }
    };

    this.peerConnection.onnegotiationneeded = async () => {
      if (this.isNegotiating) return;
      this.isNegotiating = true;
      // Handle renegotiation if needed
    };
  }

  private emitIceCandidate: (candidate: RTCIceCandidate) => void = () => {};

  setIceCandidateEmitter(emitter: (candidate: RTCIceCandidate) => void): void {
    this.emitIceCandidate = emitter;
  }

  addListener(listener: CallStateListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notifyListeners(state: Partial<CallState>): void {
    this.listeners.forEach((listener) => listener(state));
  }

  async startLocalStream(useRearCamera: boolean = true): Promise<MediaStream> {
    try {
      const facingMode = useRearCamera ? 'environment' : 'user';

      const stream = await mediaDevices.getUserMedia({
        audio: true,
        video: {
          facingMode,
          width: { ideal: 1280 },
          height: { ideal: 720 },
          frameRate: { ideal: 30 },
        },
      });

      this.localStream = stream as MediaStream;

      // Add tracks to peer connection
      this.localStream.getTracks().forEach((track: MediaStreamTrack) => {
        if (this.peerConnection && this.localStream) {
          this.peerConnection.addTrack(track, this.localStream);
        }
      });

      this.notifyListeners({ localStream: this.localStream });
      return this.localStream;
    } catch (error) {
      console.error('Error starting local stream:', error);
      throw error;
    }
  }

  async createOffer(): Promise<RTCSessionDescriptionInit> {
    if (!this.peerConnection) {
      throw new Error('Peer connection not initialized');
    }

    this.notifyListeners({ isCalling: true, isConnecting: true });

    try {
      const offer = await this.peerConnection.createOffer({
        offerToReceiveAudio: true,
        offerToReceiveVideo: true,
      });

      await this.peerConnection.setLocalDescription(offer);
      this.isNegotiating = false;

      return offer;
    } catch (error) {
      this.notifyListeners({ error: 'Failed to create offer' });
      throw error;
    }
  }

  async handleOffer(offer: RTCSessionDescriptionInit): Promise<RTCSessionDescriptionInit> {
    if (!this.peerConnection) {
      throw new Error('Peer connection not initialized');
    }

    this.notifyListeners({ isReceiving: true, isConnecting: true });

    try {
      await this.peerConnection.setRemoteDescription(
        new RTCSessionDescription(offer)
      );

      // Process queued ICE candidates
      await this.processIceCandidatesQueue();

      const answer = await this.peerConnection.createAnswer();
      await this.peerConnection.setLocalDescription(answer);

      return answer;
    } catch (error) {
      this.notifyListeners({ error: 'Failed to handle offer' });
      throw error;
    }
  }

  async handleAnswer(answer: RTCSessionDescriptionInit): Promise<void> {
    if (!this.peerConnection) {
      throw new Error('Peer connection not initialized');
    }

    try {
      await this.peerConnection.setRemoteDescription(
        new RTCSessionDescription(answer)
      );

      // Process queued ICE candidates
      await this.processIceCandidatesQueue();
    } catch (error) {
      this.notifyListeners({ error: 'Failed to handle answer' });
      throw error;
    }
  }

  async addIceCandidate(candidate: RTCIceCandidateInit): Promise<void> {
    if (!this.peerConnection) {
      throw new Error('Peer connection not initialized');
    }

    try {
      // Queue candidates if remote description is not set yet
      if (!this.peerConnection.remoteDescription) {
        this.iceCandidatesQueue.push(candidate);
        return;
      }

      await this.peerConnection.addIceCandidate(
        new RTCIceCandidate(candidate)
      );
    } catch (error) {
      console.error('Error adding ICE candidate:', error);
    }
  }

  private async processIceCandidatesQueue(): Promise<void> {
    for (const candidate of this.iceCandidatesQueue) {
      try {
        await this.peerConnection?.addIceCandidate(
          new RTCIceCandidate(candidate)
        );
      } catch (error) {
        console.error('Error processing queued ICE candidate:', error);
      }
    }
    this.iceCandidatesQueue = [];
  }

  async switchCamera(): Promise<void> {
    if (!this.localStream) return;

    const videoTrack = this.localStream.getVideoTracks()[0];
    if (videoTrack) {
      // @ts-ignore - _switchCamera is available in react-native-webrtc
      videoTrack._switchCamera();
    }
  }

  toggleMute(): boolean {
    if (!this.localStream) return false;

    const audioTrack = this.localStream.getAudioTracks()[0];
    if (audioTrack) {
      audioTrack.enabled = !audioTrack.enabled;
      return audioTrack.enabled;
    }
    return false;
  }

  toggleVideo(): boolean {
    if (!this.localStream) return false;

    const videoTrack = this.localStream.getVideoTracks()[0];
    if (videoTrack) {
      videoTrack.enabled = !videoTrack.enabled;
      return videoTrack.enabled;
    }
    return false;
  }

  endCall(): void {
    // Stop all tracks
    if (this.localStream) {
      this.localStream.getTracks().forEach((track: MediaStreamTrack) => track.stop());
      this.localStream = null;
    }

    if (this.remoteStream) {
      this.remoteStream.getTracks().forEach((track: MediaStreamTrack) => track.stop());
      this.remoteStream = null;
    }

    // Close peer connection
    if (this.peerConnection) {
      this.peerConnection.close();
      this.peerConnection = null;
    }

    // Reset state
    this.iceCandidatesQueue = [];
    this.isNegotiating = false;

    // Reinitialize for next call
    this.initializePeerConnection();

    this.notifyListeners({
      isConnected: false,
      isConnecting: false,
      isCalling: false,
      isReceiving: false,
      localStream: null,
      remoteStream: null,
    });
  }

  getLocalStream(): MediaStream | null {
    return this.localStream;
  }

  getRemoteStream(): MediaStream | null {
    return this.remoteStream;
  }

  getConnectionState(): string | null {
    return this.peerConnection?.iceConnectionState || null;
  }
}

export const webRTCService = new WebRTCService();
