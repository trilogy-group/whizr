import SwiftUI
import ApplicationServices
import os.log

class ContextDetector: ObservableObject {
    @Published var currentApplication: String = ""
    @Published var selectedText: String = ""
    @Published var contextInfo: ContextInfo = ContextInfo()
    
    // PROACTIVE CACHING: Always keep current context ready
    @Published var cachedContext: ContextInfo?
    private var cachedTextContent: String = ""
    private var lastTextUpdate: Date = Date()
    
    private var isMonitoring = false
    private let logger = Logger(subsystem: "com.whizr.Whizr", category: "ContextDetector")
    
    // Context optimization settings
    private let maxContextLength = 500 // Maximum characters to send as context
    private let contextPadding = 100   // Characters before/after cursor position
    
    init() {
        logger.info("🚀 ContextDetector initialized")
        startMonitoring()
    }
    
    deinit {
        logger.info("🛑 ContextDetector deinitialized")
        stopMonitoring()
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        logger.info("👀 Starting context monitoring")
        
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
        
        logger.info("🛑 Stopping context monitoring")
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    @objc private func applicationDidActivate(_ notification: Notification) {
        logger.info("📱 Application switch detected")
        DispatchQueue.main.async {
            let previousApp = self.currentApplication
            self.currentApplication = self.getCurrentApplication()
            self.logger.info("📱 App changed: '\(previousApp, privacy: .public)' → '\(self.currentApplication, privacy: .public)'")
            
            // SKIP proactive extraction when switching TO Whizr (avoid overwriting cache with empty input)
            if self.currentApplication == "Whizr" || self.currentApplication == "Terminal" {
                self.logger.info("🚫 SKIP: Not extracting text from system app (\(self.currentApplication, privacy: .public))")
                return
            }
            
            // PROACTIVE CACHING: Extract text with small delay to allow app to stabilize
            self.logger.info("🚀 PROACTIVE: Starting proactive text extraction...")
            
            // Wait 500ms for accessibility elements to stabilize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.logger.info("⏰ PROACTIVE: Starting delayed extraction after app stabilization...")
                self.extractAndCacheCurrentText()
            }
        }
    }
    
    func updateCurrentContext() {
        DispatchQueue.main.async {
            self.logger.info("🔄 Updating current context (full)")
            self.currentApplication = self.getCurrentApplication()
            // Extract text context using improved accessibility APIs
            let extractionResult = self.getSmartTextContext()
            self.selectedText = extractionResult.text
            self.logger.info("📝 Text context (\(self.selectedText.count, privacy: .public) chars): '\(self.selectedText.prefix(100), privacy: .public)...'")
            self.contextInfo = self.analyzeContext(withTextExtraction: true)
        }
    }
    
    /// PROACTIVE CACHING: Extract and cache text from current app
    func extractAndCacheCurrentText() {
        // Use reliable app detection
        let appName = getCurrentApplication()
        currentApplication = appName
        logger.info("🔄 PROACTIVE: Extracting text from: \(appName, privacy: .public)")
        
        // Add safety check
        guard !appName.isEmpty && appName != "Unknown" else {
            logger.warning("⚠️ PROACTIVE: Invalid app name, skipping extraction")
            return
        }
        
        logger.info("🔍 PROACTIVE: About to call getSmartTextContext()...")
        
        // Extract text context using improved accessibility APIs
        let extractionResult = getSmartTextContext()
        let extractedText = extractionResult.text
        let isTerminalDetected = extractionResult.isTerminalDetected
        let primaryText = extractionResult.primaryText
        let contextText = extractionResult.contextText
        let primarySource = extractionResult.primarySource
        let contextSource = extractionResult.contextSource
        
        cachedTextContent = extractedText
        lastTextUpdate = Date()
        
        logger.info("📝 PROACTIVE: Cached \(extractedText.count, privacy: .public) chars: '\(extractedText.prefix(50), privacy: .public)...'")
        logger.info("📝 PRIMARY: \(primaryText.count, privacy: .public) chars from \(primarySource, privacy: .public)")
        logger.info("📄 CONTEXT: \(contextText.count, privacy: .public) chars from \(contextSource, privacy: .public)")
        
        logger.info("🏗️ PROACTIVE: Creating context analysis...")
        
        // Create and cache full context info
        cachedContext = analyzeContextForText(
            appName: appName, 
            text: extractedText, 
            isTerminalDetected: isTerminalDetected,
            primaryText: primaryText,
            contextText: contextText,
            primarySource: primarySource,
            contextSource: contextSource
        )
        
        logger.info("💾 PROACTIVE: Updating published properties...")
        
        // Also update the published properties for UI
        selectedText = extractedText
        contextInfo = cachedContext ?? ContextInfo()
        
        logger.info("✅ PROACTIVE: Text extraction and caching complete!")
    }
    
    /// Get cached context for immediate hotkey usage
    func getCachedContext() -> ContextInfo? {
        logger.info("⚡ CACHE: Getting cached context for hotkey...")
        
        guard let cached = cachedContext else {
            logger.warning("⚠️ CACHE: No cached context available, extracting fresh...")
            extractAndCacheCurrentText()
            return cachedContext
        }
        
        // Check if cache is recent (within 30 seconds)
        let cacheAge = Date().timeIntervalSince(lastTextUpdate)
        if cacheAge > 30 {
            logger.info("🔄 CACHE: Context is \(Int(cacheAge), privacy: .public)s old, refreshing...")
            extractAndCacheCurrentText()
            return cachedContext
        }
        
        logger.info("✅ CACHE: Using cached context (\(cached.selectedText.count, privacy: .public) chars, \(Int(cacheAge), privacy: .public)s old)")
        return cached
    }
    
    /// Analyze context for specific app and text (without side effects)
    private func analyzeContextForText(
        appName: String, 
        text: String, 
        isTerminalDetected: Bool = false,
        primaryText: String = "",
        contextText: String = "",
        primarySource: String = "",
        contextSource: String = ""
    ) -> ContextInfo {
        let info = ContextInfo()
        info.applicationName = appName
        info.selectedText = text  // Legacy field
        info.textLength = text.count
        info.hasSelection = !text.isEmpty
        
        // 🎯 NEW: Populate separated text fields for better LLM understanding
        info.primaryText = primaryText
        info.contextText = contextText
        info.primaryTextSource = primarySource
        info.contextTextSource = contextSource
        
        // Analyze application type
        info.applicationType = detectApplicationType(appName)
        logger.info("🏷️ Application type detected: \(info.applicationType.description, privacy: .public)")
        
        // 🎯 KEY FIX: If UI properties detected terminal, override text-based detection
        if isTerminalDetected {
            info.contextType = .terminalCommand
            logger.info("🎯 Context type OVERRIDDEN by UI detection: Terminal Command")
        } else {
            info.contextType = detectContextType(appName, text)
            logger.info("🎯 Context type detected: \(info.contextType.description, privacy: .public)")
        }
        
        info.programmingLanguage = detectProgrammingLanguage(text, info.applicationType)
        if info.programmingLanguage != "Unknown" {
            logger.info("💻 Programming language detected: \(info.programmingLanguage, privacy: .public)")
        }
        
        // Analyze text type
        if !text.isEmpty {
            info.textType = detectTextType(text)
            info.language = detectLanguage(text)
            info.suggestions = generateSuggestions(for: text, in: info.applicationType)
        }
        
        logger.info("✅ Context analysis complete:")
        logger.info("   📱 App: \(info.applicationName, privacy: .public) (\(info.applicationType.description, privacy: .public))")
        logger.info("   🎯 Context: \(info.contextType.description, privacy: .public)")
        logger.info("   💻 Language: \(info.programmingLanguage, privacy: .public)")
        logger.info("   📝 Primary: \(info.primaryText.count, privacy: .public) chars from \(info.primaryTextSource, privacy: .public)")
        logger.info("   📄 Context: \(info.contextText.count, privacy: .public) chars from \(info.contextTextSource, privacy: .public)")
        logger.info("   📝 Total: \(info.textLength, privacy: .public) chars, Type: \(info.textType.description, privacy: .public)")
        
        return info
    }
    
