import Foundation
import Combine
import SwiftUI

@MainActor
class AppState: ObservableObject {
    /// this should be set to the URL used to load the model and used to
    /// track security access for it.
    private var currentModelURL: URL?
    
    @Published var modelConfig: ModelConfiguration?
    
    /// the loaded conversations the app is tracking
    @Published var conversations: [ConversationMetadata] = []
    
    /// if present, indicates that the conversation matching that id is 'selected' in the application
    @Published var currentConversationID: UUID?
    
    /// main storage for all of the messages in the log
    @Published var messageLog: [Message] = []
    
    /// tracks the first message to be included in the prompt allowing some maintenance
    /// of KV cache stability so that constant prompt ingestion doesn't have to happen.
    @Published var contextAnchorID: UUID?
    
    /// keeps track of the loaded LLM and its context
    @Published var llamaContext: LlamaContext?
    
    /// this should be set to true while waiting to load the model
    @Published var isLoadingModel = false
    
    /// will be set to true if the app is generating text with AI
    @Published var isGenerating = false
    
    /// set this to true to request the generation loop to stop
    @Published var shouldStopGenerating = false
    
    /// the last error message reported by the user
    @Published var lastErrorMessage: String?
    
    /// whether or not to show the error alert with the lastErrorMessage text
    @Published var showingErrorAlert = false
    
    /// saves the token count of the last prompt used to generate a response
    @Published var lastPromptTokenCount: Int = 0
    
    /// used to track the processing status for the app (like prompt ingestion); 0.0..1.0 range.
    @Published var processingProgress: Double? = nil
    
    /// describes the current processing task (e.g. "Processing Prompt...")
    @Published var processingStatus: String? = nil
    
    /// returns `true` if the app is currently performing a long, heavy action
    /// like loading a model or generating a reply - something that should not be interrupted.
    var isBusy: Bool {
        return isGenerating || isLoadingModel
    }
    
