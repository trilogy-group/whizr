# Whizr Release - v1.0.0

## Installation Instructions

### Option 1: Using DMG (Recommended)
1. Download `Whizr.dmg`
2. Double-click to mount the DMG
3. Drag Whizr.app to your Applications folder
4. Eject the DMG

### Option 2: Using ZIP
1. Download `Whizr.zip`
2. Double-click to extract
3. Move Whizr.app to your Applications folder

## First Run Setup

1. **Launch Whizr** from your Applications folder or Spotlight
2. **Grant Permissions**: 
   - macOS will ask for Accessibility permissions
   - Go to System Settings → Privacy & Security → Accessibility
   - Enable Whizr
   - You may need to restart the app after granting permissions

3. **Configure LLM**:
   - Click the Whizr icon in the menu bar
   - Select your preferred LLM provider (OpenAI, Anthropic, or Local/Ollama)
   - Enter your API key or endpoint
   - Choose your model
   - Click "Save Configuration"

## How to Use

1. **Global Hotkey**: Press `⌘+Shift+Space` anywhere to trigger Whizr
2. **Type your request** in the popup
3. **Press Enter** to generate AI response
4. The response will be automatically inserted at your cursor position

## Features

- **Context-aware responses**: Whizr detects what app you're using and adapts
- **Screenshot support**: Click the camera icon to include a screenshot
- **Multi-line input**: The input field supports multiple lines (Shift+Enter for new line)
- **Smart text injection**: Works with most macOS applications

## Known Issues

- First launch may require restarting the app after granting permissions
- Some apps may require additional accessibility permissions

## System Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

## Troubleshooting

1. **Hotkey not working**: 
   - Check Accessibility permissions in System Settings
   - Restart Whizr after granting permissions

2. **LLM not responding**:
   - Verify your API key is correct
   - Check your internet connection
   - Try a different model

3. **Text not inserting**:
   - Make sure the target app has a text field focused
   - Some apps may have restrictions on programmatic text input

## Release Notes

### v1.0.0 (July 11, 2025)
- Initial release
- Context-aware AI assistance
- Screenshot support
- Multiple LLM provider support
- Improved UI with compact design
- Fixed screenshot reopening issue
- Enhanced prompt generation to prevent clarification requests 