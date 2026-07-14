import Foundation

enum InferenceError: Error, LocalizedError {
    case notLoaded(String)
    case loadFailed(String)
    case generationFailed(String)
    case promptBuildFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notLoaded(let detail),
              .loadFailed(let detail),
             .generationFailed(let detail),
             .promptBuildFailed(let detail):
            return detail
        }
    }
}

struct GenerationSettings {
    let maxTokens: Int
    let enableThinking: Bool
    let reasoningEffort: ReasoningEffort    // only for .remoteApi backend
    let remoteSamplers: Set<String>         // only for .remoteApi backend
    let samplerSettings: SamplerSettings
    let reservedContextBuffer: Int
    let contextRunway: Int
    let chatTemplate: String?
}

@MainActor
protocol InferenceBackend: AnyObject {
    var isLoaded: Bool { get }
    var contextLimit: Int { get }
    
    /// returns the number of tokens in the last ingested prompt.
    /// returns nil if no generation has occurred or the backend doesn't track it.
    var lastPromptTokenCount: Int? { get }
    
    /// returns the message IDs that were included in the last prompt sent to the backend.
    /// returns nil if no generation has occurred or the backend doesn't track it.
    var lastIncludedMessageIDs: [UUID]? { get }

    func load(from config: AppConfiguration) async throws
    func unload() async
    func shutdown()
    
    func countTokens(for text: String) async -> Int
    
    func generate(
        messages: [Message],
        systemMessage: String?,
        isContinuation: Bool,
        settings: GenerationSettings
    ) async throws -> AsyncThrowingStream<GenerationChunk, Error>
}

struct GenerationChunk: Sendable {
    let text: String
    let isPromptProcessing: Bool
    let promptProgress: Double  // 0..1, only valid while isPromptProcessing == true
    let tokensDecoded: Int      // only valid while isPromptProcessing == true
    let tokensGenerated: Int
}
