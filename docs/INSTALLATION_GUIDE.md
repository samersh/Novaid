# Novaid Installation & Deployment Guide

## A Complete Step-by-Step Tutorial

This guide will walk you through every single step needed to install, build, and test the Novaid app on your mobile devices and tablets. Follow each step carefully, and you'll have the app running in no time!

---

## Table of Contents

1. [What You Need (Prerequisites)](#1-what-you-need-prerequisites)
2. [Setting Up Your Computer](#2-setting-up-your-computer)
3. [Installing Node.js](#3-installing-nodejs)
4. [Setting Up for iPhone/iPad (iOS)](#4-setting-up-for-iphoneipad-ios)
5. [Setting Up for Android](#5-setting-up-for-android)
6. [Getting Google Maps API Key](#6-getting-google-maps-api-key)
7. [Downloading and Setting Up Novaid](#7-downloading-and-setting-up-novaid)
8. [Starting the Server](#8-starting-the-server)
9. [Running on iPhone/iPad](#9-running-on-iphoneipad)
10. [Running on Android](#10-running-on-android)
11. [Testing on Real Devices](#11-testing-on-real-devices)
12. [Testing the App Features](#12-testing-the-app-features)
13. [Common Problems and Solutions](#13-common-problems-and-solutions)
14. [Sharing the App with Others](#14-sharing-the-app-with-others)

---

## 1. What You Need (Prerequisites)

### For Building iOS Apps (iPhone/iPad):
- A Mac computer (MacBook, iMac, Mac Mini, or Mac Pro)
- macOS Ventura (13.0) or newer
- At least 50GB of free disk space
- An Apple ID (free to create at apple.com)

### For Building Android Apps:
- Any computer (Mac, Windows, or Linux)
- At least 30GB of free disk space

### For Testing on Real Devices:
- For iOS: An iPhone or iPad with iOS 13 or newer
- For Android: An Android phone or tablet with Android 6.0 or newer
- A USB cable to connect your device to your computer

### Internet Connection:
- You need a stable internet connection to download all the tools

---

## 2. Setting Up Your Computer

### Step 2.1: Check Your Operating System

**On Mac:**
1. Click the Apple logo () in the top-left corner of your screen
2. Click "About This Mac"
3. Look at the version number - it should say macOS 13 (Ventura) or higher

**On Windows:**
1. Press the Windows key + R
2. Type `winver` and press Enter
3. You should have Windows 10 or Windows 11

### Step 2.2: Open Terminal (Mac) or Command Prompt (Windows)

**On Mac:**
1. Press Command (⌘) + Space to open Spotlight
2. Type "Terminal"
3. Press Enter to open it
4. A window with a black or white background will appear - this is where you'll type commands

**On Windows:**
1. Press Windows key + R
2. Type `cmd` and press Enter
3. A black window will appear - this is Command Prompt

💡 **Tip:** Keep this window open throughout the entire installation process!

---

## 3. Installing Node.js

Node.js is a program that helps run JavaScript code on your computer. We need it to build our app.

### Step 3.1: Download Node.js

1. Open your web browser (Safari, Chrome, Firefox, etc.)
2. Go to: **https://nodejs.org**
3. You'll see two big green buttons
4. Click the button that says **"LTS"** (this is the stable version)
5. A file will start downloading

### Step 3.2: Install Node.js

**On Mac:**
1. Open your Downloads folder
2. Double-click the file that looks like `node-v20.x.x.pkg`
3. A window will pop up - click "Continue"
4. Click "Continue" again
5. Click "Agree" to accept the license
6. Click "Install"
7. Enter your Mac password when asked
8. Click "Close" when it's done

**On Windows:**
1. Open your Downloads folder
2. Double-click the file that looks like `node-v20.x.x-x64.msi`
3. Click "Next"
4. Check the box to accept the license, click "Next"
5. Click "Next" (keep the default location)
6. Click "Next" (keep the default features)
7. Click "Install"
8. Click "Yes" if Windows asks for permission
9. Click "Finish" when it's done

### Step 3.3: Verify Node.js is Installed

1. Close your Terminal/Command Prompt
2. Open a NEW Terminal/Command Prompt (very important!)
3. Type this command and press Enter:

```bash
node --version
```

4. You should see something like `v20.10.0` (the numbers might be different)

5. Now type this command and press Enter:

```bash
npm --version
```

6. You should see something like `10.2.0`

✅ **Success!** If you see version numbers for both, Node.js is installed correctly!

---

## 4. Setting Up for iPhone/iPad (iOS)

⚠️ **Important:** This section is ONLY for Mac computers. You cannot build iOS apps on Windows.

### Step 4.1: Install Xcode

Xcode is Apple's tool for building iPhone and iPad apps.

1. Open the **App Store** on your Mac (click the blue "A" icon in your dock)
2. In the search bar at the top, type "Xcode"
3. Find "Xcode" by Apple (it has a blue hammer icon)
4. Click "Get" then "Install"
5. Enter your Apple ID password if asked
6. **Wait patiently** - Xcode is very large (about 12GB) and can take 30-60 minutes to download!

### Step 4.2: Open Xcode for the First Time

1. When download is complete, open Xcode from your Applications folder
2. A window will appear saying "Install additional required components"
3. Click "Install"
4. Enter your Mac password
5. Wait for the installation to finish
6. Close Xcode when done

### Step 4.3: Accept Xcode License

1. Open Terminal
2. Type this command and press Enter:

```bash
sudo xcodebuild -license accept
```

3. Enter your Mac password when asked (you won't see the characters as you type - this is normal!)
4. Press Enter

### Step 4.4: Install Xcode Command Line Tools

1. In Terminal, type this command and press Enter:

```bash
xcode-select --install
```

2. A popup will appear - click "Install"
3. Click "Agree" to the license
4. Wait for the installation to complete (5-10 minutes)

### Step 4.5: Install Homebrew (Package Manager)

Homebrew helps you install other tools easily.

1. In Terminal, copy and paste this ENTIRE command (it's very long):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

2. Press Enter
3. Press Enter again when it asks you to continue
4. Enter your Mac password when asked
5. Wait for the installation (5-10 minutes)

6. **Important!** When it finishes, it will show some commands under "Next steps". Copy and run those commands. They usually look like:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### Step 4.6: Install CocoaPods

CocoaPods helps manage iOS libraries.

1. In Terminal, type:

```bash
sudo gem install cocoapods
```

2. Enter your password
3. Wait for installation (2-3 minutes)

4. Verify it's installed:

```bash
pod --version
```

You should see a version number like `1.14.3`

### Step 4.7: Install Watchman

Watchman helps React Native detect file changes.

1. In Terminal, type:

```bash
brew install watchman
```

2. Wait for installation (2-3 minutes)

✅ **iOS Setup Complete!** Your Mac is now ready to build iOS apps!

---

## 5. Setting Up for Android

### Step 5.1: Download Android Studio

1. Open your web browser
2. Go to: **https://developer.android.com/studio**
3. Click the big green button "Download Android Studio"
4. Check the box to accept the terms
5. Click "Download"
6. Wait for the download to complete

### Step 5.2: Install Android Studio

**On Mac:**
1. Open your Downloads folder
2. Double-click the file `android-studio-xxx-mac.dmg`
3. A window will appear with the Android Studio icon
4. Drag the Android Studio icon to the Applications folder
5. Open Android Studio from Applications
6. Click "Open" if a security warning appears

**On Windows:**
1. Open your Downloads folder
2. Double-click `android-studio-xxx-windows.exe`
3. Click "Yes" if Windows asks for permission
4. Click "Next"
5. Make sure "Android Virtual Device" is checked
6. Click "Next"
7. Click "Install"
8. Wait for installation
9. Click "Finish"
10. Android Studio will open automatically

### Step 5.3: Initial Android Studio Setup

1. When Android Studio opens, select "Do not import settings"
2. Click "OK"
3. Click "Next" on the Welcome screen
4. Select "Standard" installation type
5. Click "Next"
6. Choose a theme (light or dark - your preference)
7. Click "Next"
8. Click "Finish" to download components
9. **Wait** - this downloads about 2-3GB of files (15-30 minutes)
10. Click "Finish" when done

### Step 5.4: Install Additional SDK Components

1. In Android Studio, click "More Actions" (or the three dots menu)
2. Click "SDK Manager"
3. In the "SDK Platforms" tab:
   - Check "Android 14.0 (UpsideDownCake)" or the latest version
   - Check "Android 13.0 (Tiramisu)"
4. Click the "SDK Tools" tab
5. Check these items:
   - Android SDK Build-Tools
   - Android Emulator
   - Android SDK Platform-Tools
   - Google Play services
6. Click "Apply"
7. Click "OK" to confirm
8. Wait for downloads to complete
9. Click "Finish"

### Step 5.5: Set Up Environment Variables

This tells your computer where Android tools are located.

**On Mac:**

1. Open Terminal
2. Type this command to open your profile file:

```bash
nano ~/.zshrc
```

3. Use arrow keys to go to the bottom of the file
4. Copy and paste these lines:

```bash
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
```

5. Press Control + X
6. Press Y to save
7. Press Enter
8. Close Terminal and open a new one
9. Verify it works:

```bash
echo $ANDROID_HOME
```

You should see a path like `/Users/yourname/Library/Android/sdk`

**On Windows:**

1. Press Windows key, type "environment" and click "Edit the system environment variables"
2. Click "Environment Variables" button
3. Under "User variables", click "New"
4. Variable name: `ANDROID_HOME`
5. Variable value: `C:\Users\YOUR_USERNAME\AppData\Local\Android\Sdk`
   (Replace YOUR_USERNAME with your actual Windows username)
6. Click "OK"
7. Find "Path" in User variables, click it, then click "Edit"
8. Click "New" and add: `%ANDROID_HOME%\platform-tools`
9. Click "New" and add: `%ANDROID_HOME%\emulator`
10. Click "New" and add: `%ANDROID_HOME%\tools`
11. Click "New" and add: `%ANDROID_HOME%\tools\bin`
12. Click "OK" three times to close all windows
13. Close and reopen Command Prompt
14. Verify:

```bash
echo %ANDROID_HOME%
```

### Step 5.6: Create an Android Virtual Device (Emulator)

1. Open Android Studio
2. Click "More Actions" (or three dots)
3. Click "Virtual Device Manager"
4. Click "Create device"
5. Select "Pixel 6" (or any phone you like)
6. Click "Next"
7. Click "Download" next to "UpsideDownCake" (Android 14)
8. Wait for download (this takes a few minutes)
9. Click "Finish" when download completes
10. Click "Next"
11. Give it a name like "Pixel 6 Test"
12. Click "Finish"

### Step 5.7: Test the Emulator

1. In Virtual Device Manager, find your new device
2. Click the Play button (triangle icon) to start it
3. Wait for the virtual phone to boot up (1-2 minutes)
4. You should see an Android phone on your screen!
5. You can close it for now

✅ **Android Setup Complete!** Your computer is now ready to build Android apps!

---

## 6. Getting Google Maps API Key

The app uses Google Maps to show locations. You need an API key to make it work.

### Step 6.1: Create a Google Cloud Account

1. Go to: **https://console.cloud.google.com**
2. Sign in with your Google account (Gmail)
3. If this is your first time, accept the terms of service

### Step 6.2: Create a New Project

1. Click "Select a project" at the top of the page
2. Click "New Project"
3. Project name: `Novaid-App`
4. Click "Create"
5. Wait a moment for the project to be created
6. Make sure "Novaid-App" is selected in the project dropdown

### Step 6.3: Enable Billing

⚠️ **Note:** Google requires a credit card, but the Maps API has a generous free tier. You won't be charged unless you have millions of users.

1. Click the hamburger menu (☰) in the top-left
2. Click "Billing"
3. Click "Link a billing account"
4. Click "Create billing account"
5. Enter your country and accept terms
6. Click "Continue"
7. Choose "Individual" account type
8. Enter your payment information
9. Click "Start my free trial" (you get $300 free credit!)

### Step 6.4: Enable Maps APIs

1. Click the hamburger menu (☰)
2. Go to "APIs & Services" > "Library"
3. Search for "Maps SDK for Android"
4. Click on it
5. Click "Enable"
6. Go back to the Library
7. Search for "Maps SDK for iOS"
8. Click on it
9. Click "Enable"

### Step 6.5: Create API Key

1. Click the hamburger menu (☰)
2. Go to "APIs & Services" > "Credentials"
3. Click "Create Credentials" at the top
4. Select "API key"
5. A popup will show your new API key
6. **COPY THIS KEY AND SAVE IT SOMEWHERE SAFE!**
   - It looks like: `AIzaSyBxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
7. Click "Close"

### Step 6.6: (Optional but Recommended) Restrict Your API Key

1. Click on your newly created API key
2. Under "Application restrictions", you can:
   - For Android: Select "Android apps" and add your app's package name (`com.novaid`)
   - For iOS: Select "iOS apps" and add your app's bundle ID (`com.novaid`)
3. Under "API restrictions", select "Restrict key"
4. Check only "Maps SDK for Android" and "Maps SDK for iOS"
5. Click "Save"

✅ **Google Maps API Key Created!** Save this key - you'll need it soon!

---

## 7. Downloading and Setting Up Novaid

### Step 7.1: Download the Project

If you have the project on GitHub:

1. Open Terminal (Mac) or Command Prompt (Windows)
2. Navigate to where you want to put the project:

```bash
cd ~/Desktop
```

3. Clone the repository (replace with your actual repository URL):

```bash
git clone https://github.com/yourusername/Novaid.git
```

If you already have the project folder, just navigate to it:

```bash
cd /path/to/Novaid
```

### Step 7.2: Install JavaScript Dependencies

1. Make sure you're in the Novaid folder:

```bash
cd Novaid
```

2. Install all the packages:

```bash
npm install
```

3. Wait for installation (this downloads many files, may take 5-10 minutes)

You'll see a progress bar and lots of text scrolling by. This is normal!

### Step 7.3: Install iOS Dependencies (Mac Only)

1. Navigate to the iOS folder:

```bash
cd ios
```

2. Install CocoaPods dependencies:

```bash
pod install
```

3. Wait for installation (2-5 minutes)

4. Go back to the main folder:

```bash
cd ..
```

### Step 7.4: Add Your Google Maps API Key

**For iOS:**

1. Open the file `ios/Novaid/AppDelegate.mm` in a text editor
2. Find this line:
   ```
   [GMSServices provideAPIKey:@"YOUR_GOOGLE_MAPS_API_KEY"];
   ```
3. Replace `YOUR_GOOGLE_MAPS_API_KEY` with your actual API key
4. Save the file

**For Android:**

1. Open the file `android/app/src/main/AndroidManifest.xml` in a text editor
2. Find this line:
   ```xml
   android:value="YOUR_GOOGLE_MAPS_API_KEY"
   ```
3. Replace `YOUR_GOOGLE_MAPS_API_KEY` with your actual API key
4. Save the file

### Step 7.5: Configure Server URL

The app needs to know where to find the server.

1. Open the file `src/services/SocketService.ts`
2. Find this line near the top:
   ```typescript
   constructor(serverUrl: string = 'http://localhost:3000') {
   ```
3. For testing on a real device, you'll need to change `localhost` to your computer's IP address

**To find your computer's IP address:**

**On Mac:**
```bash
ipconfig getifaddr en0
```

**On Windows:**
```bash
ipconfig
```
Look for "IPv4 Address" under your Wi-Fi adapter

The IP will look like `192.168.1.100` (your numbers will be different)

4. Update the server URL:
   ```typescript
   constructor(serverUrl: string = 'http://192.168.1.100:3000') {
   ```

5. Save the file

---

## 8. Starting the Server

The server helps phones connect to each other. You need to run it before testing the app.

### Step 8.1: Open a New Terminal Window

- Keep your existing Terminal open
- Open a brand new Terminal window
- **On Mac:** Press Command + N in Terminal
- **On Windows:** Open a new Command Prompt

### Step 8.2: Navigate to Server Folder

```bash
cd ~/Desktop/Novaid/server
```

(Adjust the path based on where you put the Novaid folder)

### Step 8.3: Install Server Dependencies

```bash
npm install
```

Wait for installation to complete.

### Step 8.4: Start the Server

```bash
npm start
```

You should see:
```
Signaling server running on port 3000
```

✅ **Server is Running!** Keep this Terminal window open while testing!

---

## 9. Running on iPhone/iPad

### Step 9.1: Running on iOS Simulator

1. Open a NEW Terminal window (keep the server running in the other one)
2. Navigate to the Novaid folder:

```bash
cd ~/Desktop/Novaid
```

3. Start the app on iOS simulator:

```bash
npm run ios
```

4. Wait... This first build takes a LONG time (10-20 minutes)!
5. The iPhone Simulator will open automatically
6. The Novaid app will launch on the simulated iPhone

### Step 9.2: Choosing a Different Simulator

To run on a specific device (like iPad):

```bash
npm run ios -- --simulator="iPad Pro (12.9-inch) (6th generation)"
```

To see all available simulators:

```bash
xcrun simctl list devices
```

### Step 9.3: Common iOS Simulator Issues

**If the build fails:**

1. Clean the build:
```bash
cd ios
xcodebuild clean
cd ..
```

2. Delete derived data:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```

3. Reinstall pods:
```bash
cd ios
pod deintegrate
pod install
cd ..
```

4. Try building again:
```bash
npm run ios
```

---

## 10. Running on Android

### Step 10.1: Start Android Emulator

1. Open Android Studio
2. Click "More Actions" > "Virtual Device Manager"
3. Click the Play button next to your virtual device
4. Wait for the emulator to fully boot up (you'll see the Android home screen)

### Step 10.2: Running the App

1. Open a NEW Terminal window
2. Navigate to the Novaid folder:

```bash
cd ~/Desktop/Novaid
```

3. Start the app on Android:

```bash
npm run android
```

4. Wait for the build (first time takes 5-10 minutes)
5. The app will automatically install and launch on the emulator

### Step 10.3: Verify Device Connection

If the app doesn't launch automatically:

1. Check that the emulator is detected:

```bash
adb devices
```

You should see something like:
```
List of devices attached
emulator-5554   device
```

2. If you see "unauthorized" instead of "device", look at the emulator - there might be a popup asking for permission. Click "Allow".

### Step 10.4: Common Android Issues

**If you see "SDK location not found":**

Create a file called `local.properties` in the `android` folder:

**On Mac:**
```bash
echo "sdk.dir=$HOME/Library/Android/sdk" > android/local.properties
```

**On Windows:**
```bash
echo sdk.dir=C:\\Users\\YOUR_USERNAME\\AppData\\Local\\Android\\Sdk > android\local.properties
```

**If build fails with "license not accepted":**

```bash
cd ~/Library/Android/sdk/tools/bin  # Mac
cd %ANDROID_HOME%\tools\bin         # Windows

./sdkmanager --licenses             # Mac
sdkmanager --licenses               # Windows
```

Type `y` and press Enter for each license.

---

## 11. Testing on Real Devices

Testing on real devices is important because:
- Camera actually works (simulators have limited camera support)
- GPS works properly
- You can test the real user experience

### For iPhone/iPad:

#### Step 11.1: Connect Your Device

1. Connect your iPhone/iPad to your Mac with a USB cable
2. On your iPhone/iPad, tap "Trust" when asked to trust this computer
3. Enter your device passcode

#### Step 11.2: Set Up Code Signing

1. Open `ios/Novaid.xcworkspace` in Xcode (double-click the file)
2. In the left sidebar, click on "Novaid" (the top item with a blue icon)
3. In the main area, click "Signing & Capabilities"
4. Check "Automatically manage signing"
5. Click the "Team" dropdown
6. Select "Add an Account..."
7. Sign in with your Apple ID
8. Select your personal team (it will say "Personal Team")
9. Xcode might show a warning about the bundle ID - if so, click "Fix Issue"

#### Step 11.3: Build and Run on Device

1. At the top of Xcode, click on the device selector (it might say "iPhone 15 Pro")
2. You should see your connected iPhone/iPad in the list - select it
3. Click the Play button (▶) to build and run
4. First time only: Your iPhone might show an error about untrusted developer

#### Step 11.4: Trust the Developer on iPhone

1. On your iPhone, go to Settings
2. Go to General > VPN & Device Management
3. Find your Apple ID under "Developer App"
4. Tap on it
5. Tap "Trust [your Apple ID]"
6. Tap "Trust" again to confirm
7. Go back to Xcode and click Play again

### For Android Devices:

#### Step 11.1: Enable Developer Options

1. On your Android device, go to Settings
2. Scroll down and tap "About phone" (or "About tablet")
3. Find "Build number"
4. **Tap on "Build number" 7 times quickly!**
5. You'll see a message saying "You are now a developer!"

#### Step 11.2: Enable USB Debugging

1. Go back to Settings
2. Look for "Developer options" (usually near the bottom or in System)
3. Tap "Developer options"
4. Find "USB debugging"
5. Turn it ON
6. Tap "OK" to confirm

#### Step 11.3: Connect Your Device

1. Connect your Android device to your computer with a USB cable
2. On your device, you might see a popup asking to allow USB debugging
3. Check "Always allow from this computer"
4. Tap "Allow"

#### Step 11.4: Verify Connection

In Terminal/Command Prompt:

```bash
adb devices
```

You should see your device listed:
```
List of devices attached
XXXXXXXX    device
```

#### Step 11.5: Build and Run

```bash
npm run android
```

The app will install and launch on your connected device!

---

## 12. Testing the App Features

Now let's test all the features of the app!

### Step 12.1: Test Setup

For full testing, you need:
- TWO devices (or one device and one simulator)
- One will be the "User" (person needing help)
- One will be the "Professional" (person giving help)
- Both must be on the same Wi-Fi network as your computer

### Step 12.2: Test User Flow

On Device 1 (User):
1. Open the Novaid app
2. Tap "I Need Help"
3. You'll see your unique ID (like "ABC-123")
4. The green dot should show "Connected" (meaning connected to server)
5. Tap the big red "Call for Help" button
6. Wait for a professional to answer

### Step 12.3: Test Professional Flow

On Device 2 (Professional):
1. Open the Novaid app
2. Tap "I'm a Professional"
3. You'll see your professional dashboard
4. Make sure it shows "Connected" to the server
5. When the User calls, you'll see an incoming call notification
6. Tap "Accept" to answer the call

### Step 12.4: Test Video Call

Once connected:
- User: Your rear camera should be streaming
- Professional: You should see the User's video feed
- Test the mute button
- Test the end call button

### Step 12.5: Test AR Annotations (Professional Side)

1. On the Professional's screen, tap the pencil icon to draw
2. Draw on the video - the User should see your drawings!
3. Try different tools:
   - Freehand drawing
   - Arrows
   - Circles
   - Different colors
4. Try the "PAUSE" button to freeze the video
5. Draw more detailed annotations on the frozen frame
6. Tap "PLAY" to resume

### Step 12.6: Test Location

On the Professional's screen:
- Look for the small map in the corner
- It should show the User's location
- Tap the map to make it full screen

### Step 12.7: Troubleshooting Test Issues

**Video not showing:**
- Make sure you granted camera permissions
- Check that both devices are on the same network

**Can't connect to server:**
- Make sure the server is running (check the Terminal window)
- Verify the IP address in SocketService.ts is correct
- Make sure devices are on the same Wi-Fi network

**Annotations not appearing:**
- Make sure the call is connected (green status)
- Try clearing annotations and drawing again

---

## 13. Common Problems and Solutions

### Problem: "Command not found: npm"
**Solution:** Node.js isn't installed correctly. Go back to Step 3 and reinstall it.

### Problem: "Command not found: pod"
**Solution:** CocoaPods isn't installed. Run:
```bash
sudo gem install cocoapods
```

### Problem: iOS build fails with "signing" errors
**Solution:**
1. Open `ios/Novaid.xcworkspace` in Xcode
2. Go to Signing & Capabilities
3. Make sure a team is selected
4. Let Xcode fix any issues

### Problem: Android build fails with "SDK not found"
**Solution:** Create `android/local.properties` with the correct SDK path (see Step 10.4)

### Problem: "Unable to connect to server"
**Solution:**
1. Make sure the server is running (`npm start` in the server folder)
2. Check your IP address is correct in SocketService.ts
3. Make sure your firewall allows connections on port 3000

### Problem: Camera shows black screen
**Solution:**
1. Make sure camera permissions are granted
2. On iOS: Settings > Novaid > Camera (turn ON)
3. On Android: Settings > Apps > Novaid > Permissions > Camera (Allow)

### Problem: App crashes on launch
**Solution:**
1. Clear the build cache:
   ```bash
   npm start -- --reset-cache
   ```
2. For iOS: Delete app from simulator, rebuild
3. For Android: Clear app data or reinstall

### Problem: Maps not showing
**Solution:**
1. Make sure your Google Maps API key is correct
2. Check that Maps SDK is enabled in Google Cloud Console
3. Check that billing is set up

### Problem: "Port 3000 already in use"
**Solution:**
```bash
# Find what's using port 3000
lsof -i :3000  # Mac
netstat -ano | findstr :3000  # Windows

# Kill the process (replace XXXX with the PID number)
kill -9 XXXX  # Mac
taskkill /PID XXXX /F  # Windows
```

---

## 14. Sharing the App with Others

### For iOS Testing (TestFlight):

1. **Register for Apple Developer Program** ($99/year)
   - Go to: https://developer.apple.com/programs/
   - Click "Enroll"
   - Follow the steps

2. **Create App in App Store Connect**
   - Go to: https://appstoreconnect.apple.com
   - Click "My Apps"
   - Click "+" and "New App"
   - Fill in the details

3. **Archive and Upload**
   - In Xcode, select "Any iOS Device" as the destination
   - Go to Product > Archive
   - Click "Distribute App"
   - Select "TestFlight & App Store"
   - Follow the prompts

4. **Invite Testers**
   - In App Store Connect, go to TestFlight
   - Add internal or external testers
   - They'll receive an email to download TestFlight and your app

### For Android Testing (Google Play Internal Testing):

1. **Register for Google Play Console** ($25 one-time)
   - Go to: https://play.google.com/console
   - Follow the registration steps

2. **Create App**
   - Click "Create app"
   - Fill in the details

3. **Build Release APK**
   ```bash
   cd android
   ./gradlew assembleRelease
   ```
   The APK will be at: `android/app/build/outputs/apk/release/app-release.apk`

4. **Upload to Play Console**
   - Go to Release > Testing > Internal testing
   - Create a new release
   - Upload the APK
   - Add tester email addresses

### For Quick Sharing (Development Builds):

**Android APK:**
```bash
cd android
./gradlew assembleDebug
```
Share the APK file: `android/app/build/outputs/apk/debug/app-debug.apk`

People can install this directly on their Android devices by:
1. Enabling "Install from unknown sources" in settings
2. Opening the APK file

**iOS (Ad Hoc):**
This requires an Apple Developer account and is more complex. Use TestFlight instead for easier distribution.

---

## Quick Reference Commands

Keep this handy list of common commands:

```bash
# Start the signaling server
cd server && npm start

# Run on iOS Simulator
npm run ios

# Run on Android Emulator
npm run android

# Run on specific iOS device
npm run ios -- --device "Your Device Name"

# Clear Metro cache
npm start -- --reset-cache

# Clean iOS build
cd ios && xcodebuild clean && pod install && cd ..

# Clean Android build
cd android && ./gradlew clean && cd ..

# Check connected Android devices
adb devices

# Install dependencies
npm install

# Install iOS pods
cd ios && pod install && cd ..
```

---

## Congratulations! 🎉

You've successfully set up and deployed the Novaid app!

If you followed all the steps, you should now be able to:
- ✅ Run the app on iOS Simulator
- ✅ Run the app on Android Emulator
- ✅ Run the app on real iPhones and iPads
- ✅ Run the app on real Android devices
- ✅ Test all the features including video calling and AR annotations

If you have any issues, go back to the troubleshooting section or check the error messages carefully - they often tell you exactly what's wrong!

Happy testing! 📱
