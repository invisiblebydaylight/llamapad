// LibLlama.swift imported initially from llama.cpp, which is licensed under MIT as well:
//    https://github.com/ggml-org/llama.cpp/blob/master/examples/llama.swiftui/llama.cpp.swift/LibLlama.swift
//    from commit 8c0d6bb4
//
// Modified to suit this project.

import Foundation
import llama

func initializeLlamaCppBackend() {
    llama_backend_init()
}

func shutdownLlamaCppBackend() {
    llama_backend_free()
}

func getBuiltinTemplateNames() -> [String] {
    // First call: get required buffer size
    let count = llama_chat_builtin_templates(nil, 0)
    guard count > 0 else { return [] }
    
    // Allocate uninitialized buffer
    let buffer = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: Int(count))
    defer { buffer.deallocate() }
    
    // Second call: populate buffer
    let actualCount = llama_chat_builtin_templates(buffer, Int(count))
    guard actualCount == count else {
        print("ERROR: template count mismatch (expected \(count), got \(actualCount))")
        return []
    }
    
    // Convert to Swift strings
    return (0..<Int(actualCount)).compactMap { index in
        guard let cString = buffer[index] else { return nil }
        return String(cString: cString)
    }
}

enum LlamaError: Error, LocalizedError {
    case couldNotInitializeContext
    case modelLoadFailed
    case contextInitFailed
    case completionNotInitialized
    case decodeFailed
    case memoryAllocationFailed
    case notEnoughContext(Int, Int) // (requested size, loaded model's context size)
    case couldNotApplyChatTemplate
    
    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load the model from file"
        case .couldNotInitializeContext:
            return "Failed to create the initial context for the LLM"
        case .contextInitFailed:
            return "Failed to create the initial context for the loaded LLM"
        case .completionNotInitialized:
            return "Must call completionInit() before completionStep()"
        case .decodeFailed:
            return "Failed to decode the next token"
        case .memoryAllocationFailed:
            return "Failed to allocate required memory"
        case .notEnoughContext(let requested, let actual):
            return "The loaded model's context size is too small (\(actual)) for the requested amount of tokens (\(requested))"
        case .couldNotApplyChatTemplate:
            return "Failed to apply the chat template formmatting to generate the prompt string"
        }
    }
}

struct SamplerSettings : Codable {
    var temperature: Float = 0.7
    var topK: Int32 = 40
    var topP: Float = 0.95
    var minP: Float = 0.05
    var xtcThreshold: Float = 0.1
    var xtcProbability: Float = 0.0
    var xtcMinKeep: Int = 1
    var dryMultiplier: Float = 0.0
    var dryBase: Float = 1.75
    var dryAllowedLen: Int32 = 2
    var dryPenaltyLastN: Int32 = 0
    var repeatPenalty: Float = 1.05
    var repeatLastN: Int32 = 2048
    var freqPenalty: Float = 0.0
    var presencePenalty: Float = 0.0
    var magic_seed: UInt32 = 0
}

