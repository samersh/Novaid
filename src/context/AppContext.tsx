import React, {
  createContext,
  useContext,
  useReducer,
  useEffect,
  useCallback,
  ReactNode,
} from 'react';
import { User, GPSLocation, Annotation, CallState } from '../types';
import { userService } from '../services/UserService';
import { socketService } from '../services/SocketService';
import { webRTCService } from '../services/WebRTCService';
import { locationService } from '../services/LocationService';
import { annotationService } from '../services/AnnotationService';

// State types
interface AppState {
  user: User | null;
  isInitialized: boolean;
  isConnectedToServer: boolean;
  callState: CallState;
  location: GPSLocation | null;
  remoteLocation: GPSLocation | null;
  annotations: Annotation[];
  isFrozen: boolean;
  incomingCall: { callerId: string; callerCode: string } | null;
  currentSessionId: string | null;
  remoteUserId: string | null;
  error: string | null;
}

const initialState: AppState = {
  user: null,
  isInitialized: false,
  isConnectedToServer: false,
  callState: {
    isConnected: false,
    isConnecting: false,
    isCalling: false,
    isReceiving: false,
    localStream: null,
    remoteStream: null,
    error: null,
  },
  location: null,
  remoteLocation: null,
  annotations: [],
  isFrozen: false,
  incomingCall: null,
  currentSessionId: null,
  remoteUserId: null,
  error: null,
};

// Action types
type AppAction =
  | { type: 'SET_USER'; payload: User }
  | { type: 'SET_INITIALIZED'; payload: boolean }
  | { type: 'SET_CONNECTED_TO_SERVER'; payload: boolean }
  | { type: 'UPDATE_CALL_STATE'; payload: Partial<CallState> }
  | { type: 'SET_LOCATION'; payload: GPSLocation }
  | { type: 'SET_REMOTE_LOCATION'; payload: GPSLocation }
  | { type: 'SET_ANNOTATIONS'; payload: Annotation[] }
  | { type: 'ADD_ANNOTATION'; payload: Annotation }
  | { type: 'CLEAR_ANNOTATIONS' }
  | { type: 'SET_FROZEN'; payload: boolean }
  | { type: 'SET_INCOMING_CALL'; payload: { callerId: string; callerCode: string } | null }
  | { type: 'SET_SESSION'; payload: { sessionId: string; remoteUserId: string } }
  | { type: 'CLEAR_SESSION' }
  | { type: 'SET_ERROR'; payload: string | null };

// Reducer
function appReducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case 'SET_USER':
      return { ...state, user: action.payload };
    case 'SET_INITIALIZED':
      return { ...state, isInitialized: action.payload };
    case 'SET_CONNECTED_TO_SERVER':
      return { ...state, isConnectedToServer: action.payload };
    case 'UPDATE_CALL_STATE':
      return { ...state, callState: { ...state.callState, ...action.payload } };
    case 'SET_LOCATION':
      return { ...state, location: action.payload };
    case 'SET_REMOTE_LOCATION':
      return { ...state, remoteLocation: action.payload };
    case 'SET_ANNOTATIONS':
      return { ...state, annotations: action.payload };
    case 'ADD_ANNOTATION':
      return { ...state, annotations: [...state.annotations, action.payload] };
    case 'CLEAR_ANNOTATIONS':
      return { ...state, annotations: [] };
    case 'SET_FROZEN':
      return { ...state, isFrozen: action.payload };
    case 'SET_INCOMING_CALL':
      return { ...state, incomingCall: action.payload };
    case 'SET_SESSION':
      return {
        ...state,
        currentSessionId: action.payload.sessionId,
        remoteUserId: action.payload.remoteUserId,
      };
    case 'CLEAR_SESSION':
      return {
        ...state,
        currentSessionId: null,
        remoteUserId: null,
        callState: initialState.callState,
        annotations: [],
        isFrozen: false,
      };
    case 'SET_ERROR':
      return { ...state, error: action.payload };
    default:
      return state;
  }
}

