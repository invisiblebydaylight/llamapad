import Foundation
import Combine
import MLX

@MainActor
class LlamaBackend : InferenceBackend {
    /// keeps track of the loaded LLM and its context
    var llamaContext: LlamaContext?

    private var loadedConfig: AppConfiguration?
    
    /// this should be set to the URL used to load the model and used to
    /// track security access for it.
    private var currentModelURLs: [URL] = []
    
    /// tracks the first message to be included in the prompt allowing some maintenance
    /// of KV cache stability so that constant prompt ingestion doesn't have to happen.
    private var contextAnchorID: UUID?
    
    private var internalLastPromptTokenCount: Int? = nil

    var isLoaded: Bool { llamaContext != nil }
    var contextLimit: Int { Int(llamaContext?.contextLength ?? 0) }
    var lastPromptTokenCount: Int? { internalLastPromptTokenCount }
    
    func load(from config: AppConfiguration) async throws {
        loadedConfig = config
        guard !config.modelPaths.isEmpty else {
            throw InferenceError.loadFailed("Error: No model paths configured; make sure to setup the model in the configuration.")
        }
        guard !config.modelBookmarks.isEmpty else {
            throw InferenceError.loadFailed("Error: No model bookmark data; make sure to setup the model in the configuration.")
        }

        // attempt to use the stored security scoped bookmark if one
        // was aquired for this model file when building the new
        // URL to access.
        var activatedURLS: [URL] = []
        for data in config.modelBookmarks {
            // Resolve the bookmark
            var isStale = false
            
            #if os(macOS)
            let url = try? URL(resolvingBookmarkData: data,
                               options: .withSecurityScope,
                               relativeTo: nil,
                               bookmarkDataIsStale: &isStale)
            #else
            let url = try? URL(resolvingBookmarkData: data,
                               options: [],
                               relativeTo: nil,
                               bookmarkDataIsStale: &isStale)
            #endif
            if let url = url {
                if url.startAccessingSecurityScopedResource() {
                    activatedURLS.append(url)
                }
            }
        }
        
        self.currentModelURLs = activatedURLS
        if currentModelURLs.isEmpty {
            throw InferenceError.loadFailed("Error: Could not obtain the security scoped bookmark data needed to load the model.")
        }
        
        // do the actual model loading
        let modelURL = config.modelPaths.first!
        print("Loading model: \(modelURL)\n")
        do {
            llamaContext = try await LlamaContext.createContext(
                path: modelURL,
                offloadCount: Int32(config.layerCountToOffload),
                contextLength: UInt32(config.contextLength),
                samplerSettings: config.customSampler,
                kvCacheType: config.kvCacheType)
            print("Info: Model loading complete.\n")
        } catch {
            throw InferenceError.loadFailed("Error: failed to load model file \(modelURL): \(error.localizedDescription)")
        }
        
    }
    
    func unload() async {
        await self.llamaContext?.unload()
        self.llamaContext = nil
        
        for url in currentModelURLs {
            url.stopAccessingSecurityScopedResource()
        }
        currentModelURLs = []

        // by creating an array and immediately asking for a value,
        // we force the CPU to wait for the GPU to finish all pending
        // tasks (including the deallocations from llama.cpp).
        //
        // without this, memory that we free from deallocating the
        // LLM *won't actually be released* and another load will
        // potentially hard-lock or force a reboot of the device.
        let syncArray = MLXArray(Array(0...10))
        _ = syncArray.sum().item(Int.self)
        await Task.yield()
            
        print("Info: Model unloaded and security scope released.")
    }
    
    func shutdown() {
        // drop the reference to the actor.
        // this will trigger the actor's deinit eventually,
        // but we'll also call the C-level shutdown.
        self.llamaContext = nil
        
        for url in currentModelURLs {
            url.stopAccessingSecurityScopedResource()
        }
        
        // We already have this in the delegate, but calling it here
        // ensures the backend-specific state is cleared.
        shutdownLlamaCppBackend()
    }
    
