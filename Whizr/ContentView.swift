import SwiftUI

struct ContentView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var llmClient: LLMClient
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var preferencesManager: PreferencesManager
    @EnvironmentObject var contextDetector: ContextDetector
    @EnvironmentObject var textInjector: TextInjector
    @EnvironmentObject var popupManager: PopupWindowManager
    
    @State private var testPrompt = ""
    @State private var testResponse = ""
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image("MenuBarIcon")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.accentColor)
                Text("Whizr")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .padding(.top, 8)
            
            // Status indicators
            VStack(alignment: .leading, spacing: 8) {
                statusRow("Hotkey", hotkeyManager.isListening ? "Active" : "Inactive", hotkeyManager.isListening)
                statusRow("Accessibility", permissionManager.hasAccessibilityPermission ? "Granted" : "Needed", permissionManager.hasAccessibilityPermission)
                statusRow("LLM", llmClient.isConfigured ? "Ready" : "Not configured", llmClient.isConfigured)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Note about permissions
            if !permissionManager.hasAllPermissions {
                Text("💡 Only Accessibility permission is needed on macOS 15.5+")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            // Test section
            VStack(alignment: .leading, spacing: 8) {
                Text("Test LLM")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Enter test prompt", text: $testPrompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Test") {
                    testLLM()
                }
                .disabled(testPrompt.isEmpty || !llmClient.isConfigured)
                
                if !testResponse.isEmpty {
                    Text(testResponse)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            
            Divider()
            
            // Actions
            VStack(spacing: 8) {
                if !permissionManager.hasAllPermissions {
                    Button("Request Permissions") {
                        requestPermissions()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if !hotkeyManager.isListening && permissionManager.hasAccessibilityPermission {
                    Button("Restart Hotkey Listener") {
                        hotkeyManager.restartHotkeyListener()
                    }
                    .buttonStyle(.bordered)
                }
                
                Button("Preferences") {
                    openPreferencesWindow()
                }
                .buttonStyle(.bordered)
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 280, height: 450)
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyPressed)) { _ in
            handleHotkeyPress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reopenPopup)) { notification in
            handleReopenPopup(notification: notification)
        }
    }
    
    private func statusRow(_ title: String, _ status: String, _ isActive: Bool) -> some View {
        HStack {
            Circle()
                .fill(isActive ? .green : .red)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
            Text(status)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    

    
    private func testLLM() {
        Task {
            do {
                testResponse = try await llmClient.generateText(prompt: testPrompt)
            } catch {
                testResponse = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func requestPermissions() {
        permissionManager.requestPermissions()
        
        // Show system preferences if needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !permissionManager.hasAllPermissions {
                permissionManager.openSystemPreferences()
            }
        }
    }
    
    private func openPreferencesWindow() {
        // Check if preferences window already exists
        if let existingWindow = NSApplication.shared.windows.first(where: { $0.title == "Preferences" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        // Create new preferences window
        let preferencesView = SimplePreferencesView()
            .environmentObject(preferencesManager)
            .environmentObject(llmClient)
        
        let hostingController = NSHostingController(rootView: preferencesView)
        let window = NSWindow(
            contentViewController: hostingController
        )
        
        window.title = "Preferences"
        window.setContentSize(NSSize(width: 400, height: 400))
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    private func handleHotkeyPress() {
        print("🎯 Hotkey triggered! Showing popup...")
        
        // Show the popup window for user input
        popupManager.showPopup(
            llmClient: llmClient,
            preferencesManager: preferencesManager,
            contextDetector: contextDetector,
            textInjector: textInjector
        )
    }
    
    private func handleReopenPopup(notification: Notification) {
        print("🎯 Reopening popup after screenshot...")
        
        // Extract all state from notification
        let originalFocusedApp = notification.userInfo?["originalFocusedApp"] as? NSRunningApplication
        let screenshotPath = notification.userInfo?["screenshotPath"] as? String
        let userInput = notification.userInfo?["userInput"] as? String ?? ""
        let includeClipboard = notification.userInfo?["includeClipboard"] as? Bool ?? true
        
        popupManager.showPopup(
            llmClient: llmClient,
            preferencesManager: preferencesManager,
            contextDetector: contextDetector,
            textInjector: textInjector,
            originalFocusedApp: originalFocusedApp,
            screenshotPath: screenshotPath,
            userInput: userInput,
            includeClipboard: includeClipboard
        )
    }
}

// Simple embedded preferences view
struct SimplePreferencesView: View {
    @EnvironmentObject var preferencesManager: PreferencesManager
    @EnvironmentObject var llmClient: LLMClient
    
    @State private var selectedProvider: LLMClient.LLMProvider = .openai
    @State private var apiKey = ""
    @State private var model = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Preferences")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("LLM Provider")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Picker("Provider", selection: $selectedProvider) {
                    Text("OpenAI").tag(LLMClient.LLMProvider.openai)
                    Text("Anthropic").tag(LLMClient.LLMProvider.anthropic)
                    Text("Local (Ollama)").tag(LLMClient.LLMProvider.local)
                }
                .pickerStyle(.segmented)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedProvider == .local ? "Base URL" : "API Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if selectedProvider == .local {
                        TextField("http://localhost:11434", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    } else {
                        SecureField("Enter API Key", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(modelPlaceholder, text: $model)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    closeWindow()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save") {
                    savePreferences()
                    closeWindow()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 400, height: 350)
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    private var modelPlaceholder: String {
        switch selectedProvider {
        case .openai: return "gpt-4o-mini"
        case .anthropic: return "claude-3-haiku-20240307"
        case .local: return "llama3.2:3b"
        }
    }
    
    private func loadCurrentSettings() {
        selectedProvider = preferencesManager.llmProvider
        
        switch selectedProvider {
        case .openai:
            apiKey = preferencesManager.openaiApiKey
            model = preferencesManager.openaiModel
        case .anthropic:
            apiKey = preferencesManager.anthropicApiKey
            model = preferencesManager.anthropicModel
        case .local:
            apiKey = preferencesManager.ollamaHost
            model = preferencesManager.ollamaModel
        }
    }
    
    private func savePreferences() {
        preferencesManager.llmProvider = selectedProvider
        
        switch selectedProvider {
        case .openai:
            preferencesManager.openaiApiKey = apiKey
            preferencesManager.openaiModel = model
        case .anthropic:
            preferencesManager.anthropicApiKey = apiKey
            preferencesManager.anthropicModel = model
        case .local:
            preferencesManager.ollamaHost = apiKey
            preferencesManager.ollamaModel = model
        }
        
        preferencesManager.savePreferences()
        llmClient.configure()
    }
    
    private func closeWindow() {
        // Find and close the preferences window
        if let window = NSApplication.shared.windows.first(where: { $0.title.contains("Preferences") || $0.identifier?.rawValue == "preferences" }) {
            window.close()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(HotkeyManager())
        .environmentObject(LLMClient())
        .environmentObject(PermissionManager())
        .environmentObject(PreferencesManager())
        .environmentObject(ContextDetector())
        .environmentObject(TextInjector())
        .environmentObject(PopupWindowManager())
} 