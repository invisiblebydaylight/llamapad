import Combine
import SwiftUI

enum ReasoningEffort: String, Codable, CaseIterable {
    case max, xhigh, high, medium, low, minimal, none
}

enum TTSEngine: String, Codable, CaseIterable {
    case kokoro = "Kokoro"
    case qwen3 = "Qwen3-TTS"
    case chatterbox = "Chatterbox"
}

enum InferenceBackendType: String, Codable, CaseIterable {
    case llamaCPP = "llama.cpp"
    case mlx = "mlx"
    case remoteAPI = "api"
}

struct TTSConfiguration: Codable {
    var engine: TTSEngine = .kokoro
    var isEnabled: Bool = false
    var modelDirectory: String = ""
    var modelBookmark: Data? = nil
    var refAudioPath: String? = nil
    var refAudioBookmark: Data? = nil
    var refAudioText: String = ""
    var autoPlayEnabled: Bool = false
    var voice: String = ""
    var language: String = "en"
    var cfg: Float? = 0.5
    var emotion: Float? = 0.0
}

struct SamplerSettings : Codable, Equatable {
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

class AppConfiguration: ObservableObject, Codable {
    @Published var backendType: InferenceBackendType = .llamaCPP
    @Published var modelPaths: [String] = []
    @Published var modelBookmarks: [Data] = []
    @Published var apiEndpoint: String = ""
    @Published var apiKey: String = ""
    @Published var apiModelName: String = ""
    @Published var apiEnabledSamplers: Set<String> = []
    @Published var chatTemplate: String? = nil
    @Published var enableThinking: Bool = true
    @Published var apiReasoningEffort: ReasoningEffort = .none
    @Published var contextLength: Int = 4096
    @Published var maxGenerationLength: Int = 0
    @Published var reservedContextBuffer: Int = 1024
    @Published var contextRunway: Int = 512
    @Published var layerCountToOffload: Int = 99
    @Published var kvCacheType: KVCacheType = .f16
    @Published var customSampler: SamplerSettings = SamplerSettings()
    @Published var tts: TTSConfiguration = TTSConfiguration()

    enum CodingKeys: String, CodingKey {
        case backendType, modelPaths, modelBookmarks, apiEndpoint, apiKey, apiModelName, apiEnabledSamplers, chatTemplate, enableThinking, apiReasoningEffort, contextLength, maxGenerationLength, reservedContextBuffer, contextRunway, layerCountToOffload, kvCacheType, customSampler, tts
    }
    
    var isRemote: Bool { backendType == .remoteAPI }

    init() {}
    
    /// returns a Bool indicating whether or not the `other` AppConfiguration settings require
    /// a model reload in order to be effective.
    func requiresReload(comparedTo other: AppConfiguration?) -> Bool {
        guard let other = other else { return true }
        
        return self.backendType != other.backendType ||
               self.modelPaths != other.modelPaths ||
               self.contextLength != other.contextLength ||
               self.layerCountToOffload != other.layerCountToOffload ||
               self.kvCacheType != other.kvCacheType ||
               self.apiEndpoint != other.apiEndpoint ||
               self.apiKey != other.apiKey ||
               self.apiModelName != other.apiModelName
    }

    required convenience init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backendType = try container.decodeIfPresent(InferenceBackendType.self, forKey: .backendType) ?? .llamaCPP
        modelPaths = try container.decode([String].self, forKey: .modelPaths)
        modelBookmarks = try container.decode([Data].self, forKey: .modelBookmarks)
        apiEndpoint = try container.decodeIfPresent(String.self, forKey: .apiEndpoint) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        apiModelName = try container.decodeIfPresent(String.self, forKey: .apiModelName) ?? ""
        apiEnabledSamplers = try container.decodeIfPresent(Set<String>.self, forKey: .apiEnabledSamplers) ?? []
        chatTemplate = try container.decodeIfPresent(String.self, forKey: .chatTemplate)
        enableThinking = try container.decodeIfPresent(Bool.self, forKey: .enableThinking) ?? true
        apiReasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .apiReasoningEffort) ?? .none
        contextLength = try container.decode(Int.self, forKey: .contextLength)
        maxGenerationLength = try container.decode(Int.self, forKey: .maxGenerationLength)
        contextRunway = try container.decode(Int.self, forKey: .contextRunway)
        reservedContextBuffer = try container.decodeIfPresent(Int.self, forKey: .reservedContextBuffer) ?? 1024
        layerCountToOffload = try container.decode(Int.self, forKey: .layerCountToOffload)
        kvCacheType = try container.decodeIfPresent(KVCacheType.self, forKey: .kvCacheType) ?? .f16
        customSampler = try container.decode(SamplerSettings.self, forKey: .customSampler)
        tts = try container.decode(TTSConfiguration.self, forKey: .tts)
    }
    
    // deep copy initializer
    init(_ other: AppConfiguration) {
        self.backendType = other.backendType
        self.modelPaths = other.modelPaths
        self.modelBookmarks = other.modelBookmarks
        self.apiKey = other.apiKey
        self.apiEndpoint = other.apiEndpoint
        self.apiModelName = other.apiModelName
        self.apiEnabledSamplers = other.apiEnabledSamplers
        self.chatTemplate = other.chatTemplate
        self.enableThinking = other.enableThinking
        self.apiReasoningEffort = other.apiReasoningEffort
        self.contextLength = other.contextLength
        self.maxGenerationLength = other.maxGenerationLength
        self.contextRunway = other.contextRunway
        self.reservedContextBuffer = other.reservedContextBuffer
        self.layerCountToOffload = other.layerCountToOffload
        self.kvCacheType = other.kvCacheType
        self.customSampler = other.customSampler
        self.tts = other.tts
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(backendType, forKey: .backendType)
        try container.encode(modelPaths, forKey: .modelPaths)
        try container.encode(modelBookmarks, forKey: .modelBookmarks)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(apiEndpoint, forKey: .apiEndpoint)
        try container.encode(apiModelName, forKey: .apiModelName)
        try container.encode(apiEnabledSamplers, forKey: .apiEnabledSamplers)
        try container.encode(chatTemplate, forKey: .chatTemplate)
        try container.encode(enableThinking, forKey: .enableThinking)
        try container.encode(apiReasoningEffort, forKey: .apiReasoningEffort)
        try container.encode(contextLength, forKey: .contextLength)
        try container.encode(maxGenerationLength, forKey: .maxGenerationLength)
        try container.encode(contextRunway, forKey: .contextRunway)
        try container.encode(reservedContextBuffer, forKey: .reservedContextBuffer)
        try container.encode(layerCountToOffload, forKey: .layerCountToOffload)
        try container.encode(kvCacheType, forKey: .kvCacheType)
        try container.encode(customSampler, forKey: .customSampler)
        try container.encode(tts, forKey: .tts)
    }
}

