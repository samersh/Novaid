# Installation Guide

Complete guide for setting up Novaid Remote Assistance on your development machine.

## Prerequisites

### Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| macOS | 13.0+ | Development OS |
| Xcode | 15.0+ | iOS development |
| Node.js | 18+ | Signaling server |
| npm | 9+ | Package management |

### Hardware Requirements

- Mac with Apple Silicon or Intel processor
- iPhone/iPad for testing (iOS 16+) or iOS Simulator
- Stable internet connection

## Step 1: Clone the Repository

```bash
git clone https://github.com/samersh/Novaid.git
cd Novaid
```

## Step 2: Set Up the Signaling Server

The signaling server coordinates WebRTC connections between users and professionals.

```bash
# Navigate to server directory
cd server

# Install dependencies
npm install

# Start the server
npm start
```

You should see:
```
Novaid Signaling Server running on port 3001
Health check: http://localhost:3001/health
```

**Keep this terminal open** while developing.

## Step 3: Open the iOS Project

```bash
# Navigate to the iOS project
cd ../NovaidAssist

# Open in Xcode
open NovaidAssist.xcodeproj
```

## Step 4: Configure Signing

1. In Xcode, select the **NovaidAssist** project in the navigator
2. Select the **NovaidAssist** target
3. Go to **Signing & Capabilities** tab
4. Select your **Team** from the dropdown
5. Ensure **Automatically manage signing** is checked

## Step 5: Build and Run

### On Simulator

1. Select a simulator from the device dropdown (e.g., "iPhone 16")
2. Press **Cmd + R** or click the **Play** button

### On Physical Device

1. Connect your iPhone via USB
2. Select your device from the dropdown
3. Trust the computer on your iPhone if prompted
4. Press **Cmd + R**

**Note:** Camera features require a physical device.

## Step 6: Configure Server URL (Optional)

By default, the app connects to `ws://localhost:3001`. For remote testing:

1. Open `NovaidAssist/Services/SignalingService.swift`
2. Update the default URL:

```swift
init(userId: String, serverURL: String = "ws://YOUR_SERVER_IP:3001")
```

## Project Configuration

### Info.plist Permissions

The app requires these permissions (already configured):

| Key | Description |
|-----|-------------|
| NSCameraUsageDescription | Camera access for video calls |
| NSMicrophoneUsageDescription | Microphone for audio |
| UIBackgroundModes | Audio and VoIP for background calls |

### Build Settings

| Setting | Value |
|---------|-------|
| iOS Deployment Target | 16.0 |
| Swift Version | 5.0 |
| Supported Platforms | iPhone, iPad |

## Running Tests

### Unit Tests

```bash
# From command line
xcodebuild test \
  -project NovaidAssist/NovaidAssist.xcodeproj \
  -scheme NovaidAssist \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Or in Xcode: **Cmd + U**

### UI Tests

```bash
xcodebuild test \
  -project NovaidAssist/NovaidAssist.xcodeproj \
  -scheme NovaidAssist \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:NovaidAssistUITests
```

## Troubleshooting

### Build Errors

**"No such module" error:**
```bash
# Clean build folder
# In Xcode: Product > Clean Build Folder (Cmd + Shift + K)
# Then rebuild
```

**Signing issues:**
- Ensure you have an Apple Developer account
- Check that your Team is selected in Signing & Capabilities

### Runtime Issues

**Camera not working on Simulator:**
- Camera requires a physical device
- Use Demo mode for UI testing on simulator

**Cannot connect to server:**
1. Verify server is running (`http://localhost:3001/health`)
2. Check firewall settings
3. For physical device, use your Mac's IP address instead of localhost

### Server Issues

**Port already in use:**
```bash
# Find and kill process using port 3001
lsof -i :3001
kill -9 <PID>
```

**Dependencies issues:**
```bash
rm -rf node_modules
npm install
```

## Production Deployment

### iOS App

1. Update version in Xcode project settings
2. Archive: **Product > Archive**
3. Distribute via App Store Connect

### Signaling Server

Deploy to any Node.js hosting service:

**Heroku:**
```bash
heroku create novaid-signaling
git subtree push --prefix server heroku main
```

**Docker:**
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY server/package*.json ./
RUN npm install
COPY server/ .
EXPOSE 3001
CMD ["npm", "start"]
```

## Environment Variables

### Server Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| PORT | 3001 | Server port |
| NODE_ENV | development | Environment mode |

## Next Steps

- Read the [Quick Start Guide](QUICK_START.md)
- Explore the [README](../README.md) for architecture details
- Check the test files for usage examples
