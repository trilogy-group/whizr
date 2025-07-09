import SwiftUI
import AppKit

// MARK: - Notification Names
extension Notification.Name {
    static let reopenPopup = Notification.Name("reopenPopup")
}

struct WhizrPopupView: View {
    @EnvironmentObject var llmClient: LLMClient
    @EnvironmentObject var preferencesManager: PreferencesManager
    @EnvironmentObject var contextDetector: ContextDetector
    @EnvironmentObject var textInjector: TextInjector
    
    @State private var userInput = ""
    @State private var isProcessing = false
    @State private var includeClipboard = true
    @State private var screenshotPath: String?
    @State private var errorMessage = ""
    @State private var originalFocusedApp: NSRunningApplication?
    
    @FocusState private var isTextFieldFocused: Bool
    
    let onClose: () -> Void
    
    init(originalFocusedApp: NSRunningApplication? = nil, screenshotPath: String? = nil, userInput: String = "", includeClipboard: Bool = true, onClose: @escaping () -> Void) {
        self.onClose = onClose
        self._originalFocusedApp = State(initialValue: originalFocusedApp)
        self._screenshotPath = State(initialValue: screenshotPath)
        self._userInput = State(initialValue: userInput)
        self._includeClipboard = State(initialValue: includeClipboard)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image("MenuBarIcon")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.accentColor)
                Text("What can I help you with?")
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            
            // Input field
            VStack(alignment: .leading, spacing: 8) {
                TextField("Type your request here...", text: $userInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        if !userInput.isEmpty && !isProcessing {
                            handleSubmit()
                        }
                    }
                
                // Context options
                HStack {
                    // Clipboard
                     Toggle("📋 Clipboard", isOn: $includeClipboard)
                         .toggleStyle(.checkbox)
                         .font(.caption)
                     
                     Button(action: captureScreenshot) {
                         HStack(spacing: 4) {
                             Image(systemName: "camera")
                                 .font(.caption)
                             Text(screenshotPath != nil ? "Screenshot Added" : "Add Screenshot")
                                 .font(.caption)
                         }
                         .foregroundColor(screenshotPath != nil ? .green : .accentColor)
                     }
                     .buttonStyle(.borderless)
                     
                     Spacer()
                 }
            }
            
