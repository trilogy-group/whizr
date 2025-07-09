import SwiftUI
import ApplicationServices

class ContextDetector: ObservableObject {
    @Published var currentApplication: String = ""
    @Published var selectedText: String = ""
    @Published var contextInfo: ContextInfo = ContextInfo()
    
    private var isMonitoring = false
    
    init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Monitor for application switches
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        updateCurrentContext()
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    @objc private func applicationDidActivate(_ notification: Notification) {
        // Only update app name on app switch, don't fetch selected text automatically
        DispatchQueue.main.async {
            self.currentApplication = self.getCurrentApplication()
            // Don't auto-fetch selected text on every app switch - only when needed
            self.contextInfo = self.analyzeContext()
        }
    }
    
    func updateCurrentContext() {
        DispatchQueue.main.async {
            self.currentApplication = self.getCurrentApplication()
            // Only fetch selected text when explicitly requested (like during popup)
            self.selectedText = self.getSelectedText()
            self.contextInfo = self.analyzeContext()
        }
    }
    
    private func getCurrentApplication() -> String {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return "Unknown"
        }
        return frontApp.localizedName ?? "Unknown"
    }
    
    private func getSelectedText() -> String {
        // Only fetch selected text when explicitly needed (not on every app switch)
        // This is called synchronously, so we need to be careful
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        
        // Clear pasteboard temporarily
        pasteboard.clearContents()
        
        // Simulate Cmd+C to copy selected text
        let copyEvent = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true) // 'C' key
        copyEvent?.flags = .maskCommand
        copyEvent?.post(tap: .cghidEventTap)
        
        let copyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false)
        copyUpEvent?.flags = .maskCommand
        copyUpEvent?.post(tap: .cghidEventTap)
        
        // Use a shorter delay and don't block with usleep
        Thread.sleep(forTimeInterval: 0.05) // 50ms instead of 100ms
        
        // Get the copied text
        let selectedText = pasteboard.string(forType: .string) ?? ""
        
        // Restore original pasteboard content
        pasteboard.clearContents()
        if let originalContent = originalContent {
            pasteboard.setString(originalContent, forType: .string)
        }
        
        return selectedText
    }
    
    private func analyzeContext() -> ContextInfo {
        let info = ContextInfo()
        info.applicationName = currentApplication
        info.selectedText = selectedText
        info.textLength = selectedText.count
        info.hasSelection = !selectedText.isEmpty
        
        // Analyze application type
        info.applicationType = detectApplicationType(currentApplication)
        
        // Analyze text type
        if !selectedText.isEmpty {
            info.textType = detectTextType(selectedText)
            info.language = detectLanguage(selectedText)
            info.suggestions = generateSuggestions(for: selectedText, in: info.applicationType)
        }
        
        return info
    }
    
    private func detectApplicationType(_ appName: String) -> ApplicationType {
        let appNameLower = appName.lowercased()
        
        if appNameLower.contains("mail") || appNameLower.contains("outlook") {
            return .email
        } else if appNameLower.contains("safari") || appNameLower.contains("chrome") || appNameLower.contains("firefox") {
            return .browser
        } else if appNameLower.contains("word") || appNameLower.contains("pages") || appNameLower.contains("notes") {
            return .textEditor
        } else if appNameLower.contains("xcode") || appNameLower.contains("code") {
            return .codeEditor
        } else if appNameLower.contains("slack") || appNameLower.contains("discord") || appNameLower.contains("messages") {
            return .chat
        } else {
            return .other
        }
    }
    
    private func detectTextType(_ text: String) -> TextType {
        if text.contains("def ") || text.contains("function ") || text.contains("class ") {
            return .code
        } else if text.contains("@") && text.contains(".") {
            return .email
        } else if text.contains("http") || text.contains("www.") {
            return .url
        } else if text.split(separator: " ").count < 10 {
            return .snippet
        } else {
            return .paragraph
        }
    }
    
    private func detectLanguage(_ text: String) -> String {
        // Simple language detection - in a real app you might use NLLanguageRecognizer
        if text.range(of: "[a-zA-Z]", options: .regularExpression) != nil {
            return "English"
        }
        return "Unknown"
    }
    
    private func generateSuggestions(for text: String, in appType: ApplicationType) -> [String] {
        var suggestions: [String] = []
        
        if text.isEmpty {
            suggestions.append("Help me write...")
            suggestions.append("Summarize this...")
            suggestions.append("Explain this...")
        } else {
            switch appType {
            case .email:
                suggestions.append("Make this more professional")
                suggestions.append("Shorten this message")
                suggestions.append("Add a polite greeting")
            case .textEditor:
                suggestions.append("Improve the writing")
                suggestions.append("Fix grammar and spelling")
                suggestions.append("Make it more concise")
            case .codeEditor:
                suggestions.append("Explain this code")
                suggestions.append("Add comments")
                suggestions.append("Optimize this code")
            case .chat:
                suggestions.append("Make this friendlier")
                suggestions.append("Add some humor")
                suggestions.append("Clarify the message")
            default:
                suggestions.append("Improve this text")
                suggestions.append("Explain this")
                suggestions.append("Summarize this")
            }
        }
        
        return suggestions
    }
}

// MARK: - Supporting Types

class ContextInfo: ObservableObject {
    @Published var applicationName: String = ""
    @Published var applicationType: ApplicationType = .other
    @Published var selectedText: String = ""
    @Published var textLength: Int = 0
    @Published var hasSelection: Bool = false
    @Published var textType: TextType = .paragraph
    @Published var language: String = "Unknown"
    @Published var suggestions: [String] = []
}

enum ApplicationType {
    case email
    case browser
    case textEditor
    case codeEditor
    case chat
    case other
    
    var description: String {
        switch self {
        case .email: return "Email"
        case .browser: return "Browser"
        case .textEditor: return "Text Editor"
        case .codeEditor: return "Code Editor"
        case .chat: return "Chat"
        case .other: return "Other"
        }
    }
}

enum TextType {
    case code
    case email
    case url
    case snippet
    case paragraph
    
    var description: String {
        switch self {
        case .code: return "Code"
        case .email: return "Email"
        case .url: return "URL"
        case .snippet: return "Snippet"
        case .paragraph: return "Paragraph"
        }
    }
} 