#!/usr/bin/env swift

import Foundation
import AppKit
import ApplicationServices

// MARK: - Accessibility Information Extractor

class AccessibilityInfoExtractor {
    
    static func checkPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    static func getCurrentApplicationInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        
        // Get frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            info["error"] = "Cannot get frontmost application"
            return info
        }
        
        // Basic app info
        info["bundleIdentifier"] = frontApp.bundleIdentifier ?? "Unknown"
        info["localizedName"] = frontApp.localizedName ?? "Unknown"
        info["processIdentifier"] = frontApp.processIdentifier
        info["launchDate"] = frontApp.launchDate?.description ?? "Unknown"
        
        // Get accessibility element for the app
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        // Try to get window information
        if let windowInfo = getWindowInfo(from: appElement) {
            info["windows"] = windowInfo
        }
        
        // Try to get focused element information
        if let focusedInfo = getFocusedElementInfo(from: appElement) {
            info["focusedElement"] = focusedInfo
        }
        
        return info
    }
    
    static func getWindowInfo(from appElement: AXUIElement) -> [String: Any]? {
        var windowInfo: [String: Any] = [:]
        
        // Get all windows
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        if result == .success, let windows = windowsRef as? [AXUIElement] {
            windowInfo["windowCount"] = windows.count
            
            // Get info from first window (usually the main one)
            if let firstWindow = windows.first {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(firstWindow, kAXTitleAttribute as CFString, &titleRef) == .success {
                    windowInfo["title"] = titleRef as? String ?? "No title"
                }
                
                var roleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(firstWindow, kAXRoleAttribute as CFString, &roleRef) == .success {
                    windowInfo["role"] = roleRef as? String ?? "Unknown role"
                }
                
                var positionRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(firstWindow, kAXPositionAttribute as CFString, &positionRef) == .success {
                    windowInfo["position"] = "\(positionRef as AnyObject)"
                }
                
                var sizeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(firstWindow, kAXSizeAttribute as CFString, &sizeRef) == .success {
                    windowInfo["size"] = "\(sizeRef as AnyObject)"
                }
            }
        }
        
        return windowInfo.isEmpty ? nil : windowInfo
    }
    
    static func getFocusedElementInfo(from appElement: AXUIElement) -> [String: Any]? {
        var focusedInfo: [String: Any] = [:]
        
        // Get focused UI element
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        
        if result == .success, let focusedElement = focusedRef {
            let element = focusedElement as! AXUIElement
            
            // Get role
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success {
                focusedInfo["role"] = roleRef as? String ?? "Unknown"
            }
            
            // Get role description
            var roleDescRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescRef) == .success {
                focusedInfo["roleDescription"] = roleDescRef as? String ?? "Unknown"
            }
            
            // Get title
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success {
                focusedInfo["title"] = titleRef as? String ?? "No title"
            }
            
            // Get value (for text fields)
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
                focusedInfo["value"] = valueRef as? String ?? "No value"
            }
            
            // Get selected text
            var selectedTextRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success {
                focusedInfo["selectedText"] = selectedTextRef as? String ?? "No selection"
            }
            
            // Get placeholder value
            var placeholderRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPlaceholderValueAttribute as CFString, &placeholderRef) == .success {
                focusedInfo["placeholder"] = placeholderRef as? String ?? "No placeholder"
            }
            
            // Get help text
            var helpRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &helpRef) == .success {
                focusedInfo["help"] = helpRef as? String ?? "No help"
            }
            
            // Get description
            var descRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success {
                focusedInfo["description"] = descRef as? String ?? "No description"
            }
            
            // For browsers, try to get URL
            if let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                if bundleId.contains("safari") || bundleId.contains("chrome") || bundleId.contains("firefox") {
                    if let url = getBrowserURL(from: element) {
                        focusedInfo["url"] = url
                    }
                }
            }
        }
        
        return focusedInfo.isEmpty ? nil : focusedInfo
    }
    
    static func getBrowserURL(from element: AXUIElement) -> String? {
        // Try to find the address bar
        var addressBar: AXUIElement?
        
        // Look for URL field in the UI hierarchy
        if let urlField = findElementByRole(element, role: "AXTextField", containing: "http") {
            addressBar = urlField
        }
        
        // If we found an address bar, get its value
        if let addressBar = addressBar {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(addressBar, kAXValueAttribute as CFString, &valueRef) == .success {
                return valueRef as? String
            }
        }
        
        return nil
    }
    
    static func findElementByRole(_ element: AXUIElement, role: String, containing text: String) -> AXUIElement? {
        // This is a simplified search - in practice you'd need to traverse the UI hierarchy
        // For now, just check if the current element matches
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success {
            if let elementRole = roleRef as? String, elementRole == role {
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
                    if let value = valueRef as? String, value.contains(text) {
                        return element
                    }
                }
            }
        }
        return nil
    }
    
    static func getSelectedTextViaCopy() -> String? {
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        
        // Clear clipboard
        pasteboard.clearContents()
        
        // Simulate Cmd+C
        let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true) // 'C' key
        keyDownEvent?.flags = .maskCommand
        keyDownEvent?.post(tap: .cghidEventTap)
        
        let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false)
        keyUpEvent?.flags = .maskCommand
        keyUpEvent?.post(tap: .cghidEventTap)
        
        // Wait for copy to complete
        Thread.sleep(forTimeInterval: 0.1)
        
        // Get copied text
        let copiedText = pasteboard.string(forType: .string)
        
        // Restore original clipboard content
        pasteboard.clearContents()
        if let originalContent = originalContent {
            pasteboard.setString(originalContent, forType: .string)
        }
        
        return copiedText
    }
}

