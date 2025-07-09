import SwiftUI
import Foundation

class PreferencesManager: ObservableObject {
    @Published var llmProvider: LLMClient.LLMProvider = .openai
    @Published var openaiApiKey: String = ""
    @Published var anthropicApiKey: String = ""
    @Published var openaiModel: String = "gpt-4"
    @Published var anthropicModel: String = "claude-3-sonnet-20240229"
    @Published var ollamaModel: String = "llama3"
    @Published var ollamaHost: String = "http://localhost:11434"
    
    @Published var hotkeyEnabled: Bool = true
    @Published var contextDetectionEnabled: Bool = true
    @Published var autoInjectEnabled: Bool = true
    
    private let userDefaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private struct Keys {
        static let llmProvider = "llm_provider"
        static let openaiApiKey = "openai_api_key"
        static let anthropicApiKey = "anthropic_api_key"
        static let openaiModel = "openai_model"
        static let anthropicModel = "anthropic_model"
        static let ollamaModel = "ollama_model"
        static let ollamaHost = "ollama_host"
        static let hotkeyEnabled = "hotkey_enabled"
        static let contextDetectionEnabled = "context_detection_enabled"
        static let autoInjectEnabled = "auto_inject_enabled"
    }
    
    init() {
        loadPreferences()
    }
    
    func loadPreferences() {
        // Load LLM settings
        if let providerString = userDefaults.string(forKey: Keys.llmProvider),
           let provider = LLMClient.LLMProvider(rawValue: providerString) {
            llmProvider = provider
        }
        
        openaiApiKey = userDefaults.string(forKey: Keys.openaiApiKey) ?? ""
        anthropicApiKey = userDefaults.string(forKey: Keys.anthropicApiKey) ?? ""
        openaiModel = userDefaults.string(forKey: Keys.openaiModel) ?? "gpt-4"
        anthropicModel = userDefaults.string(forKey: Keys.anthropicModel) ?? "claude-3-sonnet-20240229"
        ollamaModel = userDefaults.string(forKey: Keys.ollamaModel) ?? "llama3"
        ollamaHost = userDefaults.string(forKey: Keys.ollamaHost) ?? "http://localhost:11434"
        
        // Load general settings
        hotkeyEnabled = userDefaults.bool(forKey: Keys.hotkeyEnabled)
        contextDetectionEnabled = userDefaults.bool(forKey: Keys.contextDetectionEnabled)
        autoInjectEnabled = userDefaults.bool(forKey: Keys.autoInjectEnabled)
        
        // Set defaults if first run
        if !userDefaults.bool(forKey: "has_loaded_defaults") {
            hotkeyEnabled = true
            contextDetectionEnabled = true
            autoInjectEnabled = true
            userDefaults.set(true, forKey: "has_loaded_defaults")
            savePreferences()
        }
    }
    
    func savePreferences() {
        // Save LLM settings
        userDefaults.set(llmProvider.rawValue, forKey: Keys.llmProvider)
        userDefaults.set(openaiApiKey, forKey: Keys.openaiApiKey)
        userDefaults.set(anthropicApiKey, forKey: Keys.anthropicApiKey)
        userDefaults.set(openaiModel, forKey: Keys.openaiModel)
        userDefaults.set(anthropicModel, forKey: Keys.anthropicModel)
        userDefaults.set(ollamaModel, forKey: Keys.ollamaModel)
        userDefaults.set(ollamaHost, forKey: Keys.ollamaHost)
        
        // Save general settings
        userDefaults.set(hotkeyEnabled, forKey: Keys.hotkeyEnabled)
        userDefaults.set(contextDetectionEnabled, forKey: Keys.contextDetectionEnabled)
        userDefaults.set(autoInjectEnabled, forKey: Keys.autoInjectEnabled)
        
        // Save to LLM client compatible keys
        updateLLMClientPreferences()
        
        // Notify that preferences changed
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }
    
    private func updateLLMClientPreferences() {
        // Update UserDefaults keys that LLMClient expects
        userDefaults.set(llmProvider.rawValue, forKey: "llm_provider")
        
        let apiKey: String
        let model: String
        
        switch llmProvider {
        case .openai:
            apiKey = openaiApiKey
            model = openaiModel
        case .anthropic:
            apiKey = anthropicApiKey
            model = anthropicModel
        case .local:
            apiKey = "" // No API key needed for local
            model = ollamaModel
        }
        
        userDefaults.set(apiKey, forKey: "llm_api_key")
        userDefaults.set(model, forKey: "llm_model")
    }
    
    func resetToDefaults() {
        llmProvider = .openai
        openaiApiKey = ""
        anthropicApiKey = ""
        openaiModel = "gpt-4"
        anthropicModel = "claude-3-sonnet-20240229"
        ollamaModel = "llama3"
        ollamaHost = "http://localhost:11434"
        hotkeyEnabled = true
        contextDetectionEnabled = true
        autoInjectEnabled = true
        
        savePreferences()
    }
    
    func validateSettings() -> [String] {
        var errors: [String] = []
        
        switch llmProvider {
        case .openai:
            if openaiApiKey.isEmpty {
                errors.append("OpenAI API key is required")
            }
            if openaiModel.isEmpty {
                errors.append("OpenAI model is required")
            }
        case .anthropic:
            if anthropicApiKey.isEmpty {
                errors.append("Anthropic API key is required")
            }
            if anthropicModel.isEmpty {
                errors.append("Anthropic model is required")
            }
        case .local:
            if ollamaModel.isEmpty {
                errors.append("Ollama model is required")
            }
            if ollamaHost.isEmpty {
                errors.append("Ollama host is required")
            }
        }
        
        return errors
    }
    
    var isConfigurationValid: Bool {
        return validateSettings().isEmpty
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let preferencesChanged = Notification.Name("preferencesChanged")
} 