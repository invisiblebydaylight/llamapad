import SwiftUI
import MLX

@main
struct MainApp: App {
    @StateObject var appState = AppState()
    @StateObject var voiceContext = VoiceContext()
    
    @ApplicationDelegateAdaptor(LlamaPadAppDelegate.self) var appDelegate

    init() {
        // put a leash on the MLX cache as it has a tendency
        // to run wild and allow the app to OOM and crash.
        Memory.cacheLimit = 100 * 1024 * 1024
 
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
                                // FIXME: broke TTS
                                try? await voiceContext.speak(
                                    text: message.parsedContent.responseContent,
                                    messageId: message.id,
                                    config: config.tts
                                )
                            }
                        }
                    }
                }
        }
    }
}
