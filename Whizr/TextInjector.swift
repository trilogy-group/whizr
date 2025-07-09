import SwiftUI
import ApplicationServices
import Carbon

class TextInjector: ObservableObject {
    @Published var isReady = false
    
    init() {
        checkReady()
    }
    
    func checkReady() {
        // Check if we have the necessary permissions
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.isReady = trusted
        }
    }
    
    func injectText(_ text: String, targetApp: NSRunningApplication? = nil) async {
        // Re-check permissions just in case
        checkReady()
        
        guard isReady else {
            print("❌ TextInjector not ready - missing accessibility permissions")
            print("❌ Please enable accessibility permissions in System Preferences > Privacy & Security > Accessibility")
            return
        }
        
        print("📝 Injecting text: \(text.prefix(50))...")
        print("🎯 Target app: \(targetApp?.localizedName ?? "Unknown")")
        print("🎯 Current frontmost app: \(getActiveApplication() ?? "Unknown")")
        
        // Method 1: Try direct AX injection first
        if await injectViaAccessibility(text, targetApp: targetApp) {
            print("✅ Text injected via Accessibility API")
            return
        }
        
        // Method 2: Fallback to pasteboard method
        await injectViaPasteboard(text, targetApp: targetApp)
    }
    
    private func injectViaAccessibility(_ text: String, targetApp: NSRunningApplication?) async -> Bool {
        guard let targetApp = targetApp else {
            print("❌ No target app specified for Accessibility injection")
            return false
        }
        
        // Get the AXApplication for the target app
        let axApp = AXUIElementCreateApplication(targetApp.processIdentifier)
        
        // Get the focused element
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result != .success {
            print("❌ Could not get focused element from target app")
            return false
        }
        
        guard let focusedAXElement = focusedElement else {
            print("❌ No focused element found in target app")
            return false
        }
        
        // Try to set the value directly
        let textCFString = text as CFString
        let setResult = AXUIElementSetAttributeValue(focusedAXElement as! AXUIElement, kAXValueAttribute as CFString, textCFString)
        
        if setResult == .success {
            print("✅ Text injected directly via AXUIElement")
            return true
        } else {
            print("❌ Failed to inject text via AXUIElement: \(setResult)")
            return false
        }
    }
    
    private func injectViaPasteboard(_ text: String, targetApp: NSRunningApplication? = nil) async {
        // Save current pasteboard content
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)
        
        // Set new content
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        
        if !success {
            print("❌ Failed to set pasteboard content")
            return
        }
        
        print("📋 Text set to pasteboard successfully, length: \(text.count)")
        
        // Ensure target app is focused with better error handling
        if let targetApp = targetApp {
            print("🎯 Activating target app: \(targetApp.localizedName ?? "Unknown")")
            targetApp.activate(options: [.activateIgnoringOtherApps])
            
            // Wait longer for app focus to ensure proper injection
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Verify the app is actually focused
            let currentApp = NSWorkspace.shared.frontmostApplication
            print("🎯 Current frontmost app after activation: \(currentApp?.localizedName ?? "Unknown")")
        }
        
        print("⌨️  Simulating Cmd+V...")
        
        // Method 1: Standard CGEvent (most reliable)
        await MainActor.run {
            self.simulateKeyPress(key: CGKeyCode(kVK_ANSI_V), modifiers: .maskCommand)
        }
        
        // Longer delay to ensure the event is processed
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Method 2: Alternative CGEvent method as backup
        await MainActor.run {
            self.simulateKeyPressAlternative(key: CGKeyCode(kVK_ANSI_V), modifiers: .maskCommand)
        }
        
        print("✅ Text injection attempts completed")
        
        // Restore previous content after a short delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        await MainActor.run {
            pasteboard.clearContents()
            if let previousContent = previousContent {
                pasteboard.setString(previousContent, forType: .string)
                print("🔄 Previous pasteboard content restored")
            }
        }
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
        // Create events with proper event source
        let eventSource = CGEventSource(stateID: .hidSystemState)
        
        guard let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: false) else {
            print("❌ Failed to create CGEvent for key: \(key)")
            return
        }
        
        keyDownEvent.flags = modifiers
        keyUpEvent.flags = modifiers
        
        // Post to multiple taps for better reliability
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
        
        // Small delay between key events
        usleep(10000) // 10ms
        
        print("⌨️  Posted CGEvent for key: \(key) with modifiers: \(modifiers.rawValue)")
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
        // Basic character to key code mapping
        switch character.lowercased() {
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
private let kVK_Return: Int = 0x24
private let kVK_Tab: Int = 0x30
private let kVK_Space: Int = 0x31 