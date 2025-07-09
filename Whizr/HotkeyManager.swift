import SwiftUI
import Carbon
import ApplicationServices

class HotkeyManager: ObservableObject {
    @Published var isListening = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private let hotkey = HotkeyDefinition(
        key: kVK_Space,
        modifiers: [.command, .shift]
    )
    
    var onHotkeyPressed: (() -> Void)?
    
    init() {
        setupHotkey()
        
        // Listen for permission changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(permissionsChanged),
            name: .permissionsChanged,
            object: nil
        )
    }
    
    deinit {
        stopListening()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func permissionsChanged() {
        print("🔄 Permissions changed - restarting hotkey listener...")
        
        // Stop current listener
        stopListening()
        
        // Wait a bit then restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupHotkey()
        }
    }
    
    func setupHotkey() {
        guard !isListening else { return }
        
        // Set up the callback for when hotkey is pressed
        onHotkeyPressed = { [weak self] in
            self?.handleHotkeyPress()
        }
        
        startListening()
    }
    
    func restartHotkeyListener() {
        print("🔄 Manually restarting hotkey listener...")
        stopListening()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupHotkey()
        }
    }
    
    private func startListening() {
        print("🔑 Starting hotkey listener...")
        
        // Create event tap for global key monitoring
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            print("❌ Failed to create event tap - Input Monitoring permission likely missing!")
            DispatchQueue.main.async {
                self.isListening = false
            }
            return
        }
        
        print("✅ Event tap created successfully")
        
        // Add to run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource = runLoopSource else {
            print("❌ Failed to create run loop source")
            return
        }
        
        // Use common modes to ensure CGEvents can be processed properly
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the event tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        print("✅ Hotkey manager is now listening for ⌘+Shift+Space")
        
        DispatchQueue.main.async {
            self.isListening = true
        }
    }
    
    private func stopListening() {
        if let eventTap = eventTap, let runLoopSource = runLoopSource {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
            self.runLoopSource = nil
        }
        
        DispatchQueue.main.async {
            self.isListening = false
        }
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
            print("🎯 HOTKEY MATCH! ⌘+Shift+Space detected")
            
            // Call the hotkey handler on a background queue to avoid blocking
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async {
                    self.onHotkeyPressed?()
                }
            }
            
            // Consume the event (don't pass it through)
            return nil
        }
        
        // Pass through all other events
        return Unmanaged.passUnretained(event)
    }
    
    private func checkModifiers(flags: CGEventFlags) -> Bool {
        let requiredFlags: CGEventFlags = [.maskCommand, .maskShift]
        
        // Check if required modifiers are pressed
        let hasRequired = requiredFlags.isSubset(of: flags)
        
        // Check if unwanted modifiers are pressed
        let unwantedFlags: CGEventFlags = [.maskControl, .maskAlternate]
        let hasUnwanted = !unwantedFlags.intersection(flags).isEmpty
        
        return hasRequired && !hasUnwanted
    }
    
    private func handleHotkeyPress() {
        print("Hotkey pressed: ⌘+Shift+Space")
        // This will be connected to the main app logic
        NotificationCenter.default.post(name: .hotkeyPressed, object: nil)
    }
    
    // MARK: - Diagnostics
    
    func getDiagnostics() -> String {
        var diagnostics = "🔍 Whizr Diagnostics:\n"
        diagnostics += "- Event Tap: \(eventTap != nil ? "Active" : "Inactive")\n"
        diagnostics += "- Run Loop Source: \(runLoopSource != nil ? "Active" : "Inactive")\n"
        diagnostics += "- Listening: \(isListening)\n"
        diagnostics += "- Memory Usage: \(String(format: "%.1fMB", Double(MemoryUsage.getUsage()) / 1024 / 1024))\n"
        return diagnostics
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