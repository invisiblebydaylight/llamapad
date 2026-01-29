import Combine
import SwiftUI

class ModelConfiguration: ObservableObject, Codable {
    @Published var modelPath: String = ""
    @Published var modelBookmark: Data? = nil
    @Published var chatTemplate: String? = nil
    @Published var enableThinking: Bool = true
    @Published var contextLength: Int = 4096
    @Published var maxGenerationLength: Int = 0
    @Published var reservedContextBuffer: Int = 1024
    @Published var layerCountToOffload: Int = 99
    @Published var customSampler: SamplerSettings = SamplerSettings()

    enum CodingKeys: String, CodingKey {
        case modelPath, modelBookmark, chatTemplate, enableThinking, contextLength, maxGenerationLength, reservedContextBuffer, layerCountToOffload, customSampler
    }

    init() {}

    required convenience init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelPath = try container.decode(String.self, forKey: .modelPath)
        modelBookmark = try container.decodeIfPresent(Data.self, forKey: .modelBookmark)
        chatTemplate = try container.decodeIfPresent(String.self, forKey: .chatTemplate)
        enableThinking = try container.decodeIfPresent(Bool.self, forKey: .enableThinking) ?? true
        contextLength = try container.decode(Int.self, forKey: .contextLength)
        maxGenerationLength = try container.decode(Int.self, forKey: .maxGenerationLength)
        reservedContextBuffer = try container.decodeIfPresent(Int.self, forKey: .reservedContextBuffer) ?? 1024
        layerCountToOffload = try container.decode(Int.self, forKey: .layerCountToOffload)
        customSampler = try container.decode(SamplerSettings.self, forKey: .customSampler)
    }
    
    // deep copy initializer
    init(_ other: ModelConfiguration) {
        self.modelPath = other.modelPath
        self.modelBookmark = other.modelBookmark
        self.chatTemplate = other.chatTemplate
        self.enableThinking = other.enableThinking
        self.contextLength = other.contextLength
        self.maxGenerationLength = other.maxGenerationLength
        self.reservedContextBuffer = other.reservedContextBuffer
        self.layerCountToOffload = other.layerCountToOffload
        self.customSampler = other.customSampler
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelPath, forKey: .modelPath)
        try container.encode(modelBookmark, forKey: .modelBookmark)
        try container.encode(chatTemplate, forKey: .chatTemplate)
        try container.encode(enableThinking, forKey: .enableThinking)
        try container.encode(contextLength, forKey: .contextLength)
        try container.encode(maxGenerationLength, forKey: .maxGenerationLength)
        try container.encode(reservedContextBuffer, forKey: .reservedContextBuffer)
        try container.encode(layerCountToOffload, forKey: .layerCountToOffload)
        try container.encode(customSampler, forKey: .customSampler)
    }
}

