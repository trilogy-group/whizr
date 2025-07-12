import SwiftUI
import ApplicationServices
import Carbon
import os.log

class TextInjector: ObservableObject {
    @Published var isReady = false
    
    private let logger = Logger(subsystem: "com.whizr.Whizr", category: "TextInjector")
    
    init() {
        logger.info("🚀 TextInjector initialized")
        checkReady()
    }
    
    func checkReady() {
        // Check if we have the necessary permissions
        let trusted = AXIsProcessTrusted()
        logger.info("🔒 Accessibility permissions: \(trusted ? "GRANTED" : "DENIED", privacy: .public)")
        DispatchQueue.main.async {
            self.isReady = trusted
        }
    }
    
    func injectText(_ text: String, targetApp: NSRunningApplication? = nil, contextType: ContextType = .generalText) async {
        // Re-check permissions just in case
        checkReady()
        
        guard isReady else {
            logger.error("❌ TextInjector not ready - missing accessibility permissions")
            logger.error("❌ Please enable accessibility permissions in System Preferences > Privacy & Security > Accessibility")
            return
        }
        
        logger.info("💉 Starting text injection...")
        logger.info("📝 Text to inject (first 50 chars): '\(String(text.prefix(50)), privacy: .public)...'")
        logger.info("📝 Total text length: \(text.count, privacy: .public) characters")
        logger.info("🎯 Target app: \(targetApp?.localizedName ?? "Unknown", privacy: .public)")
        logger.info("🎯 Context type: \(contextType.description, privacy: .public)")
        logger.info("🎯 Current frontmost app: \(self.getActiveApplication() ?? "Unknown", privacy: .public)")
        
        // Special handling for terminal contexts
        if contextType == .terminalCommand {
            logger.info("🔧 Terminal context detected - using terminal-optimized injection...")
            
            if await injectViaTerminalMethod(text, targetApp: targetApp) {
                logger.info("✅ SUCCESS: Text injected via terminal method")
                return
            }
        }
        
        // Method 1: Try direct AX injection first (with verification)
        logger.info("🔧 Attempting Method 1: Direct accessibility injection...")
        
        if await injectViaAccessibilityWithVerification(text, targetApp: targetApp) {
            logger.info("✅ SUCCESS: Text injected via Accessibility API")
            return
        }
        
        // Method 2: Fallback to pasteboard method
        logger.info("🔧 Attempting Method 2: Pasteboard + Cmd+V...")
        await injectViaPasteboard(text, targetApp: targetApp)
    }
    
    /// Terminal-optimized injection method
    private func injectViaTerminalMethod(_ text: String, targetApp: NSRunningApplication?) async -> Bool {
        guard let targetApp = targetApp else {
            logger.warning("❌ No target app specified for terminal injection")
            return false
        }
        
        logger.info("🔧 Attempting terminal-optimized injection to \(targetApp.localizedName ?? "Unknown", privacy: .public)")
        
        // Get the AXApplication for the target app
        let axApp = AXUIElementCreateApplication(targetApp.processIdentifier)
        
        // Try to find terminal-specific elements
        if let terminalElement = findTerminalElement(in: axApp, appName: targetApp.localizedName ?? "") {
            logger.info("✅ Found terminal element, attempting direct injection")
            
            let textCFString = text as CFString
            let setResult = AXUIElementSetAttributeValue(terminalElement, kAXValueAttribute as CFString, textCFString)
            
            if setResult == .success {
                logger.info("✅ Terminal injection successful via accessibility")
                return true
            } else {
                logger.info("⚠️ Terminal accessibility injection failed, trying typing simulation")
            }
        }
        
        // Fallback: Use character-by-character typing for terminals (some terminals prefer this)
        logger.info("🔧 Using character-by-character typing for terminal")
        
        // Ensure target app is active
        targetApp.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Type each character with small delays (more reliable for terminals)
        for character in text {
            if let keyCode = characterToKeyCode(character) {
                await MainActor.run {
                    self.simulateKeyPress(key: keyCode, modifiers: [])
                }
                // Small delay between characters for terminal responsiveness
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            }
        }
        
        logger.info("✅ Terminal typing simulation completed")
        return true
    }
    
