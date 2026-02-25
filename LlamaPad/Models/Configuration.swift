import Combine
import SwiftUI

struct TTSConfiguration: Codable {
    var isEnabled: Bool = false
    var modelPath: String = ""
    var modelBookmark: Data? = nil
    var voicePath: String = ""
    var voiceBookmark: Data? = nil
    var autoPlayEnabled: Bool = false
}

class AppConfiguration: ObservableObject, Codable {
    @Published var modelPath: String = ""
    @Published var modelBookmark: Data? = nil
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
        case modelPath, modelBookmark, chatTemplate, enableThinking, contextLength, maxGenerationLength, reservedContextBuffer, contextRunway, layerCountToOffload, kvCacheType, customSampler, tts
    }

    init() {}
    
    /// returns a Bool indicating whether or not the `other` AppConfiguration settings require
    /// a model reload in order to be effective.
    func requiresReload(comparedTo other: AppConfiguration?) -> Bool {
        guard let other = other else { return true }
        
        return self.modelPath != other.modelPath ||
               self.contextLength != other.contextLength ||
               self.layerCountToOffload != other.layerCountToOffload ||
               self.kvCacheType != other.kvCacheType
    }

    required convenience init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelPath = try container.decode(String.self, forKey: .modelPath)
        modelBookmark = try container.decodeIfPresent(Data.self, forKey: .modelBookmark)
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
        self.modelPath = other.modelPath
        self.modelBookmark = other.modelBookmark
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
        try container.encode(modelPath, forKey: .modelPath)
        try container.encode(modelBookmark, forKey: .modelBookmark)
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

