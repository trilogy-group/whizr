import SwiftUI
import AppKit
import os.log

// MARK: - Notification Names
extension Notification.Name {
    static let reopenPopup = Notification.Name("reopenPopup")
}

struct WhizrPopupView: View {
    @EnvironmentObject var llmClient: LLMClient
    @EnvironmentObject var preferencesManager: PreferencesManager
    @EnvironmentObject var contextDetector: ContextDetector
    @EnvironmentObject var textInjector: TextInjector
    @EnvironmentObject var contextPromptGenerator: ContextPromptGenerator
    
    @State private var userInput = ""
    @State private var isProcessing = false
    // @State private var includeClipboard = true  // COMMENTED OUT: Clipboard functionality disabled to reduce confusion
    @State private var screenshotPath: String?
    @State private var errorMessage = ""
    @State private var originalFocusedApp: NSRunningApplication?
    @State private var originalContext: ContextInfo?  // ✅ Store original context here
    
    @FocusState private var isTextFieldFocused: Bool
    
    private let logger = Logger(subsystem: "com.whizr.Whizr", category: "PopupView")
    
    let onClose: () -> Void
    
    init(originalFocusedApp: NSRunningApplication? = nil, screenshotPath: String? = nil, userInput: String = "", includeClipboard: Bool = true, originalContext: ContextInfo? = nil, onClose: @escaping () -> Void) {
        self.onClose = onClose
        self._originalFocusedApp = State(initialValue: originalFocusedApp)
        self._screenshotPath = State(initialValue: screenshotPath)
        self._userInput = State(initialValue: userInput)
        // self._includeClipboard = State(initialValue: includeClipboard)  // COMMENTED OUT: Keep for future use
        self._originalContext = State(initialValue: originalContext)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image("MenuBarIcon")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.accentColor)
                    Text("What can I help you with?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.8))
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            
            // Input field
            VStack(alignment: .leading, spacing: 6) {  // Reduced from 8 to 6
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $userInput)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 50, maxHeight: 100)  // Allow expansion up to ~4 lines
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(.separatorColor), lineWidth: 0.5)
                        )
                        .focused($isTextFieldFocused)
                    
                    // Placeholder text
                    if userInput.isEmpty {
                        Text("Type your request here...")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                
                // Context options
                HStack {
                    Button(action: captureScreenshot) {
                        HStack(spacing: 6) {
                            Image(systemName: screenshotPath != nil ? "checkmark.circle.fill" : "camera.fill")
                                .font(.system(size: 12))
                            Text(screenshotPath != nil ? "Screenshot Added" : "Add Screenshot")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(screenshotPath != nil ? Color.green : Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(screenshotPath != nil ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
            }
            
            // Error message
            if !errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                }
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.1))
                )
            }
            
            // Action buttons
            HStack(spacing: 10) {
                Button("Cancel") {
                    onClose()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                )
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: handleSubmit) {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(isProcessing ? "Generating..." : "Generate")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(isProcessing || userInput.isEmpty 
                                ? Color.accentColor.opacity(0.5) 
                                : Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)  // Cmd+Enter to submit
                .disabled(userInput.isEmpty || isProcessing)
            }
        }
        .padding(20)
        .frame(width: 440, height: 240)  // Increased height to accommodate multi-line input
        .background(
            ZStack {
                // Base layer - solid color for contrast
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor))
                
                // Material layer for depth
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.2),
                            Color.primary.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(0.2),
            radius: 20,
            x: 0,
            y: 10
        )
        .shadow(
            color: Color.accentColor.opacity(0.1),
            radius: 40,
            x: 0,
            y: 20
        )
        .onAppear {
            logger.info("🪟 Popup view appeared")
            logger.info("📱 Original focused app: \(originalFocusedApp?.localizedName ?? "None", privacy: .public)")
            logger.info("📝 Pre-filled user input: '\(userInput, privacy: .public)'")
            // logger.info("📋 Include clipboard: \(includeClipboard)")  // COMMENTED OUT
            logger.info("📸 Screenshot path: \(screenshotPath ?? "None", privacy: .public)")
            
            print("🪟 Popup view appeared")
            print("📱 Original focused app: \(originalFocusedApp?.localizedName ?? "None")")
            print("📝 Pre-filled user input: '\(userInput)'")
            // print("📋 Include clipboard: \(includeClipboard)")  // COMMENTED OUT
            print("📸 Screenshot path: \(screenshotPath ?? "None")")
            
            // Focus the text field when popup appears
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
            // Backup focus attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isTextFieldFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            logger.info("🔄 App became active, refocusing text field")
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
        }
    }
    
    private func handleSubmit() {
        guard !userInput.isEmpty && !isProcessing else { return }
        
        logger.info("🚀 Starting AI generation workflow")
        logger.info("📝 User input: '\(userInput, privacy: .public)'")
        // logger.info("📋 Include clipboard: \(includeClipboard)")  // COMMENTED OUT
        logger.info("📸 Screenshot: \(screenshotPath != nil ? "Yes" : "No", privacy: .public)")
        
        isProcessing = true
        errorMessage = ""
        
        Task {
            do {
                // Use the STORED original context that was captured when popup was created
                // NOT the current context detector state (which would be Whizr itself)
                let contextToUse = originalContext ?? contextDetector.contextInfo
                
                logger.info("✅ Using stored original context")
                logger.info("📱 Original app: \(contextToUse.applicationName, privacy: .public)")
                logger.info("🏷️ App type: \(contextToUse.applicationType.description, privacy: .public)")
                logger.info("🎯 Context type: \(contextToUse.contextType.description, privacy: .public)")
                logger.info("💻 Programming language: \(contextToUse.programmingLanguage.description, privacy: .public)")
                logger.info("📄 Selected text: \(contextToUse.selectedText.count, privacy: .public) chars")
                
                print("✅ Using stored original context")
                print("📱 Original app: \(contextToUse.applicationName)")
                print("🏷️ App type: \(contextToUse.applicationType.description)")
                print("🎯 Context type: \(contextToUse.contextType.description)")
                print("💻 Programming language: \(contextToUse.programmingLanguage.description)")
                print("📄 Selected text: \(contextToUse.selectedText.count) chars")
                
                // COMMENTED OUT: Clipboard functionality disabled to reduce confusion
                /*
                logger.info("📋 Getting clipboard text...")
                print("📋 Getting clipboard text...")
                let clipboardText = includeClipboard ? NSPasteboard.general.string(forType: .string) : nil
                logger.info("📋 Clipboard text: \(clipboardText?.count ?? 0) chars")
                print("📋 Clipboard text: \(clipboardText?.count ?? 0) chars")
                */
                let clipboardText: String? = nil // No clipboard functionality for now
                
                logger.info("🎭 Generating context-aware prompt...")
                print("🎭 Generating context-aware prompt...")
                
                // Generate prompt using the STORED original context
                let prompt = contextPromptGenerator.generatePrompt(
                    userInput: userInput,
                    contextInfo: contextToUse,  // Use stored original context!
                    selectedText: contextToUse.selectedText,
                    clipboardText: clipboardText,
                    includeClipboard: false // COMMENTED OUT
                )
                
                logger.info("✅ Prompt generated (\(prompt.count, privacy: .public) chars)")
                print("✅ Prompt generated (\(prompt.count) chars)")
                
                logger.info("🤖 Sending request to LLM...")
                print("🤖 Sending request to LLM...")
                let response = try await llmClient.generateText(prompt: prompt, imagePath: screenshotPath)
                
                await MainActor.run {
                    logger.info("✅ LLM response received (\(response.count, privacy: .public) chars)")
                    logger.info("📝 Response preview: '\(String(response.prefix(50)), privacy: .public)...'")
                    
                    print("✅ LLM response received (\(response.count) chars)")
                    print("📝 Response preview: '\(String(response.prefix(50)))...'")
                    
                    isProcessing = false
                    closeAndInjectText(response)
                }
            } catch {
                await MainActor.run {
                    logger.error("❌ Error: \(error.localizedDescription, privacy: .public)")
                    print("❌ Error: \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
    
    private func captureScreenshot() {
        // Hide the popup temporarily
        onClose()
        
        // Small delay to ensure popup is hidden
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.performScreenshot()
        }
    }
    
    private func performScreenshot() {
        Task {
            do {
                // Create temporary screenshot file
                let tempDir = NSTemporaryDirectory()
                let timestamp = Int(Date().timeIntervalSince1970)
                let screenshotFileName = "whizr_screenshot_\(timestamp).png"
                let screenshotPath = "\(tempDir)\(screenshotFileName)"
                
                // Use macOS screencapture utility for area selection
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-s", screenshotPath] // -i for interactive, -s for selection
                
                try process.run()
                process.waitUntilExit()
                
                // Check if screenshot was captured (user didn't cancel)
                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: screenshotPath) {
                    await MainActor.run {
                        self.screenshotPath = screenshotPath
                        print("📸 Screenshot captured: \(screenshotPath)")
                    }
                    
                    // Re-open the popup after screenshot capture
                    await MainActor.run {
                        // Small delay to ensure screenshot UI is dismissed
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            // Re-show the popup with the screenshot
                            self.showPopupAgain()
                        }
                    }
                } else {
                    print("📸 Screenshot capture cancelled by user")
                    // Re-open the popup even if cancelled
                    await MainActor.run {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.showPopupAgain()
                        }
                    }
                }
                
            } catch {
                print("❌ Error capturing screenshot: \(error)")
                // Re-open the popup on error
                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.showPopupAgain()
                    }
                }
            }
        }
    }
    
    private func showPopupAgain() {
        // Pass the original focused app, screenshot path, and current state to the notification
        let userInfo: [String: Any] = [
            "originalFocusedApp": originalFocusedApp as Any,
            "screenshotPath": screenshotPath as Any,
            "userInput": userInput,
            "includeClipboard": false,  // Fixed: Always pass false since clipboard is disabled
            "originalContext": originalContext as Any  // ✅ Pass the original context
        ]
        NotificationCenter.default.post(name: .reopenPopup, object: nil, userInfo: userInfo)
    }
    
    private func closeAndInjectText(_ response: String) {
        onClose() // Close popup first
        logger.info("🪟 Popup closed")
        
        // Close popup first and return focus to original app
        DispatchQueue.main.async {
            logger.info("🎯 Returning focus to original app: \(originalFocusedApp?.localizedName ?? "Unknown", privacy: .public)")
            
            // Try to activate the original app
            if let originalApp = originalFocusedApp {
                originalApp.activate()
            }
        }
        
        // Small delay to ensure focus is returned
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { // Increased delay slightly
            logger.info("💉 Injecting text into target app...")
            Task {
                await textInjector.injectText(response, targetApp: originalFocusedApp, contextType: originalContext?.contextType ?? .generalText)
                logger.info("✅ AI workflow completed successfully")
                print("✅ AI workflow completed successfully")
            }
        }
    }
}

