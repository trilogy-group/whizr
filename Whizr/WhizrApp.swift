import SwiftUI
import ApplicationServices

@main
struct WhizrApp: App {
    // Use an AppDelegate to manage the application lifecycle and global state
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Whizr", image: "MenuBarIcon") {
            // Provide all the managers from the AppDelegate's controller to the ContentView
            ContentView()
                .environmentObject(appDelegate.appController)
                .environmentObject(appDelegate.appController.hotkeyManager)
                .environmentObject(appDelegate.appController.llmClient)
                .environmentObject(appDelegate.appController.permissionManager)
                .environmentObject(appDelegate.appController.preferencesManager)
                .environmentObject(appDelegate.appController.contextDetector)
                .environmentObject(appDelegate.appController.textInjector)
                .environmentObject(appDelegate.appController.contextPromptGenerator)
                .environmentObject(appDelegate.appController.popupManager)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var appController: AppController = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("✅ Whizr has finished launching")
    }
}

// MARK: - AppController

/// The main controller class that manages all application logic and state
class AppController: ObservableObject {
    
    // Managers
    @Published var llmClient: LLMClient
    @Published var permissionManager: PermissionManager
    @Published var preferencesManager: PreferencesManager
    @Published var contextDetector: ContextDetector
    @Published var textInjector: TextInjector
    @Published var popupManager: PopupWindowManager
    @Published var contextPromptGenerator: ContextPromptGenerator
    @Published var hotkeyManager: HotkeyManager

    init() {
        // Initialize all managers in correct order
        let contextDetector = ContextDetector()
        
        self.llmClient = LLMClient()
        self.permissionManager = PermissionManager()
        self.preferencesManager = PreferencesManager()
        self.contextDetector = contextDetector
        self.textInjector = TextInjector()
        self.popupManager = PopupWindowManager()
        self.contextPromptGenerator = ContextPromptGenerator()
        // HotkeyManager must be initialized last since it depends on contextDetector
        self.hotkeyManager = HotkeyManager(contextDetector: contextDetector)
        
        print("🚀 AppController initialized. Setting up application...")
        
        setupNotificationListeners()
        
        // Configure dependencies
        self.llmClient.configure()
        
        // Start hotkey listening if permissions are available
        if AXIsProcessTrusted() {
            self.hotkeyManager.startListening()
            print("✅ Accessibility permissions granted on launch - hotkey listener started")
        } else {
            print("⚠️ Accessibility permissions not yet granted")
        }
    }

    private func setupNotificationListeners() {
        print("🎧 Setting up global notification listeners...")
        
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleHotkeyPress(_:)), 
            name: .hotkeyPressed, 
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleReopenPopup(_:)), 
            name: .reopenPopup, 
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handlePermissionsChanged(_:)), 
            name: .permissionsChanged, 
            object: nil
        )
    }
    
    @objc private func handleHotkeyPress(_ notification: Notification) {
        print("⚡ AppController received hotkey press notification")
        let preExtractedContext = notification.object as? ContextInfo
        
        // CRITICAL: Capture the currently focused app BEFORE showing popup
        let originalFocusedApp = contextDetector.getCurrentRunningApplication()
        print("🎯 Captured focused app before popup: \(originalFocusedApp?.localizedName ?? "Unknown")")
        
        // Use pre-extracted context or create new one
        let capturedContext: ContextInfo
        if let preExtracted = preExtractedContext {
            print("⚡ Using pre-extracted context from key event: \(preExtracted.primaryText.count) chars from \(preExtracted.applicationName)")
            capturedContext = preExtracted
        } else {
            print("⚠️ No pre-extracted context found. Creating minimal context")
            if let app = originalFocusedApp {
                capturedContext = contextDetector.createContextForApp(app)
            } else {
                capturedContext = ContextInfo()
            }
        }
        
        print("🚀 Showing popup from AppController...")
        
        // Show popup with the captured context
        popupManager.showPopup(
            llmClient: llmClient,
            preferencesManager: preferencesManager,
            contextDetector: contextDetector,
            textInjector: textInjector,
            contextPromptGenerator: contextPromptGenerator,
            originalFocusedApp: originalFocusedApp,
            screenshotPath: nil,
            userInput: "",
            includeClipboard: false,
            originalContext: capturedContext
        )
    }
    
    @objc private func handleReopenPopup(_ notification: Notification) {
        print("🖼️ AppController received reopen popup notification")
        
        guard let userInfo = notification.userInfo,
              let screenshotPath = userInfo["screenshotPath"] as? String,
              let userInput = userInfo["userInput"] as? String,
              let includeClipboard = userInfo["includeClipboard"] as? Bool,
              let originalContext = userInfo["originalContext"] as? ContextInfo,
              let originalFocusedApp = userInfo["originalFocusedApp"] as? NSRunningApplication else {
            print("❌ Failed to parse user info from reopen popup notification")
            return
        }

        print("🚀 Reopening popup from AppController with screenshot...")
        
        popupManager.showPopup(
            llmClient: llmClient,
            preferencesManager: preferencesManager,
            contextDetector: contextDetector,
            textInjector: textInjector,
            contextPromptGenerator: contextPromptGenerator,
            originalFocusedApp: originalFocusedApp,
            screenshotPath: screenshotPath,
            userInput: userInput,
            includeClipboard: includeClipboard,
            originalContext: originalContext
        )
    }
    
    @objc private func handlePermissionsChanged(_ notification: Notification) {
        print("🔑 Permissions changed notification received")
        if AXIsProcessTrusted() && !hotkeyManager.isEnabled {
            print("✅ Permissions granted! Starting hotkey listener...")
            hotkeyManager.startListening()
        } else if !AXIsProcessTrusted() && hotkeyManager.isEnabled {
            print("❌ Permissions revoked! Stopping hotkey listener...")
            hotkeyManager.stopListening()
        }
    }
} 