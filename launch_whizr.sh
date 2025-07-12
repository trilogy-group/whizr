#!/bin/bash

# Parse command line arguments
DEBUG_MODE=false
CONFIGURATION="Release"

if [[ "$1" == "--debug" ]]; then
    DEBUG_MODE=true
    CONFIGURATION="Debug"
    echo "🔧 Debug mode enabled"
else
    echo "🚀 Release mode (use --debug for debug build)"
fi

echo "🚀 Launching Whizr ($CONFIGURATION)..."

# Kill any existing Whizr processes
echo "🛑 Stopping any running Whizr instances..."
pkill -f "Whizr.app" 2>/dev/null || true
killall "Whizr" 2>/dev/null || true
sleep 1

# Build the app
echo "📦 Building Whizr ($CONFIGURATION)..."
xcodebuild -project Whizr.xcodeproj -scheme Whizr -configuration $CONFIGURATION build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    # Find the app path dynamically
    DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData"
    APP_PATH=$(find "$DERIVED_DATA_PATH" -name "Whizr.app" -path "*/$CONFIGURATION/*" | head -1)
    
    if [ -z "$APP_PATH" ]; then
        echo "⚠️  Could not find built app, trying fallback location..."
        # Fallback: try to find any Whizr.app in DerivedData
        APP_PATH=$(find "$DERIVED_DATA_PATH" -name "Whizr.app" | head -1)
    fi
    
    if [ -z "$APP_PATH" ]; then
        echo "❌ Could not locate Whizr.app after build!"
        exit 1
    fi
    
    echo "📍 App location: $APP_PATH"
    
    # Check if permissions are needed
    echo ""
    echo "🔐 PERMISSION REQUIRED:"
    echo "On macOS 15.5+, Whizr only needs Accessibility permission:"
    echo ""
    echo "1. Accessibility (Everything you need):"
    echo "   System Settings → Privacy & Security → Accessibility"
    echo "   Add: $APP_PATH"
    echo "   ⚡ Enables: Global hotkeys, text detection, and text injection"
    echo ""
    echo "💡 Input Monitoring is NOT required on modern macOS!"
    echo "   Apple consolidated these permissions under Accessibility"
    echo ""
    
    # Launch the app
    echo "🎯 Launching Whizr..."
    open "$APP_PATH"
    
    echo ""
    echo "✨ Whizr should now be running in your menu bar!"
    echo "   Press ⌘+Shift+Space to test the hotkey"
    echo ""
    if [ "$DEBUG_MODE" = true ]; then
        echo "🔧 Debug build - check Console.app for detailed logs"
    fi
    echo "💡 Only Accessibility permission is needed - the app will guide you through setup"
    
else
    echo "❌ Build failed!"
    exit 1
fi 