// MARK: - Privacy and Security Analysis

class PrivacyAnalyzer {
    static func analyzeExtractedData(_ data: [String: Any]) {
        print("\n🔒 PRIVACY ANALYSIS")
        print(String(repeating: "=", count: 50))
        
        // Check what sensitive information we're collecting
        var sensitiveData: [String] = []
        var regularData: [String] = []
        
        for (key, value) in data {
            switch key {
            case "bundleIdentifier", "localizedName", "processIdentifier":
                regularData.append("\(key): \(value)")
            case "value", "selectedText", "url":
                if let stringValue = value as? String, !stringValue.isEmpty && stringValue != "No value" && stringValue != "No selection" {
                    sensitiveData.append("\(key): \(stringValue)")
                }
            case "title":
                if let stringValue = value as? String, !stringValue.isEmpty && stringValue != "No title" {
                    // Window titles can be sensitive (document names, etc.)
                    sensitiveData.append("\(key): \(stringValue)")
                }
            default:
                regularData.append("\(key): \(value)")
            }
        }
        
        print("✅ SAFE DATA (App identification):")
        for item in regularData {
            print("  • \(item)")
        }
        
        print("\n⚠️  SENSITIVE DATA (User content):")
        for item in sensitiveData {
            print("  • \(item)")
        }
        
        print("\n📋 RECOMMENDATIONS:")
        print("• Only collect app identification data by default")
        print("• Ask user permission before collecting content data")
        print("• Provide clear privacy controls")
        print("• Allow users to opt out of content collection")
        print("• Never log or store sensitive user data")
    }
}

// MARK: - Main Execution

func main() {
    print("🔍 ACCESSIBILITY INFORMATION EXTRACTOR")
    print(String(repeating: "=", count: 50))
    
    // Check permissions
    if !AccessibilityInfoExtractor.checkPermissions() {
        print("❌ Accessibility permissions required!")
        print("Please enable accessibility permissions in System Settings")
        return
    }
    
    print("✅ Accessibility permissions granted")
    print("\nWaiting 3 seconds for you to focus on a different app...")
    sleep(3)
    
    // Get current app info
    let info = AccessibilityInfoExtractor.getCurrentApplicationInfo()
    
    print("\n📱 APPLICATION INFORMATION")
    print(String(repeating: "=", count: 50))
    
    for (key, value) in info {
        if let dict = value as? [String: Any] {
            print("\n\(key.uppercased()):")
            for (subKey, subValue) in dict {
                print("  \(subKey): \(subValue)")
            }
        } else {
            print("\(key): \(value)")
        }
    }
    
    // Test selected text extraction
    print("\n📝 SELECTED TEXT EXTRACTION")
    print(String(repeating: "=", count: 30))
    
    if let selectedText = AccessibilityInfoExtractor.getSelectedTextViaCopy() {
        print("Selected text: '\(selectedText)'")
        if selectedText.isEmpty {
            print("(No text selected)")
        }
    } else {
        print("Could not extract selected text")
    }
    
    // Privacy analysis
    PrivacyAnalyzer.analyzeExtractedData(info)
}

// Execute
main() 