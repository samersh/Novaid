# Novaid Remote Assistance

A native iOS application for real-time remote assistance with AR annotations. Built with Swift and SwiftUI.

![Platform](https://img.shields.io/badge/platform-iOS%2016%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

## Overview

Novaid Remote Assistance enables professionals to provide real-time guidance to users through video calls with AR annotations. Users can share their rear camera view while professionals draw, point, and highlight directly on the video feed.

### Key Features

- **One-Click Calling**: Users initiate calls with a single button tap - no codes or session numbers needed
- **Rear Camera Broadcasting**: High-quality video from device's rear camera
- **Video Stabilization**: Kalman filter-based software stabilization for smoother video
- **AR Annotations**: Real-time drawing, arrows, circles, pointers, and animations
- **Freeze Frame**: Professionals can pause video to draw precise annotations
- **Unique User IDs**: Automatic user identification without manual input

## Application Flow

### User Journey
1. **Splash Screen** → Animated app introduction
2. **Role Selection** → Choose "User" role
3. **Home Screen** → One-tap call button + demo mode option
4. **Video Call** → Rear camera view with received AR annotations

### Professional Journey
1. **Splash Screen** → Animated app introduction
2. **Role Selection** → Choose "Professional" role
3. **Home Screen** → Wait for incoming calls with accept/reject options
4. **Video Call** → View user's camera with full AR annotation tools

## Technology Stack

- **SwiftUI** - Modern declarative UI framework
- **AVFoundation** - Camera and video processing
- **CoreMotion** - Motion data for video stabilization
- **WebSocket** - Real-time signaling communication
- **Combine** - Reactive data flow

## Project Structure

```
NovaidAssist/
├── NovaidAssist.xcodeproj     # Xcode project
├── NovaidAssist/
│   ├── NovaidAssistApp.swift  # App entry point
│   ├── ContentView.swift      # Main navigation
│   ├── Views/
│   │   ├── SplashView.swift
│   │   ├── User/              # User screens
│   │   │   ├── UserHomeView.swift
│   │   │   └── UserVideoCallView.swift
│   │   ├── Professional/      # Professional screens
│   │   │   ├── ProfessionalHomeView.swift
│   │   │   └── ProfessionalVideoCallView.swift
│   │   ├── AnnotationOverlay.swift
│   │   ├── DrawingCanvas.swift
│   │   └── CameraPreview.swift
│   ├── Services/
│   │   ├── WebRTCService.swift
│   │   ├── SignalingService.swift
│   │   ├── VideoStabilizer.swift
│   │   ├── AnnotationService.swift
│   │   ├── UserManager.swift
│   │   └── CallManager.swift
│   ├── Models/
│   │   └── Models.swift
│   ├── Utils/
│   │   └── Extensions.swift
│   └── Assets.xcassets
├── NovaidAssistTests/         # Unit tests
└── NovaidAssistUITests/       # UI tests
```

## Quick Start

See [docs/QUICK_START.md](docs/QUICK_START.md) for a rapid setup guide.

## Installation

See [docs/INSTALLATION.md](docs/INSTALLATION.md) for detailed installation instructions.

## Core Services

### WebRTC Service
Manages video capture and peer-to-peer connections. Handles camera setup, stream management, and call state.

### Video Stabilizer
Software-based video stabilization using Kalman filtering. Processes accelerometer and gyroscope data to compensate for camera shake.

```swift
let stabilizer = VideoStabilizer()
stabilizer.startStabilization()
// Apply stabilizer.stabilizationTransform() to video frames
```

### Annotation Service
Manages AR annotations including:
- **Drawing**: Freehand paths with customizable colors and stroke widths
- **Arrows**: Direction indicators
- **Circles**: Area highlights
- **Pointers**: Animated attention markers (pulse, bounce, highlight)
- **Text**: Labels and instructions

```swift
let service = AnnotationService()
service.startDrawing(at: point)
service.continueDrawing(to: nextPoint)
service.endDrawing()
```

### User Manager
Handles user identification and persistence. Automatically generates unique IDs without requiring manual input.

```swift
let manager = UserManager.shared
manager.initializeUser(role: .user)
print(manager.shortId) // "ABC123"
```

## Running Tests

```bash
# Open in Xcode
open NovaidAssist/NovaidAssist.xcodeproj

# Run tests with Cmd+U or:
xcodebuild test -scheme NovaidAssist -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Running the Signaling Server

```bash
cd server
npm install
npm start
```

Server runs on `http://localhost:3001` by default.

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+
- Node.js 18+ (for signaling server)

## Configuration

### Signaling Server URL
Update the server URL in `Services/SignalingService.swift`:

```swift
init(userId: String, serverURL: String = "ws://your-server.com:3001")
```

### Video Stabilization
Adjust stabilization parameters in `Services/VideoStabilizer.swift`:

```swift
var config = VideoStabilizer.Config()
config.smoothingFactor = 0.95  // Higher = smoother but more lag
config.maxOffset = 50.0        // Maximum pixel compensation
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
