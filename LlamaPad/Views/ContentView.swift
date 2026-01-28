import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    /// keeps track of the selected conversation's ID
    @State private var selectedConversationID: UUID?

    /// keeps track of the selected conversation's metadata; derived from `selectedConversation`
    @State private var selectedConversationMeta: ConversationMetadata?

    /// bound to the TextEditor inside InputBarView
    @State private var inputText: String = ""
    
    /// set to true when the configuration should be shown
    /// instead of the chatlog
    @State private var showingConfiguration: Bool = false
    
    /// controlls the sidebar visibility
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    /// controls appearance of the conversation delete confirmation dialog
    @State private var isShowingDeleteConfirmation = false
    
    /// used for tracking while the user inputs a new title for a conversation
    @State private var renamedTitle: String = ""
    
    /// whether or not to be trying to rename the selected conversation
    @State private var isShowingRenameAlert = false
    
    /// returns the View for the main set of widgets representing the chatlog
    func mainChatLogView() -> some View {
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
    
    func sidebarView() -> some View {
        List(selection: $selectedConversationID) {
            ForEach(appState.conversations) { convo in
                NavigationLink(value: convo.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(convo.title)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(convo.updatedAt, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu {
                    // only show the context menu for the selected navigation link
                    if convo.id == selectedConversationID {
                        Button {
                            duplicateConversation(convo)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        
                        Button {
                            renamedTitle = convo.title
                            isShowingRenameAlert = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            deleteConversation(convo)
                        } label: {
                            Label("Delete Conversation", systemImage: "trash")
                        }
                    }
                }
            }
            .onDelete(perform: deleteConversations)
        }
        .navigationTitle("Conversations")
        .navigationSplitViewStyle(.prominentDetail)
        .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 450)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createConversation) {
                    Label("New Conversation", systemImage: "plus.circle")
                }
            }
        }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView()
                .disabled(appState.isBusy)
                .opacity(appState.isBusy ? 0.3 : 1.0)
        } detail: {
            if selectedConversationID != nil {
                mainChatLogView()
            } else {
                ContentUnavailableView(
                    "Select a Discourse",
                    systemImage: "moon.stars",
                    description: Text("Choose an existing conversation from the sidebar or start a new one.")
                )
            }
        }
        .onChange(of: selectedConversationID) { oldID, newID in
            appState.selectConversation(newID)
            if let id = newID, let convo = appState.getConversation(for: id) {
                selectedConversationMeta = convo
            }
        }
        .onAppear() {
            selectedConversationID = appState.currentConversationID
            if let id = selectedConversationID, let convo = appState.getConversation(for: id) {
                selectedConversationMeta = convo
            }
        }
        .confirmationDialog("Delete this conversation?", isPresented: $isShowingDeleteConfirmation) {
            let title = selectedConversationMeta?.title ?? "Unknown Discourse"
            let abbrevTitle: String = String(title.prefix(17))
            Button("Delete conversation: \"\(abbrevTitle)...\"?", role: .destructive) {
                do {
                    if let meta = selectedConversationMeta {
                        try appState.deleteConversation(for: meta.id)
                    }
                    selectedConversationID = nil
                    selectedConversationMeta = nil
                    isShowingDeleteConfirmation = false;
                } catch {
                    appState.reportError("Was unable to delete the conversation: \"\(abbrevTitle)...\"")
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently erase all files related to this conversation and cannot be undone.")
        }
        .alert("Rename Conversation", isPresented: $isShowingRenameAlert, presenting: selectedConversationMeta) { convo in
            TextField("Title", text: $renamedTitle)
            Button("OK") {
                appState.renameConversation(convo.id, to: renamedTitle)
                selectedConversationMeta = appState.getConversation(for: convo.id)
                selectedConversationID = convo.id
            }
            Button("Cancel", role: .cancel) { }
        }

    }
    
    private func createConversation() {
        do {
            let newMeta = try appState.createConversation()
            selectedConversationID = newMeta.id
            selectedConversationMeta = newMeta
        } catch {
            appState.reportError("Failed to create a new conversation: \(error.localizedDescription)")
        }
    }
    
    private func deleteConversations(at offsets: IndexSet) {
        isShowingDeleteConfirmation = true
    }
        
    private func deleteConversation(_ convo: ConversationMetadata) {
        isShowingDeleteConfirmation = true
    }
    
    private func duplicateConversation(_ convo: ConversationMetadata) {
        do {
            if let dupe = try appState.duplicateConversation(for: convo.id) {
                // ensure that we select everything with the new duplicate
                appState.currentConversationID = dupe.id
                selectedConversationID = dupe.id
                selectedConversationMeta = dupe
            }
        } catch {
            appState.reportError("Failed to duplicate the conversation: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
}
