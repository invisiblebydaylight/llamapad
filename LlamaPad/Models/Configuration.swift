import Combine
import SwiftUI

enum ReasoningEffort: String, Codable, CaseIterable {
    case max, xhigh, high, medium, low, minimal, none
}

enum TTSEngine: String, Codable, CaseIterable {
    case kokoro = "Kokoro"
    case qwen3 = "Qwen3-TTS"
    case chatterbox = "Chatterbox"
    case omnivoice = "OmniVoice"
}

enum InferenceBackendType: String, Codable, CaseIterable {
    case llamaCPP = "llama.cpp"
    case mlx = "mlx"
    case remoteAPI = "api"
}

enum Quality: String, Codable, CaseIterable {
    case fast = "Fast"
    case standard = "Standard"
    case high = "High"
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
    var stripCodeBlocks: Bool = true
    var stripMarkdown: Bool = true
    var codeBlockSkipMessage: String = "Skipping a block of code..."
    var cfg: Float? = 0.5
    var emotion: Float? = 0.0
    var hfRepoId: String? = ""
    var voiceQuality: Quality? = .standard
    var voiceSpeed: Float? = 1.0
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engine = try c.decodeIfPresent(TTSEngine.self, forKey: .engine) ?? .kokoro
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        modelDirectory = try c.decodeIfPresent(String.self, forKey: .modelDirectory) ?? ""
        modelBookmark = try c.decodeIfPresent(Data.self, forKey: .modelBookmark)
        refAudioPath = try c.decodeIfPresent(String.self, forKey: .refAudioPath)
        refAudioBookmark = try c.decodeIfPresent(Data.self, forKey: .refAudioBookmark)
        refAudioText = try c.decodeIfPresent(String.self, forKey: .refAudioText) ?? ""
        autoPlayEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoPlayEnabled) ?? false
        voice = try c.decodeIfPresent(String.self, forKey: .voice) ?? ""
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "en"
        stripCodeBlocks = try c.decodeIfPresent(Bool.self, forKey: .stripCodeBlocks) ?? true
        stripMarkdown = try c.decodeIfPresent(Bool.self, forKey: .stripMarkdown) ?? true
        codeBlockSkipMessage = try c.decodeIfPresent(String.self, forKey: .codeBlockSkipMessage) ?? "Skipping a block of code..."
        cfg = try c.decodeIfPresent(Float.self, forKey: .cfg) ?? 0.5
        emotion = try c.decodeIfPresent(Float.self, forKey: .emotion) ?? 0.0
        hfRepoId = try c.decodeIfPresent(String.self, forKey: .hfRepoId) ?? "mlx-community/OmniVoice-bfloat16"
        voiceQuality = try c.decodeIfPresent(Quality.self, forKey: .voiceQuality) ?? .standard
        voiceSpeed = try c.decodeIfPresent(Float.self, forKey: .voiceSpeed) ?? 1.0
    }

}

struct AppSettings: Codable {
    var fontSize: Double = 14.0
    var autoScrollDuringGeneration: Bool = true
    
    init() {
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 14.0
        autoScrollDuringGeneration = try c.decodeIfPresent(Bool.self, forKey: .autoScrollDuringGeneration) ?? true
    }
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

struct APIProfile: Codable, Identifiable {
    let id: UUID                /// Profile ID
    var name: String            /// User-facing name like "openrouter"
    var endpoint: String        /// URL to chat/completions
    var apiKey: String          /// API key to use for requests
    var modelName: String       /// Model to use by the server
    var modelHistory: [String] = [] /// Models used successfully in the past
    var customBody: String? = nil /// JSON to get overlaid on the request body sent to API

