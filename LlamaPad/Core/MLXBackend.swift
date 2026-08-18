import Foundation
import CoreImage
import Combine
import MLXLMCommon
import MLXLLM
import MLXVLM
import MLXLMTransformers
import MLX

private func logMemoryUsage(_ prefix: String) {
    let snapshot = Memory.snapshot()
    print("\(prefix) | MLX Memory: \(snapshot.description)")
}

/// this struct gets built to act as a String representation of the KV cache and gets
/// used to test if a new ChatSession needs to be created.
private struct SessionSignature: Equatable {
    let system: String?
    let messages: [String]
    let attachmentIDs: [UUID]

    static func createChatSessionSignature(instruction: String?, messages: [Chat.Message], attachmentIDs: [UUID] = []) -> Self {
        let strings: [String] = messages.map(\.content)
        return Self.init(
            system: instruction,
            messages: strings,
            attachmentIDs: attachmentIDs,
        )
    }
    
    /// checks to see if the session signatures are considered equal without change
    func checkSignature(against other: Self) -> Bool {
        system == other.system
            && messages.prefix(other.messages.count).elementsEqual(other.messages)
            && attachmentIDs.prefix(other.attachmentIDs.count).elementsEqual(other.attachmentIDs)
    }
}

@MainActor
class MLXBackend: InferenceBackend {
    private var loadedConfig: AppConfiguration?
    private var loadedModel: ModelContainer?
    private var internalLastPromptTokenCount: Int? = nil
    
    /// this is the cached ChatSessiont that can be reused if SessionSignature checks out
    private var chatSession: ChatSession? = nil
    
    /// keeps track of the task used for generation so that it can be cancelled if needed.
    private var generationTask: Task<Void, Never>?
    
    /// this is used to test against the current messages the client wishes to send to the
    /// backend to see if a new ChatSession needs to get created because messages changed.
    private var chatSessionSignature: SessionSignature? = nil

    /// this is used to track the last 'seed' value used to seed the RNG; it's used as a comparison
    /// test so that we don't keep reseeding the RNG unless necessary to do so.
    /// NOTE: we store the user visible value, not the *actual* seed if '0' was used to randomize the seed.
    private var lastSeed: UInt32? = nil

    var isLoaded: Bool { loadedModel != nil }
    var contextLimit: Int = 0
    
    /// NOTE: we don't return `internalLastPromptTokenCount` here because we can't track it accurately.
    /// For example, regenerating the last message several times would just report more and more tokens used in
    /// the cache space, which would be inaccurate. Instead, we just disable this number for this backend.
    var lastPromptTokenCount: Int? { nil }

    private var internalLastIncludedMessageIDs: [UUID]? = nil
    var lastIncludedMessageIDs: [UUID]? { internalLastIncludedMessageIDs }

    /// used by `prepareMessageForBackend` to figure out where to start the message log
    /// to send to the backend engine. that way we can constrict the log a little more, pin it to start
    /// at a message and then let it grow without having to risk full context reprocessing with every message.
    private var contextAnchorID: UUID? = nil

    
    func load(from config: AppConfiguration) async throws {
        // make sure to seed the RNG
        if config.customSampler.magic_seed > 0 {
            MLX.seed(UInt64(config.customSampler.magic_seed))
        } else {
            MLX.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        }
        lastSeed = config.customSampler.magic_seed
        
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
        
        if activatedURLS.isEmpty {
            throw InferenceError.loadFailed("Error: Could not obtain the security scoped bookmark data needed to load the model.")
        }
        
        // do the actual model loading
        let modelDirectoryURL = activatedURLS.first!
        
        do {
            // try forcing the VLM pipeline to see if it works, and fall back
            // to text-only implementation in the catch block if needed.
            print("Attempting to load as VLM ...")
            loadedModel = try await VLMModelFactory.shared.loadContainer(from: modelDirectoryURL)
        } catch ModelFactoryError.unsupportedModelType {
            // NOTE: only works because of the swift-transformers adapter library `swift-transformers-mlx`
            // providing easier to use tokenizer from that library.
            print("Not a VLM; now attempting to load as text-only LLM ...")
            loadedModel = try await loadModelContainer(from: modelDirectoryURL)
        } catch {
            print("VLM load failed with error type: \(type(of: error))")
            print("VLM load error: \(error)")
            throw error
        }
        
        loadedConfig = config
        logMemoryUsage("Memory usage after loading")
    }
    
