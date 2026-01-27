import SwiftUI

@main
struct MainApp: App {
    @StateObject var appState = AppState()
    @ApplicationDelegateAdaptor(LlamaPadAppDelegate.self) var appDelegate

    init() {
        // NOTE: this disables bfloat16 to avoid the Metal 4 / M5 compiler crash
        // See also:
        // https://github.com/mybigday/llama.rn/issues/263
        // https://github.com/ggml-org/llama.cpp/pull/16634
        setenv("GGML_METAL_BF16_DISABLE", "1", 1)

        initializeLlamaCppBackend()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    appDelegate.appState = appState
                }
        }
    }
}
