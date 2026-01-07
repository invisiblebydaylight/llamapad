import Foundation
import Combine
import SwiftUI

@MainActor
class AppState: ObservableObject {
    /// this should be set to the URL used to load the model and used to
    /// track security access for it.
    private var currentModelURL: URL?
    
    @Published var modelConfig: ModelConfiguration?
    
    /// main storage for all of the messages in the log
    @Published var messageLog: [Message] = []
    
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

    init() {
        // start off by loading the configuration file first, if it exists
        do {
            modelConfig = try PersistenceService.loadConfiguration()
            if modelConfig != nil {
                Task {
                    await loadModelFromConfiguration()
                }
            }
        } catch PersistenceError.fileNotFound {
            // ignore this and don't report it; it'll freak out first time users
        }
        catch {
            reportError("Configuration error: \(error.localizedDescription)")
        }
        
        // next, try to load the chatlog file, if it exists
        do {
            messageLog = try PersistenceService.loadChatLog()
        } catch PersistenceError.fileNotFound {
            // ignore this and don't report it; it'll freak out first time users
        } catch {
            reportError("Chatlog error: \(error.localizedDescription)")
        }
    }

    // a helper to trigger the UI alerts
    func reportError(_ message: String) {
        self.lastErrorMessage = message
        self.showingErrorAlert = true
    }

    func reloadModel() async {
        await unloadModel()
        await loadModelFromConfiguration()
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
    
    private func validateModelPath(_ path: String) -> Bool {
        #if os(iOS)
        // On iOS, ensure file exists in our sandbox
        return FileManager.default.fileExists(atPath: path)
        #else
        // On macOS, check access more thoroughly
        return FileManager.default.isReadableFile(atPath: path)
        #endif
    }

    // generates an AI response based on the current message log using the embedded model formatting
    func generateChatResponse() async {
        guard let config = modelConfig else {
            reportError("Error: No configuration available; hit that gear icon and setup the app.")
            return
        }
        guard let llamaContext else {
            reportError("Error: Model not loaded and it really should be at this point... Interesting.")
            return
        }
        
        // set the generation control flags appropriately and defer the reset of
        // the generation control flags to their default state
        self.isGenerating = true
        self.shouldStopGenerating = false
        defer {
            self.isGenerating = false
            self.shouldStopGenerating = false
        }
        
        // prepare messages (remove thinking blocks, filter by context) and
        // transform it into a Sendable tuple
        let processedMessages = await prepareMessagesForPrompt()
        
        let prompt: String
        do {
            prompt = try await llamaContext.formatPrompt(messages: processedMessages, template: config.chatTemplate)
        } catch {
            reportError("Prompt formatting failed: \(error.localizedDescription)")
            return
        }
        
        // add placeholder AI message that we'll update as tokens arrive
        let aiMessage = Message(sender: .ai, content: "")
        self.messageLog.append(aiMessage)
        
        // initialize completion
        let t_start = DispatchTime.now().uptimeNanoseconds
        do {
            await llamaContext.setNumberToPredict(modelConfig!.maxGenerationLength)
            try await llamaContext.completionInit(text: prompt)
        } catch {
            // remove prediction placeholder on failure
            reportError("Completion initialization failed: \(error.localizedDescription)")
            self.messageLog.removeLast()
            return
        }
        let promptTokenCount = await llamaContext.getTokenCount()
        
        // generate tokens and update UI incrementally
        var generatedTokens = 0
        var fullResponse = ""
        var timeToFirstToken: UInt64 = 0
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
        
        // clean up
        await llamaContext.clear()
        
        // print statistics
        let t_heat = Double(timeToFirstToken - t_start) / NS_PER_S
        let t_end = DispatchTime.now().uptimeNanoseconds
        let t_generation = Double(t_end - timeToFirstToken) / NS_PER_S
        let prompt_tps = Double(promptTokenCount) / t_heat
        let generation_tps = Double(generatedTokens-1) / t_generation
        
        print("Info: Generation complete:")
        print("  Time to first token: \(t_heat)s")
        print("  Prompt speeds: \(promptTokenCount) tokens ; \(prompt_tps) t/s")
        print("  Generation speeds: \(generatedTokens) tokens ; \(generation_tps) t/s")
        
        do {
            try PersistenceService.saveChatLog(messageLog)
        } catch {
            reportError("Warning: Failed to save chat log: \(error.localizedDescription)")
        }
    }
    
    // rough token estimation (1 token ≈ 4 chars for English text)
    private func estimateTokenCount(for text: String) -> Int {
        return max(1, text.count / 4)
    }
    
    // prepares messages for prompt by removing thinking blocks and filtering by context size
    private func prepareMessagesForPrompt() async -> [(sender: MessageSender, content: String)] {
        guard let llamaContext = llamaContext else { return [] }
        
        // reserve space for generation budget and template overhead
        let contextLength = Int(llamaContext.contextLength)
        let generationBudget = await Int(llamaContext.numToPredict)
        let availableTokens = contextLength - generationBudget
        
        var totalTokensUsed = 0
        var processedMessages: [(sender: MessageSender, content: String)] = []
        
        // process from newest to oldest to prioritize recent context
        for message in messageLog.reversed() {
            let parsed = ParsedMessage.parse(message.content)
            let contentForPrompt = parsed.responseContent.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // skip empty messages (e.g., thinking-only partial messages)
            guard !contentForPrompt.isEmpty else { continue }
            
            let estimatedTokens = estimateTokenCount(for: contentForPrompt)
            
            // stop if adding this message would exceed context
            if totalTokensUsed + estimatedTokens > availableTokens {
                break
            }
            
            totalTokensUsed += estimatedTokens
            processedMessages.append((sender: message.sender, content: contentForPrompt))
        }
        
        // return in chronological order
        return processedMessages.reversed()
    }
}
