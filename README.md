# Novaid - Remote Assistance Platform

A cross-platform mobile application for real-time remote assistance using WebRTC, AR annotations, and GPS tracking.

## Features

### User Features
- **One-Click Calling**: Instantly connect with a professional with a single tap
- **Unique User ID**: Auto-generated 6-character code for identification (no manual entry required)
- **Rear Camera Streaming**: Broadcast your camera view to professionals
- **Video Stabilization**: Software-based stabilization for clearer video
- **GPS Location Sharing**: Automatic location transmission to professionals
- **AR Annotation Display**: See professional's annotations overlaid on your screen

### Professional Features
- **Call Reception**: Receive and accept incoming calls from users
- **Live Video Viewing**: See the user's stabilized camera feed in real-time
- **GPS Map View**: Track user location on an integrated mini-map
- **AR Annotation Tools**:
  - Freehand drawing
  - Arrows and lines
  - Circles and rectangles
  - Pointer/highlight tool
  - Multiple colors and stroke widths
- **Frame Freeze/Resume**: Pause video for precise annotations, then resume
- **Annotation Clear**: Remove all annotations at once

## Technology Stack

- **React Native** 0.73.4 - Cross-platform mobile development
- **TypeScript** - Type-safe JavaScript
- **WebRTC** - Real-time peer-to-peer video/audio communication
- **Socket.IO** - Real-time bidirectional event-based communication
- **React Navigation** - Native navigation for React Native
- **React Native Maps** - Google Maps integration
- **React Native SVG** - Vector graphics for annotations
- **React Native Reanimated** - Smooth animations

## Project Structure

```
novaid/
├── App.tsx                    # Main application entry
├── index.js                   # React Native entry point
├── src/
│   ├── components/            # Reusable UI components
│   │   ├── VideoStream.tsx    # WebRTC video player
│   │   ├── AnnotationCanvas.tsx # AR drawing canvas
│   │   ├── AnnotationToolbar.tsx # Drawing tools UI
│   │   ├── CallControls.tsx   # Call control buttons
│   │   └── LocationMap.tsx    # GPS map component
│   ├── screens/               # App screens
│   │   ├── HomeScreen.tsx     # Role selection
│   │   ├── UserScreen.tsx     # User waiting/calling screen
│   │   ├── ProfessionalScreen.tsx # Professional dashboard
│   │   └── CallScreen.tsx     # Active call interface
│   ├── services/              # Core services
│   │   ├── WebRTCService.ts   # WebRTC connection handling
│   │   ├── SocketService.ts   # Socket.IO communication
│   │   ├── LocationService.ts # GPS tracking
│   │   ├── AnnotationService.ts # Annotation management
│   │   └── UserService.ts     # User ID management
│   ├── utils/                 # Utility functions
│   │   └── VideoStabilizer.ts # Video stabilization algorithm
│   ├── context/               # React Context
│   │   └── AppContext.tsx     # Global state management
│   └── types/                 # TypeScript definitions
│       └── index.ts           # Type definitions
├── server/                    # Signaling server
│   ├── index.js               # Express + Socket.IO server
│   └── package.json           # Server dependencies
├── ios/                       # iOS native code
│   ├── Podfile                # CocoaPods dependencies
│   └── Novaid/                # iOS app files
├── android/                   # Android native code
│   └── app/                   # Android app files
└── package.json               # Project dependencies
```

## Prerequisites

- Node.js >= 18
- npm or yarn
- Xcode 15+ (for iOS)
- Android Studio (for Android)
- CocoaPods (for iOS)
- Google Maps API Key

## Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd novaid
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Install iOS dependencies**
   ```bash
   cd ios && pod install && cd ..
   ```

4. **Configure Google Maps API**

   iOS: Replace `YOUR_GOOGLE_MAPS_API_KEY` in `ios/Novaid/AppDelegate.mm`

   Android: Replace `YOUR_GOOGLE_MAPS_API_KEY` in `android/app/src/main/AndroidManifest.xml`

## Running the App

### Start the Signaling Server
```bash
cd server
npm install
npm start
```

The server runs on port 3000 by default.

### iOS
```bash
npm run ios
```

### Android
```bash
npm run android
```

## Configuration

### Server URL
Update the server URL in `src/services/SocketService.ts`:
```typescript
constructor(serverUrl: string = 'http://your-server-ip:3000') {
```

### STUN/TURN Servers
Configure ICE servers in `src/services/WebRTCService.ts` for production:
```typescript
const ICE_SERVERS = {
  iceServers: [
    { urls: 'stun:your-stun-server.com:19302' },
    {
      urls: 'turn:your-turn-server.com:443',
      username: 'username',
      credential: 'password',
    },
  ],
};
```

## Architecture

### WebRTC Flow
1. User initiates call via Socket.IO to signaling server
2. Server assigns an available professional
3. Professional accepts, triggering WebRTC offer/answer exchange
4. ICE candidates are exchanged for NAT traversal
5. Direct peer-to-peer connection established for video/audio

### Annotation Flow
1. Professional draws on canvas overlay
2. Annotations serialized and sent via Socket.IO
3. User receives and renders annotations on their screen
4. Frame freeze pauses video, allowing precise annotation
5. Resume sends annotations to be placed in video context

### Location Flow
1. User's device tracks GPS using high-accuracy mode
2. Location updates sent via Socket.IO
3. Professional sees real-time position on mini-map

## Permissions Required

### iOS
- Camera
- Microphone
- Location (When In Use & Always)
- Background Modes: audio, voip, location

### Android
- CAMERA
- RECORD_AUDIO
- ACCESS_FINE_LOCATION
- ACCESS_COARSE_LOCATION
- ACCESS_BACKGROUND_LOCATION
- INTERNET
- BLUETOOTH

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

MIT License - see LICENSE file for details

## Support

For issues and feature requests, please use the GitHub issue tracker.
