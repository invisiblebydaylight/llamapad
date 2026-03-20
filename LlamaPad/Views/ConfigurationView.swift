import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationView: View {
    @ObservedObject var appState: AppState
    @EnvironmentObject var voiceContext: VoiceContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var isSysMsgExpanded = false
    @State private var isAdvSamplerExpanded = false
    
    @State private var showingFilePicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    /// draft configuration - all edits happen here
    @StateObject private var draftConfig: AppConfiguration
    
    /// the proxy of the real system message value for this View;
    /// must be synced to the real system message if settings are saved.
    @State private var localSystemMessage: String

    /// keeps track of the token count for the system message text
    @State private var systemMessageTokenCount: Int = 0
    
    init(appState: AppState) {
        self.appState = appState
        
        let baseConfig = appState.modelConfig ?? AppConfiguration()
        _draftConfig = StateObject(wrappedValue: AppConfiguration(baseConfig))
        
        // make sure the state of the system message is setup appropriately
        var initialSystemMessage = ""
        if let id = appState.currentConversationID {
            if let conv = appState.conversations.first(where: { $0.id == id }) {
                initialSystemMessage = conv.systemMessage ?? ""
            }
        }
        _localSystemMessage = .init(initialValue: initialSystemMessage);
    }

    var body: some View {
        NavigationStack {
            TabView {
                ModelConfigTab(appState: appState, draftConfig: draftConfig, showingFilePicker: $showingFilePicker).tabItem {
                    Label("Model", systemImage: "cpu")
                }
                
                SystemMessageConfigTab(appState: appState, systemMessage: $localSystemMessage, tokenCount: $systemMessageTokenCount).tabItem {
                    Label("System", systemImage: "text.badge.plus")
                }
                
                TTSConfigTab(appState: appState, draftConfig: draftConfig, showingError: $showingError, errorMessage: $errorMessage).tabItem {
                    Label("Voice", systemImage: "speaker.wave.3")
                }
            }
            .tabViewStyle(.automatic)
            .padding(.vertical, 8)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        saveConfiguration()
                        dismiss()
                    }) {
                        if appState.isBusy {
                            HStack {
                                Text("Busy...")
                                Image(systemName: "hourglass")
                            }
                        } else {
                            Text("Save Changes")
                        }
                    }
                    .disabled(draftConfig.modelPaths.isEmpty || appState.isBusy)
                    .buttonStyle(.borderedProminent)
                    .help(appState.isBusy ? "Cannot save changes while a model is being used..." : "Save all changes")
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "gguf", conformingTo: .data) ?? .data],
                allowsMultipleSelection: true
            ) { result in
                handleModelSelect(result)
            }
            .alert("Configuration Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveConfiguration() {
        Task {
            let isModelReloadNeeded = draftConfig.requiresReload(comparedTo: appState.modelConfig)
            let isVoiceReloadNeeded = appState.modelConfig == nil ||
                (draftConfig.tts.modelPath != appState.modelConfig!.tts.modelPath) ||
                (draftConfig.tts.voicePath != appState.modelConfig!.tts.voicePath)
            
            appState.modelConfig = AppConfiguration(draftConfig)
            do {
                // save out the configuration and if one of the settings that requires
                // reloading was changed, then we reload the model here as well.
                try PersistenceService.saveConfiguration(draftConfig)
                if isModelReloadNeeded {
                    // here we unload and just let the user load back up when ready
                    await appState.unloadModel()
                } else {
                    await appState.calculatePromptTokenCount()
                }
                
                if appState.modelConfig!.tts.isEnabled == false {
                    voiceContext.unload()
                }
                if isVoiceReloadNeeded {
                    try await voiceContext.load(from: appState.modelConfig!.tts)
                }
                
                // sync our proxied system message String back to the conversation
                // metadata file.
                if let id = appState.currentConversationID {
                    if var conv = appState.getConversation(for: id) {
                        conv.systemMessage = localSystemMessage
                        conv.updatedAt = Date()
                        try appState.updateConversation(id: id, withMeta: conv)
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func handleModelSelect(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // Sort the URLs to ensure the first shard is actually the first in the list
            let sortedUrls = urls.sorted { $0.path < $1.path }
                    
            var modelBookmarks: [Data] = []
            let modelPaths = sortedUrls.compactMap { url in url.path() }
            for url in urls {
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if gotAccess { url.stopAccessingSecurityScopedResource() }
                }
                
                do {
                    // generate our persistent bookmark
                    #if os(macOS)
                    let bookmarkData = try url.bookmarkData(
                        options: .securityScopeAllowOnlyReadAccess,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    #else
                    let bookmarkData = try url.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    #endif
                    modelBookmarks.append(bookmarkData)
                } catch {
                    errorMessage = "Failed to create the bookmark for the model: \(error)"
                    showingError = true
                }
            }
            draftConfig.modelPaths = modelPaths
            draftConfig.modelBookmarks = modelBookmarks
            
        case .failure(let error):
            errorMessage = "File picker error: \(error)"
            showingError = true
        }
    }
}
