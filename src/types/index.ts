// User types
export type UserRole = 'user' | 'professional';

export interface User {
  id: string;
  role: UserRole;
  name?: string;
  createdAt: number;
}

// Call states
export type CallState =
  | 'idle'
  | 'calling'
  | 'receiving'
  | 'connecting'
  | 'connected'
  | 'disconnected'
  | 'failed';

// Signaling message types
export type SignalType =
  | 'offer'
  | 'answer'
  | 'ice-candidate'
  | 'call-request'
  | 'call-accepted'
  | 'call-rejected'
  | 'call-ended'
  | 'annotation'
  | 'freeze-video'
  | 'resume-video';

export interface SignalMessage {
  type: SignalType;
  from: string;
  to: string;
  payload?: any;
  timestamp: number;
}

// Annotation types
export type AnnotationType = 'drawing' | 'pointer' | 'arrow' | 'circle' | 'text' | 'animation';

export interface Point {
  x: number;
  y: number;
}

export interface Annotation {
  id: string;
  type: AnnotationType;
  points: Point[];
  color: string;
  strokeWidth: number;
  text?: string;
  animationType?: 'pulse' | 'bounce' | 'highlight';
  timestamp: number;
  isComplete: boolean;
}

// Video stabilization config
export interface StabilizationConfig {
  enabled: boolean;
  smoothingFactor: number;
  maxOffset: number;
}

// WebRTC configuration
export interface WebRTCConfig {
  iceServers: RTCIceServer[];
  videoConstraints: MediaTrackConstraints;
  audioConstraints: MediaTrackConstraints;
}

// Call session
export interface CallSession {
  id: string;
  userId: string;
  professionalId?: string;
  state: CallState;
  startTime?: number;
  endTime?: number;
  annotations: Annotation[];
  isVideoFrozen: boolean;
  frozenFrameData?: string;
}

// App state
export interface AppState {
  user: User | null;
  currentSession: CallSession | null;
  isConnectedToServer: boolean;
  error: string | null;
}

// Navigation types
export type UserStackParamList = {
  UserSplash: undefined;
  UserHome: undefined;
  UserVideoCall: { sessionId: string };
};

export type ProfessionalStackParamList = {
  ProfessionalSplash: undefined;
  ProfessionalHome: undefined;
  ProfessionalVideoCall: { sessionId: string };
};

export type RootStackParamList = {
  RoleSelection: undefined;
  UserStack: undefined;
  ProfessionalStack: undefined;
};
