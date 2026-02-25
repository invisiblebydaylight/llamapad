import SwiftUI

@main
struct MainApp: App {
    @StateObject var appState = AppState()
    @StateObject var voiceContext = VoiceContext()
    
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
                .environmentObject(voiceContext)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    appDelegate.appState = appState
                    
                    // we setup our callback for newly generated messages here to avoid
                    // coupling AppState any further.
                    appState.onGenerationFinished = { message in
                        if let config = appState.modelConfig, config.tts.autoPlayEnabled, config.tts.isEnabled {
                            Task {
                                try? await voiceContext.speak(
                                    text: message.parsedContent.responseContent,
                                    config: config.tts,
                                    messageId: message.id
                                )
                            }
                        }
                    }
                }
        }
    }
}
