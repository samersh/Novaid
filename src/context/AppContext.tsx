import React, { createContext, useContext, useReducer, useCallback, useEffect, ReactNode } from 'react';
import { AppState, User, CallSession, CallState, UserRole, Annotation } from '../types';
import { SignalingService } from '../services/SignalingService';
import { WebRTCService } from '../services/WebRTCService';
import { userIdService } from '../services/UserIdService';
import { annotationService, AnnotationService } from '../services/AnnotationService';
import { VideoStabilizer } from '../services/VideoStabilizer';
import { MediaStream } from 'react-native-webrtc';

// Action types
type AppAction =
  | { type: 'SET_USER'; payload: User }
  | { type: 'SET_SESSION'; payload: CallSession | null }
  | { type: 'UPDATE_SESSION'; payload: Partial<CallSession> }
  | { type: 'SET_CALL_STATE'; payload: CallState }
  | { type: 'SET_CONNECTED'; payload: boolean }
  | { type: 'SET_ERROR'; payload: string | null }
  | { type: 'ADD_ANNOTATION'; payload: Annotation }
  | { type: 'CLEAR_ANNOTATIONS' }
  | { type: 'SET_VIDEO_FROZEN'; payload: boolean }
  | { type: 'RESET' };

// Initial state
const initialState: AppState = {
  user: null,
  currentSession: null,
  isConnectedToServer: false,
  error: null,
};

// Reducer
function appReducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case 'SET_USER':
      return { ...state, user: action.payload };
    case 'SET_SESSION':
      return { ...state, currentSession: action.payload };
    case 'UPDATE_SESSION':
      if (!state.currentSession) return state;
      return {
        ...state,
        currentSession: { ...state.currentSession, ...action.payload },
      };
    case 'SET_CALL_STATE':
      if (!state.currentSession) return state;
      return {
        ...state,
        currentSession: { ...state.currentSession, state: action.payload },
      };
    case 'SET_CONNECTED':
      return { ...state, isConnectedToServer: action.payload };
    case 'SET_ERROR':
      return { ...state, error: action.payload };
    case 'ADD_ANNOTATION':
      if (!state.currentSession) return state;
      return {
        ...state,
        currentSession: {
          ...state.currentSession,
          annotations: [...state.currentSession.annotations, action.payload],
        },
      };
    case 'CLEAR_ANNOTATIONS':
      if (!state.currentSession) return state;
      return {
        ...state,
        currentSession: { ...state.currentSession, annotations: [] },
      };
    case 'SET_VIDEO_FROZEN':
      if (!state.currentSession) return state;
      return {
        ...state,
        currentSession: { ...state.currentSession, isVideoFrozen: action.payload },
      };
    case 'RESET':
      return initialState;
    default:
      return state;
  }
}

// Context types
interface AppContextValue {
  state: AppState;
  signalingService: SignalingService | null;
  webRTCService: WebRTCService | null;
  annotationService: AnnotationService;
  videoStabilizer: VideoStabilizer;
  localStream: MediaStream | null;
  remoteStream: MediaStream | null;
  initializeUser: (role: UserRole) => Promise<User>;
  connectToServer: () => Promise<void>;
  startCall: () => Promise<void>;
  acceptCall: (callerId: string) => Promise<void>;
  rejectCall: (callerId: string) => void;
  endCall: () => void;
  sendAnnotation: (annotation: Annotation) => void;
  freezeVideo: () => void;
  resumeVideo: () => void;
  clearError: () => void;
}

// Create context
const AppContext = createContext<AppContextValue | null>(null);

// Server URL - can be configured via environment
const SIGNALING_SERVER_URL = process.env.SIGNALING_SERVER_URL || 'ws://localhost:3001';

// Provider component
interface AppProviderProps {
  children: ReactNode;
}

