import MLX
import CoreML
import AVFoundation
import Combine
import MLXAudioTTS
import MLXAudioCore

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
    private var producerTask: Task<Void, Never>?

    /// this tracks the currently played message, if the data is provided
    @Published var speakingMessageID: UUID?

    /// this should be set to true while the models are loading
    private var isLoadingModel = false
    
    private let audioEngine: AVAudioEngine!
    private let playerNode: AVAudioPlayerNode!

    // track the URLs used so we can stop accessing them on unload
    private var currentModelURL: URL?
    private var currentRefAudioURL: URL?

    /// the loaded kokoro engine
    private var tts: SpeechGenerationModel?
    
    var isLoaded: Bool {
        return tts != nil
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
    private func loadModelFiles(modelDirectory: URL, config: TTSConfiguration) async throws {
        guard !isLoadingModel else { return }
        
        isReady = false
        isLoadingModel = true
        producerTask = nil
        defer {
            isLoadingModel = false
        }

        switch config.engine {
        case .kokoro:
            let processor = MLXAudioTTS.KokoroMultilingualProcessor()
            tts = try await KokoroModel.fromModelDirectory(modelDirectory, textProcessor: processor)
        case .qwen3:
            tts = try await Qwen3TTSModel.fromModelDirectory(modelDirectory)
        case .chatterbox:
            let chatter = try await ChatterboxModel.fromModelDirectory(modelDirectory, hfToken: nil)
            if let emotion = config.emotion {
                chatter.emotionAdvOverride = emotion
            }
            if let cfg = config.cfg {
                chatter.cfgWeightOverride = cfg
            }
            tts = chatter
        }
        
        isReady = true
    }
    
    // loads the kokoro model safetensors file and the selected voice safetensors file
    // that is specified in the configuration object; throws an exception on error.
    func load(from config: TTSConfiguration) async throws {
        guard let modelURL = try resolve(config.modelBookmark, fallback: config.modelDirectory) else {
            throw VoiceError.notReady
        }
        
        unload()
        
        guard modelURL.startAccessingSecurityScopedResource() else {
            throw VoiceError.securityScopeFailed(modelURL.path)
        }
        
        currentModelURL = modelURL
        try await self.loadModelFiles(modelDirectory: modelURL, config: config)
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
    func speak(text: String, messageId: UUID?, config: TTSConfiguration) async throws {
        // try loading first if we don't have an engine loaded
        if !isLoaded {
            try await load(from: config)
        }
        
        // ensure we're good to go from this point.
        guard isReady, let tts = tts else {
            throw VoiceError.notReady
        }
        
        // tag this particular messageId as the one we're speaking, if supplied with the UUID
        speakingMessageID = messageId
        defer { speakingMessageID = nil }
        
        // make sure any generative parameters are set
        if let chatterboxTTS = tts as? MLXAudioTTS.ChatterboxModel {
            if let emotion = config.emotion {
                chatterboxTTS.emotionAdvOverride = emotion
            }
            if let cfg = config.cfg {
                chatterboxTTS.cfgWeightOverride = cfg
            }
        }
        
        // break the text string into 'paragraphs' by splitting at newlines and trimming
        let paragraphs = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).removingEmoji() }
            .filter { !$0.isEmpty }
        
        
        // if we setup voice cloning data then load it up
        var refAudio: MLXArray? = nil
        var refAudioText: String? = nil
        if !config.refAudioText.isEmpty {
            refAudioText = config.refAudioText
        }
        if  refAudioText != nil,
            let refAudioURL = config.refAudioPath,
            let refURL = try resolve(config.refAudioBookmark, fallback: refAudioURL)
        {
            let gotAccess = refURL.startAccessingSecurityScopedResource()
            defer {
                if gotAccess { refURL.stopAccessingSecurityScopedResource() }
            }
            
            do {
                let (_, refAudioArray) = try loadAudioArray(from: refURL)
                currentRefAudioURL = refURL
                refAudio = refAudioArray
            } catch {
                refAudioText = nil
                print("Warning: Failed to load reference audio: \(error.localizedDescription)")
                // Continue without cloning rather than crashing
            }
        }
        
        // 'speak' each of them separately so as to *hopefully* not overwhelm the TTS
        let (stream, continuation) = AsyncStream.makeStream(of: [Float].self)
        
        // Producer: generates audio as fast as possible
        producerTask = Task.detached(priority: .utility) {
            do {
                for paragraph in paragraphs {
                    if Task.isCancelled { break }
                    
                    let audio = try await tts.generate(
                        text: paragraph,
                        voice: !config.voice.isEmpty ? config.voice : nil,
                        refAudio: refAudio,
                        refText: refAudioText,
                        language: !config.language.isEmpty ? config.language : nil,
                    )
                    
                    MLX.Memory.clearCache()
                    
                    continuation.yield(Array(audio.asArray(Float.self)))
                }
            } catch {
                continuation.finish()
                return
            }
            continuation.finish()
        }
        
        // Consumer: plays audio in order, waiting for each to finish
        for try await audio in stream {
            if producerTask?.isCancelled ?? false || speakingMessageID != messageId { break }
            try playBuffer(audio)
            
            // wait for playback to complete
            while isPlaying && !(producerTask?.isCancelled ?? false) && speakingMessageID == messageId {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        
        if let task = producerTask {
            await task.value
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
        producerTask?.cancel()
        isPlaying = false
        speakingMessageID = nil
    }
    
    func unload() {
        stopPlaying()
        tts = nil
        isReady = false
        isPlaying = false
        producerTask = nil
        speakingMessageID = nil
        
        // release the sandbox hold on the files
        currentModelURL?.stopAccessingSecurityScopedResource()
        currentRefAudioURL?.stopAccessingSecurityScopedResource()
        currentModelURL = nil
        currentRefAudioURL = nil
    }
}

extension String {
    func removingEmoji() -> String {
        return self.replacingOccurrences(
            of: "[\\p{Emoji_Presentation}\\p{Extended_Pictographic}]",
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    }
}
