#!/bin/bash

echo "🚀 Launching Whizr..."

# Build the app first
echo "📦 Building Whizr..."
xcodebuild -project Whizr.xcodeproj -scheme Whizr -configuration Debug build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    # Find the app path
    APP_PATH="/Users/ricardofernandes/Library/Developer/Xcode/DerivedData/Whizr-fnqwztihyozrphdxfzmtauqiqmos/Build/Products/Debug/Whizr.app"
    
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
    echo "💡 Only Accessibility permission is needed - the app will guide you through setup"
    
else
    echo "❌ Build failed!"
    exit 1
fi 