    init(name: String, endpoint: String = "", apiKey: String = "", modelName: String = "") {
        self.id = UUID()
        self.name = name
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelName = modelName
        self.modelHistory = []
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, endpoint, apiKey, modelName, modelHistory
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        endpoint = try c.decode(String.self, forKey: .endpoint)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        modelName = try c.decode(String.self, forKey: .modelName)
        modelHistory = try c.decodeIfPresent([String].self, forKey: .modelHistory) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(modelHistory, forKey: .modelHistory)
    }
}

class AppConfiguration: ObservableObject, Codable {
    @Published var backendType: InferenceBackendType = .llamaCPP
    @Published var modelPaths: [String] = []
    @Published var modelBookmarks: [Data] = []
    @Published var activeProfileId: UUID? = nil
    @Published var apiProfiles: [APIProfile] = []
    var activeProfile: APIProfile? {
        guard let id = activeProfileId else { return nil }
        return apiProfiles.first(where: { $0.id == id })
    }
    var apiEndpoint: String {
        return activeProfile?.endpoint ?? ""
    }
    var apiKey: String {
        return activeProfile?.apiKey ?? ""
    }
    var apiModelName: String {
        return activeProfile?.modelName ?? ""
    }
    var apiCustomBody: String? {
        guard let id = activeProfileId,
              let profile = apiProfiles.first(where: { $0.id == id }) else { return nil }
        return profile.customBody
    }
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
    @Published var appSettings: AppSettings = AppSettings()

    enum CodingKeys: String, CodingKey {
        case backendType, modelPaths, modelBookmarks, activeProfileId, apiProfiles, apiEnabledSamplers, chatTemplate, enableThinking, apiReasoningEffort, contextLength, maxGenerationLength, reservedContextBuffer, contextRunway, layerCountToOffload, kvCacheType, customSampler, tts, appSettings
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
               self.apiModelName != other.apiModelName ||
               self.apiCustomBody != other.apiCustomBody
    }
   
    // gets the best history match from the current APIProfile for a given `input` string
    func bestModelMatch(for input: String) -> String? {
        guard !input.isEmpty,
              let id = activeProfileId,
              let profile = apiProfiles.first(where: { $0.id == id }) else { return nil }
        return profile.modelHistory
            .filter { $0.hasPrefix(input) && $0 != input }
            .sorted()
            .first
    }

    // record model name in active profile's history
    func addModelToProfileHistory() {
        if let id = self.activeProfileId,
           let idx = self.apiProfiles.firstIndex(where: { $0.id == id }) {
            let name = self.apiProfiles[idx].modelName
            if !name.isEmpty && !self.apiProfiles[idx].modelHistory.contains(name) {
                self.apiProfiles[idx].modelHistory.append(name)
            }
        }
    }
    
    required convenience init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backendType = try container.decodeIfPresent(InferenceBackendType.self, forKey: .backendType) ?? .llamaCPP
        modelPaths = try container.decode([String].self, forKey: .modelPaths)
        modelBookmarks = try container.decode([Data].self, forKey: .modelBookmarks)
        activeProfileId = try container.decodeIfPresent(UUID.self, forKey: .activeProfileId)
        apiProfiles = try container.decodeIfPresent([APIProfile].self, forKey: .apiProfiles) ?? []
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
        appSettings = try container.decodeIfPresent(AppSettings.self, forKey: .appSettings) ?? AppSettings()
    }
    
    // deep copy initializer
    init(_ other: AppConfiguration) {
        self.backendType = other.backendType
        self.modelPaths = other.modelPaths
        self.modelBookmarks = other.modelBookmarks
        self.activeProfileId = other.activeProfileId
        self.apiProfiles = other.apiProfiles
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
        self.appSettings = other.appSettings
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(backendType, forKey: .backendType)
        try container.encode(modelPaths, forKey: .modelPaths)
        try container.encode(modelBookmarks, forKey: .modelBookmarks)
        try container.encode(activeProfileId, forKey: .activeProfileId)
        try container.encode(apiProfiles, forKey: .apiProfiles)
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
        try container.encode(appSettings, forKey: .appSettings)
    }
}

