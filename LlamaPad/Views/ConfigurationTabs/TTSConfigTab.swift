import SwiftUI
import UniformTypeIdentifiers

enum TTSPickerTarget {
    case model
    case refAudio
}

struct TTSConfigTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var draftConfig: AppConfiguration
    @Binding var showingError: Bool
    @Binding var errorMessage: String
    
    @State private var showingFilePicker = false
    @State private var pickerTarget: TTSPickerTarget = .model
    @State private var isSpeechTextProcessingExpanded = false

    var body: some View {
        Form {
            Section("Text to Speech") {
                HStack {
                    Toggle("Enable Text-to-Speech", isOn: $draftConfig.tts.isEnabled)
                }
                
                HStack {
                    Text("Engine")
                    Spacer()
                    Picker("", selection: Binding<TTSEngine>(
                        get: { draftConfig.tts.engine },
                        set: { newValue in
                            DispatchQueue.main.async {
                                draftConfig.tts.engine = newValue
                            }
                        }
                    )) {
                        ForEach(TTSEngine.allCases, id: \.self) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .disabled(!draftConfig.tts.isEnabled)
                .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)
             
                HStack {
                    Toggle("Automatic Play", isOn: $draftConfig.tts.autoPlayEnabled)
                        .help("Automatically play generated text when it is added to the chat")

                }
                .disabled(!draftConfig.tts.isEnabled)
                .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)
                
                VStack {
                    if draftConfig.tts.engine != .omnivoice {
                        HStack {
                            Text("TTS Model Folder")
                            
                            Spacer()
                            
                            if draftConfig.tts.modelDirectory.isEmpty {
                                Text("TTS model folder required...")
                                    .foregroundColor(Color(.systemRed))
                                    .italic()
                            } else {
                                Text(URL(fileURLWithPath: draftConfig.tts.modelDirectory).lastPathComponent)
                                    .foregroundColor(.primary)
                            }
                            
                            Button("Browse...") {
                                pickerTarget = .model
                                showingFilePicker = true
                            }
                            .buttonStyle(.bordered)
                            .fixedSize()
                            
                        }
                    } else {
                        HStack {
                            Text("HuggingFace Repo ID")
                            Spacer()
                            TextField("", text: Binding(
                                get: {draftConfig.tts.hfRepoId ?? "mlx-community/OmniVoice-bfloat16" },
                                set: {draftConfig.tts.hfRepoId = $0 }
                            ))
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 200, maxWidth: 300)
                        }
                    }
                }
                .disabled(!draftConfig.tts.isEnabled)
                .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)
                
                if draftConfig.tts.engine == .kokoro {
                    HStack {
                        Text("Voice Name")
                        Spacer()
                        TextField("", text: $draftConfig.tts.voice)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width:200)
                            .help("Kokoro voice name (e.g., af_heart, af_bell, am_adam)")
                    }
                    .disabled(!draftConfig.tts.isEnabled)
                    .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)
                } else if draftConfig.tts.engine  == .qwen3 || draftConfig.tts.engine == .omnivoice {
                    HStack {
                        Text("Voice Description")
                        Spacer()
                        TextField("", text: $draftConfig.tts.voice)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth:200, maxWidth:300)
                            .help("Description of the voice.")
                    }
                    .disabled(!draftConfig.tts.isEnabled)
                    .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)
                }
                
                HStack {
                    Text("Language")
                    Spacer()
                    TextField("", text: $draftConfig.tts.language)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width:200)
                        .help(draftConfig.tts.engine != .qwen3 ?
                              "Language code (e.g., en, es, fr, ja, ko, zh)" : "Language (e.g. 'English')"
                        )
                }
                .disabled(!draftConfig.tts.isEnabled)
                .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)

                if draftConfig.tts.engine == .qwen3 || draftConfig.tts.engine == .chatterbox  || draftConfig.tts.engine == .omnivoice {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Reference Audio")
                            Spacer()
                            if draftConfig.tts.refAudioPath == nil {
                                Text("No file selected")
                                    .foregroundColor(.secondary)
                                    .italic()
                            } else {
                                Text(URL(fileURLWithPath: draftConfig.tts.refAudioPath!).lastPathComponent)
                                    .lineLimit(1)
                            }
                            Button("Browse...") {
                                pickerTarget = .refAudio
                                showingFilePicker = true
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if draftConfig.tts.engine == .qwen3 || draftConfig.tts.engine == .omnivoice {
                            HStack {
                                Text("Reference Text")
                                Spacer()
                                TextField("", text: $draftConfig.tts.refAudioText)
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth:200, maxWidth:300)
                                    .help("Transcription of what is being said in the reference audio file.")
                            }
                        }
                        
                        if draftConfig.tts.refAudioPath != nil {
                            Button("Clear") {
                                draftConfig.tts.refAudioPath = nil
                                draftConfig.tts.refAudioBookmark = nil
                                draftConfig.tts.refAudioText = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }

                    }
                    .disabled(!draftConfig.tts.isEnabled)
                    .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)
                }
                
                if draftConfig.tts.engine == .chatterbox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("CFG Weight")
                                .help("Pacing and stability control")
                            Spacer()
                            Text(String(format: "%.2f", draftConfig.tts.cfg ?? 0.5))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        Slider(value: Binding<Float>(
                            get: { draftConfig.tts.cfg ?? 0.5 },
                            set: { draftConfig.tts.cfg = $0 }
                        ), in: 0.0...1.0)

                        HStack {
                            Text("Emotion")
                                .help("Expressiveness intensity")
                            Spacer()
                            Text(String(format: "%.2f", draftConfig.tts.emotion ?? 0.0))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        Slider(value: Binding<Float>(
                            get: { draftConfig.tts.emotion ?? 0.0 },
                            set: { draftConfig.tts.emotion = $0 }
                        ), in: 0.0...1.0)
                    }
                    .disabled(!draftConfig.tts.isEnabled)
                    .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)
                }
                
                if draftConfig.tts.engine == .omnivoice {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Quality")
                            Spacer()
                            Picker("", selection: Binding<Quality>(
                                get: {draftConfig.tts.voiceQuality ?? .standard },
                                set: {newValue in
                                    DispatchQueue.main.async {
                                        draftConfig.tts.voiceQuality = newValue
                                    }
                                }
                            )) {
                                ForEach(Quality.allCases, id: \.self) { q in
                                    Text(q.rawValue).tag(q)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                        HStack {
                            Text("Speed")
                            Spacer()
                            Text(String(format: "%.1f×", draftConfig.tts.voiceSpeed ?? 1.0))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        Slider(
                            value: Binding(
                                get: { draftConfig.tts.voiceSpeed ?? 1.0},
                                set: { draftConfig.tts.voiceSpeed = $0 }
                            ),
                            in: 0.5...2.0, step: 0.1)
                    }
                    .disabled(!draftConfig.tts.isEnabled)
                    .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)
                }
                
                DisclosureGroup(isExpanded: $isSpeechTextProcessingExpanded) {
                    Toggle("Skip code blocks", isOn: $draftConfig.tts.stripCodeBlocks)
                    
                    if draftConfig.tts.stripCodeBlocks {
                        TextField("Skip message", text: $draftConfig.tts.codeBlockSkipMessage)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Toggle("Strip markdown formatting", isOn: $draftConfig.tts.stripMarkdown)
                }
                label: {
                   Text("Speech Text Processing")
                       .onTapGesture {
                           withAnimation {
                               isSpeechTextProcessingExpanded.toggle()
                           }
                       }
                }
                .disabled(!draftConfig.tts.isEnabled)
                .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: pickerTarget == .model
                ? [.folder]
                : [UTType(filenameExtension: "wav", conformingTo: .data) ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let url = urls.first!
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gotAccess { url.stopAccessingSecurityScopedResource() }
            }

            do {
                // generate our persistent bookmark; we use read-only for the
                // audio reference, but we take read-write for the TTS model
                // directory because the mlx-audio-swift library will write
                // files to it for some engine types (like Qwen3-TTS).
                #if os(macOS)
                let bookmarkData = try url.bookmarkData(
                    options: pickerTarget == .model ?
                        .withSecurityScope :
                        .securityScopeAllowOnlyReadAccess,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                #else
                let bookmarkData = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                #endif
                
                switch pickerTarget {
                case .model:
                    draftConfig.tts.modelDirectory = url.path
                    draftConfig.tts.modelBookmark = bookmarkData
                case .refAudio:
                    draftConfig.tts.refAudioPath = url.path
                    draftConfig.tts.refAudioBookmark = bookmarkData
                }
            } catch {
                errorMessage = "Failed to create the bookmark: \(error)"
                showingError = true
            }
        case .failure(let error):
            errorMessage = "File picker error: \(error)"
            showingError = true
        }
    }
}