// Context
interface AppContextType {
  state: AppState;
  dispatch: React.Dispatch<AppAction>;
  initializeApp: (role: 'user' | 'professional') => Promise<void>;
  initiateCall: () => Promise<void>;
  acceptCall: (callerId: string) => Promise<void>;
  rejectCall: (callerId: string) => void;
  endCall: () => void;
  toggleMute: () => boolean;
  toggleVideo: () => boolean;
  switchCamera: () => void;
  sendAnnotation: (annotation: Annotation) => void;
  clearAnnotations: () => void;
  freezeFrame: () => void;
  resumeFrame: () => void;
}

const AppContext = createContext<AppContextType | null>(null);

// Provider component
export const AppProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [state, dispatch] = useReducer(appReducer, initialState);

  // Initialize app
  const initializeApp = useCallback(async (role: 'user' | 'professional') => {
    try {
      // Initialize user
      const user = await userService.initializeUser(role);
      dispatch({ type: 'SET_USER', payload: user });

      // Connect to signaling server
      await socketService.connect(user.id, role);
      dispatch({ type: 'SET_CONNECTED_TO_SERVER', payload: true });

      // Set up socket event handlers
      setupSocketHandlers();

      // Set up WebRTC handlers
      setupWebRTCHandlers();

      // Start location tracking for users
      if (role === 'user') {
        await locationService.startTracking();
        locationService.onLocationUpdate((location) => {
          dispatch({ type: 'SET_LOCATION', payload: location });
          if (state.callState.isConnected) {
            socketService.sendLocation(location);
          }
        });
      }

      // Set up annotation handlers
      annotationService.onAnnotationsChange((annotations) => {
        dispatch({ type: 'SET_ANNOTATIONS', payload: annotations });
      });

      dispatch({ type: 'SET_INITIALIZED', payload: true });
    } catch (error) {
      console.error('Failed to initialize app:', error);
      dispatch({ type: 'SET_ERROR', payload: 'Failed to initialize app' });
    }
  }, [state.callState.isConnected]);

  const setupSocketHandlers = useCallback(() => {
    // Incoming call handler
    socketService.on('call:incoming', (data) => {
      dispatch({ type: 'SET_INCOMING_CALL', payload: data });
    });

    // Call accepted handler
    socketService.on('call:accepted', async (data) => {
      dispatch({
        type: 'SET_SESSION',
        payload: { sessionId: data.sessionId, remoteUserId: data.professionalId },
      });
      dispatch({ type: 'SET_INCOMING_CALL', payload: null });

      // Create and send WebRTC offer
      try {
        await webRTCService.startLocalStream(true);
        const offer = await webRTCService.createOffer();
        socketService.sendOffer(offer, data.professionalId);
      } catch (error) {
        console.error('Failed to create offer:', error);
      }
    });

    // Call rejected handler
    socketService.on('call:rejected', (data) => {
      dispatch({ type: 'SET_ERROR', payload: `Call rejected: ${data.reason}` });
      dispatch({ type: 'CLEAR_SESSION' });
    });

    // Call ended handler
    socketService.on('call:ended', () => {
      webRTCService.endCall();
      dispatch({ type: 'CLEAR_SESSION' });
    });

    // WebRTC offer handler
    socketService.on('signal:offer', async (data) => {
      try {
        await webRTCService.startLocalStream(false);
        const answer = await webRTCService.handleOffer(data.offer);
        socketService.sendAnswer(answer, data.from);
      } catch (error) {
        console.error('Failed to handle offer:', error);
      }
    });

    // WebRTC answer handler
    socketService.on('signal:answer', async (data) => {
      try {
        await webRTCService.handleAnswer(data.answer);
      } catch (error) {
        console.error('Failed to handle answer:', error);
      }
    });

    // ICE candidate handler
    socketService.on('signal:ice', (data) => {
      webRTCService.addIceCandidate(data.candidate);
    });

    // Location update handler
    socketService.on('location:update', (data) => {
      dispatch({ type: 'SET_REMOTE_LOCATION', payload: data.location });
    });

    // Annotation received handler
    socketService.on('annotation:received', (data) => {
      annotationService.addAnnotation(data.annotation);
    });

    // Annotation clear handler
    socketService.on('annotation:clear', () => {
      annotationService.clearAnnotations();
    });

    // Frame frozen handler
    socketService.on('frame:frozen', (data) => {
      dispatch({ type: 'SET_FROZEN', payload: true });
    });

    // Frame resumed handler
    socketService.on('frame:resumed', () => {
      dispatch({ type: 'SET_FROZEN', payload: false });
    });
  }, []);

  const setupWebRTCHandlers = useCallback(() => {
    // Set up ICE candidate emitter
    webRTCService.setIceCandidateEmitter((candidate) => {
      if (state.remoteUserId) {
        socketService.sendIceCandidate(candidate, state.remoteUserId);
      }
    });

    // Listen for call state changes
    webRTCService.addListener((callState) => {
      dispatch({ type: 'UPDATE_CALL_STATE', payload: callState });
    });
  }, [state.remoteUserId]);

  // Call functions
  const initiateCall = useCallback(async () => {
    dispatch({ type: 'UPDATE_CALL_STATE', payload: { isCalling: true, isConnecting: true } });
    socketService.initiateCall();
  }, []);

  const acceptCall = useCallback(async (callerId: string) => {
    socketService.acceptCall(callerId);
    dispatch({ type: 'SET_INCOMING_CALL', payload: null });
  }, []);

  const rejectCall = useCallback((callerId: string) => {
    socketService.rejectCall(callerId);
    dispatch({ type: 'SET_INCOMING_CALL', payload: null });
  }, []);

  const endCall = useCallback(() => {
    socketService.endCall();
    webRTCService.endCall();
    dispatch({ type: 'CLEAR_SESSION' });
  }, []);

  const toggleMute = useCallback(() => {
    return webRTCService.toggleMute();
  }, []);

  const toggleVideo = useCallback(() => {
    return webRTCService.toggleVideo();
  }, []);

  const switchCamera = useCallback(() => {
    webRTCService.switchCamera();
  }, []);

  // Annotation functions
  const sendAnnotation = useCallback((annotation: Annotation) => {
    annotationService.addAnnotation(annotation);
    socketService.sendAnnotation(annotation);
  }, []);

  const clearAnnotations = useCallback(() => {
    annotationService.clearAnnotations();
    socketService.clearAnnotations();
  }, []);

  const freezeFrame = useCallback(() => {
    const frame = annotationService.freezeFrame();
    dispatch({ type: 'SET_FROZEN', payload: true });
    socketService.freezeFrame('', frame.frameTimestamp);
  }, []);

  const resumeFrame = useCallback(() => {
    annotationService.resumeFrame();
    dispatch({ type: 'SET_FROZEN', payload: false });
    socketService.resumeFrame();
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      locationService.stopTracking();
      socketService.disconnect();
      webRTCService.endCall();
    };
  }, []);

  const contextValue: AppContextType = {
    state,
    dispatch,
    initializeApp,
    initiateCall,
    acceptCall,
    rejectCall,
    endCall,
    toggleMute,
    toggleVideo,
    switchCamera,
    sendAnnotation,
    clearAnnotations,
    freezeFrame,
    resumeFrame,
  };

  return (
    <AppContext.Provider value={contextValue}>
      {children}
    </AppContext.Provider>
  );
};

// Custom hook
export const useApp = (): AppContextType => {
  const context = useContext(AppContext);
  if (!context) {
    throw new Error('useApp must be used within an AppProvider');
  }
  return context;
};

export default AppContext;