    /// Find terminal-specific UI elements
    private func findTerminalElement(in appElement: AXUIElement, appName: String) -> AXUIElement? {
        logger.info("🔍 Looking for terminal element in \(appName, privacy: .public)")
        
        // Look for terminal-specific roles and elements
        let terminalRoles = [
            "AXTextArea",           // Common in many terminals
            "AXTextField",          // Command input areas
            "AXScrollArea",         // Terminal content areas
            "AXWebArea",            // For Electron-based terminals
            "AXGroup"               // Generic containers that might contain terminal
        ]
        
        // Get all windows
        if let windows = getChildElements(appElement, role: "AXWindow") {
            for window in windows {
                // Look through terminal roles
                for role in terminalRoles {
                    if let elements = getChildElements(window, role: role) {
                        for element in elements {
                            // Check if this element might be a terminal
                            if isLikelyTerminalElement(element) {
                                logger.info("✅ Found potential terminal element with role: \(role, privacy: .public)")
                                return element
                            }
                        }
                    }
                }
                
                // Also try to find the focused element within the window
                var focusedElement: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(window, kAXFocusedUIElementAttribute as CFString, &focusedElement)
                if result == .success, let focused = focusedElement {
                    let focusedAXElement = focused as! AXUIElement
                    if isLikelyTerminalElement(focusedAXElement) {
                        logger.info("✅ Found focused terminal element")
                        return focusedAXElement
                    }
                }
            }
        }
        
        logger.info("⚠️ No terminal-specific element found")
        return nil
    }
    
    /// Check if an element is likely to be a terminal
    private func isLikelyTerminalElement(_ element: AXUIElement) -> Bool {
        // Get element's current text content
        if let currentText = getElementText(element) {
            // Check for terminal-like patterns in the content
            let textLower = currentText.lowercased()
            
            // Terminal indicators
            let terminalPatterns = [
                "$", "~", "#", "%",  // Prompt indicators
                "bash", "zsh", "sh", // Shell names
                "command not found", "permission denied", // Terminal messages
                "/usr/", "/home/", "~/", // Path patterns
            ]
            
            for pattern in terminalPatterns {
                if textLower.contains(pattern) {
                    return true
                }
            }
            
            // Check if it looks like command output (lots of lines)
            let lineCount = currentText.components(separatedBy: .newlines).count
            if lineCount > 5 && currentText.count > 100 {
                return true
            }
        }
        
        // Check element properties
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            // Some elements are more likely to be terminals
            if role == "AXTextArea" || role == "AXScrollArea" {
                return true
            }
        }
        
