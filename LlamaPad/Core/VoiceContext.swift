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
    case securityScopeFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noVoiceTensor: return "No voice tensor found in the voice file. Make sure the right safetensors file is provided."
        case .notReady: return "Voice context is not ready. Make sure to load the model and voice files first."
        case .bufferCreationFailed: return "Failed to create the audio buffer"
        case .securityScopeFailed(let path): return "Failed to obtain security scope for: \(path)"
        }
    }
}

@MainActor
class VoiceContext: ObservableObject {
    @Published var isPlaying = false
    @Published var isReady = false
    @Published var lastError: String?
    @Published var interruptRequested  = false

    /// this tracks the currently played message, if the data is provided
    @Published var speakingMessageID: UUID?

    /// this should be set to true while the models are loading
    private var isLoadingModel = false
    
    private let audioEngine: AVAudioEngine!
    private let playerNode: AVAudioPlayerNode!

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
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)
        
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Error happened initializing TTS... \(error.localizedDescription)")
        }
        #endif
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
    }
    
    /// loads the kokoro model safetensors file and the selected kokoro voice safetensors file and throws
    /// an exception if something goes wrong.
    private func loadModelFiles(modelSafetensors: URL, voiceSafetensors: URL) async throws {
        guard !isLoadingModel else { return }
        
        isReady = false
        isLoadingModel = true
        interruptRequested = false
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
    
    // loads the kokoro model safetensors file and the selected voice safetensors file
    // that is specified in the configuration object; throws an exception on error.
    func load(from config: TTSConfiguration) async throws {
        guard let modelURL = try resolve(config.modelBookmark, fallback: config.modelPath),
              let voiceURL = try resolve(config.voiceBookmark, fallback: config.voicePath) else {
            throw VoiceError.notReady
        }
        
        unload()
        
        guard modelURL.startAccessingSecurityScopedResource() else {
            throw VoiceError.securityScopeFailed(modelURL.path)
        }
        
        guard voiceURL.startAccessingSecurityScopedResource() else {
            throw VoiceError.securityScopeFailed(voiceURL.path)
        }
        currentModelURL = modelURL
        currentVoiceURL = voiceURL
        try await self.loadModelFiles(modelSafetensors: modelURL, voiceSafetensors: voiceURL)
    }
    
    private func resolve(_ data: Data?, fallback: String) throws -> URL? {
        if let data = data {
            var isStale = false
            #if os(macOS)
            let url = try URL(resolvingBookmarkData: data,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            #else
            let url = try URL(resolvingBookmarkData: data,
                              options: [],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            #endif
            return url
        }
        return fallback.isEmpty ? nil : URL(fileURLWithPath: fallback)
    }
        
    // does the TTS transformation of the supplied text String and then
    // plays the audio out.
    func speak(text: String, config: TTSConfiguration, messageId: UUID?, lang: Language = .enUS) async throws {
        // tag this particular messageId as the one we're speaking, if supplied with the UUID
        speakingMessageID = messageId
        defer { speakingMessageID = nil }

        // if we haven't loaded the model yet, give that a shot
        if !isLoaded {
            try await load(from: config)
        }
        
        guard isReady,
              let tts = tts,
              let voiceEmbedding = currentVoice else {
            throw VoiceError.noVoiceTensor
        }
        
        // break the text string into 'paragraphs' by splitting at newlines and trimming
        let paragraphs = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // 'speak' each of them separately so as to *hopefully* not overwhelm the TTS
        interruptRequested = false
        for (i, paragraph) in paragraphs.enumerated() {
            if interruptRequested { break }

            // too heavy of a compute for the main actor...
            let audio = try await Task.detached(priority: .utility) {
                let result = try tts.generateAudio(
                    voice: voiceEmbedding,
                    language: lang,
                    text: paragraph
                ).0
                
                // without clearing the cache, it would appear that memory stacks up
                // until it will cause crashes on iOS.
                MLX.GPU.clearCache()
                
                return result
            }.value

            // wait for the playback to finish before starting the next paragraph
            // but only if it's not the first time through the loop
            if i > 0 {
                while isPlaying && !interruptRequested {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            
            if interruptRequested { break }

            speakingMessageID = messageId
            try playBuffer(audio)
        }
        
        // final delay to wait until the last message is finished playing
        while isPlaying && !interruptRequested {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    private func playBuffer(_ audio: [Float]) throws {
        isPlaying = true

        let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false,
        )!
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: AVAudioFrameCount(audio.count)
        ) else {
            throw VoiceError.bufferCreationFailed
        }
        
        buffer.frameLength = AVAudioFrameCount(audio.count)
        let channels = buffer.floatChannelData!
        let dst: UnsafeMutablePointer<Float> = channels[0]
        audio.withUnsafeBufferPointer { buf in
            precondition(buf.baseAddress != nil)
            let byteCount = buf.count * MemoryLayout<Float>.stride
            UnsafeMutableRawPointer(dst)
                .copyMemory(from: UnsafeRawPointer(buf.baseAddress!), byteCount: byteCount)
        }

        if !audioEngine.isRunning {
            try audioEngine.start()
        }
        
        playerNode.scheduleBuffer(buffer, completionHandler: { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.isPlaying = false
            }
        })

        playerNode.play()
        
        //print("DEBUG: audio Length: " + String(format: "%.4f", Double(audio.count) / 24000))
    }
    
    func stopPlaying() {
        playerNode.stop()
        audioEngine.stop()
        interruptRequested = true
        isPlaying = false
        speakingMessageID = nil
    }
    
    func unload() {
        stopPlaying()
        tts = nil
        currentVoice = nil
        isReady = false
        isPlaying = false
        interruptRequested = true
        speakingMessageID = nil
        
        // release the sandbox hold on the files
        currentModelURL?.stopAccessingSecurityScopedResource()
        currentVoiceURL?.stopAccessingSecurityScopedResource()
        currentModelURL = nil
        currentVoiceURL = nil
    }
}