export function AppProvider({ children }: AppProviderProps) {
  const [state, dispatch] = useReducer(appReducer, initialState);

  // Services refs (using refs to prevent re-renders)
  const [signalingService, setSignalingService] = React.useState<SignalingService | null>(null);
  const [webRTCService, setWebRTCService] = React.useState<WebRTCService | null>(null);
  const [localStream, setLocalStream] = React.useState<MediaStream | null>(null);
  const [remoteStream, setRemoteStream] = React.useState<MediaStream | null>(null);

  // Video stabilizer (always available)
  const videoStabilizer = React.useMemo(() => new VideoStabilizer(), []);

  // Initialize user
  const initializeUser = useCallback(async (role: UserRole): Promise<User> => {
    try {
      const user = await userIdService.initializeUser(role);
      dispatch({ type: 'SET_USER', payload: user });
      return user;
    } catch (error) {
      dispatch({ type: 'SET_ERROR', payload: 'Failed to initialize user' });
      throw error;
    }
  }, []);

  // Connect to signaling server
  const connectToServer = useCallback(async (): Promise<void> => {
    if (!state.user) {
      throw new Error('User not initialized');
    }

    try {
      const signaling = new SignalingService(state.user.id, SIGNALING_SERVER_URL);

      signaling.on('connected', () => {
        dispatch({ type: 'SET_CONNECTED', payload: true });
      });

      signaling.on('disconnected', () => {
        dispatch({ type: 'SET_CONNECTED', payload: false });
      });

      signaling.on('callRequest', (message: any) => {
        // Create a new session for incoming call
        const session: CallSession = {
          id: `session_${Date.now()}`,
          userId: message.from,
          state: 'receiving',
          annotations: [],
          isVideoFrozen: false,
        };
        dispatch({ type: 'SET_SESSION', payload: session });
      });

      signaling.on('callAccepted', async (message: any) => {
        dispatch({ type: 'SET_CALL_STATE', payload: 'connecting' });
      });

      signaling.on('callRejected', () => {
        dispatch({ type: 'SET_CALL_STATE', payload: 'failed' });
        dispatch({ type: 'SET_ERROR', payload: 'Call was rejected' });
      });

      signaling.on('noProfessionalAvailable', () => {
        dispatch({ type: 'SET_CALL_STATE', payload: 'failed' });
        dispatch({ type: 'SET_ERROR', payload: 'No professional available' });
      });

      await signaling.connect();
      setSignalingService(signaling);

      // Create WebRTC service
      const webrtc = new WebRTCService(signaling, state.user.id);

      webrtc.on('localStream', (stream: MediaStream) => {
        setLocalStream(stream);
      });

      webrtc.on('remoteStream', (stream: MediaStream) => {
        setRemoteStream(stream);
      });

      webrtc.on('connected', () => {
        dispatch({ type: 'SET_CALL_STATE', payload: 'connected' });
      });

      webrtc.on('disconnected', () => {
        dispatch({ type: 'SET_CALL_STATE', payload: 'disconnected' });
      });

      webrtc.on('annotation', (annotation: Annotation) => {
        dispatch({ type: 'ADD_ANNOTATION', payload: annotation });
        annotationService.addRemoteAnnotation(annotation);
      });

      webrtc.on('freezeVideo', () => {
        dispatch({ type: 'SET_VIDEO_FROZEN', payload: true });
      });

      webrtc.on('resumeVideo', (data: { annotations: Annotation[] }) => {
        dispatch({ type: 'SET_VIDEO_FROZEN', payload: false });
        // Add received annotations
        data.annotations?.forEach((ann: Annotation) => {
          dispatch({ type: 'ADD_ANNOTATION', payload: ann });
          annotationService.addRemoteAnnotation(ann);
        });
      });

      webrtc.on('callEnded', () => {
        endCall();
      });

      setWebRTCService(webrtc);

      // Register as professional if needed
      if (state.user.role === 'professional') {
        signaling.registerAsProfessional();
      }
    } catch (error) {
      dispatch({ type: 'SET_ERROR', payload: 'Failed to connect to server' });
      throw error;
    }
  }, [state.user]);

  // Start a call (user initiates)
  const startCall = useCallback(async (): Promise<void> => {
    if (!webRTCService || !signalingService || !state.user) {
      throw new Error('Services not initialized');
    }

    try {
      // Create session
      const session: CallSession = {
        id: `session_${Date.now()}`,
        userId: state.user.id,
        state: 'calling',
        startTime: Date.now(),
        annotations: [],
        isVideoFrozen: false,
      };
      dispatch({ type: 'SET_SESSION', payload: session });

      // Initialize local stream with rear camera
      await webRTCService.initializeLocalStream(true);

      // Create peer connection
      await webRTCService.createPeerConnection();

      // Request a call to available professional
      signalingService.requestCall();
    } catch (error) {
      dispatch({ type: 'SET_ERROR', payload: 'Failed to start call' });
      throw error;
    }
  }, [webRTCService, signalingService, state.user]);

  // Accept incoming call (professional accepts)
  const acceptCall = useCallback(async (callerId: string): Promise<void> => {
    if (!webRTCService || !signalingService) {
      throw new Error('Services not initialized');
    }

    try {
      await webRTCService.acceptCall(callerId);
      dispatch({ type: 'SET_CALL_STATE', payload: 'connecting' });
    } catch (error) {
      dispatch({ type: 'SET_ERROR', payload: 'Failed to accept call' });
      throw error;
    }
  }, [webRTCService, signalingService]);

  // Reject incoming call
  const rejectCall = useCallback((callerId: string): void => {
    if (webRTCService) {
      webRTCService.rejectCall(callerId);
    }
    dispatch({ type: 'SET_SESSION', payload: null });
  }, [webRTCService]);

  // End call
  const endCall = useCallback((): void => {
    if (webRTCService) {
      webRTCService.endCall();
    }
    setLocalStream(null);
    setRemoteStream(null);
    annotationService.clearAllAnnotations();
    dispatch({ type: 'SET_SESSION', payload: null });
  }, [webRTCService]);

  // Send annotation
  const sendAnnotation = useCallback((annotation: Annotation): void => {
    if (webRTCService) {
      webRTCService.sendAnnotation(annotation);
      dispatch({ type: 'ADD_ANNOTATION', payload: annotation });
    }
  }, [webRTCService]);

  // Freeze video
  const freezeVideo = useCallback((): void => {
    if (webRTCService) {
      webRTCService.freezeVideo();
      dispatch({ type: 'SET_VIDEO_FROZEN', payload: true });
    }
  }, [webRTCService]);

  // Resume video
  const resumeVideo = useCallback((): void => {
    if (webRTCService) {
      const annotations = annotationService.getAllAnnotations();
      webRTCService.resumeVideo(annotations);
      dispatch({ type: 'SET_VIDEO_FROZEN', payload: false });
    }
  }, [webRTCService]);

  // Clear error
  const clearError = useCallback((): void => {
    dispatch({ type: 'SET_ERROR', payload: null });
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (webRTCService) {
        webRTCService.cleanup();
      }
      if (signalingService) {
        signalingService.disconnect();
      }
    };
  }, [signalingService, webRTCService]);

  const value: AppContextValue = {
    state,
    signalingService,
    webRTCService,
    annotationService,
    videoStabilizer,
    localStream,
    remoteStream,
    initializeUser,
    connectToServer,
    startCall,
    acceptCall,
    rejectCall,
    endCall,
    sendAnnotation,
    freezeVideo,
    resumeVideo,
    clearError,
  };

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

// Custom hook for using app context
export function useApp(): AppContextValue {
  const context = useContext(AppContext);
  if (!context) {
    throw new Error('useApp must be used within an AppProvider');
  }
  return context;
}

export default AppContext;
