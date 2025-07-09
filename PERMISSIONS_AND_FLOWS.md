# Whizr Permissions and Flows

## Overview
Whizr requires Accessibility permission to function properly on macOS 15.5+. This document outlines the permissions needed for different app flows.

## Required Permissions

### 1. Accessibility (Essential) ✅
- **Required For**: 
  - Global hotkey detection (⌘+Shift+Space)
  - Getting selected text via CMD+C simulation
  - Text injection functionality
  - App focus detection and window management
- **System Path**: System Settings → Privacy & Security → Accessibility
- **Impact**: Without this, core functionality won't work
- **Restart Required**: No - hotkey listener restarts automatically
- **Auto-Restart**: ✅ Hotkey listener restarts when permission is granted

### 2. AppleEvents/Automation (Declared)
- **Required For**: System Events scripting and some text injection methods
- **System Path**: Listed in app entitlements
- **Impact**: Some text injection methods may not work
- **Restart Required**: No

## Important Note: Input Monitoring Not Required ⚠️

On **macOS 15.5+ (Sequoia)**, the `CGEvent.tapCreate` API used for global hotkey detection **does not require Input Monitoring permission** when used with Accessibility permission. Apple has simplified the permission model, and Accessibility permission is sufficient for keyboard event taps in our use case.

Previous versions of macOS might have required both permissions, but modern macOS consolidates this under Accessibility.

## App Flows and Permission Requirements

### Core Hotkey Flow
1. **User presses ⌘+Shift+Space**
   - Requires: Accessibility
   - Falls back to: None (hotkey simply won't work)

2. **App detects selected text**
   - Requires: Accessibility
   - Falls back to: User can manually enter text

3. **App shows popup window**
   - Requires: No special permissions
   - Always works

4. **User interacts with LLM**
   - Requires: Network access (granted by default)
   - Falls back to: Error message shown

5. **App injects text back**
   - Requires: Accessibility
   - Falls back to: Copy to clipboard

### Screenshot Flow
1. **User clicks screenshot button**
   - Requires: No special permissions
   - Uses system screenshot API

2. **App processes screenshot**
   - Requires: Network access for LLM
   - Falls back to: Error message

3. **App returns to popup**
   - Requires: No special permissions
   - Always works

### Context Detection Flow
1. **App monitors active application**
   - Requires: No special permissions
   - Uses NSWorkspace notifications

2. **App gets selected text**
   - Requires: Accessibility
   - Falls back to: Empty context

3. **App analyzes context**
   - Requires: No special permissions
   - Always works

## Permission Monitoring System

### How It Works
1. **Permission Monitoring**: App checks Accessibility permission every 2 seconds
2. **Automatic Restart**: When Accessibility is granted, hotkey listener restarts automatically
3. **No App Restart Required**: Unlike Input Monitoring, Accessibility changes don't require full app restart

### Manual Restart Options
- **Restart Hotkey Listener**: Available in menu when Accessibility permission is granted but hotkey isn't working

## Permission Status in UI

### Status Indicators
- **Green Circle**: Permission granted and working
- **Red Circle**: Permission missing or not working

### Status Types
- **Hotkey**: Shows if global hotkey listener is active
- **Accessibility**: Shows if accessibility permission is granted
- **LLM**: Shows if LLM client is configured

## Troubleshooting

### Hotkey Not Working
1. Check Accessibility permission
2. Use "Restart Hotkey Listener" button if available
3. If still not working, restart app completely

### Text Injection Not Working
1. Check Accessibility permission
2. Try manual text selection
3. Fall back to clipboard copy

## Development Notes

### Permission Checking
- Uses `AXIsProcessTrusted()` for Accessibility
- Uses `CGEvent.tapCreate()` test for hotkey capability
- Checks every 2 seconds for permission changes

### Event Tap Management
- Uses CGEvent tap for global hotkey detection
- Requires only Accessibility permission on macOS 15.5+
- Automatically restarts when permissions change

### Graceful Degradation
- App continues to work with limited functionality
- Clear error messages when permissions are missing
- Fallback options for all critical flows

## Testing

### Permission Testing
1. Reset permissions: `tccutil reset Accessibility com.whizr.Whizr`
2. Launch app and test permission flow
3. Grant Accessibility permission
4. Verify hotkey listener restarts automatically

### Hotkey Testing
1. Test hotkey before granting permissions (should fail)
2. Grant Accessibility permission
3. Verify hotkey listener restarts
4. Test hotkey after permission grant (should work)

### Text Injection Testing
1. Test with Accessibility permission denied
2. Grant Accessibility permission
3. Verify hotkey listener restarts
4. Test text injection (should work) 