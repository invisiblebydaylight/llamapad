import Combine
import SwiftUI

enum InferenceBackendType: String, Codable, CaseIterable {
    case llamaCPP = "llama.cpp"
    case mlx = "mlx"
    // case remoteAPI = "api"  // future
}

struct TTSConfiguration: Codable {
    var isEnabled: Bool = false
    var modelDirectory: String = ""
    var modelBookmark: Data? = nil
    var autoPlayEnabled: Bool = false
}

class AppConfiguration: ObservableObject, Codable {
    @Published var backendType: InferenceBackendType = .llamaCPP
    @Published var modelPaths: [String] = []
    @Published var modelBookmarks: [Data] = []
    @Published var chatTemplate: String? = nil
    @Published var enableThinking: Bool = true
    @Published var contextLength: Int = 4096
    @Published var maxGenerationLength: Int = 0
    @Published var reservedContextBuffer: Int = 1024
    @Published var contextRunway: Int = 512
    @Published var layerCountToOffload: Int = 99
    @Published var kvCacheType: KVCacheType = .f16
    @Published var customSampler: SamplerSettings = SamplerSettings()
    @Published var tts: TTSConfiguration = TTSConfiguration()

    enum CodingKeys: String, CodingKey {
        case backendType, modelPaths, modelBookmarks, chatTemplate, enableThinking, contextLength, maxGenerationLength, reservedContextBuffer, contextRunway, layerCountToOffload, kvCacheType, customSampler, tts
    }

    init() {}
    
    /// returns a Bool indicating whether or not the `other` AppConfiguration settings require
    /// a model reload in order to be effective.
    func requiresReload(comparedTo other: AppConfiguration?) -> Bool {
        guard let other = other else { return true }
        
        return self.modelPaths != other.modelPaths ||
               self.contextLength != other.contextLength ||
               self.layerCountToOffload != other.layerCountToOffload ||
               self.kvCacheType != other.kvCacheType
    }

    required convenience init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backendType = try container.decodeIfPresent(InferenceBackendType.self, forKey: .backendType) ?? .llamaCPP
        modelPaths = try container.decode([String].self, forKey: .modelPaths)
        modelBookmarks = try container.decode([Data].self, forKey: .modelBookmarks)
        chatTemplate = try container.decodeIfPresent(String.self, forKey: .chatTemplate)
        enableThinking = try container.decodeIfPresent(Bool.self, forKey: .enableThinking) ?? true
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
        self.chatTemplate = other.chatTemplate
        self.enableThinking = other.enableThinking
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
        try container.encode(chatTemplate, forKey: .chatTemplate)
        try container.encode(enableThinking, forKey: .enableThinking)
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