            // Error message
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            // Buttons
            HStack {
                Spacer()
                
                Button("Cancel") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                
                Button(action: handleSubmit) {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Generating...")
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .medium))
                            Text("Generate")
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(userInput.isEmpty || isProcessing)
            }
        }
        .padding(20)
        .frame(width: 420, height: 200)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 0.5)
        )
        .shadow(color: Color.primary.opacity(0.1), radius: 20, x: 0, y: 10)
        .onAppear {
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
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
        }
    }
    
    private func handleSubmit() {
        guard !userInput.isEmpty && !isProcessing else { return }
        
        isProcessing = true
        errorMessage = ""
        
        Task {
            do {
                // Build context
                await MainActor.run {
                    contextDetector.updateCurrentContext()
                }
                
                var contextParts: [String] = []
                
                // Add current application context
                contextParts.append("Application: \(contextDetector.currentApplication)")
                if !contextDetector.selectedText.isEmpty {
                    contextParts.append("Selected Text: \(contextDetector.selectedText)")
                }
                
                // Add clipboard if requested
                if includeClipboard {
                    let pasteboard = NSPasteboard.general
                    if let clipboardText = pasteboard.string(forType: .string), !clipboardText.isEmpty {
                        contextParts.append("Clipboard: \(clipboardText)")
                    }
                }
                
                let context = contextParts.joined(separator: "\n")
                
                // Create full prompt (don't include screenshot path as text since we'll send the image)
                let fullPrompt = """
                User Request: \(userInput)
                
                Context:
                \(context)
                
                Please provide a helpful response based on the user's request and the given context. Be concise and actionable.
                """
                
                // Generate AI response with image if available
                let response = try await llmClient.generateText(prompt: fullPrompt, imagePath: screenshotPath)
                
                // Inject the response text
                await MainActor.run {
                    isProcessing = false
                    onClose() // Close popup first
                }
                
                // Close popup first and return focus to original app
                await MainActor.run {
                    print("🎯 Returning focus to original app: \(originalFocusedApp?.localizedName ?? "Unknown")")
                    
                    // Try to activate the original app
                    if let originalApp = originalFocusedApp {
                        originalApp.activate(options: [.activateIgnoringOtherApps])
                    }
                }
                
                // Small delay to ensure focus is returned
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                
                await textInjector.injectText(response, targetApp: originalFocusedApp)
                
                print("✅ AI workflow completed successfully")
                
            } catch {
                await MainActor.run {
                    isProcessing = false
                    
                    // Provide more helpful error messages
                    if let llmError = error as? LLMClient.LLMError {
                        switch llmError {
                        case .notConfigured:
                            errorMessage = "⚙️ LLM not configured. Click Whizr menu → Preferences to set up API key."
                        case .noApiKey:
                            errorMessage = "🔑 API key missing. Check your preferences."
                        case .invalidResponse:
                            errorMessage = "📡 Invalid response from LLM service. Try again."
                        case .networkError(let details):
                            errorMessage = "🌐 Network error: \(details)"
                        }
                    } else {
                        errorMessage = "Error: \(error.localizedDescription)"
                    }
                    
                    print("❌ Error in AI workflow: \(error)")
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
            "includeClipboard": includeClipboard
        ]
        NotificationCenter.default.post(name: .reopenPopup, object: nil, userInfo: userInfo)
    }
}

// MARK: - Popup Window Manager

class PopupWindowManager: ObservableObject {
    private var popupWindow: NSWindow?
    private var windowController: NSWindowController?
    
    func showPopup(
        llmClient: LLMClient,
        preferencesManager: PreferencesManager,
        contextDetector: ContextDetector,
        textInjector: TextInjector,
        originalFocusedApp: NSRunningApplication? = nil,
        screenshotPath: String? = nil,
        userInput: String = "",
        includeClipboard: Bool = true
    ) {
        // Close existing popup if any
        closePopup()
        
        // Use provided original focused app or capture current
        let focusedApp = originalFocusedApp ?? NSWorkspace.shared.frontmostApplication
        print("🎯 Captured focused app before popup: \(focusedApp?.localizedName ?? "Unknown")")
        
        // Create the SwiftUI view
        let popupView = WhizrPopupView(originalFocusedApp: focusedApp, screenshotPath: screenshotPath, userInput: userInput, includeClipboard: includeClipboard) {
            self.closePopup()
        }
        .environmentObject(llmClient)
        .environmentObject(preferencesManager)
        .environmentObject(contextDetector)
        .environmentObject(textInjector)
        
        // Create hosting controller
        let hostingController = NSHostingController(rootView: popupView)
        
        // Create custom window that can become key
        popupWindow = KeyableWindow(
            contentViewController: hostingController
        )
        
        guard let window = popupWindow else { return }
        
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
        window.setContentSize(NSSize(width: 420, height: 200))
        
        // Center window on screen
        window.center()
        
        // Position slightly above center for better visual balance
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let windowFrame = window.frame
        let newY = screenFrame.midY + (screenFrame.height * 0.1)
        window.setFrameOrigin(NSPoint(x: windowFrame.origin.x, y: newY))
        
        // Create window controller
        windowController = NSWindowController(window: window)
        
        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Force window to become key for text input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            window.makeKey()
            window.makeFirstResponder(window.contentView)
        }
        
        // Set up close callback
        window.delegate = WindowDelegate { [weak self] in
            self?.closePopup()
        }
    }
    
    func closePopup() {
        popupWindow?.close()
        popupWindow = nil
        windowController = nil
    }
}

// MARK: - Custom Window Class

private class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

// MARK: - Window Delegate

private class WindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        // Optionally close when window loses focus
        // onClose()
    }
}

#Preview {
    WhizrPopupView(originalFocusedApp: nil, screenshotPath: nil) {
        print("Popup closed")
    }
    .environmentObject(LLMClient())
    .environmentObject(PreferencesManager())
    .environmentObject(ContextDetector())
    .environmentObject(TextInjector())
} 