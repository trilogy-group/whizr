import SwiftUI

@main
struct WhizrApp: App {
    @StateObject private var hotkeyManager = HotkeyManager()
    @StateObject private var llmClient = LLMClient()
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var preferencesManager = PreferencesManager()
    @StateObject private var contextDetector = ContextDetector()
    @StateObject private var textInjector = TextInjector()
    @StateObject private var popupManager = PopupWindowManager()
    
    var body: some Scene {
        MenuBarExtra("Whizr", image: "MenuBarIcon") {
            ContentView()
                .environmentObject(hotkeyManager)
                .environmentObject(llmClient)
                .environmentObject(permissionManager)
                .environmentObject(preferencesManager)
                .environmentObject(contextDetector)
                .environmentObject(textInjector)
                .environmentObject(popupManager)
        }
        .menuBarExtraStyle(.window)
    }
} 