    /// Extract text context from a specific app (not just frontmost)
    func getTextContextFromApp(_ app: NSRunningApplication) -> String {
        logger.info("🔍 Extracting text context from specific app: \(app.localizedName ?? "Unknown", privacy: .public)")
        
        // Get application's accessibility element
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Try to get text context using accessibility APIs
        if let textContext = getAccessibilityTextContext(from: appElement) {
            logger.info("✅ Extracted \(textContext.count, privacy: .public) chars from \(app.localizedName ?? "Unknown", privacy: .public)")
            return textContext
        }
        
        // Fallback to clipboard method if accessibility fails
        logger.info("⚠️ Accessibility text extraction failed for \(app.localizedName ?? "Unknown", privacy: .public), falling back to copy method")
        return getFallbackTextContextFromApp(app)
    }
    
    /// Fallback text extraction for specific app using targeted clipboard simulation
    private func getFallbackTextContextFromApp(_ app: NSRunningApplication) -> String {
        logger.info("📋 Using fallback clipboard method for \(app.localizedName ?? "Unknown", privacy: .public)...")
        
        // Store original clipboard content
        let originalClipboard = NSPasteboard.general.string(forType: .string)
        
        // Clear clipboard
        NSPasteboard.general.clearContents()
        
        // Activate the target app first
        app.activate()
        
        // Small delay to ensure app is active
        Thread.sleep(forTimeInterval: 0.2)
        
        // Simulate copy command
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdC = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // C key
        cmdC?.flags = .maskCommand
        cmdC?.post(tap: .cghidEventTap)
        
        let cmdCUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) // C key
        cmdCUp?.flags = .maskCommand
        cmdCUp?.post(tap: .cghidEventTap)
        
        // Small delay to allow copy to complete
        Thread.sleep(forTimeInterval: 0.1)
        
        // Get copied text
        let copiedText = NSPasteboard.general.string(forType: .string) ?? ""
        
        // Restore original clipboard
        NSPasteboard.general.clearContents()
        if let original = originalClipboard {
            NSPasteboard.general.setString(original, forType: .string)
        }
        
