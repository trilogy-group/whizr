import SwiftUI
import Foundation
import os.log

/// Generates context-aware prompts for LLM based on detected application context
class ContextPromptGenerator: ObservableObject {
    private let logger = Logger(subsystem: "com.whizr.Whizr", category: "PromptGenerator")
    
    /// Generate a context-aware prompt based on the detected context
    func generatePrompt(
        userInput: String,
        contextInfo: ContextInfo,
        selectedText: String,
        clipboardText: String?,
        includeClipboard: Bool
    ) -> String {
        
        logger.info("🎭 Starting prompt generation...")
        logger.info("📝 User input: '\(userInput, privacy: .public)'")
        logger.info("📱 Application: \(contextInfo.applicationName, privacy: .public) (\(contextInfo.applicationType.description, privacy: .public))")
        logger.info("🎯 Context type: \(contextInfo.contextType.description, privacy: .public)")
        logger.info("💻 Programming language: \(contextInfo.programmingLanguage, privacy: .public)")
        logger.info("📄 Selected text: \(selectedText.count, privacy: .public) chars")
        
        // Build context parts
        var contextParts: [String] = []
        
        // Add application context
        contextParts.append("Application: \(contextInfo.applicationName) (\(contextInfo.applicationType.description))")
        
        // Add context type
        contextParts.append("Context: \(contextInfo.contextType.description)")
        
        // Add primary text (focused field content) and context text separately
        if !contextInfo.primaryText.isEmpty {
            contextParts.append("Current Field Content (\(contextInfo.primaryTextSource)): \(contextInfo.primaryText)")
            logger.info("✅ Added primary text to context")
        }
        
        if !contextInfo.contextText.isEmpty {
            contextParts.append("Background Context (\(contextInfo.contextTextSource)): \(contextInfo.contextText)")
            logger.info("✅ Added context text for background understanding")
        }
        
        // Fallback to legacy selectedText if new fields aren't populated
        if contextInfo.primaryText.isEmpty && contextInfo.contextText.isEmpty && !selectedText.isEmpty {
            contextParts.append("Selected Text: \(selectedText)")
            logger.info("✅ Added legacy selected text to context")
        }
        
        // Add programming language if detected
        if contextInfo.programmingLanguage != "Unknown" {
            contextParts.append("Programming Language: \(contextInfo.programmingLanguage)")
            logger.info("✅ Added programming language to context")
        }
        
        let context = contextParts.joined(separator: "\n")
        
        // Generate intelligent system prompt that delegates intent analysis to the LLM
        let systemPrompt = generateIntelligentSystemPrompt(
            contextType: contextInfo.contextType,
            applicationType: contextInfo.applicationType,
            programmingLanguage: contextInfo.programmingLanguage
        )
        
        let fullPrompt = """
        \(systemPrompt)

        User Request: \(userInput)
        
        Context:
        \(context)
        
        \(generateContextualInstructions(contextType: contextInfo.contextType))
        """
        
        logger.info("✅ Final prompt generated (\(fullPrompt.count, privacy: .public) chars)")
        logger.info("🎭 Prompt preview:")
        logger.info("   System: \(systemPrompt.prefix(100), privacy: .public)...")
        logger.info("   Context parts: \(contextParts.count, privacy: .public)")
        logger.info("   Full length: \(fullPrompt.count, privacy: .public) characters")
        
        return fullPrompt
    }
    
    /// Generate intelligent system prompt that delegates intent analysis to the LLM
    private func generateIntelligentSystemPrompt(
        contextType: ContextType,
        applicationType: ApplicationType,
        programmingLanguage: String
    ) -> String {
        let contextRole = getContextRole(contextType, applicationType, programmingLanguage)
        
        return """
        You are Whizr, an AI writing assistant. \(contextRole)

        CRITICAL INSTRUCTIONS:

        1. FIRST, analyze the user's intent from their request:
           - QUESTION: They're asking for information, clarification, or your identity
           - COMMAND: They want you to execute a task (create, list, run, etc.)
           - CONTINUATION: They want you to continue or expand existing content
           - IMPROVEMENT: They want you to fix, enhance, or refactor existing content
           - CREATION: They want you to write something new from scratch
           
        2. THEN, respond based on their intent:
           
           FOR QUESTIONS:
           - Answer directly and helpfully
           - If they ask "what is your name?" → "I'm Whizr, your AI writing assistant"
           - Use context to understand situation but focus on answering their question
           - Be conversational but match the application's formality level
           
           FOR COMMANDS:
           - Execute exactly what they requested
           - For terminal: return ONLY the command, no explanations
           - For code: return ONLY the code needed
           - For text: provide the requested content directly
           
           FOR CONTINUATION:
           - Continue the "Current Field Content" seamlessly
           - Match existing tone, style, and format perfectly
           - Use "Background Context" only for understanding
           
           FOR IMPROVEMENT:
           - Enhance the "Current Field Content" per their request
           - Fix issues while maintaining original intent
           - Return the complete improved version
           
           FOR CREATION:
           - Create new content as requested
           - Make it appropriate for the current application context
           - Provide complete, ready-to-use content

        3. CONTEXT GUIDANCE:
           - "Current Field Content" = where your output will be inserted (primary focus)
           - "Background Context" = additional info for understanding (supporting info)
           - Programming Language = use appropriate syntax and conventions
           - Application = match the expected style and format

        4. ABSOLUTE RULES:
           - NEVER ask for clarification or more information
           - NEVER ask the user to choose between options
           - NEVER say things like "Would you like me to..." or "Should I..."
           - ALWAYS take action based on your best understanding of the request
           - User intent ALWAYS takes priority over context patterns
           - If the user request is clear, execute it regardless of current context
           - Be helpful and direct, not robotic
           - Match the application's expected output format
           
        5. PRIORITY ORDER:
           - User's explicit request is ALWAYS the highest priority
           - Context is secondary - it helps you understand HOW to fulfill the request
           - If user says "write X", write X, don't ask about the context
           - If user gives a clear instruction, follow it immediately
        """
    }
    