        return false
    }
    
    /// Helper to get child elements with specific role
    private func getChildElements(_ element: AXUIElement, role: String? = nil) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        
        guard result == .success, let childrenRef = childrenRef else {
            return nil
        }
        
        let cfArray = childrenRef as! CFArray
        let count = CFArrayGetCount(cfArray)
        var children: [AXUIElement] = []
        
        for i in 0..<count {
            let element = CFArrayGetValueAtIndex(cfArray, i)
            let axElement = Unmanaged<AXUIElement>.fromOpaque(element!).takeUnretainedValue()
            children.append(axElement)
        }
        
        if let role = role {
            return children.filter { child in
                var roleRef: CFTypeRef?
                let roleResult = AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
                guard roleResult == .success, let roleRef = roleRef else { return false }
                return (roleRef as! CFString as String) == role
            }
        }
        
        return children
    }
    
    private func injectViaAccessibilityWithVerification(_ text: String, targetApp: NSRunningApplication?) async -> Bool {
        guard let targetApp = targetApp else {
            logger.warning("❌ No target app specified for Accessibility injection")
            return false
        }
        
        logger.info("🔧 Attempting verified accessibility injection to \(targetApp.localizedName ?? "Unknown", privacy: .public)")
        
        // Get the AXApplication for the target app
        let axApp = AXUIElementCreateApplication(targetApp.processIdentifier)
        logger.info("🔧 Created AX application element for PID: \(targetApp.processIdentifier, privacy: .public)")
        
        // Get the focused element
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result != .success {
            logger.info("ℹ️ Direct accessibility injection not available for \(targetApp.localizedName ?? "Unknown", privacy: .public) (AXError: \(result.rawValue, privacy: .public))")
            return false
        }
        
        guard let focusedAXElement = focusedElement else {
            logger.info("ℹ️ No accessible text field found in \(targetApp.localizedName ?? "Unknown", privacy: .public)")
            return false
        }
        
        logger.info("✅ Found focused accessibility element in \(targetApp.localizedName ?? "Unknown", privacy: .public)")
        
        // GET CURRENT TEXT BEFORE INJECTION (for verification)
        let beforeText = getElementText(focusedAXElement as! AXUIElement) ?? ""
        logger.info("🔍 Text before injection: \(beforeText.count, privacy: .public) chars")
        
        // 🎯 CRITICAL FIX: Insert at cursor position instead of replacing all content
        let textCFString = text as CFString
        
        // Try insertion method first (for text editors like TextEdit)
        let insertResult = AXUIElementSetAttributeValue(focusedAXElement as! AXUIElement, kAXSelectedTextAttribute as CFString, textCFString)
        
        var setResult: AXError = insertResult
        var method = "cursor insertion"
        
        // If insertion fails, fallback to replacement (for other apps)
        if insertResult != .success {
            logger.info("🔄 Cursor insertion failed, trying content replacement...")
            setResult = AXUIElementSetAttributeValue(focusedAXElement as! AXUIElement, kAXValueAttribute as CFString, textCFString)
            method = "content replacement"
        }
        
        if setResult != .success {
            logger.info("ℹ️ Accessibility injection failed for \(targetApp.localizedName ?? "Unknown", privacy: .public) (AXError: \(setResult.rawValue, privacy: .public))")
            return false
        }
        
        logger.info("✅ Used \(method, privacy: .public) method")
        
        // VERIFY INJECTION ACTUALLY WORKED
        logger.info("🔍 Verifying text injection actually worked...")
        
        // Wait a moment for the change to take effect
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let afterText = getElementText(focusedAXElement as! AXUIElement) ?? ""
        logger.info("🔍 Text after injection: \(afterText.count, privacy: .public) chars")
        
        // For insertion method, verify the text was added (not replaced)
        if insertResult == .success {
            // Check if our text was inserted (text should be longer and contain our content)
            if afterText.count >= beforeText.count && afterText.contains(text.prefix(50)) {
                logger.info("✅ VERIFICATION PASSED: Text successfully inserted at cursor position")
                return true
            } else {
                logger.warning("⚠️ VERIFICATION FAILED: Text insertion didn't work as expected")
                return false
            }
        } else {
            // For replacement method, use the old verification logic
            if afterText == beforeText {
                logger.warning("⚠️ VERIFICATION FAILED: Text didn't change despite 'success' return")
                logger.warning("⚠️ \(targetApp.localizedName ?? "Unknown", privacy: .public) silently ignored accessibility injection")
                return false
            }
            
            if !afterText.contains(text.prefix(50)) {
                logger.warning("⚠️ VERIFICATION FAILED: Injected text not found in result")
                return false
            }
            
            logger.info("✅ VERIFICATION PASSED: Text replacement successful and verified")
            return true
        }
    }
    
    private func injectViaAccessibility(_ text: String, targetApp: NSRunningApplication?) async -> Bool {
        guard let targetApp = targetApp else {
            logger.warning("❌ No target app specified for Accessibility injection")
            return false
        }
        
        logger.info("🔧 Attempting direct accessibility injection to \(targetApp.localizedName ?? "Unknown", privacy: .public)")
        
        // Get the AXApplication for the target app
        let axApp = AXUIElementCreateApplication(targetApp.processIdentifier)
        logger.info("🔧 Created AX application element for PID: \(targetApp.processIdentifier, privacy: .public)")
        
        // Get the focused element
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result != .success {
            logger.info("ℹ️ Direct accessibility injection not available for \(targetApp.localizedName ?? "Unknown", privacy: .public) (AXError: \(result.rawValue, privacy: .public))")
            return false
        }
        
        guard let focusedAXElement = focusedElement else {
            logger.info("ℹ️ No accessible text field found in \(targetApp.localizedName ?? "Unknown", privacy: .public)")
            return false
        }
        
        logger.info("✅ Found focused accessibility element in \(targetApp.localizedName ?? "Unknown", privacy: .public)")
        
        // Try to set the value directly
        let textCFString = text as CFString
        let setResult = AXUIElementSetAttributeValue(focusedAXElement as! AXUIElement, kAXValueAttribute as CFString, textCFString)
        
        if setResult == .success {
            logger.info("✅ SUCCESS: Text injected directly via Accessibility API")
            return true
        } else {
            logger.info("ℹ️ Accessibility injection failed for \(targetApp.localizedName ?? "Unknown", privacy: .public) (AXError: \(setResult.rawValue, privacy: .public))")
            return false
        }
    }
    
    private func injectViaPasteboard(_ text: String, targetApp: NSRunningApplication? = nil) async {
        logger.info("📋 Starting pasteboard injection method...")
        
        // Save current pasteboard content
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)
        logger.info("📋 Previous pasteboard content: \(previousContent?.count ?? 0, privacy: .public) chars")
        
        // Set new content
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        
        if !success {
            logger.error("❌ FAILED: Could not set pasteboard content")
            return
        }
        
        logger.info("✅ Text set to pasteboard successfully, length: \(text.count, privacy: .public)")
        
        // Verify pasteboard content was set correctly
        let verifyContent = pasteboard.string(forType: .string)
        logger.info("🔍 Pasteboard verification: \(verifyContent?.count ?? 0, privacy: .public) chars match")
        
        // Ensure target app is focused with better error handling
        if let targetApp = targetApp {
            logger.info("🎯 Activating target app: \(targetApp.localizedName ?? "Unknown", privacy: .public)")
            targetApp.activate(options: [.activateIgnoringOtherApps])
            
            // Wait longer for app focus to ensure proper injection
            logger.info("⏳ Waiting 0.5s for app activation...")
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Verify the app is actually focused
            let currentApp = NSWorkspace.shared.frontmostApplication
            let currentAppName = currentApp?.localizedName ?? "Unknown"
            logger.info("🎯 Current frontmost app after activation: \(currentAppName, privacy: .public)")
            
            if currentAppName != targetApp.localizedName {
                logger.warning("⚠️ WARNING: Target app activation may have failed!")
                logger.warning("⚠️ Expected: \(targetApp.localizedName ?? "Unknown", privacy: .public), Got: \(currentAppName, privacy: .public)")
            } else {
                logger.info("✅ Target app successfully activated")
            }
        } else {
            logger.warning("⚠️ No target app specified, using current app")
        }
        
        logger.info("⌨️ Simulating Cmd+V keystroke...")
        
        // Primary method: Standard CGEvent
        await MainActor.run {
            self.simulateKeyPress(key: CGKeyCode(kVK_ANSI_V), modifiers: .maskCommand)
        }
        
        // Wait for the paste to complete
        logger.info("⏳ Waiting 0.2s for paste completion...")
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        logger.info("✅ Text injection attempt completed")
        
        // Check if pasteboard content changed (some apps clear it after paste)
        let afterPasteContent = pasteboard.string(forType: .string)
        if afterPasteContent != text {
            logger.info("🔄 Pasteboard content changed after paste (normal behavior)")
        }
        
        // Restore previous content after a short delay
        logger.info("⏳ Waiting 0.5s before restoring pasteboard...")
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        await MainActor.run {
            pasteboard.clearContents()
            if let previousContent = previousContent {
                pasteboard.setString(previousContent, forType: .string)
                self.logger.info("🔄 Previous pasteboard content restored")
            } else {
                self.logger.info("🔄 Pasteboard cleared (no previous content)")
            }
        }
        
        logger.info("✅ Pasteboard injection method completed")
    }
    
    private func injectViaKeyEvents(_ text: String) {
        // Method 2: Direct key event injection (less reliable but useful for some cases)
        for character in text {
            if let keyCode = characterToKeyCode(character) {
                simulateKeyPress(key: keyCode, modifiers: [])
            }
        }
    }
    
    private func simulateKeyPress(key: CGKeyCode, modifiers: CGEventFlags) {
        logger.info("⌨️ Creating key events for key: \(key, privacy: .public) with modifiers: \(modifiers.rawValue, privacy: .public)")
        
        // Create events with proper event source
        let eventSource = CGEventSource(stateID: .hidSystemState)
        
        guard let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: false) else {
            logger.error("❌ FAILED: Could not create CGEvent for key: \(key, privacy: .public)")
            return
        }
        
        keyDownEvent.flags = modifiers
        keyUpEvent.flags = modifiers
        
        logger.info("⌨️ Posting key DOWN event...")
        keyDownEvent.post(tap: .cghidEventTap)
        
        logger.info("⌨️ Posting key UP event...")
        keyUpEvent.post(tap: .cghidEventTap)
        
        // Small delay between key events
        usleep(10000) // 10ms
        
        logger.info("✅ CGEvent posted successfully for key: \(key, privacy: .public)")
    }
    
    /// Get element text value using accessibility API
    private func getElementText(_ element: AXUIElement) -> String? {
        var textRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef)
        
        guard result == .success, let textRef = textRef else {
            return nil
        }
        
        return textRef as! CFString as String
    }
    
    private func simulateKeyPressAlternative(key: CGKeyCode, modifiers: CGEventFlags) {
        // Alternative method using different event source
        let eventSource = CGEventSource(stateID: .hidSystemState)
        
        guard let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: false) else {
            print("❌ Failed to create alternative CGEvent for key: \(key)")
            return
        }
        
        keyDownEvent.flags = modifiers
        keyUpEvent.flags = modifiers
        
        // Try posting to different taps
        keyDownEvent.post(tap: .cgSessionEventTap)
        keyUpEvent.post(tap: .cgSessionEventTap)
        
        print("⌨️  Posted alternative CGEvent for key: \(key)")
    }
    
    private func characterToKeyCode(_ character: Character) -> CGKeyCode? {
        // Enhanced character to key code mapping
        switch character.lowercased() {
        // Letters
        case "a": return CGKeyCode(kVK_ANSI_A)
        case "b": return CGKeyCode(kVK_ANSI_B)
        case "c": return CGKeyCode(kVK_ANSI_C)
        case "d": return CGKeyCode(kVK_ANSI_D)
        case "e": return CGKeyCode(kVK_ANSI_E)
        case "f": return CGKeyCode(kVK_ANSI_F)
        case "g": return CGKeyCode(kVK_ANSI_G)
        case "h": return CGKeyCode(kVK_ANSI_H)
        case "i": return CGKeyCode(kVK_ANSI_I)
        case "j": return CGKeyCode(kVK_ANSI_J)
        case "k": return CGKeyCode(kVK_ANSI_K)
        case "l": return CGKeyCode(kVK_ANSI_L)
        case "m": return CGKeyCode(kVK_ANSI_M)
        case "n": return CGKeyCode(kVK_ANSI_N)
        case "o": return CGKeyCode(kVK_ANSI_O)
        case "p": return CGKeyCode(kVK_ANSI_P)
        case "q": return CGKeyCode(kVK_ANSI_Q)
        case "r": return CGKeyCode(kVK_ANSI_R)
        case "s": return CGKeyCode(kVK_ANSI_S)
        case "t": return CGKeyCode(kVK_ANSI_T)
        case "u": return CGKeyCode(kVK_ANSI_U)
        case "v": return CGKeyCode(kVK_ANSI_V)
        case "w": return CGKeyCode(kVK_ANSI_W)
        case "x": return CGKeyCode(kVK_ANSI_X)
        case "y": return CGKeyCode(kVK_ANSI_Y)
        case "z": return CGKeyCode(kVK_ANSI_Z)
        
        // Numbers
        case "0": return CGKeyCode(kVK_ANSI_0)
        case "1": return CGKeyCode(kVK_ANSI_1)
        case "2": return CGKeyCode(kVK_ANSI_2)
        case "3": return CGKeyCode(kVK_ANSI_3)
        case "4": return CGKeyCode(kVK_ANSI_4)
        case "5": return CGKeyCode(kVK_ANSI_5)
        case "6": return CGKeyCode(kVK_ANSI_6)
        case "7": return CGKeyCode(kVK_ANSI_7)
        case "8": return CGKeyCode(kVK_ANSI_8)
        case "9": return CGKeyCode(kVK_ANSI_9)
        
        // Common punctuation and symbols
        case "-": return CGKeyCode(kVK_ANSI_Minus)          // CRITICAL: The missing dash!
        case "=": return CGKeyCode(kVK_ANSI_Equal)
        case "[": return CGKeyCode(kVK_ANSI_LeftBracket)
        case "]": return CGKeyCode(kVK_ANSI_RightBracket)
        case "\\": return CGKeyCode(kVK_ANSI_Backslash)
        case ";": return CGKeyCode(kVK_ANSI_Semicolon)
        case "'": return CGKeyCode(kVK_ANSI_Quote)
        case "`": return CGKeyCode(kVK_ANSI_Grave)
        case ",": return CGKeyCode(kVK_ANSI_Comma)
        case ".": return CGKeyCode(kVK_ANSI_Period)
        case "/": return CGKeyCode(kVK_ANSI_Slash)
        
        // Whitespace and control characters
        case " ": return CGKeyCode(kVK_Space)
        case "\n": return CGKeyCode(kVK_Return)
        case "\t": return CGKeyCode(kVK_Tab)
        
        default: return nil
        }
    }
    
    func getActiveApplication() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return frontApp.localizedName
    }
}

