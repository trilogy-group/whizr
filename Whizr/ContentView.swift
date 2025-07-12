import SwiftUI
import AppKit
import os.log

struct ContentView: View {
    @EnvironmentObject var llmClient: LLMClient
    @EnvironmentObject var preferencesManager: PreferencesManager
    @EnvironmentObject var contextDetector: ContextDetector
    @EnvironmentObject var textInjector: TextInjector
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var contextPromptGenerator: ContextPromptGenerator
    @EnvironmentObject var popupManager: PopupWindowManager
    
    // Add logger for structured logging
    private let logger = Logger(subsystem: "com.whizr.Whizr", category: "ContentView")
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            
            // Status section
            VStack(alignment: .leading, spacing: 10) {
                statusRow("Hotkey", hotkeyManager.isEnabled ? "Active" : "Inactive", hotkeyManager.isEnabled)
                statusRow("LLM Client", llmClient.isProcessing ? "Processing" : (llmClient.isConfigured ? "Ready" : "Not Configured"), llmClient.isConfigured && !llmClient.isProcessing)
                statusRow("Text Injection", "Ready", true)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            
            // Embedded preferences section
            PreferencesSection()
                .environmentObject(preferencesManager)
                .environmentObject(llmClient)
            
            Spacer()
            
            // Quit Button
            Button(action: {
                NSApp.terminate(nil)
            }) {
                Text("Quit Whizr")
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom)
        }
        .padding()
        .onAppear {
            logger.info("🪟 ContentView appeared (config window opened)")
            // Hotkey listener now starts automatically on app launch, not here
        }
        // Notification listeners removed - now handled by AppController
    }
    
    private var headerSection: some View {
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
    }
    
    private func statusRow(_ title: String, _ status: String, _ isActive: Bool) -> some View {
        HStack {
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Text(status)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// Embedded preferences section for main window
struct PreferencesSection: View {
    @EnvironmentObject var preferencesManager: PreferencesManager
    @EnvironmentObject var llmClient: LLMClient
    
    @State private var selectedProvider: LLMClient.LLMProvider = .openai
    @State private var apiKey = ""
    @State private var model = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("LLM Configuration")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Provider")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Provider", selection: $selectedProvider) {
                    Text("OpenAI").tag(LLMClient.LLMProvider.openai)
                    Text("Anthropic").tag(LLMClient.LLMProvider.anthropic)
                    Text("Local (Ollama)").tag(LLMClient.LLMProvider.local)
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedProvider) { newProvider in
                    loadSettingsForProvider(newProvider)
                }
                
                VStack(alignment: .leading, spacing: 6) {
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
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(modelPlaceholder, text: $model)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Button("Save Configuration") {
                    savePreferences()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
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
            model = preferencesManager.openaiModel.isEmpty ? "gpt-4o-mini" : preferencesManager.openaiModel
        case .anthropic:
            apiKey = preferencesManager.anthropicApiKey
            model = preferencesManager.anthropicModel.isEmpty ? "claude-3-haiku-20240307" : preferencesManager.anthropicModel
        case .local:
            apiKey = preferencesManager.ollamaHost.isEmpty ? "http://localhost:11434" : preferencesManager.ollamaHost
            model = preferencesManager.ollamaModel.isEmpty ? "llama3.2:3b" : preferencesManager.ollamaModel
        }
    }
    
    private func loadSettingsForProvider(_ provider: LLMClient.LLMProvider) {
        switch provider {
        case .openai:
            apiKey = preferencesManager.openaiApiKey
            model = preferencesManager.openaiModel.isEmpty ? "gpt-4o-mini" : preferencesManager.openaiModel
        case .anthropic:
            apiKey = preferencesManager.anthropicApiKey
            model = preferencesManager.anthropicModel.isEmpty ? "claude-3-haiku-20240307" : preferencesManager.anthropicModel
        case .local:
            apiKey = preferencesManager.ollamaHost.isEmpty ? "http://localhost:11434" : preferencesManager.ollamaHost
            model = preferencesManager.ollamaModel.isEmpty ? "llama3.2:3b" : preferencesManager.ollamaModel
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
        
        // Update UserDefaults with the correct keys that LLMClient expects
        UserDefaults.standard.set(apiKey, forKey: "llm_api_key")
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: "llm_provider")
        UserDefaults.standard.set(model, forKey: "llm_model")
        
        // Reconfigure LLMClient
        llmClient.configure()
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
    let contextDetector = ContextDetector()
    let hotkeyManager = HotkeyManager(contextDetector: contextDetector)
    let popupManager = PopupWindowManager()
    
    return ContentView()
        .environmentObject(hotkeyManager)
        .environmentObject(LLMClient())
        .environmentObject(PermissionManager())
        .environmentObject(PreferencesManager())
        .environmentObject(contextDetector)
        .environmentObject(TextInjector())
        .environmentObject(popupManager)
        .environmentObject(ContextPromptGenerator())
} 