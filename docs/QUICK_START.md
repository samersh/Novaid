# Quick Start Guide

Get Novaid Remote Assistance running in under 10 minutes.

## Prerequisites Check

```bash
# Verify Node.js (18+)
node --version

# Verify npm (9+)
npm --version

# Verify React Native CLI
npx react-native --version
```

## 5-Minute Setup

### Step 1: Install Dependencies

```bash
cd Novaid
npm install
```

### Step 2: Start the Signaling Server

```bash
# Open a new terminal
cd server
npm install
npm start
```

You should see:
```
Novaid Signaling Server running on port 3001
```

### Step 3: Run the App

**For iOS (Mac only):**
```bash
cd ios && pod install && cd ..
npm run ios
```

**For Android:**
```bash
npm run android
```

### Step 4: Test the App

1. Run the app on **two devices** (or simulators)
2. On Device 1: Select **"User"** role
3. On Device 2: Select **"Professional"** role
4. On Device 1: Tap **"Start Call"**
5. On Device 2: Tap **"Accept"** when call appears
6. You're now in a video call with AR annotation support!

---

## Quick Demo Mode

Don't have two devices? Use Demo Mode:

1. Launch the app
2. Select "User"
3. Tap "Try Demo"
4. Explore the video call interface

---

## Key Features to Try

### As a User
- **One-tap calling**: Just press the call button
- **Rear camera view**: Your view is shared with the professional
- **Receive annotations**: See drawings appear on your screen

### As a Professional
- **Accept calls**: Incoming calls show with user ID
- **Draw annotations**: Tap the pencil icon to draw
- **Freeze video**: Pause the video for precise annotations
- **Multiple tools**: Pen, arrow, circle, pointer

---

## Annotation Tools

| Tool | Icon | Usage |
|------|------|-------|
| Pen | ✏️ | Freehand drawing |
| Arrow | ➡️ | Direction indicators |
| Circle | ⭕ | Highlight areas |
| Pointer | 👆 | Animated attention marker |

**Color Palette**: Red, Green, Blue, Yellow, Magenta, Cyan, White

---

## Project Structure Overview

```
src/
├── screens/           # App screens
│   ├── user/         # User role: Splash, Home, VideoCall
│   └── professional/ # Professional role: Splash, Home, VideoCall
├── services/         # Core logic
│   ├── WebRTCService.ts       # Video calling
│   ├── AnnotationService.ts   # AR annotations
│   └── VideoStabilizer.ts     # Camera stabilization
└── components/       # UI components
    ├── VideoView.tsx          # Video display
    ├── AnnotationOverlay.tsx  # Annotation layer
    └── DrawingCanvas.tsx      # Drawing interface
```

---

## Common Commands

```bash
# Start development server
npm start

# Run on iOS
npm run ios

# Run on Android
npm run android

# Run tests
npm test

# Type check
npm run typecheck

# Start signaling server
cd server && npm start
```

---

## Configuration Options

### Change Server URL

Edit `src/services/SignalingService.ts`:

```typescript
const DEFAULT_SERVER_URL = 'wss://your-server.com';
```

### Adjust Video Stabilization

Edit `src/services/VideoStabilizer.ts`:

```typescript
// More smoothing (reduces shake but adds lag)
smoothingFactor: 0.98

// Less smoothing (more responsive but shakier)
smoothingFactor: 0.85
```

---

## Troubleshooting Quick Fixes

| Problem | Solution |
|---------|----------|
| Metro bundler stuck | `npm start -- --reset-cache` |
| iOS pods issue | `cd ios && pod install --repo-update` |
| Android build fail | `cd android && ./gradlew clean` |
| No connection | Check signaling server is running |

---

## Next Steps

- Read the full [Installation Guide](INSTALLATION.md) for detailed setup
- Explore the [README](../README.md) for architecture details
- Check `/server/index.js` for signaling server customization
- Review `/src/services/` for service customization

---

## Support

- GitHub Issues: Report bugs or request features
- Documentation: Check `/docs` for detailed guides

Happy coding! 🚀