    /// Get appropriate role description for the context
    private func getContextRole(_ contextType: ContextType, _ applicationType: ApplicationType, _ programmingLanguage: String) -> String {
        switch contextType {
        case .terminalCommand:
            return "You're currently helping in a terminal/command-line environment."
        case .emailComposition, .emailReply:
            return "You're currently helping with email composition."
        case .codeWriting:
            let lang = programmingLanguage != "Unknown" ? " (specifically \(programmingLanguage))" : ""
            return "You're currently helping with code writing\(lang)."
        case .codeComment:
            return "You're currently helping with code documentation."
        case .casualMessage:
            return "You're currently helping with casual messaging."
        case .documentWriting:
            return "You're currently helping with document writing."
        case .formFilling:
            return "You're currently helping with form completion."
        case .webSearch:
            return "You're currently helping with web search."
        case .webForm:
            return "You're currently helping with web form completion."
        case .generalText:
            return "You're currently helping with text writing."
        }
    }
    
    /// Generate context-specific instructions and examples
    private func generateContextualInstructions(contextType: ContextType) -> String {
        switch contextType {
        case .terminalCommand:
            return """
            TERMINAL CONTEXT NOTES:
            - For commands: Return ONLY the executable command (e.g., "ls -la", not "Here's the command: ls -la")
            - Be precise and safe with command flags
            - Assume macOS unless specified otherwise
            
            Examples of good responses:
            - User: "list files" → "ls -la"
            - User: "what is ls?" → "ls is a command that lists directory contents. The -l flag shows detailed info."
            - User: "continue this script" → [continue the script in Current Field Content]
            - User: "write a message to Mari saying I love her" → "echo 'I love you, Mari!'"
            """
            
        case .codeWriting:
            return """
            CODE CONTEXT NOTES:
            - Return clean, executable code without explanations (unless asked)
            - Use proper indentation and formatting
            - Follow language-specific best practices
            - Include imports only if the current field needs them
            
            Examples of good responses:
            - User: "create a function" → [write the function code]
            - User: "what does this do?" → [explain the Current Field Content]
            - User: "fix this bug" → [return corrected version of Current Field Content]
            - User: "write a message to Mari saying I love her" → // I love you, Mari!
            """
            
        case .emailComposition, .emailReply:
            return """
            EMAIL CONTEXT NOTES:
            - Match professional or casual tone as appropriate
            - Include proper email structure for new emails
            - For replies, maintain conversation tone
            - Be concise but complete
            
            Examples of good responses:
            - User: "write a message to Mari saying I love her" → "Dear Mari,\n\nI love you.\n\nWith all my heart,"
            """
            
        case .documentWriting:
            return """
            DOCUMENT CONTEXT NOTES:
            - Use appropriate formal language
            - Structure content clearly
            - Maintain consistency in style
            - Focus on clarity and readability
            
            Examples of good responses:
            - User: "write a message to Mari saying I love her" → "I love you, Mari."
            - User: "add a paragraph about X" → [write the paragraph about X]
            """
            
        case .generalText:
            return """
            TEXT CONTEXT NOTES:
            - ALWAYS execute the user's request directly
            - NEVER ask where to place content or what to do with existing content
            - If user wants something written, write it immediately
            - Existing content is just context, not a constraint
            
            Examples of good responses:
            - User: "write a message to Mari saying I love her" → "I love you, Mari! ❤️"
            - User: "continue this" → [continue the existing content naturally]
            - User: "make this better" → [improve the existing content]
            
            BAD responses to avoid:
            - "Would you like me to replace the current content?"
            - "Should I add this at the end?"
            - "I notice you have technical content open..."
            """
            
        default:
            return """
            GENERAL CONTEXT NOTES:
            - Execute user requests immediately and directly
            - NEVER ask for clarification or offer choices
            - Adapt your response style to match the application context
            - Be helpful and direct
            - Focus on what the user actually needs
            
            Examples of good responses:
            - User: "write a message to Mari saying I love her" → "I love you, Mari! ❤️"
            - User: "help me with X" → [provide help with X]
            
            BAD responses to avoid:
            - Any response that asks "Would you like me to..."
            - Any response that offers options instead of taking action
            - Any response that questions where to place content
            """
        }
    }
} 