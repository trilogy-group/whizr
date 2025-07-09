import SwiftUI
import ApplicationServices

class PermissionManager: ObservableObject {
    @Published var hasAccessibilityPermission = false
    @Published var hasAllPermissions = false
    
    // Note: On macOS 15.5+, Input Monitoring may not be required for CGEvent.tapCreate
    // when used for simple keyboard event taps - Accessibility permission is sufficient
    
    private var permissionCheckTimer: Timer?
    
    init() {
        checkPermissions()
        startPermissionMonitoring()
    }
    
    deinit {
        permissionCheckTimer?.invalidate()
    }
    
    private func startPermissionMonitoring() {
        // Check permissions every 2 seconds to detect changes
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.checkPermissionsAndHandleChanges()
        }
    }
    
    private func checkPermissionsAndHandleChanges() {
        let previousAccessibility = hasAccessibilityPermission
        
        checkPermissions()
        
        // If Accessibility permission was just granted, restart hotkey manager
        if !previousAccessibility && hasAccessibilityPermission {
            print("✅ Accessibility permission granted - restarting hotkey manager...")
            NotificationCenter.default.post(name: .permissionsChanged, object: nil)
        }
    }
    
    func checkPermissions() {
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = AXIsProcessTrusted()
            // On modern macOS, Accessibility permission is sufficient for our use case
            self.hasAllPermissions = self.hasAccessibilityPermission
        }
    }
    
    func requestPermissions() {
        print("🔒 Requesting permissions...")
        
        // Request Accessibility permission (this is what we actually need)
        requestAccessibilityPermission()
        
        // Recheck permissions after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkPermissions()
        }
    }
    
    private func requestAccessibilityPermission() {
        // This will prompt the user to grant accessibility permissions
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() : true] as CFDictionary)
        
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = trusted
            self.hasAllPermissions = self.hasAccessibilityPermission
        }
    }
    
    func openSystemPreferences() {
        // Open Accessibility preferences directly since that's what we need
        let prefPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        
        if NSWorkspace.shared.open(prefPaneURL) {
            print("📱 Opened Accessibility preferences")
            
            // Show alert with instructions
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "To enable global hotkeys (⌘+Shift+Space) and text operations, please:\n\n1. Find 'Whizr' in the Accessibility list\n2. Check the box next to it\n\nThis allows Whizr to detect hotkeys and inject text system-wide."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } else {
            // Fallback to general Privacy & Security
            let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
            NSWorkspace.shared.open(privacyURL)
        }
    }
    
    func getPermissionStatus() -> PermissionStatus {
        checkPermissions()
        
        if hasAllPermissions {
            return .granted
        } else {
            return .denied
        }
    }
}

// MARK: - Supporting Types

enum PermissionStatus {
    case granted
    case denied
    
    var description: String {
        switch self {
        case .granted:
            return "All permissions granted"
        case .denied:
            return "Accessibility permission required"
        }
    }
    
    var isComplete: Bool {
        if case .granted = self {
            return true
        }
        return false
    }
} 