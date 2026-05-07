import Foundation
import Combine
import MLXLMCommon
import MLXLLM
import MLXLMTransformers
import MLX

@MainActor
class MLXBackend: InferenceBackend {
    private var loadedConfig: AppConfiguration?
    private var loadedModel: ModelContainer?
    private var internalLastPromptTokenCount: Int? = nil
    
    var isLoaded: Bool { loadedModel != nil }
    var contextLimit: Int = 0
    var lastPromptTokenCount: Int? { internalLastPromptTokenCount }
    
    func load(from config: AppConfiguration) async throws {
        // make sure to seed the RNG
        if config.customSampler.magic_seed > 0 {
            MLX.seed(UInt64(config.customSampler.magic_seed))
        } else {
            MLX.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
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
        
        if activatedURLS.isEmpty {
            throw InferenceError.loadFailed("Error: Could not obtain the security scoped bookmark data needed to load the model.")
        }
        
        // do the actual model loading
        let modelDirectoryURL = activatedURLS.first!
        
        // NOTE: only works because of the swift-transformers adapter library `swift-transformers-mlx`
        // providing easier to use tokenizer from that library.
        loadedModel = try await loadModelContainer(from: modelDirectoryURL)
        loadedConfig = config
    }
    
    func unload() async {
        // FIXME: is this enough? confirm...
        loadedModel = nil
    }
    func shutdown() {
        // FIXME: is this enough? confirm...
        loadedModel = nil
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
    
    func generate(messages: [Message], systemMessage: String?,
                  isContinuation: Bool, maxTokens: Int) async throws
    -> AsyncThrowingStream<GenerationChunk, Error> {
        guard let model = loadedModel else {
            throw InferenceError.notLoaded("MLX backend not loaded")
        }
        
        // should always be true. even with a blank chatlog, there'll be a user message
        // and then the 'blank' AI message.
        guard messages.count >= 2 else {
            throw InferenceError.generationFailed("Not at least 2 messages (one for user, one for AI).")
        }
        
        // FIXME: continuation support doesn't fully work
        var prunedMessages = messages
        if isContinuation == false {
            // let go of the AI one, but keep the user one
            let _ = prunedMessages.popLast()
        }
        
        // we go through and select only the messages that fit within a given context log.
        // NOTE: for the MLX backend, we don't have a sliding context window yet
        prunedMessages = await prepareMessagesForBackend(messages: prunedMessages, systemMessage: systemMessage)
        let targetMsg = prunedMessages.popLast()
        
        // build the chat history
        var mlxMessages = [Chat.Message]()
        mlxMessages = prunedMessages.compactMap { msg -> Chat.Message? in
            let content = msg.parsedContent.responseContent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return Chat.Message(role: msg.sender == .user
                                ? Chat.Message.Role.user
                                : Chat.Message.Role.assistant,
                                content: content)
        }
        
        // use our stored sampler settings
        var generateParameters = GenerateParameters(maxTokens: loadedConfig?.maxGenerationLength,
                                                    maxKVSize: loadedConfig?.contextLength,
                                                    temperature: loadedConfig?.customSampler.temperature ?? 0.6,
                                                    topP: loadedConfig?.customSampler.topP ?? 1.0,
                                                    topK: Int(loadedConfig?.customSampler.topK ?? 0),
                                                    minP: loadedConfig?.customSampler.minP ?? 0.0,
                                                    repetitionPenalty: loadedConfig?.customSampler.repeatPenalty,
                                                    repetitionContextSize: Int(loadedConfig?.customSampler.repeatLastN ?? 20),
                                                    presencePenalty: loadedConfig?.customSampler.presencePenalty,
                                                    presenceContextSize: Int(loadedConfig?.customSampler.repeatLastN ?? 20),
                                                    frequencyPenalty: loadedConfig?.customSampler.freqPenalty,
                                                    frequencyContextSize: Int(loadedConfig?.customSampler.repeatLastN ?? 20))
        if generateParameters.maxTokens != nil && generateParameters.maxTokens! < 1 {
            generateParameters.maxTokens = nil
        }
        
        let session = ChatSession(model,
                                  instructions: systemMessage,
                                  history: mlxMessages,
                                  generateParameters: generateParameters,
                                  additionalContext: ["enable_thinking" : loadedConfig?.enableThinking ?? false])
        
        // This returns AsyncThrowingStream<String, Error>
        // but we need it to be AsyncThrowingStream<GenerationChunk, Error> ...
        let mlxStream = session.streamDetails(to: targetMsg?.parsedContent.responseContent ??
                                              "Tell the user the software they use is bugged because the AI cannot see the message to respond to.",
                                              images: [], videos: [])
        
        // So we just wrap it in this AsyncThrowingStream...
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var tokensGenerated = 0
                    
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
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: InferenceError.generationFailed(error.localizedDescription))
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    private func prepareMessagesForBackend(
        messages: [Message],
        systemMessage: String?
    ) async -> [Message] {
        // for now, estimate how many tokens the prompt format adds
        let promptTokenBaggageEst = 10
        
        guard let config = loadedConfig else { return messages }
        guard loadedModel != nil else { return messages }
        
        let effectiveContext = config.contextLength
        let generationBudget = config.maxGenerationLength > 0
            ? config.maxGenerationLength
            : config.reservedContextBuffer
        let safetyThreshold = effectiveContext - generationBudget
        
        // Tokenize system message to reserve its budget
        var totalTokens = 0
        if let sysMsg = systemMessage, !sysMsg.isEmpty {
            totalTokens = await countTokens(for: sysMsg) + promptTokenBaggageEst
        }
        
        var startIndex = messages.count
        
        for i in stride(from: messages.count - 1, through: 0, by: -1) {
            let content = messages[i].parsedContent.responseContent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            
            let msgTokens = await countTokens(for: content) + promptTokenBaggageEst
            
            if totalTokens + msgTokens > safetyThreshold {
                startIndex = i + 1
                break
            }
            totalTokens += msgTokens
        }
        
        if startIndex >= messages.count { return messages }
        return Array(messages[startIndex...])
    }

}