    init() {
        // start off by loading the configuration file first, if it exists
        do {
            modelConfig = try PersistenceService.loadConfiguration()
            if modelConfig != nil {
                Task {
                    await reloadModel()
                }
            }
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
        self.processingProgress = progress
        self.processingStatus = status
    }
    
    /// unloads any loaded model and then reloads the model specified in the configuration
    func reloadModel() async {
        await unloadModel()
        await loadModelFromConfiguration()
        Task {
            await calculatePromptTokenCount()
        }
    }
    
    /// removes all the messages in the `messageLog` and resets the prompt token counter on a background Task
    func removeAllMessages() {
        messageLog.removeAll()
        Task {
            await calculatePromptTokenCount()
        }
    }
    
    /// removes a specific message in the `messageLog` that matches the `id` passed in
    func removeMessage(id: UUID) {
        messageLog.removeAll(where: { $0.id == id })
        Task {
            await calculatePromptTokenCount()
        }
    }
    
    /// Removes the specified message and every message that follows it in the log.
    func purgeMessages(from id: UUID) {
        if let index = messageLog.firstIndex(where: { $0.id == id }) {
            messageLog.removeSubrange(index...)
            Task {
                await calculatePromptTokenCount()
            }
        }
    }
    
    func selectConversation(_ id: UUID?) {
        self.currentConversationID = id
        self.contextAnchorID = nil
        self.messageLog = []
        
        // load the new conversation's chat log
        if let id = id {
            do {
                let newLog = try ConversationService.loadChatLog(for: id)
                self.messageLog = newLog
                Task {
                    await self.calculatePromptTokenCount()
                }
            } catch {
                self.reportError("selectConversation: Faled to load the chatlog for conversation \(id): \(error.localizedDescription)")
                return
            }
        }
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
    func getConversation(for id: UUID) -> ConversationMetadata? {
        return self.conversations.first(where: {$0.id == id})
    }
    
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
    
    /// moves the specified conversation to the top of the list (note: updatedAt time not flushed to file system)
    func touchConversation(id: UUID) {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            var updated = conversations.remove(at: index)
            updated.updatedAt = Date()
            conversations.insert(updated, at: 0)
        }
    }
    
    /// if we can build a prompt, then calculate the tokens used for it; if we can't build a prompt, there's no change.
    func calculatePromptTokenCount() async {
        if let config = modelConfig {
            if config.maxGenerationLength != 0 {
                await llamaContext?.setNumberToPredict(config.maxGenerationLength)
            } else {
                await llamaContext?.setNumberToPredict(config.reservedContextBuffer)
            }
        }
        
        let prompt = await buildPrompt(isContinue:false)
        if let prompt {
            self.lastPromptTokenCount = await llamaContext?.tokenize(text: prompt, addBOS: false).count ?? 0
        }
    }
    
    private func loadModelFromConfiguration() async {
        guard let config = modelConfig else {
            reportError("Error: No configuration available; hit that gear icon and setup the app.")
            return
        }
        guard !config.modelPath.isEmpty else {
            reportError("Error: No model path configured; make sure to setup the configuration.")
            return
        }
        
        isLoadingModel = true
        defer { isLoadingModel = false }
        
        // attempt to use the stored security scoped bookmark if one
        // was aquired for this model file when building the new
        // URL to access.
        var modelURL: URL
        if let bookmarkData = config.modelBookmark {
            // Resolve the bookmark
            var isStale = false
            do {
                let options = URL.BookmarkResolutionOptions()
                modelURL = try URL(resolvingBookmarkData: bookmarkData,
                                   options: options,
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &isStale)
                
                if isStale {
                    // create a fresh bookmark from the resolved URL
                    let freshBookmark = try modelURL.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    config.modelBookmark = freshBookmark
                    try PersistenceService.saveConfiguration(config)
                    print("Info: Bookmark refreshed and saved successfully.")
                }
                
                if modelURL.startAccessingSecurityScopedResource() {
                    currentModelURL = modelURL
                }
            } catch {
                reportError("Resource access failed: \(error.localizedDescription)")
                return
            }
        } else {
            modelURL = URL(fileURLWithPath: config.modelPath)
        }
        
        // do the actual model loading
        print("Loading model: \(modelURL.path)\n")
        do {
            llamaContext = try await LlamaContext.createContext(
                path: modelURL.path,
                offloadCount: Int32(config.layerCountToOffload),
                contextLength: UInt32(config.contextLength),
                samplerSettings: config.customSampler)
            print("Info: Model loading complete.\n")
        } catch {
            reportError("Error: failed to load model file \(modelURL.path()): \(error.localizedDescription)")
        }
        
    }
    
    func unloadModel() async {
        await self.llamaContext?.unload()
        self.llamaContext = nil
        
        currentModelURL?.stopAccessingSecurityScopedResource()
        currentModelURL = nil
        
        print("Info: Model unloaded and security scope released.")
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
    
    /// builds the prompt for text generation based off the loaded model, the configuration and the messages.
    /// if it's unable to build a prompt, `nil` is returned
    private func buildPrompt(isContinue: Bool) async -> String? {
        guard let config = modelConfig else {
            return nil
        }
        guard let llamaContext else {
            return nil
        }
        
        // prepare messages (remove thinking blocks, filter by context) and
        // transform it into a Sendable tuple
        let processedMessages = await prepareMessagesForPrompt()
        
        do {
            return try await llamaContext.formatPrompt(
                messages: processedMessages,
                systemMessage: config.systemMessage,
                template: config.chatTemplate,
                isContinue: isContinue)
        } catch {
            return nil
        }
    }
    
    // generates an AI response based on the current message log using the embedded model formatting
    func generateChatResponse(isContinue: Bool = false) async {
        guard let llamaContext else {
            reportError("Error: Model not loaded and it really should be at this point... Interesting.")
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
        
        await llamaContext.setNumberToPredict(modelConfig!.maxGenerationLength)
        
        // build out the prompt
        let prompt = await Task.detached {
            return await self.buildPrompt(isContinue: isContinue)
        }.value
        
        guard let prompt else {
            reportError("Failed to build the prompt from the message log. Aborting generation.")
            return
        }
        print("Info: PROMPT------>\n\(prompt)\n<----END PROMPT")
        
        var fullResponse: String
        let aiMessage: Message
        if isContinue, let last = messageLog.last {
            // if we're continuing we don't append a new message
            aiMessage = last
            fullResponse = last.content
        } else {
            // add placeholder AI message that we'll update as tokens arrive
            aiMessage = Message(sender: .ai, content: "")
            fullResponse = ""
            self.messageLog.append(aiMessage)
        }
        
        // initialize completion
        var actualTokensProcessed: Int = 0
        let t_start = DispatchTime.now().uptimeNanoseconds
        do {
            actualTokensProcessed = try await llamaContext.completionInit(
                text: prompt,
                procUpdate: { pct in
                    await MainActor.run {
                        self.reportProcessStatus(progress: pct, status: "Processing prompt...")
                    }
                },
                canContinue: { @MainActor in
                    return !self.shouldStopGenerating
                }
            )
            // ensure the process reporting gets reset
            reportProcessStatus(progress: nil, status: nil)
        } catch {
            // remove prediction placeholder on failure
            reportError("Completion initialization failed: \(error.localizedDescription)")
            self.messageLog.removeLast()
            return
        }
        self.lastPromptTokenCount =  await llamaContext.getTokenCount()
        
        // generate tokens and update UI incrementally
        var generatedTokens = 0
        var timeToFirstToken: UInt64 = 0
        self.reportProcessStatus(progress: nil, status: nil)
        while await !llamaContext.isDone && !self.shouldStopGenerating {
            do {
                let nextChunk = try await llamaContext.completionStep()
                fullResponse.append(nextChunk)
                
                // update the ai message with accumulated content
                aiMessage.content = fullResponse
                generatedTokens += 1
                
                // do some special tracking for the first token
                if generatedTokens == 1 {
                    timeToFirstToken = DispatchTime.now().uptimeNanoseconds
                }
            } catch {
                reportError("Token generation failed: \(error.localizedDescription)")
                break
            }
        }
        
        // print statistics
        let t_heat = Double(Int64(timeToFirstToken) - Int64(t_start)) / NS_PER_S
        let t_end = DispatchTime.now().uptimeNanoseconds
        let t_generation = Double(t_end - timeToFirstToken) / NS_PER_S
        let prompt_tps = Double(actualTokensProcessed) / t_heat
        let generation_tps = Double(generatedTokens-1) / t_generation
        
        print("Info: Generation complete:")
        print("  Time to first token: \(t_heat)s")
        print("  Prompt speeds: \(actualTokensProcessed) new tokens ; \(prompt_tps) t/s")
        print("  Generation speeds: \(generatedTokens) tokens ; \(generation_tps) t/s")
        
        // make sure to serialize as the final step so nothing's lost
        saveChatLog()
        if let id = thisConversationID {
            touchConversation(id: id)
        }
    }
    
    /// a rough token estimation (1 token ≈ 4 chars for English text) is used if a loaded model cannot tokenize directly
    func getTokenCount(for text: String) async -> Int {
        guard let llamaContext = llamaContext else {
            return max(1, text.count / 4)
        }
        
        return await llamaContext.tokenize(text: text, addBOS: false).count
    }
    
    // prepares messages for prompt by removing thinking blocks and filtering by context size
    private func prepareMessagesForPrompt() async -> [(sender: MessageSender, content: String)] {
        guard let llamaContext = llamaContext else { return [] }
        let contextLength = Int(llamaContext.contextLength)
        
        // this is the number of tokens to add representing the number of tokens
        // a potential chat format might add, per message. by default this is
        // a somewhat pessimistic value.
        let perMessageOverhead = 10
        
        // make sure we have space for our text generation
        // if `maxGenerationLength` is 0, we treat this as unbound, so we then check
        // the `reservedContextBuffer` setting to see how much of the context to
        // reserve for the space to the AI reply in.
        let numToPredict = await Int(llamaContext.numToPredict)
        var generationBudget = numToPredict
        if generationBudget == 0, let config = modelConfig {
            generationBudget = config.reservedContextBuffer
        }
        
        let safetyThreshold = contextLength - generationBudget
        
        // if we have a contextAnchorID for a message, then we only consider messages from
        // that message forward in time.
        var startIndex = 0
        if let anchorID = contextAnchorID {
            if let index = messageLog.firstIndex(where: { $0.id == anchorID }) {
                startIndex = index
            } else {
                contextAnchorID = nil
            }
        }
        
        // see if we can fit the current messages into our `safetyThreshold` from our anchor, onward
        var totalTokens = 0
        for i in startIndex..<messageLog.count {
            let content = messageLog[i].parsedContent.responseContent
            totalTokens += await getTokenCount(for: content) + perMessageOverhead
        }
        
        if totalTokens > safetyThreshold {
            // safetyThreshold exceeded, so pick a new anchor with some 'runway' space
            // so that the KV cache isn't constantly regenerating
            let runwayTarget = (modelConfig?.reservedContextBuffer ?? numToPredict)
            let limitWithRunway = safetyThreshold - runwayTarget
            
            // slide the start index forward until we're under the limitWithRunway length
            while totalTokens > limitWithRunway && startIndex < messageLog.count - 1 {
                let content = messageLog[startIndex].parsedContent.responseContent
                let msgTokens = await getTokenCount(for: content) + perMessageOverhead
                totalTokens -= msgTokens
                startIndex += 1
            }
            
            // adjust the anchor to point to this new Message
            contextAnchorID = messageLog[startIndex].id
        } else if contextAnchorID == nil && !messageLog.isEmpty {
            contextAnchorID = messageLog.first!.id
        }

        // convert our stable 'window' into the messageLog into the returned format
        return messageLog[startIndex...].compactMap { message in
            let content = message.parsedContent.responseContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return (sender: message.sender, content: content)
        }
    }
}
