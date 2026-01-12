// User and Session Types
export interface User {
  id: string;
  uniqueCode: string;
  role: 'user' | 'professional';
  createdAt: Date;
}

export interface Session {
  id: string;
  userId: string;
  professionalId: string | null;
  status: 'pending' | 'active' | 'ended';
  startTime: Date;
  endTime?: Date;
}

// Location Types
export interface GPSLocation {
  latitude: number;
  longitude: number;
  altitude?: number;
  accuracy?: number;
  heading?: number;
  speed?: number;
  timestamp: number;
}

// Annotation Types
export type AnnotationType = 'line' | 'arrow' | 'circle' | 'rectangle' | 'freehand' | 'text' | 'pointer';

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
  timestamp: number;
  duration?: number; // For animated annotations
}

export interface AnnotationFrame {
  id: string;
  frameTimestamp: number;
  annotations: Annotation[];
  isFrozen: boolean;
}

// WebRTC Types
export interface RTCSignal {
  type: 'offer' | 'answer' | 'ice-candidate';
  payload: RTCSessionDescriptionInit | RTCIceCandidateInit;
  from: string;
  to: string;
}

export interface CallState {
  isConnected: boolean;
  isConnecting: boolean;
  isCalling: boolean;
  isReceiving: boolean;
  localStream: MediaStream | null;
  remoteStream: MediaStream | null;
  error: string | null;
}

// Video Stabilization Types
export interface StabilizationConfig {
  enabled: boolean;
  smoothingFactor: number;
  maxCorrection: number;
}

export interface FrameTransform {
  translateX: number;
  translateY: number;
  rotation: number;
  scale: number;
}

// Socket Events
export type SocketEvent =
  | 'connect'
  | 'disconnect'
  | 'call:initiate'
  | 'call:accept'
  | 'call:reject'
  | 'call:end'
  | 'signal:offer'
  | 'signal:answer'
  | 'signal:ice'
  | 'location:update'
  | 'annotation:add'
  | 'annotation:clear'
  | 'frame:freeze'
  | 'frame:resume'
  | 'user:register'
  | 'user:available'
  | 'error';

// Navigation Types
export type RootStackParamList = {
  Home: undefined;
  UserScreen: undefined;
  ProfessionalScreen: undefined;
  CallScreen: {
    role: 'user' | 'professional';
    sessionId?: string;
  };
  Settings: undefined;
};

// Component Props Types
export interface VideoStreamProps {
  stream: MediaStream | null;
  muted?: boolean;
  mirror?: boolean;
  stabilized?: boolean;
}

export interface AnnotationCanvasProps {
  annotations: Annotation[];
  isDrawing: boolean;
  currentTool: AnnotationType;
  currentColor: string;
  strokeWidth: number;
  onAnnotationAdd: (annotation: Annotation) => void;
  isFrozen: boolean;
}

export interface MapViewProps {
  location: GPSLocation | null;
  showUserMarker: boolean;
}

// API Response Types
export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
}

export interface RegisterResponse {
  userId: string;
  uniqueCode: string;
}

export interface CallResponse {
  sessionId: string;
  status: string;
}
