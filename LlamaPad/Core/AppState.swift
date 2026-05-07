import Foundation
import Combine
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var backend: InferenceBackend?

    @Published var isBackendLoading: Bool = false

    @Published var modelConfig: AppConfiguration?
    
    /// the loaded conversations the app is tracking
    @Published var conversations: [ConversationMetadata] = []
    
    /// if present, indicates that the conversation matching that id is 'selected' in the application
    @Published var currentConversationID: UUID?
    
    /// main storage for all of the messages in the log
    @Published var messageLog: [Message] = []
    
    /// will be set to true if the app is generating text with AI
    @Published var isGenerating = false
    
    /// set this to true to request the generation loop to stop
    @Published var shouldStopGenerating = false
    
    /// the last error message reported by the user
    @Published var lastErrorMessage: String?
    
    /// whether or not to show the error alert with the lastErrorMessage text
    @Published var showingErrorAlert = false
    
    /// used to track the processing status for the app (like prompt ingestion); 0.0..1.0 range.
    @Published var processingProgress: Double? = nil
    
    /// describes the current processing task (e.g. "Processing Prompt...")
    @Published var processingStatus: String? = nil  

    /// a callback that gets called on completion, if supplied, with the new message that was generated.
    /// this callback is skipped if the generation is cancled by the user with `shouldStopGenerating`
    var onGenerationFinished: ((Message) -> Void)?
    
    /// returns `true` if the app is currently performing a long, heavy action
    /// like loading a model or generating a reply - something that should not be interrupted.
    var isBusy: Bool {
        return isGenerating || isBackendLoading
    }
    
    init() {
        // start off by loading the configuration file first, if it exists
        do {
            modelConfig = try PersistenceService.loadConfiguration()
        } catch PersistenceError.fileNotFound {
            // ignore this and don't report it; it'll freak out first time users
        }
        catch {
            reportError("Configuration error: \(error.localizedDescription)")
        }
        
        // next we refresh the conversation list and select the last one as activated
        do {
            conversations = try ConversationService.listConversations()
            if let lastConvo = conversations.first {
                selectConversation(lastConvo.id)
            } else {
                let newConvo = try ConversationService.createConversation(title: "Untitled")
                conversations.append(newConvo)
                currentConversationID = newConvo.id
                selectConversation(newConvo.id)
            }
        } catch {
            reportError("Conversations error: \(error.localizedDescription)")
        }
    }
    
    // a helper to trigger the UI alerts
    func reportError(_ message: String) {
        self.lastErrorMessage = message
        self.showingErrorAlert = true
    }
    
    // updates the inernal processing progress of a long operation (e.g. prompt processing)
    func reportProcessStatus(progress: Double?, status: String?) {
        guard self.processingProgress != progress || self.processingStatus != status else { return }
        self.processingProgress = progress
        self.processingStatus = status
    }
    
    /// unloads any loaded model and then reloads the model specified in the configuration
    func reloadModel() async {
        guard let config = modelConfig else {
            reportError("No configuration loaded, unable to reload model.")
            return
        }
        
        self.isBackendLoading = true
        defer { self.isBackendLoading = false }
        
        // bury the old backend if one exists
        if let old = backend {
            await old.unload()
            self.backend = nil
        }

        // spawn the correct concrete backend
        let newBackend: InferenceBackend = if config.backendType == .llamaCPP {
            LlamaBackend()
        } else {
            MLXBackend()
        }
        
        do {
            try await newBackend.load(from: config)
            self.backend = newBackend
        } catch {
            self.backend = nil
            reportError("Loading error: \(error.localizedDescription)")
        }
    }
    
    /// unloads the current backend's model if any and drops the backend implementation
    func unloadModel() async {
        await backend?.unload()
        self.backend = nil
        self.isBackendLoading = false
    }
    
    /// removes all the messages in the `messageLog` and resets the prompt token counter on a background Task
    func removeAllMessages() {
        messageLog.removeAll()
    }
    
    /// removes a specific message in the `messageLog` that matches the `id` passed in
    func removeMessage(id: UUID) {
        messageLog.removeAll(where: { $0.id == id })
    }
    
    /// Removes the specified message and every message that follows it in the log.
    func purgeMessages(from id: UUID) {
        if let index = messageLog.firstIndex(where: { $0.id == id }) {
            messageLog.removeSubrange(index...)
        }
    }
    
    func selectConversation(_ id: UUID?) {
        self.currentConversationID = id
        self.messageLog = []

        // load the new conversation's chat log
        if let id = id {
            do {
                let newLog = try ConversationService.loadChatLog(for: id)
                self.messageLog = newLog
            } catch {
                self.reportError("selectConversation: Faled to load the chatlog for conversation \(id): \(error.localizedDescription)")
            }
        }
    }
    
    /// duplicates the conversation and then inserts it into the runtime `conversations` list
    func duplicateConversation(for id: UUID) throws -> ConversationMetadata? {
        do {
            let dupe = try ConversationService.duplicateConversation(id: id)
            conversations.insert(dupe, at: 0)
            currentConversationID = dupe.id
            return dupe
        } catch {
            reportError("Failed to duplicate convesration \(id): \(error.localizedDescription)")
        }
        return nil
    }
    
    func deleteConversation(for id: UUID) throws {
        try ConversationService.deleteConversation(id: id)
        conversations.removeAll(where: { $0.id == id })
        if currentConversationID == id {
            removeAllMessages()
            currentConversationID = nil
        }
    }
    
    func createConversation() throws -> ConversationMetadata {
        let newMeta = try ConversationService.createConversation(title: "New Discourse")
        conversations.insert(newMeta, at: 0)
        return newMeta
    }
    
    /// returns the first instance of a ConversationMetadata that matches the `id` passed in, `nil` if missing
    func getConversation(for id: UUID?) -> ConversationMetadata? {
        guard let id else { return nil }
        return self.conversations.first(where: {$0.id == id})
    }
    
    /// renames the conversation and saves the metadata out to file as well
    func renameConversation(_ id: UUID, to newTitle: String) {
        do {
            try ConversationService.setTitle(for: id, newTitle: newTitle)
            if let i = conversations.firstIndex(where: { $0.id == id}) {
                var conv = conversations[i]
                conv.title = newTitle
                conv.updatedAt = Date()
                conversations[i] = conv
            }
        } catch {
            reportError("Failed to rename: \(error.localizedDescription)")
        }
    }
    
    /// updates the first existing conversation that matches the id with the instance provided
    /// and saves the metadata file
    func updateConversation(id: UUID, withMeta: ConversationMetadata) throws {
        if let i = conversations.firstIndex(where: { $0.id == id}) {
            conversations[i] = withMeta
        }
        try ConversationService.saveMetadata(withMeta)
    }
    
    /// moves the specified conversation to the top of the list (note: updatedAt time not flushed to file system)
    func touchConversation(id: UUID) {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            var updated = conversations.remove(at: index)
            updated.updatedAt = Date()
            conversations.insert(updated, at: 0)
        }
    }
        
    /// Explicitly persists the current message log to disk.
    func saveChatLog() {
        do {
            if let currentID = currentConversationID {
                try ConversationService.saveChatLog(messageLog, for: currentID)
            }
        } catch {
            reportError("Warning: Failed to save chat log: \(error.localizedDescription)")
        }
    }
    
    private func validateModelPath(_ path: String) -> Bool {
#if os(iOS)
        // On iOS, ensure file exists in our sandbox
        return FileManager.default.fileExists(atPath: path)
#else
        // On macOS, check access more thoroughly
        return FileManager.default.isReadableFile(atPath: path)
#endif
    }
    
    func generateChatResponse(isContinue: Bool = false) async {
        // if no backend, load one
        if backend == nil { await reloadModel() }
        guard let backend else {
            reportError("Error: Failed to load the language model. Double check your configuration.")
            return
        }
        guard let modelConfig = modelConfig else {
            reportError("Error: Application configuration is not loaded yet so a response cannot be generated.")
            return
        }

        // set the generation control flags appropriately and defer the reset of
        // the generation control flags to their default state
        let thisConversationID = currentConversationID
        self.isGenerating = true
        self.shouldStopGenerating = false
        defer {
            self.isGenerating = false
            self.shouldStopGenerating = false
            reportProcessStatus(progress: nil, status: nil)
        }
        
        let aiMessage: Message
        if isContinue, let last = messageLog.last {
            // if we're continuing we don't append a new message
            aiMessage = last
        } else {
            aiMessage = Message(sender: .ai, content:  "")
            self.messageLog.append(aiMessage)
        }
        
        // initialize completion
        var actualTokensProcessed: Int = 0
        let t_start = DispatchTime.now().uptimeNanoseconds

        let currentConversation = getConversation(for: currentConversationID)
        var generatedTokens = 0
        var timeToFirstToken: UInt64 = 0
        do {
            let stream = try await backend.generate(
                messages: messageLog,
                systemMessage: currentConversation?.systemMessage,
                isContinuation: isContinue,
                maxTokens: modelConfig.maxGenerationLength
            )
                        
            // generate tokens and update UI incrementally
            self.reportProcessStatus(progress: nil, status: nil)
            
            var reportedProgress = 0.0
            for try await chunk in stream {
                // if something has set our 'shouldStopGenerating' flag, this will be the
                // point at which we bail out of the prediction stream. upstream (hah!)
                // code has to catch the termination and cancel the task to truly stop it.
                if shouldStopGenerating {
                    break;
                }
                
                if chunk.isPromptProcessing {
                    actualTokensProcessed = chunk.tokensDecoded
                    reportedProgress = chunk.promptProgress
                    self.reportProcessStatus(progress: reportedProgress,
                                             status: "Processing prompt...")
                } else {
                    if !chunk.text.isEmpty {
                        aiMessage.content.append(chunk.text)
                        generatedTokens = chunk.tokensGenerated
                    
                        // do some special tracking for the first token
                        if generatedTokens == 1 {
                            self.reportProcessStatus(progress: 1.0, status: nil)
                            reportedProgress = 1.0
                            timeToFirstToken = DispatchTime.now().uptimeNanoseconds
                        }
                    }

                    // for the MLX backend, we sometimes send blank strings
                    // with updated counts that aren't 0
                    if chunk.tokensDecoded > 0 {
                        actualTokensProcessed = chunk.tokensDecoded
                    }
                }
            }
        } catch {
            reportError("Error generating response: \(error.localizedDescription)")
            return
        }

        // print statistics
        let t_heat = Double(Int64(timeToFirstToken) - Int64(t_start)) / NS_PER_S
        let t_end = DispatchTime.now().uptimeNanoseconds
        let t_generation = Double(t_end - timeToFirstToken) / NS_PER_S
        let prompt_tps = Double(actualTokensProcessed) / t_heat
        let generation_tps = Double(generatedTokens-1) / t_generation
        
        // record the performance stats in the message
        let modelName = modelConfig.modelPaths.last?.split(separator: "/").last.map(String.init) ?? "unknown"
        aiMessage.stats = MessageStats(
            modelName: modelName, promptTps: prompt_tps, generationTps: generation_tps
        )
        
        print("Info: Generation complete (\(modelName)):")
        print("  Time to first token: \(t_heat)s")
        print("  Prompt speeds: \(actualTokensProcessed) new tokens ; \(prompt_tps) t/s")
        print("  Generation speeds: \(generatedTokens) tokens ; \(generation_tps) t/s")
        
        // make sure to serialize as the final step so nothing's lost
        saveChatLog()
        if let id = thisConversationID {
            touchConversation(id: id)
        }
        
        // call the callback, but only if we didn't cancel it
        if !self.shouldStopGenerating {
            self.onGenerationFinished?(aiMessage)
        }
    }
}
