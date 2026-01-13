# Novaid Remote Assistance

A cross-platform mobile application for real-time remote assistance with AR annotations. Built with React Native, WebRTC, and Socket.IO.

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-blue)
![React Native](https://img.shields.io/badge/React%20Native-0.73.4-green)
![License](https://img.shields.io/badge/license-MIT-blue)

## Overview

Novaid Remote Assistance enables professionals to provide real-time guidance to users through video calls with AR annotations. Users can share their rear camera view while professionals draw, point, and highlight directly on the video feed.

### Key Features

- **One-Click Calling**: Users can initiate calls with a single button tap
- **Rear Camera Broadcasting**: High-quality video from device's rear camera
- **Video Stabilization**: Built-in software stabilization for smoother video
- **AR Annotations**: Real-time drawing, arrows, circles, pointers, and animations
- **Freeze Frame**: Professionals can pause video to draw precise annotations
- **WebRTC P2P**: Fast, low-latency peer-to-peer connections
- **Unique User IDs**: Automatic user identification - no codes or session numbers needed

## Application Flow

### User Journey
1. **Splash Screen** → Automatic initialization and server connection
2. **Home Screen** → One-tap call button + demo mode option
3. **Video Call** → Rear camera view with received AR annotations

### Professional Journey
1. **Splash Screen** → Automatic initialization and professional registration
2. **Home Screen** → Wait for incoming calls with accept/reject options
3. **Video Call** → View user's camera with full AR annotation tools

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Novaid App                            │
├─────────────────────────────────────────────────────────────┤
│  User App                    │    Professional App           │
│  ┌──────────────┐           │    ┌──────────────┐           │
│  │ Rear Camera  │           │    │ Video View   │           │
│  │    +         │◄─────────►│    │    +         │           │
│  │ AR Overlay   │  WebRTC   │    │ Drawing Tool │           │
│  └──────────────┘   P2P     │    └──────────────┘           │
├─────────────────────────────┴───────────────────────────────┤
│                    Signaling Server                          │
│              (Socket.IO / WebSocket)                         │
└─────────────────────────────────────────────────────────────┘
```

## Technology Stack

- **React Native 0.73.4** - Cross-platform mobile framework
- **WebRTC** - Real-time peer-to-peer video communication
- **Socket.IO** - WebSocket signaling for call coordination
- **React Navigation** - Native navigation stack
- **React Native SVG** - Vector graphics for annotations
- **React Native Reanimated** - Smooth animations

## Quick Start

See [docs/QUICK_START.md](docs/QUICK_START.md) for a rapid setup guide.

## Installation

See [docs/INSTALLATION.md](docs/INSTALLATION.md) for detailed installation instructions.

## Project Structure

```
novaid/
├── src/
│   ├── components/          # Reusable UI components
│   │   ├── AnnotationOverlay.tsx
│   │   ├── DrawingCanvas.tsx
│   │   └── VideoView.tsx
│   ├── context/             # React Context providers
│   │   └── AppContext.tsx
│   ├── navigation/          # Navigation configuration
│   │   └── AppNavigator.tsx
│   ├── screens/             # Screen components
│   │   ├── user/            # User role screens
│   │   └── professional/    # Professional role screens
│   ├── services/            # Core business logic
│   │   ├── AnnotationService.ts
│   │   ├── SignalingService.ts
│   │   ├── UserIdService.ts
│   │   ├── VideoStabilizer.ts
│   │   └── WebRTCService.ts
│   ├── types/               # TypeScript type definitions
│   └── utils/               # Utility functions
├── server/                  # Signaling server
├── __tests__/               # Test files
├── android/                 # Android native code
├── ios/                     # iOS native code
└── docs/                    # Documentation
```

## Core Services

### WebRTC Service
Manages peer-to-peer video connections using WebRTC. Handles ICE candidates, offer/answer exchange, and media streams.

### Video Stabilizer
Software-based video stabilization using Kalman filtering and motion smoothing. Processes accelerometer data to compensate for camera shake.

### Annotation Service
Manages AR annotations including:
- **Drawing**: Freehand paths
- **Arrows**: Direction indicators
- **Circles**: Area highlights
- **Pointers**: Animated attention markers
- **Text**: Labels and instructions
- **Animations**: Pulse, bounce, highlight effects

### Signaling Service
Socket.IO-based signaling for WebRTC connection establishment and call coordination.

## Running Tests

```bash
# Run all tests
npm test

# Run with coverage
npm run test:coverage

# Run specific test file
npm test -- VideoStabilizer
```

## Development

### Prerequisites
- Node.js 18+
- React Native CLI
- Xcode (for iOS)
- Android Studio (for Android)

### Running the Signaling Server

```bash
cd server
npm install
npm start
```

Server runs on `http://localhost:3001` by default.

### Running the Mobile App

```bash
# Install dependencies
npm install

# iOS
npm run ios

# Android
npm run android
```

## Configuration

### Signaling Server URL
Update the server URL in `src/services/SignalingService.ts`:

```typescript
const DEFAULT_SERVER_URL = 'wss://your-server.com';
```

### Video Stabilization
Adjust stabilization parameters in `src/services/VideoStabilizer.ts`:

```typescript
const config = {
  enabled: true,
  smoothingFactor: 0.95,  // Higher = smoother but more lag
  maxOffset: 50,          // Maximum pixel compensation
};
```

## API Reference

### WebRTC Service

```typescript
// Initialize local camera stream
await webrtc.initializeLocalStream(useRearCamera);

// Start a call
await webrtc.initiateCall(targetUserId);

// Accept incoming call
await webrtc.acceptCall(callerId);

// Send annotation
webrtc.sendAnnotation(annotation);

// Freeze/resume video
webrtc.freezeVideo();
webrtc.resumeVideo(annotations);
```

### Annotation Service

```typescript
// Drawing
annotation.startDrawing(point, color, strokeWidth);
annotation.addDrawingPoint(point);
annotation.endDrawing();

// Quick annotations
annotation.createPointer(point, color);
annotation.createArrow(start, end);
annotation.createCircle(center, radius);
annotation.createText(position, text);
annotation.createAnimation(point, 'pulse');
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [WebRTC](https://webrtc.org/) for real-time communication
- [React Native](https://reactnative.dev/) for cross-platform development
- [Socket.IO](https://socket.io/) for real-time signaling
