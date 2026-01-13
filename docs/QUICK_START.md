# Quick Start Guide

Get Novaid Remote Assistance running in under 5 minutes.

## Prerequisites Check

```bash
# Verify Xcode is installed
xcode-select --version

# Verify Node.js (18+)
node --version

# Verify npm
npm --version
```

## 3-Minute Setup

### Step 1: Clone & Start Server (1 min)

```bash
# Clone repository
git clone https://github.com/samersh/Novaid.git
cd Novaid

# Start signaling server
cd server && npm install && npm start
```

Keep this terminal open.

### Step 2: Open iOS Project (30 sec)

```bash
# Open new terminal
cd NovaidAssist
open NovaidAssist.xcodeproj
```

### Step 3: Run the App (1.5 min)

1. In Xcode, select **iPhone 16** simulator (or your connected device)
2. Press **Cmd + R** to build and run

## First Run Experience

1. **Splash Screen** - Wait 2 seconds
2. **Role Selection** - Choose:
   - **User** - To request assistance
   - **Professional** - To provide assistance

## Testing the App

### Single Device Demo

1. Launch app
2. Select **User**
3. Tap **Try Demo**
4. Explore the video call interface

### Two Device Testing

**Device 1 (User):**
1. Launch app → Select **User**
2. Tap **Start Call**

**Device 2 (Professional):**
1. Launch app → Select **Professional**
2. Wait for incoming call
3. Tap **Accept**
4. Draw annotations on the video!

## Key Features to Try

### As a User
| Action | How |
|--------|-----|
| Start call | Tap the big phone button |
| Demo mode | Tap "Try Demo" |
| End call | Tap red phone button |

### As a Professional
| Action | How |
|--------|-----|
| Accept call | Tap green checkmark |
| Draw | Tap pencil → draw on screen |
| Freeze video | Tap pause button |
| Change color | Tap color circles |
| Clear drawings | Tap "Clear All" |

## Annotation Tools

| Tool | Icon | Usage |
|------|------|-------|
| Pen | ✏️ | Freehand drawing |
| Arrow | → | Direction indicators |
| Circle | ○ | Highlight areas |
| Pointer | 👆 | Animated attention marker |

## Common Commands

```bash
# Start server
cd server && npm start

# Open Xcode project
open NovaidAssist/NovaidAssist.xcodeproj

# Run tests
xcodebuild test -scheme NovaidAssist -destination 'platform=iOS Simulator,name=iPhone 16'

# Check server health
curl http://localhost:3001/health
```

## Troubleshooting Quick Fixes

| Problem | Solution |
|---------|----------|
| Build failed | Cmd + Shift + K (Clean) then Cmd + R |
| Server won't start | Check if port 3001 is free |
| Camera not working | Use physical device (not simulator) |
| Call won't connect | Restart server and app |

## Project Structure

```
Novaid/
├── NovaidAssist/           # iOS App
│   ├── Views/              # UI screens
│   ├── Services/           # Business logic
│   └── Models/             # Data models
├── server/                 # Signaling server
└── docs/                   # Documentation
```

## Next Steps

1. Read full [Installation Guide](INSTALLATION.md)
2. Explore the [README](../README.md)
3. Check test files for examples

## Support

- GitHub Issues: Report bugs
- Documentation: Check `/docs` folder

Happy coding! 🚀