// MARK: - Virtual Key Codes

// Letters
private let kVK_ANSI_A: Int = 0x00
private let kVK_ANSI_B: Int = 0x0B
private let kVK_ANSI_C: Int = 0x08
private let kVK_ANSI_D: Int = 0x02
private let kVK_ANSI_E: Int = 0x0E
private let kVK_ANSI_F: Int = 0x03
private let kVK_ANSI_G: Int = 0x05
private let kVK_ANSI_H: Int = 0x04
private let kVK_ANSI_I: Int = 0x22
private let kVK_ANSI_J: Int = 0x26
private let kVK_ANSI_K: Int = 0x28
private let kVK_ANSI_L: Int = 0x25
private let kVK_ANSI_M: Int = 0x2E
private let kVK_ANSI_N: Int = 0x2D
private let kVK_ANSI_O: Int = 0x1F
private let kVK_ANSI_P: Int = 0x23
private let kVK_ANSI_Q: Int = 0x0C
private let kVK_ANSI_R: Int = 0x0F
private let kVK_ANSI_S: Int = 0x01
private let kVK_ANSI_T: Int = 0x11
private let kVK_ANSI_U: Int = 0x20
private let kVK_ANSI_V: Int = 0x09
private let kVK_ANSI_W: Int = 0x0D
private let kVK_ANSI_X: Int = 0x07
private let kVK_ANSI_Y: Int = 0x10
private let kVK_ANSI_Z: Int = 0x06

