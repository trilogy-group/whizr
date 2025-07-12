import SwiftUI
import Carbon
import ApplicationServices
import os.log

class HotkeyManager: ObservableObject {
    @Published var isEnabled = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let hotkey = (key: 49, modifiers: [CGEventFlags.maskCommand, CGEventFlags.maskShift]) // Space key with Cmd+Shift
    private let logger = Logger(subsystem: "com.whizr.Whizr", category: "HotkeyManager")
    
    // Use shared context detector for cached context
    private let contextDetector: ContextDetector
    
    init(contextDetector: ContextDetector) {
        self.contextDetector = contextDetector
        logger.info("🚀 HotkeyManager initialized with shared ContextDetector")
        setupEventTap()
        
        // Auto-start listening if permissions are already available
        if AXIsProcessTrusted() {
            DispatchQueue.main.async {
                self.startListening()
                print("✅ Auto-started hotkey listener on init (permissions already available)")
            }
        } else {
            print("⚠️ Accessibility permissions not available on init - will start when granted")
        }
    }
    
    deinit {
        logger.info("🛑 HotkeyManager deinitialized")
        stopListening()
    }
    
    func startListening() {
        guard let eventTap = eventTap else {
            logger.error("❌ Cannot start listening: eventTap is nil")
            return
        }
        
        logger.info("🎧 Starting hotkey listening...")
        
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        DispatchQueue.main.async {
            self.isEnabled = true
            self.logger.info("✅ Hotkey listening enabled")
        }
    }
    
    func stopListening() {
        logger.info("🛑 Stopping hotkey listening...")
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        
        DispatchQueue.main.async {
            self.isEnabled = false
            self.logger.info("❌ Hotkey listening disabled")
        }
    }
    
    private func setupEventTap() {
        logger.info("🔧 Setting up event tap...")
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) in
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            logger.error("❌ Failed to create event tap")
            return
        }
        
        self.eventTap = eventTap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        
        logger.info("✅ Event tap created successfully")
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // OPTIMIZATION: Only process space key events, ignore all others immediately
        guard keyCode == Int64(hotkey.key) else {
            return Unmanaged.passUnretained(event)
        }
        
        // Check if this matches our hotkey
        if checkModifiers(flags: flags) {
            logger.info("🎯 HOTKEY MATCH! ⌘+Shift+Space detected")
            
            // Get cached context immediately (no extraction during hotkey!)
            let cachedContext = getCachedContextForHotkey()
            
            logger.info("⚡ DEBUG: Using cached context: \(cachedContext != nil ? "VALID" : "NIL", privacy: .public)")
            
            // Call the hotkey handler on a background queue to avoid blocking
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async {
                    // Pass the cached context to the handler
                    self.logger.info("⚡ DEBUG: About to call onHotkeyPressed with cached context")
                    NotificationCenter.default.post(
                        name: .hotkeyPressed,
                        object: cachedContext  // Pass the cached context
                    )
                }
            }
            
            // Consume the event to prevent it from being processed further
            return nil
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    /// Get cached context for hotkey usage (instant!)
    private func getCachedContextForHotkey() -> ContextInfo? {
        logger.info("⚡ Getting cached context for hotkey...")
        
        // Get cached context from shared ContextDetector
        if let cached = contextDetector.getCachedContext() {
            logger.info("✅ Using cached context: \(cached.selectedText.count, privacy: .public) chars from \(cached.applicationName, privacy: .public)")
            return cached
        }
        
        // Fallback: create minimal context if no cache available
        logger.warning("⚠️ No cached context available, creating minimal context")
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        var context = ContextInfo()
        context.applicationName = frontApp.localizedName ?? "Unknown"
        context.applicationType = analyzeApplicationType(context.applicationName)
        context.contextType = analyzeContextType("", appType: context.applicationType)
        context.selectedText = ""
        
        return context
    }
    
    /// Quick application type analysis
    private func analyzeApplicationType(_ appName: String) -> ApplicationType {
        let lowercased = appName.lowercased()
        
        if lowercased.contains("code") || lowercased.contains("xcode") || 
           lowercased.contains("cursor") || lowercased.contains("vim") {
            return .codeEditor
        } else if lowercased.contains("text") || lowercased.contains("edit") {
            return .textEditor
        } else if lowercased.contains("safari") || lowercased.contains("chrome") || 
                  lowercased.contains("firefox") {
            return .browser
        } else if lowercased.contains("terminal") || lowercased.contains("iterm") {
            return .terminal
        }
        
        return .other
    }
    
    /// Quick context type analysis
    private func analyzeContextType(_ text: String, appType: ApplicationType) -> ContextType {
        if appType == .codeEditor {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("//") ||
               text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") ||
               text.contains("/*") {
                return .codeComment
            }
            return .codeWriting
        } else if appType == .terminal {
            return .terminalCommand
        }
        
        return .generalText
    }
    
    private func checkModifiers(flags: CGEventFlags) -> Bool {
        let requiredFlags: CGEventFlags = [.maskCommand, .maskShift]
        let maskedFlags = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        return maskedFlags == requiredFlags
    }
}

// MARK: - Memory Diagnostics Helper

struct MemoryUsage {
    static func getUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }
}

// MARK: - Supporting Types

struct HotkeyDefinition {
    let key: Int
    let modifiers: Set<ModifierKey>
}

enum ModifierKey {
    case command
    case option
    case control
    case shift
}

// MARK: - Notification Names

extension Notification.Name {
    static let hotkeyPressed = Notification.Name("hotkeyPressed")
    static let permissionsChanged = Notification.Name("permissionsChanged")
}

// MARK: - Virtual Key Codes

private let kVK_Space: Int = 0x31 