    /// returns the total token count of the messages and system message unless no model is loaded (needed for tokenizing) in which case it returns nil
    func countTokensForPrompt(messages: [Message],
                     systemMessage: String?) async -> Int {
        guard llamaContext != nil else {
            return 0
        }

        var totalTokens = 0
        for msg in messages {
            let content = msg.parsedContent.responseContent
            let msgTokens = await countTokens(for: content)
            totalTokens += msgTokens
        }
        if let systemMessage = systemMessage {
            let sysTokens = await countTokens(for: systemMessage)
            totalTokens += sysTokens
        }
        
        return totalTokens
    }
    
    /// returns to the total token count of the string, or nil if a model wasn't loaded (needed for tokenizing)
    func countTokens(for text: String) async -> Int {
        guard let llamaContext = llamaContext else {
            return 0
        }

        let tokens = await llamaContext.tokenize(text: text, addBOS: false).count
        return tokens
    }
    
    func generate(messages: [Message],
                  systemMessage: String?,
                  isContinuation: Bool,
                  maxTokens: Int
    ) async throws -> AsyncThrowingStream<GenerationChunk, Error> {
        // making sure this is set before building the prompt is important
        // because it's used for sliding context management.
        await llamaContext?.setNumberToPredict(maxTokens)
        
        // do all prompt prep *before* opening the pipe.
        // if prompt building fails, we throw here, not inside the stream.
        let promptResult = try await buildPrompt(messages: messages,
                                           systemMessage: systemMessage,
                                           isContinuation: isContinuation)

        // return the live pipe.
        return AsyncThrowingStream { continuation in
            let task = Task {
                internalLastPromptTokenCount = await countTokens(for: promptResult.prompt)

                do {
                    // prompt ingestion
                    _ = try await self.llamaContext?.completionInit(
                        text: promptResult.prompt,
                        procUpdate: { pct, decoded in
                            continuation.yield(GenerationChunk(
                                text: "",
                                isPromptProcessing: true,
                                promptProgress: pct,
                                tokensDecoded: decoded,
                                tokensGenerated: 0
                            ))
                        },
                        canContinue: { !Task.isCancelled }
                    )

                    // if we have any prefilled text, toss that to the user first,
                    // courtesy of the Jinja templates
                    if let jinjaPrefil = promptResult.prefilledText {
                        continuation.yield(GenerationChunk(
                            text: jinjaPrefil,
                            isPromptProcessing: false,
                            promptProgress: 0,
                            tokensDecoded: 0,
                            tokensGenerated: 0,
                        ))
                    }
                    
                    // token loop
                    var tokensGenerated = 0
                    while await !(self.llamaContext?.isDone ?? true)
                            && !Task.isCancelled {
                        let chunk = try await self.llamaContext?.completionStep() ?? ""
                        tokensGenerated += 1
                        continuation.yield(GenerationChunk(
                            text: chunk,
                            isPromptProcessing: false,
                            promptProgress: 0,
                            tokensDecoded: 0,
                            tokensGenerated: tokensGenerated
                        ))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }



    // prepares messages for prompt by removing thinking blocks and filtering by context size.
    // will return an empty array if no config or model is loaded.
    private func prepareMessagesForPrompt(messages: [Message],
                                          systemMessage: String?
    )
    async -> [(sender: MessageSender, content: String)] {
        guard let modelConfig = loadedConfig else { return [] }
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
        if generationBudget == 0 {
            generationBudget = max(0, modelConfig.reservedContextBuffer)
        }
        let safetyThreshold = contextLength - generationBudget
        
        // get the length of the system message as well
        var systemTokens = 0
        if let sysMsg = systemMessage, !sysMsg.isEmpty {
            systemTokens = await countTokens(for: sysMsg) + perMessageOverhead
        }
        
        // if we have a contextAnchorID for a message, then we only consider messages from
        // that message forward in time.
        var startIndex = 0
        if let anchorID = contextAnchorID {
            if let index = messages.firstIndex(where: { $0.id == anchorID }) {
                startIndex = index
            } else {
                // if not found, we reset the anchor and keep our startIndex at 0
                contextAnchorID = nil
            }
        }
        
        // see if we can fit the current messages into our `safetyThreshold` from our anchor, onward
        // start with the number of system tokens that already take up space...
        var totalTokens = systemTokens
        for i in startIndex..<messages.count {
            let content = messages[i].parsedContent.responseContent
            totalTokens += await countTokens(for: content) + perMessageOverhead
        }
        
        if totalTokens > safetyThreshold {
            // safetyThreshold exceeded, so pick a new anchor with some 'runway' space
            // so that the KV cache isn't constantly regenerating
            let runwayTarget = max(0, modelConfig.contextRunway)
            let limitWithRunway = max(0, safetyThreshold - runwayTarget)
            
            // slide the start index forward until we're under the limitWithRunway length
            while totalTokens > limitWithRunway && startIndex < messages.count - 1 {
                let content = messages[startIndex].parsedContent.responseContent
                let msgTokens = await countTokens(for: content) + perMessageOverhead
                totalTokens -= msgTokens
                startIndex += 1
            }
            
            // adjust the anchor to point to this new Message
            contextAnchorID = messages[startIndex].id
        } else if contextAnchorID == nil && !messages.isEmpty {
            contextAnchorID = messages.first!.id
        }

        // convert our stable 'window' into the messageLog into the returned format
        return messages[startIndex...].compactMap { message in
            let content = message.parsedContent.responseContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return (sender: message.sender, content: content)
        }
    }
    
    private struct PromptResult {
        // the whole prompt that was built
        let prompt: String
        
        // if present, this should be text that the template 'prefilled'
        // as part of the response.
        let prefilledText: String?
    }

    /// builds the prompt for text generation based off the loaded model, the configuration and the messages.
    /// if it's unable to build a prompt, an error is thrown.
    private func buildPrompt(messages: [Message],
                             systemMessage: String?,
                             isContinuation: Bool) async throws -> PromptResult {
        guard let config = loadedConfig else {
            throw InferenceError.notLoaded("No configuration loaded.")
        }
        guard let llamaContext else {
            throw InferenceError.notLoaded("No model loaded.")
        }
        
        // or if it continues to get managed in AppState
        let processedMessages = await prepareMessagesForPrompt(messages: messages, systemMessage: systemMessage)
        
        // add the system prompt this way.
        if config.chatTemplate == nil { // `nil` is jinja/autodetect
            if let jinjaStr = await llamaContext.getChatTemplate() {
                var messages = processedMessages
                if let sysMsg = systemMessage, sysMsg.isEmpty == false {
                    // insert the system message as the first message in processedMessages
                    messages = [(.system, sysMsg)] + messages
                }
                let templater = TemplateSevice.init(jinjaStr: jinjaStr)
                do {
                    let prompt = try templater.render(
                        messages: messages,
                        addAssistant: !isContinuation,
                        enableThinking: config.enableThinking)
                    
                    //print("DEBUG: PROMPT->>\n\(prompt ?? "<NULL>")\n<<-END")
                    
                    // check to see if we have any thinking tags inserted by the Jinja template
                    let detectedTag = ThinkingPattern.all.first { pattern in
                        prompt!.trimmingSuffixWhitespace().hasSuffix(pattern.opening)
                    }?.opening

                    return PromptResult(prompt: prompt!, prefilledText: detectedTag)
                } catch {
                    throw InferenceError.promptBuildFailed("Failed to render jinja template: \(error.localizedDescription)")
                }
            }
        }
        
        do {
            let systemMessage = systemMessage ?? ""
            let prompt = try await llamaContext.formatPrompt(
                messages: processedMessages,
                systemMessage: systemMessage,
                template: config.chatTemplate,
                isContinue: isContinuation)
            return PromptResult(prompt: prompt, prefilledText: nil)
        } catch {
            throw InferenceError.promptBuildFailed("Failed to format the prompt using template: \(config.chatTemplate ?? "Unknown")")
        }
    }
}