actor LlamaContext: Sendable {
    var isDone: Bool = false
    let contextLength: UInt32
    var numToPredict: Int32 = 512

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampling: UnsafeMutablePointer<llama_sampler>?
    private var batch: llama_batch?
    private var residentTokens: [llama_token]
    private var samplerSettings: SamplerSettings

    // this variable is used to store temporarily invalid cchars
    private var temporary_invalid_cchars: [CChar]

    // this variable provides a stable lifetime to the token added
    // to the batch in the `completionStep()` function
    private var lastToken: [llama_token] = []

    // number of tokens currently predicted since the last prediction started
    // with a call to completionInit()
    private var currentTokenCount: Int32 = 0
    
    init(model: OpaquePointer, context: OpaquePointer, contextLength: UInt32, samplerSettings: SamplerSettings) {
        self.contextLength = contextLength
        self.model = model
        self.context = context
        self.samplerSettings = samplerSettings
        self.residentTokens = []
        self.temporary_invalid_cchars = []
        self.vocab = llama_model_get_vocab(model)
        let sparams = llama_sampler_chain_default_params()
        self.sampling = llama_sampler_chain_init(sparams)
        
        let n_ctx_train = llama_model_n_ctx_train(model)
        
        llama_sampler_chain_add(self.sampling, llama_sampler_init_penalties(
            samplerSettings.repeatLastN,
            samplerSettings.repeatPenalty,
            samplerSettings.freqPenalty,
            samplerSettings.presencePenalty))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_dry(
            vocab,
            n_ctx_train,
            samplerSettings.dryMultiplier,
            samplerSettings.dryBase,
            samplerSettings.dryAllowedLen,
            samplerSettings.dryPenaltyLastN,
            nil, //TODO: support sequence breakers
            0))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_top_k(samplerSettings.topK))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_top_p(samplerSettings.topP, 1))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_min_p(samplerSettings.minP, 1))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_xtc(
            samplerSettings.xtcProbability,
            samplerSettings.xtcThreshold,
            samplerSettings.xtcMinKeep,
            0))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_temp(samplerSettings.temperature))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_dist(
            samplerSettings.magic_seed == 0 ? LLAMA_DEFAULT_SEED : samplerSettings.magic_seed))
    }
    
    deinit{
        LlamaContext.forceUnload(sampler: sampling, context: context, model: model)
    }
    
    /// this function forces the deallocation of the held memory for the model and its context.
    /// use it for when you don't want to wait for the deconstructor to run or need more
    /// deterministic ordering of operations.
    func unload() {
        LlamaContext.forceUnload(sampler: sampling, context: context, model: model)
        self.sampling = nil
        self.context = nil
        self.model = nil
        self.vocab = nil
    }
    
    /// helper function to free all of our held pointers.
    static func forceUnload(sampler: UnsafeMutablePointer<llama_sampler>?, context: OpaquePointer?, model: OpaquePointer?) {
        if sampler != nil {
            llama_sampler_free(sampler)
        }
        if context != nil {
            llama_free(context)
        }
        if model != nil {
            llama_model_free(model)
        }
    }

    // asynchronously load a model and create a LlamaContext
    static func createContext(path: String, offloadCount: Int32, contextLength: UInt32, samplerSettings: SamplerSettings) async throws -> LlamaContext {
        let initTask = Task.detached {
            return try autoreleasepool {
                var model_params = llama_model_default_params()
                model_params.n_gpu_layers = offloadCount
                
                // turning this off for better memory management
                model_params.use_mmap = false
                
#if targetEnvironment(simulator)
                // simulators don't support Metal
                model_params.n_gpu_layers = 0
#endif
                
                guard let model = llama_model_load_from_file(path, model_params) else {
                    throw LlamaError.modelLoadFailed
                }
                
                // use the thread count heuristic that llama.cpp uses internally
                let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
                var ctx_params = llama_context_default_params()
                ctx_params.no_perf = true
                ctx_params.n_ctx = contextLength
                ctx_params.n_batch = 512
                ctx_params.n_threads       = Int32(maxThreads)
                ctx_params.n_threads_batch = Int32(maxThreads)
                
                guard let ctx = llama_init_from_model(model, ctx_params) else {
                    throw LlamaError.contextInitFailed
                }
                
                return LlamaContext(model: model, context: ctx, contextLength: contextLength, samplerSettings: samplerSettings)
            }
        }
        return try await initTask.value
    }
    
    func setNumberToPredict(_ numToPredict: Int) {
        self.numToPredict = Int32(numToPredict)
    }
    
    /// returns the number of tokens loaded into the context at present.
    func getTokenCount() -> Int {
        self.residentTokens.count
    }
    
    // start the text completion process by tokenizing the prompt and then
    // setting up the batch. it returns the actual number of new tokens
    // ingested in the prompt, which can be different than the total
    // number of tokens in the `text` String because it will reuse
    // already digested tokens if possible.
    func completionInit(text: String,
                        procUpdate: @Sendable @escaping (Double)async->Void = { _ in },
                        canContinue: @Sendable @escaping ()async->Bool = { true }
    ) async throws -> Int {
        isDone = false
        batch = nil
        currentTokenCount = 0
        temporary_invalid_cchars.removeAll()
        
        guard let context, let vocab else {
            throw LlamaError.couldNotInitializeContext
        }

        await procUpdate(0.0) 
        
        let addBOS = llama_vocab_get_add_bos(vocab)
        let newTokens = tokenize(text: text, addBOS: addBOS)

        // we're going to continue where we left off if possible,
        // this is going to check and see how many tokens match up
        var commonPrefixCount = 0
        for i in 0..<min(newTokens.count, residentTokens.count) {
            if newTokens[i] == residentTokens[i] {
                commonPrefixCount += 1
            } else {
                break
            }
        }
        
        // if the prompt is a perfect match, we still re-decode the
        // last token to refresh the logits for the sampler
        if commonPrefixCount == newTokens.count && commonPrefixCount > 0 {
            commonPrefixCount -= 1
        }
        
        // now that we know how many tokens match, we can remove everything
        // that comes after the matching section. this means that we don't
        // have to process the same part of the prompt over again.
        if commonPrefixCount < residentTokens.count {
            let mem = llama_get_memory(context)
            // seq_id 0, from position commonPrefixCount to infinity (-1)
            _ = llama_memory_seq_rm(mem, 0, Int32(commonPrefixCount), -1)
            residentTokens.removeSubrange(commonPrefixCount...)
        }
            
        // now we only decode the new tokens from the prompt
        var tokensDecoded = 0
        let tokensToDecode = Array(newTokens.suffix(from: commonPrefixCount))
        if !tokensToDecode.isEmpty {
            let n_batch_max = Int(llama_n_batch(context))
            for i in stride(from: 0, to: tokensToDecode.count, by: n_batch_max) {
                guard await canContinue() else {
                    break
                }
                
                let n_eval = Int32(min(tokensToDecode.count - i, n_batch_max))
                
                var batched = llama_batch_init(n_eval, 0, 1)
                defer { llama_batch_free(batched) }

                batched.n_tokens = n_eval
                for j in 0..<Int(n_eval) {
                    let currentTokenIdx = i + j
                    let absolutePosition = Int32(commonPrefixCount + currentTokenIdx)
                    
                    batched.token[j] = tokensToDecode[currentTokenIdx]
                    batched.pos[j] = absolutePosition
                    batched.n_seq_id[j] = 1
                    batched.seq_id[j]![0] = 0
                    
                    // we only need the logits for the very last token of the whole prompt
                    let isLastToken = (commonPrefixCount + currentTokenIdx == newTokens.count - 1)
                    batched.logits[j] = isLastToken ? 1 : 0
                }

                if llama_decode(context, batched) != 0 {
                    throw LlamaError.decodeFailed
                }
                tokensDecoded += Int(n_eval)
                await procUpdate(Double(tokensDecoded) / Double(tokensToDecode.count))
                
            }
        }
        
        // update our record of what is in the cache and return the number
        // of tokens actually decoded in this call.
        let actualCount = commonPrefixCount + tokensDecoded
        self.residentTokens = Array(newTokens.prefix(actualCount))
        await procUpdate(1.0)
        
        return tokensDecoded
    }

    // predicts the next token and returns the String equivalent if possible
    // (due to text encoding, it may not return anything and wait to see if the
    // next prediction completes the encoded text).
    // this function sets `isDone` to true when finished predicting either by
    // reaching the number of tokens requested or hitting an end-of-generation
    // token.
    // NOTE: make sure to call completionInit() first!
    func completionStep() async throws -> String {
        if batch != nil {
            if llama_decode(context, batch!) != 0 {
                throw LlamaError.decodeFailed
            }
        }

        // sample the next token
        let newTokenId = llama_sampler_sample(sampling, context, -1)

        // check to see if we hit the end of generation or maximum generation length
        if llama_vocab_is_eog(vocab, newTokenId) || ((currentTokenCount == numToPredict) && (numToPredict != 0)) {
            isDone = true
            let remainingString = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            return remainingString
        }

        // get the C characters for the token, which may or may not be fully UTF-8
        let newTokenChars = tokenToPiece(for: newTokenId)
        temporary_invalid_cchars.append(contentsOf: newTokenChars)

        let validString: String
        if let string = String(validatingUTF8: temporary_invalid_cchars + [0]) {
            // decoded as a valid UTF-8 so use it as the result
            temporary_invalid_cchars.removeAll()
            validString = string
        } else if (0 ..< temporary_invalid_cchars.count).contains(where: {$0 != 0 && String(validatingUTF8: Array(temporary_invalid_cchars.suffix($0)) + [0]) != nil}) {
            // in this case, at least the suffix of the temporary_invalid_cchars can be interpreted as UTF8 string
            let string = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            validString = string
        } else {
            validString = ""
        }
        
        // update the state with the progress
        residentTokens.append(newTokenId)
        lastToken = [newTokenId]
        
        // create batch pointing to persistent storage
        lastToken.withUnsafeMutableBufferPointer { buffer in
            batch = llama_batch_get_one(buffer.baseAddress!, 1)
        }
        
        currentTokenCount += 1

        return validString
    }

    // converts an array of Message objects to a formatted prompt using the model's chat template,
    // but not any embedded jinja code.
    func formatPrompt(messages: [(sender: MessageSender, content: String)], systemMessage: String?, template: String?, isContinue: Bool) throws -> String {
        // convert Message objects into a C llama_chat_message array and setup the
        // defer deallocation function immediately so that this will run even if
        // the function bails out early from throwing an exception
        var chatMessages: [llama_chat_message] = []
        defer {
            for msg in chatMessages {
                free(UnsafeMutablePointer(mutating: msg.role))
                free(UnsafeMutablePointer(mutating: msg.content))
            }
        }
        
        // if a system message is provided, add it first with the "system" role
        if let sysMsg = systemMessage, !sysMsg.isEmpty {
            guard let roleCString = strdup("system") else {
                throw LlamaError.memoryAllocationFailed
            }
            guard let contentCString = strdup(sysMsg) else {
                free(roleCString) // no strings left behind...
                throw LlamaError.memoryAllocationFailed
            }
            chatMessages.append(llama_chat_message(role: roleCString, content: contentCString))
        }
        
        for message in messages {
            let role: String
            switch message.sender {
            case .user:
                role = "user"
            case .ai:
                role = "assistant"
            case .system:
                role = "system"
            }
            
            // create C strings and throw an error if this fails
            guard let roleCString = strdup(role) else {
                throw LlamaError.memoryAllocationFailed
            }
            guard let contentCString = strdup(message.content) else {
                free(roleCString) // free the role we just allocated
                throw LlamaError.memoryAllocationFailed
            }
            
            chatMessages.append(llama_chat_message(role: roleCString, content: contentCString))
        }
        
        // do the first call with an empty buffer to get the required size
        let requiredSize = chatMessages.withUnsafeBufferPointer { chatBuffer -> Int32 in
            llama_chat_apply_template(
                template,
                chatBuffer.baseAddress,
                chatBuffer.count,
                !isContinue,
                nil,
                0
            )
        }
        guard requiredSize > 0 else {
            throw LlamaError.couldNotApplyChatTemplate
        }
        
        // allocate exact buffer size required, +1 for the NULL terminator
        var buffer = [CChar](repeating: 0, count: Int(requiredSize + 1))
        
        // apply the chat template. inside llama.cpp, this will still just use a basic
        // chat format builder, but it will use heuristics on the embedded jinja chat template in the GGUF
        // to match a built in template if it's not just a simple string for the template name.
        let actualSize = chatMessages.withUnsafeBufferPointer { chatBuffer in
            llama_chat_apply_template(
                template,
                chatBuffer.baseAddress,
                chatBuffer.count,
                !isContinue, // add assistant header to generate a response only if not continuing
                &buffer,
                requiredSize
            )
        }
        guard actualSize == requiredSize else {
            throw LlamaError.couldNotApplyChatTemplate
        }
        
        var prompt = String(cString: buffer)
        
        // the basic chat templating built into llama.cpp can add end-of-generation token markers for some
        // formats, which doesn't work well for us if we're trying to continue the message.
        // the simplest solution is to just purge everything that gets added to the prompt after the
        // last messages's content if we're doing a 'continue' generation
        if isContinue, let lastMessage = messages.last {
            if let range = prompt.range(of: lastMessage.content, options: .backwards) {
                prompt = String(prompt[..<range.upperBound])
            }
        }
        
        return prompt
    }

    func tokenize(text: String, addBOS: Bool, parseSpecials: Bool = true) -> [Int32] {
        let utf8Count = text.utf8.count
        let needed = -llama_tokenize(vocab, text, Int32(utf8Count), nil, 0, addBOS, parseSpecials)
        let capacity = Int(needed) + (addBOS ? 1 : 0) + 1
        let buffer = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        
        let count = llama_tokenize(vocab, text, Int32(utf8Count), buffer, Int32(capacity), addBOS, parseSpecials)
        
        return Array(UnsafeBufferPointer(start: buffer, count: Int(count)))
    }
    
    // NOTE: this function doesn't return String because it may still be an incomplete UTF-8 sequence
    private func tokenToPiece(for token: llama_token, includeSpecials: Bool = true) -> [CChar] {
        // get the required buffer size first
        let needed = llama_token_to_piece(vocab, token, nil, 0, 0, includeSpecials)

        // now create the optimally sized buffer
        let length = needed < 0 ? Int(-needed) : Int(needed)
        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: length + 1)
        defer { buffer.deallocate() }

        _ = llama_token_to_piece(vocab, token, buffer, Int32(length), 0, includeSpecials)
        return Array(UnsafeBufferPointer(start: buffer, count: length))
    }
    
    /// pulls the Jinja chat template string from the loaded model.
    func getChatTemplate() -> String? {
        guard let model = self.model else { return nil }
        
        let cTemplate = llama_model_chat_template(model, nil)
        guard let tmpl = cTemplate else { return nil }
        
        return String(cString: tmpl)
    }

    /// returns the string representation of the BOS (Beginning of Sentence) token.
    func getBOSString() -> String {
        guard let vocab else { return "" }
        let bosToken = llama_vocab_bos(vocab)
        let pieces = tokenToPiece(for: bosToken, includeSpecials: true)
        return String(cString: pieces + [0])
    }

    /// returns the string representation of the EOS (End of Sentence) token.
    func getEOSString() -> String {
        guard let vocab else { return "" }
        let eosToken = llama_vocab_eos(vocab)
        let pieces = tokenToPiece(for: eosToken, includeSpecials: true)
        return String(cString: pieces + [0])
    }

}
