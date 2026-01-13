# Installation Guide

Complete guide for setting up Novaid Remote Assistance on your development machine and deploying to devices.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Project Installation](#project-installation)
4. [iOS Setup](#ios-setup)
5. [Android Setup](#android-setup)
6. [Signaling Server Setup](#signaling-server-setup)
7. [Running the Application](#running-the-application)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| Node.js | 18.0+ | JavaScript runtime |
| npm | 9.0+ | Package manager |
| Watchman | Latest | File watching (macOS) |
| Xcode | 14.0+ | iOS development |
| Android Studio | Hedgehog+ | Android development |
| JDK | 17 | Android build tools |
| CocoaPods | 1.14+ | iOS dependencies |

### Hardware Requirements

- **Development Machine**: macOS (for iOS), Windows/Linux/macOS (for Android)
- **RAM**: Minimum 8GB, recommended 16GB
- **Disk Space**: At least 20GB free

---

## Environment Setup

### macOS

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Node.js
brew install node@18

# Install Watchman
brew install watchman

# Install CocoaPods
sudo gem install cocoapods

# Install Java Development Kit
brew install openjdk@17
```

### Windows

1. Download and install [Node.js LTS](https://nodejs.org/)
2. Download and install [Android Studio](https://developer.android.com/studio)
3. Install JDK 17 via Android Studio or separately

### Linux (Ubuntu/Debian)

```bash
# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install JDK
sudo apt-get install openjdk-17-jdk

# Install Android Studio dependencies
sudo apt-get install libc6:i386 libncurses5:i386 libstdc++6:i386 lib32z1 libbz2-1.0:i386
```

---

## Project Installation

### 1. Clone the Repository

```bash
git clone https://github.com/samersh/Novaid.git
cd Novaid
```

### 2. Install Dependencies

```bash
# Install npm packages
npm install

# If you encounter peer dependency issues
npm install --legacy-peer-deps
```

### 3. Environment Configuration

Create a `.env` file in the project root (optional):

```bash
SIGNALING_SERVER_URL=ws://localhost:3001
```

---

## iOS Setup

### 1. Install iOS Dependencies

```bash
cd ios
pod install
cd ..
```

### 2. Configure Xcode

1. Open `ios/NovaidRemoteAssistance.xcworkspace` in Xcode
2. Select your development team in **Signing & Capabilities**
3. Update the Bundle Identifier if needed

### 3. Permissions

The app requires the following permissions (already configured in `Info.plist`):

- **Camera**: For video capture
- **Microphone**: For audio during calls
- **Background Modes**: VoIP and Audio for call functionality

### 4. Build and Run

```bash
# Using React Native CLI
npm run ios

# Or specify a simulator
npx react-native run-ios --simulator="iPhone 15 Pro"

# For physical device
npx react-native run-ios --device
```

---

## Android Setup

### 1. Configure Android Studio

1. Open Android Studio
2. Go to **SDK Manager** → **SDK Tools**
3. Install:
   - Android SDK Build-Tools 34.0.0
   - Android SDK Platform 34
   - NDK 25.1.8937393
   - CMake

### 2. Set Environment Variables

**macOS/Linux** (add to `~/.bashrc` or `~/.zshrc`):
```bash
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
export JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home
```

**Windows** (System Environment Variables):
```
ANDROID_HOME = C:\Users\<user>\AppData\Local\Android\Sdk
JAVA_HOME = C:\Program Files\Java\jdk-17
```

### 3. Create an AVD (Android Virtual Device)

1. Open Android Studio → **Virtual Device Manager**
2. Create a new device (recommended: Pixel 6 with API 34)
3. Start the emulator

### 4. Build and Run

```bash
# Start Android
npm run android

# Or with specific device
npx react-native run-android --deviceId=<device-id>
```

---

## Signaling Server Setup

The signaling server coordinates WebRTC connections between users and professionals.

### Local Development

```bash
# Navigate to server directory
cd server

# Install dependencies
npm install

# Start the server
npm start

# Or with auto-reload
npm run dev
```

Server will run on `http://localhost:3001`

### Production Deployment

#### Deploy to Heroku

```bash
# Login to Heroku
heroku login

# Create app
heroku create novaid-signaling

# Deploy
cd server
git init
git add .
git commit -m "Initial server deploy"
heroku git:remote -a novaid-signaling
git push heroku main
```

#### Deploy with Docker

Create `server/Dockerfile`:

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3001
CMD ["npm", "start"]
```

Build and run:

```bash
docker build -t novaid-signaling ./server
docker run -p 3001:3001 novaid-signaling
```

### Update App Configuration

After deploying, update the server URL in `src/services/SignalingService.ts`:

```typescript
const DEFAULT_SERVER_URL = 'wss://your-deployed-server.com';
```

---

## Running the Application

### Development Mode

**Terminal 1 - Start Metro Bundler:**
```bash
npm start
```

**Terminal 2 - Start Signaling Server:**
```bash
cd server && npm start
```

**Terminal 3 - Run App:**
```bash
# iOS
npm run ios

# Android
npm run android
```

### Testing the App

1. Launch the app on two devices/emulators
2. Select "User" on one device
3. Select "Professional" on the other
4. User taps "Start Call"
5. Professional receives and accepts the call
6. Video call begins with AR annotation capability

---

## Troubleshooting

### Common Issues

#### Metro Bundler Issues

```bash
# Clear Metro cache
npm start -- --reset-cache

# Clear all caches
rm -rf node_modules
npm cache clean --force
npm install
```

#### iOS Build Failures

```bash
# Clean and rebuild
cd ios
pod deintegrate
pod cache clean --all
pod install
cd ..

# Clean Xcode build
xcodebuild clean -workspace ios/NovaidRemoteAssistance.xcworkspace -scheme NovaidRemoteAssistance
```

#### Android Build Failures

```bash
# Clean Gradle
cd android
./gradlew clean
cd ..

# Rebuild
npm run android
```

#### WebRTC Issues

- Ensure camera/microphone permissions are granted
- Check that the signaling server is running
- Verify network connectivity between devices

#### "No Professional Available"

- Ensure a device is running in "Professional" mode
- Check signaling server logs for connection issues
- Verify both devices are connected to the same server

### Debug Logging

Enable verbose logging:

```typescript
// In src/services/WebRTCService.ts
console.log('Debug:', ...);
```

View logs:
```bash
# iOS
npx react-native log-ios

# Android
npx react-native log-android
```

---

## Next Steps

After installation, check out the [Quick Start Guide](QUICK_START.md) for rapid development.