// Numbers
private let kVK_ANSI_0: Int = 0x1D
private let kVK_ANSI_1: Int = 0x12
private let kVK_ANSI_2: Int = 0x13
private let kVK_ANSI_3: Int = 0x14
private let kVK_ANSI_4: Int = 0x15
private let kVK_ANSI_5: Int = 0x17
private let kVK_ANSI_6: Int = 0x16
private let kVK_ANSI_7: Int = 0x1A
private let kVK_ANSI_8: Int = 0x1C
private let kVK_ANSI_9: Int = 0x19

// Punctuation and symbols
private let kVK_ANSI_Minus: Int = 0x1B         // - (hyphen/dash)
private let kVK_ANSI_Equal: Int = 0x18         // =
private let kVK_ANSI_LeftBracket: Int = 0x21   // [
private let kVK_ANSI_RightBracket: Int = 0x1E  // ]
private let kVK_ANSI_Backslash: Int = 0x2A     // \
private let kVK_ANSI_Semicolon: Int = 0x29     // ;
private let kVK_ANSI_Quote: Int = 0x27         // '
private let kVK_ANSI_Grave: Int = 0x32         // `
private let kVK_ANSI_Comma: Int = 0x2B         // ,
private let kVK_ANSI_Period: Int = 0x2F        // .
private let kVK_ANSI_Slash: Int = 0x2C         // /

// Control keys
private let kVK_Return: Int = 0x24
private let kVK_Tab: Int = 0x30
private let kVK_Space: Int = 0x31 