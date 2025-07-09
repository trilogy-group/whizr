import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var preferencesManager: PreferencesManager
    @EnvironmentObject var llmClient: LLMClient
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedProvider: LLMClient.LLMProvider = .openai
    @State private var openaiApiKey = ""
    @State private var anthropicApiKey = ""
    @State private var openaiModel = ""
    @State private var anthropicModel = ""
    @State private var ollamaModel = ""
    @State private var ollamaHost = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "gear")
                    .foregroundColor(.blue)
                    .font(.title2)
                Text("Preferences")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top)
            
            // LLM Provider Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("LLM Provider")
                    .font(.headline)
                
                Picker("Provider", selection: $selectedProvider) {
                    Text("OpenAI").tag(LLMClient.LLMProvider.openai)
                    Text("Anthropic").tag(LLMClient.LLMProvider.anthropic)
                    Text("Local (Ollama)").tag(LLMClient.LLMProvider.local)
                }
                .pickerStyle(.segmented)
                
                // OpenAI Settings
                if selectedProvider == .openai {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenAI API Key")
                            .font(.caption)
                        SecureField("Enter OpenAI API Key", text: $openaiApiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenAI Model")
                            .font(.caption)
                        TextField("gpt-4o-mini", text: $openaiModel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                // Anthropic Settings
                if selectedProvider == .anthropic {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anthropic API Key")
                            .font(.caption)
                        SecureField("Enter Anthropic API Key", text: $anthropicApiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anthropic Model")
                            .font(.caption)
                        TextField("claude-3-haiku-20240307", text: $anthropicModel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                // Ollama Settings
                if selectedProvider == .local {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ollama Host")
                            .font(.caption)
                        TextField("http://localhost:11434", text: $ollamaHost)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ollama Model")
                            .font(.caption)
                        TextField("llama3.2:3b", text: $ollamaModel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save") {
                    savePreferences()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isConfigurationValid)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 400, height: 400)
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    private var isConfigurationValid: Bool {
        switch selectedProvider {
        case .openai:
            return !openaiApiKey.isEmpty && !openaiModel.isEmpty
        case .anthropic:
            return !anthropicApiKey.isEmpty && !anthropicModel.isEmpty
        case .local:
            return !ollamaModel.isEmpty && !ollamaHost.isEmpty
        }
    }
    
    private func loadCurrentSettings() {
        selectedProvider = preferencesManager.llmProvider
        openaiApiKey = preferencesManager.openaiApiKey
        anthropicApiKey = preferencesManager.anthropicApiKey
        openaiModel = preferencesManager.openaiModel
        anthropicModel = preferencesManager.anthropicModel
        ollamaModel = preferencesManager.ollamaModel
        ollamaHost = preferencesManager.ollamaHost
    }
    
    private func savePreferences() {
        preferencesManager.llmProvider = selectedProvider
        preferencesManager.openaiApiKey = openaiApiKey
        preferencesManager.anthropicApiKey = anthropicApiKey
        preferencesManager.openaiModel = openaiModel
        preferencesManager.anthropicModel = anthropicModel
        preferencesManager.ollamaModel = ollamaModel
        preferencesManager.ollamaHost = ollamaHost
        
        preferencesManager.savePreferences()
        
        // Update LLM client configuration
        llmClient.configure()
    }
}

#Preview {
    PreferencesView()
        .environmentObject(PreferencesManager())
        .environmentObject(LLMClient())
} 