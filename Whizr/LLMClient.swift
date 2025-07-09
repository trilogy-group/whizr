import SwiftUI
import Foundation

class LLMClient: ObservableObject {
    @Published var isConfigured = false
    @Published var isProcessing = false
    @Published var provider: LLMProvider = .openai
    
    private var apiKey: String = ""
    private var model: String = "gpt-4"
    
    enum LLMProvider: String, CaseIterable {
        case openai = "OpenAI"
        case anthropic = "Anthropic"
        case local = "Local (Ollama)"
    }
    
    enum LLMError: Error {
        case notConfigured
        case noApiKey
        case invalidResponse
        case networkError(String)
    }
    
    init() {
        loadConfiguration()
    }
    
    func configure() {
        loadConfiguration()
    }
    
    private func loadConfiguration() {
        // Load API key from UserDefaults or Keychain
        apiKey = UserDefaults.standard.string(forKey: "llm_api_key") ?? ""
        
        if let providerString = UserDefaults.standard.string(forKey: "llm_provider"),
           let savedProvider = LLMProvider(rawValue: providerString) {
            provider = savedProvider
        }
        
        model = UserDefaults.standard.string(forKey: "llm_model") ?? defaultModel()
        
        isConfigured = !apiKey.isEmpty || provider == .local
    }
    
    private func defaultModel() -> String {
        switch provider {
        case .openai:
            return "gpt-4"
        case .anthropic:
            return "claude-3-sonnet-20240229"
        case .local:
            return "llama3"
        }
    }
    
    func generateText(prompt: String, imagePath: String? = nil) async throws -> String {
        guard isConfigured else {
            throw LLMError.notConfigured
        }
        
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        defer {
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
        
        switch provider {
        case .openai:
            return try await callOpenAI(prompt: prompt, imagePath: imagePath)
        case .anthropic:
            return try await callAnthropic(prompt: prompt, imagePath: imagePath)
        case .local:
            return try await callLocal(prompt: prompt, imagePath: imagePath)
        }
    }
    
    private func callOpenAI(prompt: String, imagePath: String? = nil) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMError.noApiKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Build user message content
        var userContent: [OpenAIMessageContent] = [
            OpenAIMessageContent(type: "text", text: prompt)
        ]
        
        // Add image if provided
        if let imagePath = imagePath {
            if let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) {
                let base64Image = imageData.base64EncodedString()
                userContent.append(OpenAIMessageContent(
                    type: "image_url",
                    image_url: OpenAIImageURL(url: "data:image/png;base64,\(base64Image)")
                ))
            }
        }
        
        let body = OpenAIRequest(
            model: imagePath != nil ? "gpt-4o" : model, // Use vision model if image provided
            messages: [
                OpenAIMessage(role: "system", content: [OpenAIMessageContent(type: "text", text: "You are a helpful writing assistant. Provide concise, helpful responses.")]),
                OpenAIMessage(role: "user", content: userContent)
            ],
            max_tokens: 1000,
            temperature: 0.7
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            
            guard let content = response.choices.first?.message.content.first?.text else {
                throw LLMError.invalidResponse
            }
            
            return content
        } catch {
            throw LLMError.networkError(error.localizedDescription)
        }
    }
    
    private func callAnthropic(prompt: String, imagePath: String? = nil) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMError.noApiKey
        }
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Build user message content
        var userContent: [AnthropicMessageContent] = [
            AnthropicMessageContent(type: "text", text: prompt)
        ]
        
        // Add image if provided
        if let imagePath = imagePath {
            if let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) {
                let base64Image = imageData.base64EncodedString()
                userContent.append(AnthropicMessageContent(
                    type: "image",
                    source: AnthropicImageSource(
                        type: "base64",
                        media_type: "image/png",
                        data: base64Image
                    )
                ))
            }
        }
        
        let body = AnthropicRequest(
            model: imagePath != nil ? "claude-3-5-sonnet-20241022" : model, // Use vision model if image provided
            max_tokens: 1000,
            messages: [
                AnthropicMessage(role: "user", content: userContent)
            ],
            system: "You are a helpful writing assistant. Provide concise, helpful responses."
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)
            
            guard let content = response.content.first?.text else {
                throw LLMError.invalidResponse
            }
            
            return content
        } catch {
            throw LLMError.networkError(error.localizedDescription)
        }
    }
    
    private func callLocal(prompt: String, imagePath: String? = nil) async throws -> String {
        let url = URL(string: "http://localhost:11434/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // For local models, include a note about the image since not all support vision
        var fullPrompt = prompt
        if let imagePath = imagePath {
            fullPrompt = "\(prompt)\n\n[Note: User provided a screenshot image, but local model may not support vision. Image path: \(imagePath)]"
        }
        
        let body = OllamaRequest(
            model: model,
            prompt: fullPrompt,
            stream: false,
            options: OllamaOptions(
                num_ctx: 4096,
                temperature: 0.7
            )
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OllamaResponse.self, from: data)
            
            return response.response
        } catch {
            throw LLMError.networkError(error.localizedDescription)
        }
    }
}

// MARK: - OpenAI Models

struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let max_tokens: Int
    let temperature: Double
}

struct OpenAIMessage: Codable {
    let role: String
    let content: [OpenAIMessageContent]
}

struct OpenAIMessageContent: Codable {
    let type: String
    let text: String?
    let image_url: OpenAIImageURL?
    
    init(type: String, text: String? = nil, image_url: OpenAIImageURL? = nil) {
        self.type = type
        self.text = text
        self.image_url = image_url
    }
}

struct OpenAIImageURL: Codable {
    let url: String
}

struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

// MARK: - Anthropic Models

struct AnthropicRequest: Codable {
    let model: String
    let max_tokens: Int
    let messages: [AnthropicMessage]
    let system: String
}

struct AnthropicMessage: Codable {
    let role: String
    let content: [AnthropicMessageContent]
}

struct AnthropicMessageContent: Codable {
    let type: String
    let text: String?
    let source: AnthropicImageSource?
    
    init(type: String, text: String? = nil, source: AnthropicImageSource? = nil) {
        self.type = type
        self.text = text
        self.source = source
    }
}

struct AnthropicImageSource: Codable {
    let type: String
    let media_type: String
    let data: String
}

struct AnthropicResponse: Codable {
    let content: [AnthropicContent]
}

struct AnthropicContent: Codable {
    let text: String
}

// MARK: - Ollama Models

struct OllamaRequest: Codable {
    let model: String
    let prompt: String
    let stream: Bool
    let options: OllamaOptions
}

struct OllamaOptions: Codable {
    let num_ctx: Int
    let temperature: Double
}

struct OllamaResponse: Codable {
    let response: String
} 