// MARK: - Popup Window Manager

class PopupWindowManager: ObservableObject {
    private var popupWindow: NSWindow?
    private var windowController: NSWindowController?
    private let logger = Logger(subsystem: "com.whizr.Whizr", category: "PopupManager")
    
    func showPopup(
        llmClient: LLMClient,
        preferencesManager: PreferencesManager,
        contextDetector: ContextDetector,
        textInjector: TextInjector,
        contextPromptGenerator: ContextPromptGenerator,
        originalFocusedApp: NSRunningApplication? = nil,
        screenshotPath: String? = nil,
        userInput: String = "",
        includeClipboard: Bool = true, // COMMENTED OUT: Keep parameter for future use
        originalContext: ContextInfo? = nil  // ✅ Optional original context parameter
    ) {
        logger.info("🪟 Creating popup window...")
        logger.info("📱 Target app: \(originalFocusedApp?.localizedName ?? "Unknown", privacy: .public)")
        logger.info("📝 User input: '\(userInput, privacy: .public)'")
        // logger.info("📋 Include clipboard: \(includeClipboard)") // COMMENTED OUT
        logger.info("📸 Screenshot: \(screenshotPath != nil ? "Yes" : "No", privacy: .public)")
        
        print("🪟 Creating popup window...")
        print("📱 Target app: \(originalFocusedApp?.localizedName ?? "Unknown")")
        
        let capturedContext: ContextInfo
        
        if let providedContext = originalContext {
            // Use provided context (for reopening scenarios)
            capturedContext = providedContext
            logger.info("✅ Using provided original context: \(capturedContext.applicationName, privacy: .public) (\(capturedContext.applicationType.description, privacy: .public))")
            print("✅ Using provided original context: \(capturedContext.applicationName) (\(capturedContext.applicationType.description))")
        } else {
            // CRITICAL: Extract context from the ORIGINAL app BEFORE showing popup
            // This ensures we get the original app's context, not Whizr's
            logger.info("📸 Capturing original context before popup...")
            print("📸 Capturing original context before popup...")
            
            if let originalApp = originalFocusedApp {
                // Extract text context from the original app
                capturedContext = contextDetector.createContextForApp(originalApp)
                logger.info("✅ Captured context from original app: \(capturedContext.applicationName, privacy: .public) (\(capturedContext.applicationType.description, privacy: .public))")
                logger.info("📝 Extracted text: \(capturedContext.selectedText.count, privacy: .public) chars")
                print("✅ Captured context from original app: \(capturedContext.applicationName) (\(capturedContext.applicationType.description))")
                print("📝 Extracted text: \(capturedContext.selectedText.count) chars")
            } else {
                // Fallback to current context if no original app provided
                logger.warning("⚠️ No original app provided, using current context")
                contextDetector.updateCurrentContext()
                capturedContext = contextDetector.contextInfo
                logger.info("⚠️ Using fallback current context: \(capturedContext.applicationName, privacy: .public)")
            }
        }
        
        // Close existing popup if any
        closePopup()
        
        // Create content view with captured context
        let contentView = WhizrPopupView(
            originalFocusedApp: originalFocusedApp,
            screenshotPath: screenshotPath,
            userInput: userInput,
            includeClipboard: includeClipboard, // COMMENTED OUT: Keep for future use but not used
            originalContext: capturedContext,  // ✅ Pass the captured context
            onClose: {
                self.closePopup()
            }
        )
        .environmentObject(llmClient)
        .environmentObject(preferencesManager)
        .environmentObject(contextDetector)
        .environmentObject(textInjector)
        .environmentObject(contextPromptGenerator)
        
        // Create hosting controller
        let hostingController = NSHostingController(rootView: contentView)
        
        // Create custom window that can become key
        popupWindow = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        guard let window = popupWindow else { 
            logger.error("❌ Failed to create popup window")
            return 
        }
        
        window.contentViewController = hostingController
        
        logger.info("🔧 Configuring window properties...")
        
        // Configure window
        window.title = "Whizr"
        window.styleMask = [.borderless, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Enable keyboard input for borderless window
        window.acceptsMouseMovedEvents = true
        
        // Set window size
        window.setContentSize(NSSize(width: 440, height: 240))
        
        // Center window on screen
        window.center()
        
        // Position slightly above center for better visual balance
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let windowFrame = window.frame
        let newY = screenFrame.midY + (screenFrame.height * 0.1)
        window.setFrameOrigin(NSPoint(x: windowFrame.origin.x, y: newY))
        
        logger.info("📍 Window positioned at: (\(windowFrame.origin.x, privacy: .public), \(newY, privacy: .public))")
        
        // Create window controller
        windowController = NSWindowController(window: window)
        
        // Show window
        logger.info("✨ Showing popup window...")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Force window to become key for text input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            window.makeKey()
            window.makeFirstResponder(window.contentView)
            self.logger.info("⌨️ Window focused for text input")
        }
        
        // REMOVED: Problematic WindowDelegate that caused infinite recursion
        
        logger.info("✅ Popup window created and shown successfully")
        print("✅ Popup window created and shown successfully")
    }
    
    func closePopup() {
        guard let window = popupWindow else { return }
        
        logger.info("🪟 Closing popup window")
        print("🪟 Closing popup window")
        
        // Clear references first to prevent multiple calls
        popupWindow = nil
        windowController = nil
        
        // Then close the window
        window.close()
    }
}


// MARK: - Custom Window Class (Minimal for keyboard input)

private class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

#Preview {
    WhizrPopupView(originalFocusedApp: nil, screenshotPath: nil, userInput: "", includeClipboard: false, originalContext: nil) {
    print("Popup closed")
}
    .environmentObject(LLMClient())
    .environmentObject(PreferencesManager())
    .environmentObject(ContextDetector())
    .environmentObject(TextInjector())
    .environmentObject(ContextPromptGenerator())
} 