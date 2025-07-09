# Whizr - AI Writing Assistant for macOS

Press ⌘+Shift+Space anywhere on your Mac to get instant AI writing help.

## Features

- **Universal Hotkey**: Works in every Mac application
- **Context-Aware**: Understands what you're writing and where
- **Lightning Fast**: Get AI assistance without breaking your flow
- **Smart Suggestions**: Adapts to email, code, documents, and more
- **Menu Bar App**: Runs discreetly in your menu bar
- **Native macOS Integration**: Built with SwiftUI for optimal performance

## Installation

### Prerequisites

- macOS 14.0+ (Sonoma and later)
- Xcode 15.0+ (for building from source)

### Quick Install

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/whizr.git
   cd whizr
   ```

2. Open the project in Xcode:
   ```bash
   open Whizr.xcodeproj
   ```

3. Build and run from Xcode (⌘+R)

### Command Line Build

```bash
# Build the app
swift build

# Run the app
swift run
```

## Required Permissions

Whizr requires the following macOS permissions to function:

### Accessibility Access
- Go to System Settings → Privacy & Security → Accessibility
- Click the '+' button and add Whizr
- Enable the toggle for Whizr

### Input Monitoring
- Go to System Settings → Privacy & Security → Input Monitoring
- Click the '+' button and add Whizr
- Enable the toggle for Whizr
- This allows Whizr to detect the ⌘+Shift+Space hotkey

## Configuration

### API Keys

Whizr supports multiple LLM providers:

1. **OpenAI**: Set your API key in the preferences
2. **Anthropic**: Set your API key in the preferences
3. **Ollama**: Configure local endpoint (default: http://localhost:11434)

API keys are stored securely in the macOS Keychain.

### Hotkey

The default hotkey is ⌘+Shift+Space. This can be customized in the preferences.

## Usage

1. Launch Whizr (it appears in your menu bar)
2. In any application, press ⌘+Shift+Space
3. Type your request in the popup window
4. Press Enter or click "Generate"
5. The AI response will be automatically inserted into the active text field

## Project Structure

```
whizr/
├── Package.swift              # Swift Package Manager configuration
├── Whizr.xcodeproj/          # Xcode project
├── Whizr/                    # Source code
│   ├── WhizrApp.swift        # Main app entry point
│   ├── ContentView.swift     # Main UI
│   ├── HotkeyManager.swift   # Hotkey detection
│   ├── LLMClient.swift       # AI provider integrations
│   ├── TextInjector.swift    # Text insertion
│   ├── PermissionManager.swift # macOS permissions
│   ├── PreferencesManager.swift # User settings
│   ├── ContextDetector.swift  # Context analysis
│   ├── WhizrPopupView.swift  # Popup UI
│   ├── PreferencesView.swift # Settings UI
│   ├── Assets.xcassets/      # App icons and images
│   └── Whizr.entitlements   # App permissions
├── README.md                 # This file
└── install.sh               # Installation script
```

## Building from Source

### Development

```bash
# Clone the repository
git clone https://github.com/yourusername/whizr.git
cd whizr

# Open in Xcode
open Whizr.xcodeproj

# Or build from command line
swift build
```

### Creating a Release Build

```bash
# Build for release
swift build -c release

# Archive in Xcode
# Product → Archive → Distribute App
```

## Supported Applications

Whizr works with all macOS applications that support text input, including:

- Mail.app
- Messages
- Safari/Chrome/Firefox
- VS Code/Xcode
- Pages/Word
- Slack/Discord
- Terminal
- And many more...

## Troubleshooting

### Hotkey Not Working

1. Check that Input Monitoring permission is granted
2. Restart Whizr after granting permissions
3. Check for hotkey conflicts with other applications
4. Verify the hotkey is set correctly in preferences

### Text Insertion Fails

1. Ensure Accessibility permission is granted
2. Try the clipboard fallback method
3. Check if the target application supports text insertion
4. Restart Whizr if permissions were recently granted

### API Errors

1. Verify your API key is correctly set in preferences
2. Check your internet connection
3. Ensure you have API credits/quota remaining
4. Try switching to a different LLM provider

### Menu Bar Icon Missing

1. Check that the app is running (look for Whizr in Activity Monitor)
2. Restart the app
3. Check macOS menu bar settings

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on macOS
5. Submit a pull request

## License

Copyright © 2025 Whizr. All rights reserved.

## Support

For support, please open an issue on GitHub or contact support@whizr.com. 