    func unload() async {
        loadedModel = nil
        chatSession = nil
        chatSessionSignature = nil
    }
    func shutdown() {
        loadedModel = nil
        chatSession = nil
        chatSessionSignature = nil
    }
    
    func countTokens(for text: String) async -> Int {
        guard let model = loadedModel else {
            return 0
        }
        let tokenCount = await model.perform { context in
            let tokens = context.tokenizer.encode(text: text)
            return tokens.count
        }
        return tokenCount
    }
    
    func cancel() async {
        generationTask?.cancel()
        generationTask = nil
    }
    
    func generate(messages: [Message],
                  systemMessage: String?,
                  isContinuation: Bool,
                  settings: GenerationSettings) async throws
    -> AsyncThrowingStream<GenerationChunk, Error> {
        guard let model = loadedModel else {
            throw InferenceError.notLoaded("MLX backend not loaded")
        }
        
        // should always be true. even with a blank chatlog, there'll be a user message
        // and then the 'blank' AI message.
        guard messages.count >= 2 else {
            throw InferenceError.generationFailed("Not at least 2 messages (one for user, one for AI).")
        }
        
        // NOTE: continuation support doesn't fully work
        var prunedMessages = messages
        if isContinuation == false {
            // let go of the AI one, but keep the user one
            let _ = prunedMessages.popLast()
        }
        
        // we go through and select only the messages that fit within a given context log.
        prunedMessages = await prepareMessagesForBackend(
            messages: prunedMessages,
            systemMessage: systemMessage,
            settings: settings)
        let targetMsg = prunedMessages.popLast()
        
        // build the chat history
        var mlxMessages = [Chat.Message]()
        mlxMessages = prunedMessages.compactMap { msg -> Chat.Message? in
            let content = msg.contentWithAttachments
            guard !content.isEmpty else { return nil }
            
            let images: [UserInput.Image] = (msg.attachments ?? [])
                .filter { $0.contentType == .image }
                .compactMap { att in
                    guard let data = att.imageData,
                          let ciImage = CIImage(data: data) else { return nil }
                    return .ciImage(ciImage)
                }
         
            return Chat.Message(
                role: msg.sender == .user ? Chat.Message.Role.user : Chat.Message.Role.assistant,
                content: content,
                images: images
            )
        }
                
        // gather attachment IDs from the app-level messages in the same order
        let historyAttachmentIDs: [UUID] = prunedMessages.flatMap {
            $0.attachments?.filter { $0.contentType == .image }.map(\.id) ?? []
        }

        // create a new signature to check against our last signature for the session
        let newSessionSignature = SessionSignature.createChatSessionSignature(
            instruction: systemMessage,
            messages: mlxMessages,
            attachmentIDs: historyAttachmentIDs
        )
        
        // reseed the RNG if necessary
        if lastSeed == nil || lastSeed == 0 || settings.samplerSettings.magic_seed != lastSeed {
            let seed = settings.samplerSettings.magic_seed == 0
                ? UInt64(Date.timeIntervalSinceReferenceDate * 1000)
                : UInt64(settings.samplerSettings.magic_seed)
            MLX.seed(seed)
            lastSeed = settings.samplerSettings.magic_seed
        }
        
        // check to see if we need to create a new session
        if chatSession == nil || !(chatSessionSignature?.checkSignature(against: newSessionSignature) ?? false) {
            // use our sampler settings provided to generate a new set of parameters
            var generateParameters = GenerateParameters(maxTokens: settings.maxTokens,
                                                        maxKVSize: loadedConfig?.contextLength,
                                                        temperature: settings.samplerSettings.temperature,
                                                        topP: settings.samplerSettings.topP,
                                                        topK: Int(settings.samplerSettings.topK),
                                                        minP: settings.samplerSettings.minP,
                                                        repetitionPenalty: settings.samplerSettings.repeatPenalty,
                                                        repetitionContextSize: Int(settings.samplerSettings.repeatLastN),
                                                        presencePenalty: settings.samplerSettings.presencePenalty,
                                                        presenceContextSize: Int(settings.samplerSettings.repeatLastN),
                                                        frequencyPenalty: settings.samplerSettings.freqPenalty,
                                                        frequencyContextSize: Int(settings.samplerSettings.repeatLastN))
            if generateParameters.maxTokens != nil && generateParameters.maxTokens! < 1 {
                generateParameters.maxTokens = nil
            }

            // now create the actual chat session itself and reset some internal tracking
            chatSession = ChatSession(model,
                                      instructions: systemMessage,
                                      history: mlxMessages,
                                      generateParameters: generateParameters,
                                      additionalContext: ["enable_thinking" : settings.enableThinking])
            chatSessionSignature = newSessionSignature
            internalLastPromptTokenCount = 0
        } else {
            if let session = chatSession {
                // we're going to reuse the session, but we need to remove any system messages in the history we're using
                session.instructions = nil
                             
                // also make sure to update the sampler settings
                session.generateParameters.maxTokens = settings.maxTokens > 0 ? settings.maxTokens : nil
                session.generateParameters.temperature = settings.samplerSettings.temperature
                session.generateParameters.topP = settings.samplerSettings.topP
                session.generateParameters.topK = Int(settings.samplerSettings.topK)
                session.generateParameters.minP = settings.samplerSettings.minP
                session.generateParameters.repetitionPenalty = settings.samplerSettings.repeatPenalty
                session.generateParameters.repetitionContextSize = Int(settings.samplerSettings.repeatLastN)
                session.generateParameters.presencePenalty = settings.samplerSettings.presencePenalty
                session.generateParameters.presenceContextSize = Int(settings.samplerSettings.repeatLastN)
                session.generateParameters.frequencyPenalty = settings.samplerSettings.freqPenalty
                session.generateParameters.frequencyContextSize = Int(settings.samplerSettings.repeatLastN)
                session.additionalContext = ["enable_thinking" : settings.enableThinking]
            }
        }
        
        // Extract image attachments from the target message
        var targetImages: [UserInput.Image] = []
        if let attachments = targetMsg?.attachments {
            for att in attachments where att.contentType == .image {
                if let data = att.imageData, let ciImage = CIImage(data: data) {
                    targetImages.append(.ciImage(ciImage))
                }
            }
        }

        let promptText = targetMsg?.contentWithAttachments ??
            "Tell the user the software they use is bugged because the AI cannot see the message to respond to."

        let mlxStream = chatSession!.streamDetails(
            to: promptText,
            images: targetImages,
            videos: []
        )
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var tokensGenerated = 0
                    var accumulatedResponse = ""
                    
                    continuation.yield(GenerationChunk(
                        text: "",
                        isPromptProcessing: true,
                        promptProgress: 0,  // 0 = "we don't know the percentage"
                        tokensDecoded: 0,
                        tokensGenerated: 0
                    ))
                    
                    for try await gen in mlxStream {
                        if Task.isCancelled { break }
                        // if we got a chunk of text generated, send it
                        if let chunk = gen.chunk {
                            tokensGenerated += 1
                            accumulatedResponse.append(chunk)
                            continuation.yield(GenerationChunk(
                                text: chunk,
                                isPromptProcessing: false,
                                promptProgress: 0,
                                tokensDecoded: 0,
                                tokensGenerated: tokensGenerated
                            ))
                        }
                        if let info = gen.info {
                            internalLastPromptTokenCount = info.promptTokenCount
                            continuation.yield(GenerationChunk(
                                text: "",
                                isPromptProcessing: false,
                                promptProgress: 1.0,
                                tokensDecoded: info.promptTokenCount,
                                tokensGenerated: info.generationTokenCount
                            ))
                        }
                    }
                    
                    // if we've completed the message, update the signature
                    if !Task.isCancelled, let target = targetMsg {
                        let userContent = target.parsedContent.responseContent
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let assistantContent = accumulatedResponse
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        // mlxMessages is the prefix WITHOUT the target user message,
                        // captured from the outer scope. build the canonical history
                        // exactly as the messageLog represents it.
                        var updatedMessages = mlxMessages.map {
                            $0.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        updatedMessages.append(userContent)
                        updatedMessages.append(assistantContent)

                        var updatedAttachmentIDs = historyAttachmentIDs
                        updatedAttachmentIDs += target.attachments?
                            .filter { $0.contentType == .image }.map(\.id) ?? []

                        self.chatSessionSignature = SessionSignature(
                            system: systemMessage,
                            messages: updatedMessages,
                            attachmentIDs: updatedAttachmentIDs
                        )
                    }
                    
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: InferenceError.generationFailed(error.localizedDescription))
                    }
                }
            }
            self.generationTask = task
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    private func prepareMessagesForBackend(
        messages: [Message],
        systemMessage: String?,
        settings: GenerationSettings
    ) async -> [Message] {
        // for now, estimate how many tokens the prompt format adds
        let promptTokenBaggageEst = 10
        
        internalLastIncludedMessageIDs = []
        guard let config = loadedConfig else { return messages }
        guard loadedModel != nil else { return messages }
        
        let effectiveContext = config.contextLength
        let generationBudget = settings.maxTokens > 0 ? settings.maxTokens : settings.reservedContextBuffer
        let safetyThreshold = effectiveContext - generationBudget
        let runwayTarget = max(0, settings.contextRunway)
        let limitWithRunway = max(0, safetyThreshold - runwayTarget)

        // Tokenize system message to reserve its budget
        var totalTokens = 0
        if let sysMsg = systemMessage, !sysMsg.isEmpty {
            totalTokens = await countTokens(for: sysMsg) + promptTokenBaggageEst
        }
        
        var startIndex = messages.count
        var safetyThresholdBreached = false
        
        for i in stride(from: messages.count - 1, through: 0, by: -1) {
            let content = messages[i].contentWithAttachments
            guard !content.isEmpty else { continue }
            
            var msgTokens = await countTokens(for: content) + promptTokenBaggageEst
            if messages[i].sender == .user, let attachments = messages[i].attachments {
                let imageTokens = attachments
                    .filter { $0.contentType == .image }
                    .reduce(0) { $0 + $1.tokenEstimate }
                msgTokens += imageTokens
            }

            if totalTokens + msgTokens > safetyThreshold {
                safetyThresholdBreached = true
                startIndex = i + 1
                break
            }
            totalTokens += msgTokens
            
            if messages[i].id == contextAnchorID {
                startIndex = i
                break
            }
        }
                
        if startIndex == messages.count {
            startIndex = 0
        }
        
        if safetyThresholdBreached {
            while startIndex < messages.count && totalTokens > limitWithRunway {
                let content = messages[startIndex].contentWithAttachments
                let msgTokens = await countTokens(for: content) + promptTokenBaggageEst
                totalTokens -= msgTokens
                
                if messages[startIndex].sender == .user, let attachments = messages[startIndex].attachments {
                    let imageTokens = attachments
                        .filter { $0.contentType == .image }
                        .reduce(0) { $0 + $1.tokenEstimate }
                    totalTokens -= imageTokens
                }

                startIndex += 1
            }
        }
        
        if !messages.isEmpty && contextAnchorID != messages[startIndex].id {
            contextAnchorID = messages[startIndex].id
        }
        
        guard startIndex < messages.count else {
            print("ERROR: startIndex out of bounds for prepareMessagesForBackend; returning empty array.")
            return []
        }
        
        let result = Array(messages[startIndex...])
        internalLastIncludedMessageIDs = result.map { $0.id }
        return result
    }

}
