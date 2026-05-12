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
                } else {
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
                        .help(draftConfig.tts.engine == .kokoro ?
                              "Language code (e.g., en, es, fr, ja, ko, zh)" : "Language (e.g. 'English')"
                        )
                }
                .disabled(!draftConfig.tts.isEnabled)
                .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)

                if draftConfig.tts.engine == .qwen3 {
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
                        
                        HStack {
                            Text("Reference Text")
                            Spacer()
                            TextField("", text: $draftConfig.tts.refAudioText)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth:200, maxWidth:300)
                                .help("Transcription of what is being said in the reference audio file.")
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