        logger.info("📝 Fallback extracted \(copiedText.count, privacy: .public) characters from \(app.localizedName ?? "Unknown", privacy: .public)")
        return copiedText
    }
    
    /// Create context info for a specific app with text extraction
    func createContextForApp(_ app: NSRunningApplication) -> ContextInfo {
        let appName = app.localizedName ?? "Unknown"
        logger.info("🎯 Creating context for app: \(appName, privacy: .public)")
        
        // Extract text context from the app
        let extractedText = getTextContextFromApp(app)
        logger.info("📝 Extracted \(extractedText.count, privacy: .public) characters from \(appName, privacy: .public)")
        
        return createContextForApp(app, withText: extractedText)
    }
    
    /// Create context info for an app with pre-extracted text (to avoid duplicate extraction)
    func createContextForApp(_ app: NSRunningApplication, withText extractedText: String) -> ContextInfo {
        let appName = app.localizedName ?? "Unknown"
        logger.info("🎯 Creating context for app: \(appName, privacy: .public) with \(extractedText.count, privacy: .public) chars of pre-extracted text")
        
        let context = ContextInfo()
        context.applicationName = appName
        context.selectedText = extractedText
        
        // Analyze the application type
        context.applicationType = detectApplicationType(appName)
        logger.info("🏷️ Application type detected: \(context.applicationType.description, privacy: .public)")
        
        // Analyze context type based on content and app
        context.contextType = detectContextType(appName, extractedText)
        logger.info("🎯 Context type detected: \(context.contextType.description, privacy: .public)")
        
        // Detect programming language if in code editor
        if context.applicationType == .codeEditor {
            context.programmingLanguage = detectProgrammingLanguage(extractedText, context.applicationType)
            logger.info("💻 Programming language detected: \(context.programmingLanguage, privacy: .public)")
        }
        
        // Analyze text structure
        context.textType = detectTextType(extractedText)
        
        logger.info("✅ Context analysis complete:")
        logger.info("   📱 App: \(context.applicationName, privacy: .public) (\(context.applicationType.description, privacy: .public))")
        logger.info("   🎯 Context: \(context.contextType.description, privacy: .public)")
        logger.info("   💻 Language: \(context.programmingLanguage, privacy: .public)")
        logger.info("   📝 Text: \(context.selectedText.count, privacy: .public) chars, Type: \(context.textType.description, privacy: .public)")
        
        return context
    }
    
    private func getCurrentApplication() -> String {
        // Use reliable window list method instead of NSWorkspace
        if let appName = getCurrentApplicationViaWindowList() {
            logger.info("🎯 Current application (via window list): '\(appName, privacy: .public)'")
            return appName
        }
        
        // Fallback to NSWorkspace method
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            logger.warning("⚠️ Could not get frontmost application via any method")
            return "Unknown"
        }
        let appName = frontApp.localizedName ?? "Unknown"
        logger.info("🎯 Current application (fallback): '\(appName, privacy: .public)'")
        return appName
    }
    
    /// Get the truly active application using window list (more reliable than NSWorkspace)
    private func getCurrentApplicationViaWindowList() -> String? {
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        
        guard let windows = windowList else {
            logger.warning("⚠️ Could not get window list")
            return nil
        }
        
        // Find the frontmost window (layer 0)
        for window in windows {
            if let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
               let ownerName = window[kCGWindowOwnerName as String] as? String {
                logger.info("🔍 Found frontmost window owner: '\(ownerName, privacy: .public)'")
                return ownerName
            }
        }
        
        logger.warning("⚠️ No frontmost window found in window list")
        return nil
    }
    
    /// Get the truly active NSRunningApplication using reliable window list method
    func getCurrentRunningApplication() -> NSRunningApplication? {
        // First try window list method to get the correct app
        if let appName = getCurrentApplicationViaWindowList() {
            // Find the NSRunningApplication for this app name
            let runningApps = NSWorkspace.shared.runningApplications
            for app in runningApps {
                if app.localizedName == appName {
                    logger.info("✅ Found running app via window list: \(appName, privacy: .public)")
                    return app
                }
            }
            logger.warning("⚠️ Could not find NSRunningApplication for: \(appName, privacy: .public)")
        }
        
        // Fallback to NSWorkspace method
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            logger.info("🔄 Using NSWorkspace fallback for app: \(frontApp.localizedName ?? "Unknown", privacy: .public)")
            return frontApp
        }
        
        logger.warning("⚠️ Could not get running application via any method")
        return nil
    }

    /// Extract smart text context using accessibility APIs with primary/context separation
    private func getSmartTextContext() -> (text: String, isTerminalDetected: Bool, primaryText: String, contextText: String, primarySource: String, contextSource: String) {
        logger.info("🔍 Extracting smart text context using accessibility APIs...")
        
        // Get the current frontmost application using reliable method
        guard let frontApp = getCurrentRunningApplication() else {
            logger.warning("⚠️ Could not get frontmost application")
            return ("", false, "", "", "", "")
        }
        
        // Get application's accessibility element
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Try enhanced context extraction first
        if let enhancedResult = getEnhancedTextContext(from: appElement, appName: frontApp.localizedName ?? "Unknown") {
            return enhancedResult
        }
        
        // Fallback to basic focused element extraction
        if let basicContext = getAccessibilityTextContext(from: appElement) {
            return (basicContext, false, basicContext, "", "Focused element", "None")
        }
        
        // Final fallback to clipboard method if accessibility fails
        logger.info("⚠️ Accessibility text extraction failed, falling back to copy method")
        let fallbackText = getFallbackTextContext()
        return (fallbackText, false, fallbackText, "", "Clipboard fallback", "None")
    }
    
    /// Get text context using accessibility APIs
    private func getAccessibilityTextContext(from appElement: AXUIElement) -> String? {
        // Get focused UI element
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        
        guard result == .success, let focusedRef = focusedRef else {
            logger.info("⚠️ Could not get focused element")
            return nil
        }
        
        let focusedElement = focusedRef as! AXUIElement
        
        // Get element role to understand what we're dealing with
        if let role = getElementRole(focusedElement) {
            logger.info("🎯 Focused element role: \(role, privacy: .public)")
        }
        
        // Get window information for debugging multi-window scenarios
        if let windowTitle = getElementWindowTitle(focusedElement) {
            logger.info("🪟 Element is in window: '\(windowTitle, privacy: .public)'")
        }
        
        // Try to get text value and selected text
        let fullText = getElementText(focusedElement) ?? ""
        let selectedText = getElementSelectedText(focusedElement) ?? ""
        
        logger.info("📝 Full text: \(fullText.count, privacy: .public) chars, Selected: \(selectedText.count, privacy: .public) chars")
        
        // Smart text context extraction
        let contextText = buildSmartTextContext(fullText: fullText, selectedText: selectedText)
        
        logger.info("✅ Extracted text context via accessibility APIs (\(contextText.count, privacy: .public) chars)")
        return contextText
    }
    
    /// Get the window title containing this element (for debugging)
    private func getElementWindowTitle(_ element: AXUIElement) -> String? {
        // Try to get the parent window
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef)
        
        guard result == .success, let windowRef = windowRef else {
            // If direct window access fails, try traversing up the hierarchy
            return getElementWindowTitleViaParent(element)
        }
        
        let windowElement = windowRef as! AXUIElement
        
        // Get window title
        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
        
        guard titleResult == .success, let titleRef = titleRef else {
            return nil
        }
        
        return titleRef as! CFString as String
    }
    
    /// Get window title by traversing up the parent hierarchy
    private func getElementWindowTitleViaParent(_ element: AXUIElement) -> String? {
        var currentElement = element
        
        // Traverse up to 10 levels to find a window
        for _ in 0..<10 {
            // Check if current element is a window
            if let role = getElementRole(currentElement), role == "AXWindow" {
                var titleRef: CFTypeRef?
                let titleResult = AXUIElementCopyAttributeValue(currentElement, kAXTitleAttribute as CFString, &titleRef)
                
                if titleResult == .success, let titleRef = titleRef {
                    return titleRef as! CFString as String
                }
            }
            
            // Get parent
            var parentRef: CFTypeRef?
            let parentResult = AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parentRef)
            
            guard parentResult == .success, let parentRef = parentRef else {
                break
            }
            
            currentElement = parentRef as! AXUIElement
        }
        
        return nil
    }
    
    /// Enhanced text context extraction - collects comprehensive context based on app type
    private func getEnhancedTextContext(from appElement: AXUIElement, appName: String) -> (text: String, isTerminalDetected: Bool, primaryText: String, contextText: String, primarySource: String, contextSource: String)? {
        logger.info("🔍 Attempting enhanced context extraction for \(appName, privacy: .public)")
        
        let appType = detectApplicationType(appName)
        
        switch appType {
        case .terminal:
            if let terminalText = getTerminalContext(from: appElement, appName: appName) {
                return (
                    text: terminalText, 
                    isTerminalDetected: true,
                    primaryText: terminalText,
                    contextText: "",
                    primarySource: "Terminal",
                    contextSource: "None"
                )
            }
            return nil
        case .codeEditor:
            return getCodeEditorContext(from: appElement, appName: appName)
        case .textEditor:
            if let textEditorResult = getTextEditorContextWithSeparation(from: appElement, appName: appName) {
                return textEditorResult
            }
            return nil
        case .browser:
            if let browserText = getBrowserContext(from: appElement, appName: appName) {
                return (
                    text: browserText, 
                    isTerminalDetected: false,
                    primaryText: browserText,
                    contextText: "",
                    primarySource: "Web page content",
                    contextSource: "None"
                )
            }
            return nil
        default:
            if let generalText = getGeneralAppContext(from: appElement, appName: appName) {
                return (
                    text: generalText, 
                    isTerminalDetected: false,
                    primaryText: generalText,
                    contextText: "",
                    primarySource: "Application content",
                    contextSource: "None"
                )
            }
            return nil
        }
    }
    
    /// Get comprehensive terminal context (output + input)
    private func getTerminalContext(from appElement: AXUIElement, appName: String) -> String? {
        logger.info("💻 Extracting terminal context from \(appName, privacy: .public)")
        
        // Try to get all text elements in the terminal
        var allText: [String] = []
        
        // Get all windows
        if let windows = getChildElements(appElement, role: "AXWindow") {
            for window in windows {
                // Look for text areas, text fields, and static text
                let textElements = getTextElementsRecursively(window)
                for element in textElements {
                    if let text = getElementText(element), !text.isEmpty {
                        allText.append(text)
                    }
                }
            }
        }
        
        if !allText.isEmpty {
            let combinedText = allText.joined(separator: "\n")
            logger.info("✅ Terminal context: \(combinedText.count, privacy: .public) chars from \(allText.count, privacy: .public) elements")
            return truncateIntelligently(combinedText, maxLength: maxContextLength)
        }
        
        logger.info("ℹ️ No terminal text found, falling back to focused element")
        return nil
    }
    
    /// Get comprehensive code editor context (surrounding code) with primary/context separation
    private func getCodeEditorContext(from appElement: AXUIElement, appName: String) -> (text: String, isTerminalDetected: Bool, primaryText: String, contextText: String, primarySource: String, contextSource: String)? {
        logger.info("👨‍💻 Extracting code editor context from \(appName, privacy: .public)")
        
        // FIRST: Get the FOCUSED element for primary content (terminal detection)
        if let focusedText = getFocusedElementTerminalContent(in: appElement, appName: appName) {
            logger.info("✅ Found terminal content in focused element: \(focusedText.count, privacy: .public) chars")
            return (
                text: focusedText, 
                isTerminalDetected: true,
                primaryText: focusedText,
                contextText: "",
                primarySource: "Terminal input field",
                contextSource: "None"
            )
        }
        
        // REGULAR CODE EDITOR: Separate focused element from surrounding context
        var primaryText = ""
        var contextText = ""
        var primarySource = ""
        var contextSource = ""
        
        // Get PRIMARY text from focused element
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focusedRef = focusedRef {
            let focusedElement = focusedRef as! AXUIElement
                         if let focusedElementText = getElementText(focusedElement) {
                 primaryText = truncateIntelligently(focusedElementText, maxLength: maxContextLength / 2)
                 primarySource = "Focused editor field"
                 logger.info("📝 Primary text from focused element: \(primaryText.count, privacy: .public) chars")
             }
         }
        
        // Get CONTEXT text from main text area (if different from focused)
        if let mainTextArea = findLargestTextArea(in: appElement) {
            if let mainText = getElementText(mainTextArea) {
                // Only use as context if it's different from primary text
                if mainText != primaryText && mainText.count > primaryText.count {
                    contextText = truncateIntelligently(mainText, maxLength: maxContextLength / 2)
                    contextSource = "Main code editor content"
                    logger.info("📄 Context text from main area: \(contextText.count, privacy: .public) chars")
                }
            }
        }
        
        // Combine for legacy compatibility
        let combinedText = primaryText.isEmpty ? contextText : primaryText
        
        if !combinedText.isEmpty {
            logger.info("✅ Code editor context extracted with separation")
            return (
                text: combinedText,
                isTerminalDetected: false,
                primaryText: primaryText,
                contextText: contextText,
                primarySource: primarySource,
                contextSource: contextSource
            )
        }
        
        logger.info("ℹ️ No code editor text found")
        return nil
    }
    
    /// Get text editor context with primary/context separation (document editing)
    private func getTextEditorContextWithSeparation(from appElement: AXUIElement, appName: String) -> (text: String, isTerminalDetected: Bool, primaryText: String, contextText: String, primarySource: String, contextSource: String)? {
        logger.info("📝 Extracting text editor context from \(appName, privacy: .public)")
        
        var primaryText = ""
        var contextText = ""
        var primarySource = ""
        var contextSource = ""
        
        // For text editors, prioritize the focused element (where user is typing)
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focusedRef = focusedRef {
            let focusedElement = focusedRef as! AXUIElement
            if let focusedText = getElementText(focusedElement) {
                // Check if this is the main document content
                if focusedText.count > 50 { // Substantial content
                    primaryText = truncateIntelligently(focusedText, maxLength: maxContextLength)
                    primarySource = "Main document content"
                    logger.info("📝 Primary text from focused document: \(primaryText.count, privacy: .public) chars")
                } else {
                    // Might be a small field, look for larger document content
                    if let mainTextArea = findLargestTextArea(in: appElement) {
                        if let documentText = getElementText(mainTextArea) {
                            primaryText = truncateIntelligently(documentText, maxLength: maxContextLength)
                            primarySource = "Main document content"
                            logger.info("📝 Primary text from main document: \(primaryText.count, privacy: .public) chars")
                        }
                    }
                }
            }
        }
        
        // If no primary text found, use the largest text area as fallback
        if primaryText.isEmpty {
            if let mainTextArea = findLargestTextArea(in: appElement) {
                if let documentText = getElementText(mainTextArea) {
                    primaryText = truncateIntelligently(documentText, maxLength: maxContextLength)
                    primarySource = "Document content"
                    logger.info("📝 Primary text from fallback document: \(primaryText.count, privacy: .public) chars")
                }
            }
        }
        
        // For text editors, we don't usually need context text from other areas
        // The primary document content is what matters
        
        let combinedText = primaryText
        
        if !combinedText.isEmpty {
            logger.info("✅ Text editor context extracted with separation")
            return (
                text: combinedText,
                isTerminalDetected: false,
                primaryText: primaryText,
                contextText: contextText,
                primarySource: primarySource,
                contextSource: contextSource.isEmpty ? "None" : contextSource
            )
        }
        
        logger.info("ℹ️ No text editor content found")
        return nil
    }
    
    /// Get comprehensive text editor context (document content) - Legacy method
    private func getTextEditorContext(from appElement: AXUIElement, appName: String) -> String? {
        logger.info("📝 Extracting text editor context from \(appName, privacy: .public)")
        
        // Similar to code editor but optimized for text documents
        if let mainTextArea = findLargestTextArea(in: appElement) {
            if let documentText = getElementText(mainTextArea) {
                logger.info("✅ Text editor context: \(documentText.count, privacy: .public) chars from document")
                return truncateIntelligently(documentText, maxLength: maxContextLength)
            }
        }
        
        logger.info("ℹ️ No document text found, falling back")
        return nil
    }
    
    /// Get browser context (page content)
    private func getBrowserContext(from appElement: AXUIElement, appName: String) -> String? {
        logger.info("🌐 Extracting browser context from \(appName, privacy: .public)")
        
        // Look for web content areas and text
        var webContent: [String] = []
        
        if let windows = getChildElements(appElement, role: "AXWindow") {
            for window in windows {
                // Look for web areas and text content
                let webElements = getWebTextElements(window)
                for element in webElements {
                    if let text = getElementText(element), !text.isEmpty && text.count > 10 {
                        webContent.append(text)
                    }
                }
            }
        }
        
        if !webContent.isEmpty {
            let combinedText = webContent.joined(separator: " ")
            logger.info("✅ Browser context: \(combinedText.count, privacy: .public) chars from page")
            return truncateIntelligently(combinedText, maxLength: maxContextLength)
        }
        
        logger.info("ℹ️ No web content found, falling back")
        return nil
    }
    
    /// Get general app context (multiple text elements)
    private func getGeneralAppContext(from appElement: AXUIElement, appName: String) -> String? {
        logger.info("📱 Extracting general app context from \(appName, privacy: .public)")
        
        // Get all meaningful text from the app
        var allText: [String] = []
        
        if let windows = getChildElements(appElement, role: "AXWindow") {
            for window in windows {
                let textElements = getTextElementsRecursively(window)
                for element in textElements {
                    if let text = getElementText(element), !text.isEmpty && text.count > 5 {
                        allText.append(text)
                    }
                }
            }
        }
        
        if !allText.isEmpty {
            // Prioritize longer text elements (likely more important)
            let sortedText = allText.sorted { $0.count > $1.count }
            let combinedText = sortedText.prefix(5).joined(separator: "\n")
            logger.info("✅ General app context: \(combinedText.count, privacy: .public) chars from \(allText.count, privacy: .public) elements")
            return truncateIntelligently(combinedText, maxLength: maxContextLength)
        }
        
        logger.info("ℹ️ No text elements found, falling back")
        return nil
    }
    
    /// Build smart text context around selection or cursor
    private func buildSmartTextContext(fullText: String, selectedText: String) -> String {
        // If we have selected text, prioritize that
        if !selectedText.isEmpty {
            // If selected text is small, include surrounding context
            if selectedText.count < maxContextLength / 2 {
                return buildContextAroundSelection(fullText: fullText, selectedText: selectedText)
            }
            // If selected text is large, truncate it intelligently
            return truncateIntelligently(selectedText, maxLength: maxContextLength)
        }
        
        // If no selection but we have full text, get relevant portion
        if !fullText.isEmpty {
            return truncateIntelligently(fullText, maxLength: maxContextLength)
        }
        
        return ""
    }
    
    /// Build context around selected text
    private func buildContextAroundSelection(fullText: String, selectedText: String) -> String {
        guard let range = fullText.range(of: selectedText) else {
            return selectedText
        }
        
        let beforeStart = max(0, fullText.distance(from: fullText.startIndex, to: range.lowerBound) - contextPadding)
        let afterEnd = min(fullText.count, fullText.distance(from: fullText.startIndex, to: range.upperBound) + contextPadding)
        
        let startIndex = fullText.index(fullText.startIndex, offsetBy: beforeStart)
        let endIndex = fullText.index(fullText.startIndex, offsetBy: afterEnd)
        
        return String(fullText[startIndex..<endIndex])
    }
    
    /// Truncate text intelligently (at word boundaries when possible)
    private func truncateIntelligently(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        
        let truncated = String(text.prefix(maxLength))
        
        // Try to cut at word boundary
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace])
        }
        
        return truncated
    }
    
    /// Get child elements of a specific role
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
    
    /// Recursively find all text elements in a UI hierarchy
    private func getTextElementsRecursively(_ element: AXUIElement) -> [AXUIElement] {
        var textElements: [AXUIElement] = []
        
        // Check if current element is a text element
        if let role = getElementRole(element) {
            let textRoles = ["AXTextArea", "AXTextField", "AXStaticText", "AXTextView"]
            if textRoles.contains(role) {
                textElements.append(element)
            }
        }
        
        // Recursively check children
        if let children = getChildElements(element) {
            for child in children {
                textElements.append(contentsOf: getTextElementsRecursively(child))
            }
        }
        
        return textElements
    }
    
    /// Get terminal content from ONLY the focused element using UI properties (not neighbors)
    private func getFocusedElementTerminalContent(in appElement: AXUIElement, appName: String) -> String? {
        logger.info("🎯 Checking ONLY focused element for terminal content in \(appName, privacy: .public)")
        
        // Get the focused UI element
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        
        guard result == .success, let focusedRef = focusedRef else {
            logger.info("⚠️ Could not get focused element")
            return nil
        }
        
        let focusedElement = focusedRef as! AXUIElement
        
        // FIRST: Check UI element properties for terminal indicators (most reliable)
        if isTerminalElementByProperties(focusedElement) {
            logger.info("✅ Detected terminal via UI properties!")
            
            // Get text content from terminal
            if let focusedText = getElementText(focusedElement) {
                logger.info("📝 Terminal content: \(focusedText.count, privacy: .public) chars")
                return truncateIntelligently(focusedText.isEmpty ? getTerminalPrompt() : focusedText, maxLength: maxContextLength)
            } else {
                // Even if no text content, we know it's a terminal, so return a terminal prompt
                logger.info("📝 No terminal text content, returning terminal prompt")
                return getTerminalPrompt()
            }
        }
        
        logger.info("🚫 Not a terminal element based on UI properties")
        return nil
    }
    
    /// Check if a UI element is a terminal based on accessibility properties
    private func isTerminalElementByProperties(_ element: AXUIElement) -> Bool {
        // Get role
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return false
        }
        
        // Get description
        var descRef: CFTypeRef?
        var description: String? = nil
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success {
            description = descRef as? String
        }
        
        logger.info("🔍 Element role: \(role, privacy: .public)")
        if let desc = description {
            logger.info("🔍 Element description: '\(desc.prefix(100), privacy: .public)...'")
        }
        
        // Terminal detection criteria based on exploration results:
        // 1. Role should be AXTextField (terminals use this)
        // 2. Description should contain terminal indicators
        
        let isTerminalRole = role == "AXTextField"
        let isTerminalDescription = description?.lowercased().contains("terminal") == true &&
                                  (description?.contains("accessibility") == true || 
                                   description?.contains("zsh") == true ||
                                   description?.contains("bash") == true ||
                                   description?.contains("shell") == true)
        
        let isTerminal = isTerminalRole && isTerminalDescription
        
        if isTerminal {
            logger.info("✅ TERMINAL DETECTED: role=\(role, privacy: .public), has_terminal_desc=\(isTerminalDescription, privacy: .public)")
        } else {
            logger.info("❌ NOT TERMINAL: role=\(role, privacy: .public), has_terminal_desc=\(isTerminalDescription, privacy: .public)")
        }
        
        return isTerminal
    }
    
    /// Get a default terminal prompt when no content is available
    private func getTerminalPrompt() -> String {
        return "$ "
    }

    /// Find and extract terminal content specifically (for embedded terminals in code editors)
    private func findAndExtractTerminalContent(in element: AXUIElement, appName: String) -> String? {
        logger.info("🔍 Searching for terminal content in \(appName, privacy: .public)")
        
        let textElements = getTextElementsRecursively(element)
        var terminalCandidates: [(element: AXUIElement, text: String, score: Int)] = []
        
        // Analyze each text element for terminal patterns
        for textElement in textElements {
            if let text = getElementText(textElement), !text.isEmpty {
                let terminalScore = calculateTerminalScore(text)
                if terminalScore > 0 {
                    terminalCandidates.append((textElement, text, terminalScore))
                    logger.info("🔍 Found potential terminal element: score=\(terminalScore, privacy: .public), length=\(text.count, privacy: .public)")
                }
            }
        }
        
        // Sort by terminal score (highest first)
        terminalCandidates.sort { $0.score > $1.score }
        
        // If we found good terminal candidates, return the best one
        if let bestCandidate = terminalCandidates.first, bestCandidate.score >= 3 {
            logger.info("✅ Selected terminal content with score \(bestCandidate.score, privacy: .public)")
            return truncateIntelligently(bestCandidate.text, maxLength: maxContextLength)
        }
        
        logger.info("ℹ️ No terminal content found (best score: \(terminalCandidates.first?.score ?? 0, privacy: .public))")
        return nil
    }
    
    /// Calculate how "terminal-like" a piece of text is using the same logic as isTerminalContent
    private func calculateTerminalScore(_ text: String) -> Int {
        let textLower = text.lowercased()
        let lines = text.components(separatedBy: .newlines)
        
        // Check for chat/conversational patterns - if found, heavily penalize
        let chatIndicators = [
            "write a", "write an", "help me", "can you", "please", "how do i", "how to",
            "i want", "i need", "could you", "would you", "let's", "we should",
            "the issue is", "the problem", "our code", "our system", "we're trying",
            "conversation", "chat", "message", "discussion", "talking about",
            "user types", "user input", "when the user", "if the user",
            "assistant", "ai", "chatgpt", "claude", "model", "llm",
            "enhancement", "feature", "improvement", "fix", "debug",
            "summary", "analysis", "review", "feedback", "suggestion"
        ]
        
        var chatScore = 0
        for indicator in chatIndicators {
            if textLower.contains(indicator) {
                chatScore += 2
            }
        }
        
        // If high chat score, return very low score
        if chatScore >= 4 {
            return 0
        }
        
        // Look for STRUCTURAL terminal patterns
        var structuralScore = 0
        
        // 1. Actual command prompt patterns at line starts
        for line in lines.prefix(10) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Actual prompt patterns: user@host:path$ or similar
            if trimmed.contains("@") && trimmed.contains(":") && (trimmed.contains("$") || trimmed.contains("#") || trimmed.contains("%")) {
                structuralScore += 5
            }
            
            // Command execution patterns (command at start of line)
            let commandStarts = ["ls", "cd", "pwd", "mkdir", "rm", "git", "npm", "curl", "sudo", "cat", "grep"]
            for command in commandStarts {
                if trimmed.hasPrefix(command + " ") || trimmed == command {
                    structuralScore += 3
                }
            }
            
            // Terminal output patterns at line start
            if trimmed.hasPrefix("total ") || trimmed.hasPrefix("drwx") || trimmed.hasPrefix("-rw") {
                structuralScore += 3
            }
            
            // Error/permission messages at line start
            if trimmed.hasPrefix("permission denied") || trimmed.hasPrefix("command not found") || 
               trimmed.hasPrefix("bash: ") || trimmed.hasPrefix("zsh: ") {
                structuralScore += 3
            }
        }
        
        // 2. Terminal environment indicators
        if textLower.contains("~/") || textLower.contains("./") || textLower.contains("../") {
            structuralScore += 1
        }
        
        // 3. Path structures that look like actual terminal paths
        let pathPatterns = ["/usr/local/", "/usr/bin/", "/home/", "/var/", "/etc/", "/tmp/"]
        for pattern in pathPatterns {
            if textLower.contains(pattern) {
                structuralScore += 2
            }
        }
        
        // Penalty for non-terminal patterns
        let nonTerminalPatterns = [
            "function", "const", "let", "var", "class", "def", "import", "{", "}", "()", "[]",
            "if (", "for (", "while (", "switch (", "try {", "catch {",
            "explanation", "description", "documentation", "comment", "note"
        ]
        
        var penalty = 0
        for pattern in nonTerminalPatterns {
            if textLower.contains(pattern) {
                penalty += 1
            }
        }
        
        // Final score calculation with chat penalty
        let finalScore = max(0, structuralScore - penalty - (chatScore * 2))
        return finalScore
    }
    
    /// Find the largest text area (likely the main content area)
    private func findLargestTextArea(in element: AXUIElement) -> AXUIElement? {
        let textElements = getTextElementsRecursively(element)
        
        var largestElement: AXUIElement?
        var largestSize = 0
        
        for textElement in textElements {
            if let text = getElementText(textElement) {
                if text.count > largestSize {
                    largestSize = text.count
                    largestElement = textElement
                }
            }
        }
        
        return largestElement
    }
    
    /// Get text elements specifically for web content
    private func getWebTextElements(_ element: AXUIElement) -> [AXUIElement] {
        var webElements: [AXUIElement] = []
        
        // Look for web-specific roles and general text elements
        let webRoles = ["AXWebArea", "AXText", "AXStaticText", "AXTextArea", "AXTextField", "AXGroup"]
        
        if let role = getElementRole(element) {
            if webRoles.contains(role) {
                webElements.append(element)
            }
        }
        
        // Recursively check children
        if let children = getChildElements(element) {
            for child in children {
                webElements.append(contentsOf: getWebTextElements(child))
            }
        }
        
        return webElements
    }
    
    /// Get element role
    private func getElementRole(_ element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        
        guard result == .success, let roleRef = roleRef else {
            return nil
        }
        
        return roleRef as! CFString as String
    }
    
    /// Get element text value
    private func getElementText(_ element: AXUIElement) -> String? {
        var textRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textRef)
        
        guard result == .success, let textRef = textRef else {
            return nil
        }
        
        return textRef as! CFString as String
    }
    
    /// Get element selected text
    private func getElementSelectedText(_ element: AXUIElement) -> String? {
        var selectedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef)
        
        guard result == .success, let selectedRef = selectedRef else {
            return nil
        }
        
        return selectedRef as! CFString as String
    }
    
    /// Fallback text context extraction using clipboard simulation
    private func getFallbackTextContext() -> String {
        logger.info("📋 Using fallback clipboard method...")
        
        // Store original clipboard content
        let originalClipboard = NSPasteboard.general.string(forType: .string)
        
        // Clear clipboard
        NSPasteboard.general.clearContents()
        
        // Simulate copy command
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdC = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // C key
        cmdC?.flags = .maskCommand
        cmdC?.post(tap: .cghidEventTap)
        
        let cmdCUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) // C key
        cmdCUp?.flags = .maskCommand
        cmdCUp?.post(tap: .cghidEventTap)
        
        // Small delay to allow copy to complete
        Thread.sleep(forTimeInterval: 0.1)
        
        // Get copied text
        let copiedText = NSPasteboard.general.string(forType: .string) ?? ""
        
        // Restore original clipboard
        NSPasteboard.general.clearContents()
        if let original = originalClipboard {
            NSPasteboard.general.setString(original, forType: .string)
        }
        
        logger.info("📝 Fallback extracted text: \(copiedText.count, privacy: .public) characters")
        return copiedText
    }
    
    /// Analyze application and text context
    private func analyzeContext(withTextExtraction: Bool = false) -> ContextInfo {
        logger.info("🔍 Analyzing context...")
        print("🔍 Analyzing context...")
        let info = ContextInfo()
        info.applicationName = currentApplication
        info.selectedText = withTextExtraction ? selectedText : ""
        info.textLength = info.selectedText.count
        info.hasSelection = !info.selectedText.isEmpty
        
        // Analyze application type with enhanced detection
        info.applicationType = detectApplicationType(currentApplication)
        logger.info("🏷️ Application type detected: \(info.applicationType.description, privacy: .public)")
        print("🏷️ Application type detected: \(info.applicationType.description)")
        
        info.contextType = detectContextType(currentApplication, info.selectedText)
        logger.info("🎯 Context type detected: \(info.contextType.description, privacy: .public)")
        print("🎯 Context type detected: \(info.contextType.description)")
        
        info.programmingLanguage = detectProgrammingLanguage(info.selectedText, info.applicationType)
        if info.programmingLanguage != "Unknown" {
            logger.info("💻 Programming language detected: \(info.programmingLanguage, privacy: .public)")
            print("💻 Programming language detected: \(info.programmingLanguage)")
        }
        
        // Analyze text type
        if !info.selectedText.isEmpty {
            info.textType = detectTextType(info.selectedText)
            logger.info("📄 Text type detected: \(info.textType.description, privacy: .public)")
            print("📄 Text type detected: \(info.textType.description)")
            
            info.language = detectLanguage(info.selectedText)
            logger.info("🗣️ Language detected: \(info.language, privacy: .public)")
            print("🗣️ Language detected: \(info.language)")
            
            info.suggestions = generateSuggestions(for: info.selectedText, in: info.applicationType)
            logger.info("💡 Generated \(info.suggestions.count, privacy: .public) suggestions")
            print("💡 Generated \(info.suggestions.count) suggestions")
        }
        
        logger.info("✅ Context analysis complete:")
        logger.info("   📱 App: \(info.applicationName, privacy: .public) (\(info.applicationType.description, privacy: .public))")
        logger.info("   🎯 Context: \(info.contextType.description, privacy: .public)")
        logger.info("   💻 Language: \(info.programmingLanguage, privacy: .public)")
        logger.info("   📝 Text: \(info.textLength, privacy: .public) chars, Type: \(info.textType.description, privacy: .public)")
        
        print("✅ Context analysis complete:")
        print("   📱 App: \(info.applicationName) (\(info.applicationType.description))")
        print("   🎯 Context: \(info.contextType.description)")
        print("   💻 Language: \(info.programmingLanguage)")
        print("   📝 Text: \(info.textLength) chars, Type: \(info.textType.description)")
        
        return info
    }
    
    private func detectApplicationType(_ appName: String) -> ApplicationType {
        let appNameLower = appName.lowercased()
        
        // Terminal applications
        if appNameLower.contains("terminal") || appNameLower.contains("iterm") || 
           appNameLower.contains("warp") || appNameLower.contains("hyper") ||
           appNameLower.contains("kitty") || appNameLower.contains("alacritty") {
            return .terminal
        }
        
        // Email applications
        if appNameLower.contains("mail") || appNameLower.contains("outlook") || 
           appNameLower.contains("thunderbird") || appNameLower.contains("spark") ||
           appNameLower.contains("airmail") {
            return .email
        }
        
        // Web browsers
        if appNameLower.contains("safari") || appNameLower.contains("chrome") || 
           appNameLower.contains("firefox") || appNameLower.contains("edge") ||
           appNameLower.contains("brave") || appNameLower.contains("opera") {
            return .browser
        }
        
        // Text editors
        if appNameLower.contains("textedit") || appNameLower.contains("notes") ||
           appNameLower.contains("bear") || appNameLower.contains("ulysses") ||
           appNameLower.contains("ia writer") || appNameLower.contains("typora") ||
           appNameLower.contains("editor de texto") || appNameLower.contains("text editor") {
            return .textEditor
        }
        
        // Code editors and IDEs
        if appNameLower.contains("xcode") || appNameLower.contains("code") ||
           appNameLower.contains("sublime") || appNameLower.contains("atom") ||
           appNameLower.contains("intellij") || appNameLower.contains("pycharm") ||
           appNameLower.contains("webstorm") || appNameLower.contains("vim") ||
           appNameLower.contains("emacs") || appNameLower.contains("cursor") {
            return .codeEditor
        }
        
        // Chat and messaging
        if appNameLower.contains("slack") || appNameLower.contains("discord") || 
           appNameLower.contains("messages") || appNameLower.contains("telegram") ||
           appNameLower.contains("whatsapp") || appNameLower.contains("teams") {
            return .chat
        }
        
        // Office applications
        if appNameLower.contains("word") || appNameLower.contains("pages") ||
           appNameLower.contains("excel") || appNameLower.contains("numbers") ||
           appNameLower.contains("powerpoint") || appNameLower.contains("keynote") {
            return .office
        }
        
        // Form applications
        if appNameLower.contains("form") || appNameLower.contains("survey") ||
           appNameLower.contains("typeform") || appNameLower.contains("google forms") {
            return .form
        }
        
        return .other
    }
    
    private func detectContextType(_ appName: String, _ selectedText: String) -> ContextType {
        let appType = detectApplicationType(appName)
        let textLower = selectedText.lowercased()
        
        // PRIORITY: Check for terminal content patterns first (even in code editors)
        if isTerminalContent(selectedText) {
            return .terminalCommand
        }
        
        switch appType {
        case .terminal:
            return .terminalCommand
        case .email:
            if textLower.contains("subject:") || textLower.contains("to:") {
                return .emailComposition
            }
            return .emailReply
        case .browser:
            if textLower.contains("http") || textLower.contains("www") {
                return .webSearch
            }
            return .webForm
        case .codeEditor:
            if detectProgrammingLanguage(selectedText, appType) != "Unknown" {
                return .codeWriting
            }
            return .codeComment
        case .chat:
            return .casualMessage
        case .office:
            return .documentWriting
        case .form:
            return .formFilling
        default:
            return .generalText
        }
    }
    
    /// Detect if text content appears to be from a terminal (even within code editors)
    private func isTerminalContent(_ text: String) -> Bool {
        let textLower = text.lowercased()
        let lines = text.components(separatedBy: .newlines)
        
        // FIRST: Check for chat/conversational patterns - if found, likely NOT terminal
        let chatIndicators = [
            "write a", "write an", "help me", "can you", "please", "how do i", "how to",
            "i want", "i need", "could you", "would you", "let's", "we should",
            "the issue is", "the problem", "our code", "our system", "we're trying",
            "conversation", "chat", "message", "discussion", "talking about",
            "user types", "user input", "when the user", "if the user",
            "assistant", "ai", "chatgpt", "claude", "model", "llm",
            "enhancement", "feature", "improvement", "fix", "debug",
            "summary", "analysis", "review", "feedback", "suggestion"
        ]
        
        var chatScore = 0
        for indicator in chatIndicators {
            if textLower.contains(indicator) {
                chatScore += 2
            }
        }
        
        // If high chat score, likely conversational content about terminals, not actual terminal
        if chatScore >= 4 {
            logger.info("🗣️ DETECTED conversational content (chat score: \(chatScore, privacy: .public)) - NOT terminal")
            return false
        }
        
        // SECOND: Look for STRUCTURAL terminal patterns (not just keywords)
        var structuralTerminalScore = 0
        
        // 1. Look for actual command prompt patterns at line starts
        for line in lines.prefix(10) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Actual prompt patterns: user@host:path$ or similar
            if trimmed.contains("@") && trimmed.contains(":") && (trimmed.contains("$") || trimmed.contains("#") || trimmed.contains("%")) {
                structuralTerminalScore += 5
            }
            
            // Command execution patterns (command at start of line)
            let commandStarts = ["ls", "cd", "pwd", "mkdir", "rm", "git", "npm", "curl", "sudo", "cat", "grep"]
            for command in commandStarts {
                if trimmed.hasPrefix(command + " ") || trimmed == command {
                    structuralTerminalScore += 3
                }
            }
            
            // Terminal output patterns at line start
            if trimmed.hasPrefix("total ") || trimmed.hasPrefix("drwx") || trimmed.hasPrefix("-rw") {
                structuralTerminalScore += 3
            }
            
            // Error/permission messages at line start
            if trimmed.hasPrefix("permission denied") || trimmed.hasPrefix("command not found") || 
               trimmed.hasPrefix("bash: ") || trimmed.hasPrefix("zsh: ") {
                structuralTerminalScore += 3
            }
        }
        
        // 3. Look for terminal environment indicators
        if textLower.contains("~/") || textLower.contains("./") || textLower.contains("../") {
            structuralTerminalScore += 1
        }
        
        // 4. Path structures that look like actual terminal paths
        let pathRegexPatterns = [
            "/usr/local/", "/usr/bin/", "/home/", "/var/", "/etc/", "/tmp/"
        ]
        for pattern in pathRegexPatterns {
            if textLower.contains(pattern) {
                structuralTerminalScore += 2
            }
        }
        
        // THIRD: Penalty for non-terminal patterns
        let nonTerminalPatterns = [
            "function", "const", "let", "var", "class", "def", "import", "{", "}", "()", "[]",
            "if (", "for (", "while (", "switch (", "try {", "catch {",
            "<div", "<html", "<body", "css", "javascript", "typescript",
            "explanation", "description", "documentation", "comment", "note"
        ]
        
        var nonTerminalScore = 0
        for pattern in nonTerminalPatterns {
            if textLower.contains(pattern) {
                nonTerminalScore += 1
            }
        }
        
        // DECISION LOGIC: Must have strong structural evidence
        let isTerminal = structuralTerminalScore >= 5 && nonTerminalScore <= 2 && chatScore <= 1
        
        if isTerminal {
            logger.info("🔍 DETECTED terminal content: structural=\(structuralTerminalScore, privacy: .public), non_terminal=\(nonTerminalScore, privacy: .public), chat=\(chatScore, privacy: .public)")
        } else {
            logger.info("🚫 NOT terminal content: structural=\(structuralTerminalScore, privacy: .public), non_terminal=\(nonTerminalScore, privacy: .public), chat=\(chatScore, privacy: .public)")
        }
        
        return isTerminal
    }
    
    private func detectProgrammingLanguage(_ text: String, _ appType: ApplicationType) -> String {
        if appType != .codeEditor && appType != .terminal {
            return "Unknown"
        }
        
        let textLower = text.lowercased()
        
        // Swift
        if textLower.contains("func ") || textLower.contains("var ") || textLower.contains("let ") ||
           textLower.contains("import ") || textLower.contains("class ") || textLower.contains("struct ") {
            return "Swift"
        }
        
        // JavaScript/TypeScript
        if textLower.contains("function ") || textLower.contains("const ") || textLower.contains("let ") ||
           textLower.contains("var ") || textLower.contains("=> ") || textLower.contains("console.") {
            return "JavaScript"
        }
        
        // Python
        if textLower.contains("def ") || textLower.contains("import ") || textLower.contains("from ") ||
           textLower.contains("class ") || textLower.contains("print(") || textLower.contains("if __name__") {
            return "Python"
        }
        
        // Shell/Bash
        if textLower.contains("#!/bin/bash") || textLower.contains("#!/bin/sh") ||
           textLower.contains("echo ") || textLower.contains("export ") || textLower.contains("grep ") {
            return "Shell"
        }
        
        // SQL
        if textLower.contains("select ") || textLower.contains("insert ") || textLower.contains("update ") ||
           textLower.contains("delete ") || textLower.contains("create table") {
            return "SQL"
        }
        
        // HTML
        if textLower.contains("<html") || textLower.contains("<div") || textLower.contains("<body") ||
           textLower.contains("</") || textLower.contains("class=") {
            return "HTML"
        }
        
        // CSS
        if textLower.contains("{") && textLower.contains("}") && textLower.contains(":") &&
           (textLower.contains("color") || textLower.contains("margin") || textLower.contains("padding")) {
            return "CSS"
        }
        
        return "Unknown"
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
            case .terminal:
                suggestions.append("Explain this command")
                suggestions.append("Make this command safer")
                suggestions.append("Add error handling")
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
            case .office:
                suggestions.append("Make this more formal")
                suggestions.append("Add professional tone")
                suggestions.append("Structure this better")
            case .form:
                suggestions.append("Make this more concise")
                suggestions.append("Add required details")
                suggestions.append("Improve clarity")
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
    @Published var contextType: ContextType = .generalText
    @Published var selectedText: String = ""  // Legacy field for compatibility
    @Published var textLength: Int = 0
    @Published var hasSelection: Bool = false
    @Published var textType: TextType = .paragraph
    @Published var language: String = "Unknown"
    @Published var programmingLanguage: String = "Unknown"
    @Published var suggestions: [String] = []
    
    // 🎯 NEW: Clearly separated text sources for better LLM understanding
    @Published var primaryText: String = ""        // Text from focused field (where output goes)
    @Published var contextText: String = ""        // Background text from other areas
    @Published var primaryTextSource: String = ""  // Description of primary text source
    @Published var contextTextSource: String = ""  // Description of context text source
}

enum ApplicationType {
    case terminal
    case email
    case browser
    case textEditor
    case codeEditor
    case chat
    case office
    case form
    case other
    
    var description: String {
        switch self {
        case .terminal: return "Terminal"
        case .email: return "Email"
        case .browser: return "Browser"
        case .textEditor: return "Text Editor"
        case .codeEditor: return "Code Editor"
        case .chat: return "Chat"
        case .office: return "Office"
        case .form: return "Form"
        case .other: return "Other"
        }
    }
}

enum ContextType {
    case terminalCommand
    case emailComposition
    case emailReply
    case webSearch
    case webForm
    case codeWriting
    case codeComment
    case casualMessage
    case documentWriting
    case formFilling
    case generalText
    
    var description: String {
        switch self {
        case .terminalCommand: return "Terminal Command"
        case .emailComposition: return "Email Composition"
        case .emailReply: return "Email Reply"
        case .webSearch: return "Web Search"
        case .webForm: return "Web Form"
        case .codeWriting: return "Code Writing"
        case .codeComment: return "Code Comment"
        case .casualMessage: return "Casual Message"
        case .documentWriting: return "Document Writing"
        case .formFilling: return "Form Filling"
        case .generalText: return "General Text"
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