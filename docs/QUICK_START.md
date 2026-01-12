# Novaid Quick Start Guide

For experienced developers who just need the commands.

## Prerequisites

- Node.js 18+
- Xcode 15+ (for iOS)
- Android Studio (for Android)
- CocoaPods (for iOS)

## Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/Novaid.git
cd Novaid

# Install dependencies
npm install

# iOS only: Install pods
cd ios && pod install && cd ..
```

## Configure API Keys

1. **Google Maps iOS:** Edit `ios/Novaid/AppDelegate.mm`
   ```objc
   [GMSServices provideAPIKey:@"YOUR_API_KEY"];
   ```

2. **Google Maps Android:** Edit `android/app/src/main/AndroidManifest.xml`
   ```xml
   android:value="YOUR_API_KEY"
   ```

3. **Server URL:** Edit `src/services/SocketService.ts`
   ```typescript
   constructor(serverUrl: string = 'http://YOUR_IP:3000') {
   ```

## Run

```bash
# Terminal 1: Start server
cd server && npm install && npm start

# Terminal 2: Run iOS
npm run ios

# OR Terminal 2: Run Android
npm run android
```

## Build for Release

### iOS
```bash
cd ios
xcodebuild -workspace Novaid.xcworkspace -scheme Novaid -configuration Release -archivePath build/Novaid.xcarchive archive
```

### Android
```bash
cd android
./gradlew assembleRelease
# APK at: android/app/build/outputs/apk/release/app-release.apk
```

## Useful Commands

```bash
# Clear cache
npm start -- --reset-cache

# Clean iOS
cd ios && xcodebuild clean && pod install && cd ..

# Clean Android
cd android && ./gradlew clean && cd ..

# List simulators
xcrun simctl list devices

# Check Android devices
adb devices

# Run on specific iOS simulator
npm run ios -- --simulator="iPhone 15 Pro"

# Run on specific Android device
npm run android -- --deviceId=DEVICE_ID
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Pod install fails | `sudo gem install cocoapods && pod repo update` |
| Android SDK not found | Create `android/local.properties` with `sdk.dir=/path/to/sdk` |
| Port 3000 in use | `lsof -i :3000` then `kill -9 PID` |
| Metro bundler stuck | `npm start -- --reset-cache` |
| iOS signing error | Open in Xcode, set team in Signing & Capabilities |

## Testing Checklist

- [ ] Server running and accessible
- [ ] User can see their unique ID
- [ ] User can initiate call
- [ ] Professional receives incoming call
- [ ] Video streaming works both ways
- [ ] AR annotations appear on user's screen
- [ ] Location shows on professional's map
- [ ] Frame freeze/resume works
- [ ] Call can be ended properly
