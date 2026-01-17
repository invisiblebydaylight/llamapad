import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    // bound to the TextEditor
    @State private var inputText: String = ""
    
    // set to true when the configuration should be shown
    // instead of the chatlog
    @State private var showingConfiguration: Bool = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                NavigationBarView(
                    appState: appState,
                    onSettingsTap: {
                        showingConfiguration = true
                    }
                )
                
                ChatLogView(
                    appState: appState)
                
                InputBarView(
                    appState: appState,
                    inputText: $inputText,
                    onSendUserMessage: { message in
                        let newMessage = Message(sender: .user, content: message)
                        appState.messageLog.append(newMessage)
                        Task {
                            await appState.generateChatResponse()
                        }
                    },
                    onGenerateAiResponse: { isContinue in
                        Task {
                            await appState.generateChatResponse(isContinue: isContinue)
                        }
                    }
                )
                
                if appState.llamaContext != nil {
                    if let config = appState.modelConfig {
                        let promptTokens = appState.lastPromptTokenCount
                        let usagePercentage = Double(promptTokens) / Double(config.contextLength) * 100
                        HStack {
                            Spacer()
                            
                            HStack(spacing: 12) {
                                Text("Context used: \(promptTokens)/\(config.contextLength) (\(usagePercentage, specifier: "%.1f")%)")
                            }
                            
                            Spacer()
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.bottom, 8)
                    }
                }
            }
            .blur(radius: appState.isLoadingModel ? 3 : 0)
            .allowsHitTesting(!appState.isLoadingModel)
            .sheet(isPresented: $showingConfiguration) {
                ConfigurationView(appState: appState)
                    .frame(minWidth: 400, minHeight: 600)
            }
            .onAppear {
                // show the config sheet if we don't have a model config loaded
                // but we wait a little bit to try and give AppState a chance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if appState.modelConfig == nil {
                        showingConfiguration = true
                    }
                }
            }
            .alert("Experiencing temporal friction...", isPresented: $appState.showingErrorAlert) {
                Button("OK", role: .cancel) {
                    appState.lastErrorMessage = nil
                }
            } message: {
                Text(appState.lastErrorMessage ?? "An unknown error occurred.")
            }
            
            if appState.isLoadingModel {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading model...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(40)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
            }
        }
    }
}

#Preview {
    ContentView()
}
