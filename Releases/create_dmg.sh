#!/bin/bash

# Create DMG for Whizr with drag-and-drop installation

echo "Creating Whizr DMG installer..."

# Variables
APP_NAME="Whizr"
DMG_NAME="Whizr"
DMG_DIR="dmg-contents"
FINAL_DMG="Whizr.dmg"

# Clean up any existing files
rm -rf "$DMG_DIR"
rm -f "$FINAL_DMG"
rm -f "${DMG_NAME}-temp.dmg"

# Create DMG contents directory
mkdir -p "$DMG_DIR"

# Copy app to DMG contents
cp -R "${APP_NAME}.app" "$DMG_DIR/"

# Create Applications symlink
ln -s /Applications "$DMG_DIR/Applications"

# Create a temporary DMG
hdiutil create -srcfolder "$DMG_DIR" -volname "$DMG_NAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size 100m "${DMG_NAME}-temp.dmg"

# Mount the temporary DMG
device=$(hdiutil attach -readwrite -noverify -noautoopen "${DMG_NAME}-temp.dmg" | \
    egrep '^/dev/' | sed 1q | awk '{print $1}')

# Wait for the volume to mount
sleep 2

# Use AppleScript to set the window properties
echo '
   tell application "Finder"
     tell disk "'${DMG_NAME}'"
           open
           set current view of container window to icon view
           set toolbar visible of container window to false
           set statusbar visible of container window to false
           set the bounds of container window to {400, 100, 900, 440}
           set theViewOptions to the icon view options of container window
           set arrangement of theViewOptions to not arranged
           set icon size of theViewOptions to 72
           set position of item "'${APP_NAME}'.app" of container window to {125, 180}
           set position of item "Applications" of container window to {375, 180}
           close
           open
           update without registering applications
           delay 2
     end tell
   end tell
' | osascript

# Set window properties again to ensure they stick
echo '
   tell application "Finder"
     tell disk "'${DMG_NAME}'"
           set current view of container window to icon view
           set toolbar visible of container window to false
           set statusbar visible of container window to false
           close
     end tell
   end tell
' | osascript

# Unmount the DMG
hdiutil detach "${device}"

# Convert to compressed DMG
hdiutil convert "${DMG_NAME}-temp.dmg" -format UDZO -imagekey zlib-level=9 -o "${FINAL_DMG}"

# Clean up
rm -f "${DMG_NAME}-temp.dmg"
rm -rf "$DMG_DIR"

echo "✅ DMG created successfully: ${FINAL_DMG}"
echo ""
echo "The DMG includes:"
echo "  - Whizr.app on the left"
echo "  - Applications folder shortcut on the right"
echo "  - Users can drag Whizr to Applications to install" 