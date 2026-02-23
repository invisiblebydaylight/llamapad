import KokoroSwift
import MLX
import CoreML
import AVFoundation
import Combine
import Safetensors

enum VoiceError: LocalizedError {
    case noVoiceTensor
    case notReady
    case bufferCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .noVoiceTensor: return "No voice tensor found in the voice file. Make sure the right safetensors file is provided."
        case .notReady: return "Voice context is not ready. Make sure to load the model and voice files first."
        case .bufferCreationFailed: return "Failed to create the audio buffer"
        }
    }
}

@MainActor
class VoiceContext: ObservableObject {
    @Published var isPlaying = false
    @Published var isReady = false
    @Published var lastError: String?

    /// this tracks the currently played message, if the data is provided
    @Published var speakingMessageID: UUID?

    /// this should be set to true while the models are loading
    private var isLoadingModel = false
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    // track the URLs used so we can stop accessing them on unload
    private var currentModelURL: URL?
    private var currentVoiceURL: URL?

    /// the loaded kokoro-ios engine
    private var tts: KokoroTTS?
    
    /// the loaded safetensors voice file for the kokoro model
    private var currentVoice: MLXArray?

    var isLoaded: Bool {
        return tts != nil && currentVoice != nil
    }

    init() {
        let sampleRate = Double(KokoroTTS.Constants.samplingRate)
        let outputFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        let audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: outputFormat.channelCount
        )!
        
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)
    }
    
    /// loads the kokoro model safetensors file and the selected kokoro voice safetensors file and throws
    /// an exception if something goes wrong.
    func load(modelSafetensors: URL, voiceSafetensors: URL) async throws {
        guard !isLoadingModel else { return }
        
        unload()
        
        isReady = false
        isLoadingModel = true
        defer {
            isLoadingModel = false
        }
        
        // first load the kokoro-ios engine up with the model
        tts = KokoroTTS(modelPath: modelSafetensors, g2p: .misaki)

        // then load the voice directly from the safetensors file
        let parsedSafetensors = try Safetensors.read(at: voiceSafetensors)
        guard let tensorKey = parsedSafetensors.keys.first else {
            throw VoiceError.noVoiceTensor
        }
        let shapedArray: MLShapedArray<Float> = try parsedSafetensors.mlShapedArray(forKey: tensorKey)
        let scalars = shapedArray.scalars
        
        // scalars is 1d here, but we went the 3d shape kokoro expects
        // while casting each dimension to an Int instead of Int32.
        currentVoice = MLXArray(scalars).reshaped(shapedArray.shape.map { Int($0) })

        isReady = true
    }
    
    func load(from config: TTSConfiguration) async throws {
        guard let modelURL = try resolve(config.modelBookmark, fallback: config.modelPath),
              let voiceURL = try resolve(config.voiceBookmark, fallback: config.voicePath) else {
            throw VoiceError.notReady
        }

        if modelURL.startAccessingSecurityScopedResource() {
            if voiceURL.startAccessingSecurityScopedResource() {
                currentModelURL = modelURL
                currentVoiceURL = voiceURL
                try await self.load(modelSafetensors: modelURL, voiceSafetensors: voiceURL)
            }
        }
    }
    
    private func resolve(_ data: Data?, fallback: String) throws -> URL? {
        if let data = data {
            var isStale = false
            let url = try URL(resolvingBookmarkData: data,
                              options: URL.BookmarkResolutionOptions(),
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            return url
        }
        return fallback.isEmpty ? nil : URL(fileURLWithPath: fallback)
    }
        
    // does the TTS transformation of the supplied text String and then
    // plays the audio out.
    func speak(text: String, config: TTSConfiguration, messageId: UUID?, lang: Language = .enUS) async throws {
        speakingMessageID = messageId
        
        // if we haven't loaded the model yet, give that a shot
        if !isLoaded {
            try await load(from: config)
        }
        
        guard isReady,
              let tts = tts,
              let voiceEmbedding = currentVoice else {
            throw VoiceError.noVoiceTensor
        }
        
        // too heavy of a compute for the main actor...
        let audio = try await Task.detached(priority: .userInitiated) {
            let (audio, _) = try tts.generateAudio(
                voice: voiceEmbedding,
                language: lang,
                text: text
            )
            return audio
        }.value
        
        try playBuffer(audio)
    }
    
    private func playBuffer(_ audio: [Float]) throws {
        let sampleRate = Double(KokoroTTS.Constants.samplingRate)
        let outputFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        let audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: outputFormat.channelCount
        )!
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: AVAudioFrameCount(audio.count)
        ) else {
            throw VoiceError.bufferCreationFailed
        }
        
        let channelCount = Int(outputFormat.channelCount)
        buffer.frameLength = buffer.frameCapacity
        
        audio.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: Float.self, capacity: buf.count) {
                for channel in 0..<channelCount {
                    buffer.floatChannelData![channel].initialize(from: $0, count: buf.count)
                }
            }
        }
        
        try audioEngine.start()
        
        playerNode.scheduleBuffer(buffer, completionHandler: { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.isPlaying = false
                self.speakingMessageID = nil
            }
        })
        
        isPlaying = true
        playerNode.play()
        
        //print("DEBUG: audio Length: " + String(format: "%.4f", Double(audio.count) / sampleRate))
    }
    
    func stopPlaying() {
        playerNode.stop()
        audioEngine.stop()
        isPlaying = false
        speakingMessageID = nil
    }
    
    func unload() {
        stopPlaying()
        tts = nil
        currentVoice = nil
        isReady = false
        isPlaying = false
        speakingMessageID = nil
        
        // release the sandbox hold on the files
        currentModelURL?.stopAccessingSecurityScopedResource()
        currentVoiceURL?.stopAccessingSecurityScopedResource()
        currentModelURL = nil
        currentVoiceURL = nil
    }
}
