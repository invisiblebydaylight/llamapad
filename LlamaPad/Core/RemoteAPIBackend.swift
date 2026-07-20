import Foundation
import Combine

@MainActor
class RemoteAPIBackend: InferenceBackend {
    private var loadedConfig: AppConfiguration?
    private var internalLastPromptTokenCount: Int? = nil
    private var internalLastIncludedMessageIDs: [UUID]? = nil

    private var contextAnchorID: UUID? = nil

    
    var isLoaded: Bool {
        return loadedConfig != nil
    }
    
    var contextLimit: Int {
        return loadedConfig?.contextLength ?? 8192
    }
    
    var lastPromptTokenCount: Int? {
        return internalLastPromptTokenCount
    }
    
    var lastIncludedMessageIDs: [UUID]? {
        internalLastIncludedMessageIDs
    }
    
    func load(from config: AppConfiguration) async throws {
        loadedConfig = config
    }
    
    func unload() async {
        loadedConfig = nil
    }
    
    func shutdown() {
        // no-op
    }
    
    func countTokens(for text: String) async -> Int {
        let charsPerTokenEstimate = 4
        return text.count / charsPerTokenEstimate
    }
    
    func generate(
        messages: [Message],
        systemMessage: String?,
        isContinuation: Bool,
        settings: GenerationSettings
    ) async throws -> AsyncThrowingStream<GenerationChunk, Error> {
        guard let config = loadedConfig else {
            throw InferenceError.notLoaded("Remote API backend not loaded")
        }

        // prune messages and apply context windowing
        var prunedMessages = messages
        if !isContinuation {
            // drop the blank AI message at the end
            prunedMessages.removeLast()
        }

        prunedMessages = await prepareMessagesForBackend(
            messages: prunedMessages,
            systemMessage: systemMessage,
            settings: settings
        )

        // build the OpenAI-compatible messages array
        var apiMessages: [[String: Any]] = []
        if let sysMsg = systemMessage, !sysMsg.isEmpty {
            apiMessages.append(["role": "system", "content": sysMsg])
        }
        for msg in prunedMessages {
            let role = msg.sender == .user ? "user" : "assistant"
            
            // check for image attachments — only user messages, only remote API
            let imageAttachments = msg.sender == .user
                ? (msg.attachments ?? []).filter { $0.contentType == .image && $0.imageData != nil }
                : []
            
            if !imageAttachments.isEmpty {
                // build the multimodal content array
                var contentArray: [[String: Any]] = []
                
                // text portion first (includes text attachments via contentWithAttachments)
                let textContent = msg.contentWithAttachments
                if !textContent.isEmpty {
                    contentArray.append(["type": "text", "text": textContent])
                }
                
                // then images
                for att in imageAttachments {
                    let base64 = att.imageData!.base64EncodedString()
                    let url = "data:\(att.mimeType);base64,\(base64)"
                    contentArray.append([
                        "type": "image_url",
                        "image_url": ["url": url]
                    ])
                }
                
                guard !contentArray.isEmpty else { continue }
                apiMessages.append(["role": role, "content": contentArray])
            } else {
                // standard text-only path
                let content = msg.contentWithAttachments
                guard !content.isEmpty else { continue }
                apiMessages.append(["role": role, "content": content])
            }
        }

        // build request body
        var body: [String: Any] = [
            "model": config.apiModelName,
            "messages": apiMessages,
            "stream": true,
        ]
        if settings.maxTokens > 0 {
            body["max_completion_tokens"] = settings.maxTokens
        }
        if settings.reasoningEffort != .none {
            body["reasoning_effort"] = settings.reasoningEffort.rawValue
        }
        // set some llama.cpp specific flags for thinking
        body["chat_template_kwargs"] = [
            "enable_thinking": settings.reasoningEffort != .none,
        ]

        // add in any sampler overrides enabled by the user
        let s = settings.samplerSettings
        let rs = settings.remoteSamplers
        if rs.contains("temperature") { body["temperature"] = s.temperature}
        if rs.contains("top_k") { body["top_k"] = s.topK}
        if rs.contains("top_p") { body["top_p"] = s.topP}
        if rs.contains("min_p") { body["min_p"] = s.minP}
        if rs.contains("frequency_penalty") { body["frequency_penalty"] = s.freqPenalty }
        if rs.contains("presence_penalty") { body["presence_penalty"] = s.presencePenalty }
        if rs.contains("repeat_penalty") { body["repeat_penalty"] = s.repeatPenalty }
        if rs.contains("dry_multiplier") { body["dry_multiplier"] = s.dryMultiplier }
        if rs.contains("xtc_probability") { body["xtc_probability"] = s.xtcProbability }
        if rs.contains("xtc_threshold") { body["xtc_threshold"] = s.xtcThreshold }
        if rs.contains("seed") { body["seed"] = s.magic_seed }
        
        // overlay any custom JSON over the body
        if let customJSON = config.apiCustomBody?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customJSON.isEmpty,
           let customData = customJSON.data(using: .utf8),
           let customDict = try? JSONSerialization.jsonObject(with: customData) as? [String: Any] {
            for (key, value) in customDict {
                body[key] = value
            }
        }
        
        // build the URL — endpoint should be like "https://example.com/v1"
        guard let url = URL(string: config.apiEndpoint)?
            .appendingPathComponent("chat/completions") else {
            throw InferenceError.generationFailed("Invalid endpoint URL: \(config.apiEndpoint)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("https://github.com/invisiblebydaylight/llamapad", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("LlamaPad", forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // set a generous timeout for large model prefill
        request.timeoutInterval = 600

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    // signal prompt processing started
                    continuation.yield(GenerationChunk(
                        text: "",
                        isPromptProcessing: true,
                        promptProgress: 0,
                        tokensDecoded: 0,
                        tokensGenerated: 0
                    ))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw InferenceError.generationFailed("Invalid response from server")
                    }

                    if httpResponse.statusCode != 200 {
                        // try to read the error body for diagnostics
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line + "\n"
                        }
                        throw InferenceError.generationFailed(
                            "Server returned \(httpResponse.statusCode): \(errorBody)"
                        )
                    }

                    var tokensGenerated = 0
                    var inReasoning = false
                    var firstTokenReceived = false

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        // SSE format: lines start with "data: "
                        guard line.hasPrefix("data: ") else { continue }
                        let dataStr = String(line.dropFirst(6))

                        if dataStr == "[DONE]" { break }

                        guard let data = dataStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        // capture usage data - openrouter format (usage) or llama.cpp format (timings)
                        if let usage = json["usage"] as? [String: Any] {
                            if let promptTokens = usage["prompt_tokens"] as? Int {
                                await MainActor.run {
                                    self.internalLastPromptTokenCount = promptTokens
                                }
                                // yield the updated count so AppState can record it
                                continuation.yield(GenerationChunk(
                                    text: "",
                                    isPromptProcessing: false,
                                    promptProgress: 0,
                                    tokensDecoded: promptTokens,
                                    tokensGenerated: tokensGenerated
                                ))
                            }
                        } else if let timings = json["timings"] as? [String: Any] {
                            let promptN = timings["prompt_n"] as? Int ?? 0
                            let cacheN = timings["cache_n"] as? Int ?? 0
                            let predictedN = timings["predicted_n"] as? Int ?? tokensGenerated
                            let totalPromptN = promptN + cacheN
                            await MainActor.run {
                                self.internalLastPromptTokenCount = totalPromptN
                            }
                            continuation.yield(GenerationChunk(
                                text: "",
                                isPromptProcessing: false,
                                promptProgress: 0,
                                tokensDecoded: totalPromptN,
                                tokensGenerated: predictedN
                            ))
                        }

                        guard let choices = json["choices"] as? [[String: Any]],
                              let choice = choices.first else { continue }

                        let delta = choice["delta"] as? [String: Any] ?? [:]
                        let content = delta["content"] as? String ?? ""

                        // check both keys — llama.cpp uses reasoning_content, OpenRouter uses reasoning
                        let reasoning = delta["reasoning_content"] as? String ?? delta["reasoning"] as? String ?? ""
                        
                        if !reasoning.isEmpty {
                            if !inReasoning {
                                inReasoning = true
                                // open the think block on first reasoning chunk
                                // (handle first token transition too)
                                if !firstTokenReceived {
                                    firstTokenReceived = true
                                    continuation.yield(GenerationChunk(
                                        text: "", isPromptProcessing: false,
                                        promptProgress: 1.0, tokensDecoded: 0, tokensGenerated: 0
                                    ))
                                }
                                tokensGenerated += 1
                                continuation.yield(GenerationChunk(
                                    text: "<think>" + reasoning, isPromptProcessing: false,
                                    promptProgress: 0, tokensDecoded: 0, tokensGenerated: tokensGenerated
                                ))
                            } else {
                                tokensGenerated += 1
                                continuation.yield(GenerationChunk(
                                    text: reasoning, isPromptProcessing: false,
                                    promptProgress: 0, tokensDecoded: 0, tokensGenerated: tokensGenerated
                                ))
                            }
                        }

                        if !content.isEmpty {
                            if !firstTokenReceived {
                                firstTokenReceived = true
                                
                                // signal prompt processing is done
                                let tokenCount = await MainActor.run { self.internalLastPromptTokenCount ?? 0 }
                                continuation.yield(GenerationChunk(
                                    text: "",
                                    isPromptProcessing: false,
                                    promptProgress: 1.0,
                                    tokensDecoded: tokenCount,
                                    tokensGenerated: 0
                                ))
                            }
                            
                            // if we had been thinking, send the close tag
                            if inReasoning {
                                inReasoning = false
                                continuation.yield(GenerationChunk(
                                    text: "</think>", isPromptProcessing: false,
                                    promptProgress: 0, tokensDecoded: 0, tokensGenerated: tokensGenerated
                                ))
                            }
                            
                            tokensGenerated += 1
                            continuation.yield(GenerationChunk(
                                text: content,
                                isPromptProcessing: false,
                                promptProgress: 0,
                                tokensDecoded: 0,
                                tokensGenerated: tokensGenerated
                            ))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: InferenceError.generationFailed(
                        error.localizedDescription
                    ))
                }
            }
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
        let promptTokenBaggageEst = 10
        internalLastIncludedMessageIDs = []
        
        guard let config = loadedConfig else { return messages }

        let effectiveContext = config.contextLength
        let generationBudget = settings.maxTokens > 0 ? settings.maxTokens : settings.reservedContextBuffer
        let safetyThreshold = effectiveContext - generationBudget
        let runwayTarget = max(0, settings.contextRunway)
        let limitWithRunway = max(0, safetyThreshold - runwayTarget)

        var totalTokens = 0
        if let sysMsg = systemMessage, !sysMsg.isEmpty {
            totalTokens = await countTokens(for: sysMsg) + promptTokenBaggageEst
        }

        var startIndex = messages.count
        var safetyThresholdBreached = false

        for i in stride(from: messages.count - 1, through: 0, by: -1) {
            let fullContent = messages[i].contentWithAttachments
            guard !fullContent.isEmpty else { continue }
            var msgTokens = await countTokens(for: fullContent) + promptTokenBaggageEst

            // add image token estimates
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
                var msgTokens = await countTokens(for: content) + promptTokenBaggageEst
             
                if messages[startIndex].sender == .user, let attachments = messages[startIndex].attachments {
                    let imageTokens = attachments
                        .filter { $0.contentType == .image }
                        .reduce(0) { $0 + $1.tokenEstimate }
                    msgTokens += imageTokens
                }
             
                totalTokens -= msgTokens
                startIndex += 1
            }
        }

        if !messages.isEmpty && startIndex < messages.count {
            if contextAnchorID != messages[startIndex].id {
                contextAnchorID = messages[startIndex].id
            }
        }

        guard startIndex < messages.count else { return [] }

        // this is where we log what message ids were included with this result
        let result = Array(messages[startIndex...])
        internalLastIncludedMessageIDs = result.map { $0.id }
        return result
    }

}
