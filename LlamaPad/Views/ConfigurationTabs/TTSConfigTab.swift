import SwiftUI
import UniformTypeIdentifiers

enum TTSPickerTarget {
    case model
    case voice
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
                    Toggle("Automatic Play", isOn: $draftConfig.tts.autoPlayEnabled)
                        .help("Automatically play generated text when it is added to the chat")

                }
                .disabled(!draftConfig.tts.isEnabled)
                .opacity(!draftConfig.tts.isEnabled ? 0.5 : 1.0)
                
                VStack {
                    HStack {
                        Text("Kokoro Model File")
                        
                        Spacer()
                        
                        if draftConfig.tts.modelPath.isEmpty {
                            Text("Safetensors File Required...")
                                .foregroundColor(Color(.systemRed))
                                .italic()
                        } else {
                            Text(URL(fileURLWithPath: draftConfig.tts.modelPath).lastPathComponent)
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
                
                VStack {
                    HStack {
                        Text("Kokoro Voice File")
                        
                        Spacer()
                        
                        if draftConfig.tts.voicePath.isEmpty {
                            Text("Safetensors File Required...")
                                .foregroundColor(Color(.systemRed))
                                .italic()
                        } else {
                            Text(URL(fileURLWithPath: draftConfig.tts.voicePath).lastPathComponent)
                                .foregroundColor(.primary)
                        }
                        
                        Button("Browse...") {
                            pickerTarget = .voice
                            showingFilePicker = true
                        }
                        .buttonStyle(.bordered)
                        .fixedSize()
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
            allowedContentTypes: [UTType(filenameExtension: "safetensors", conformingTo: .data) ?? .data],
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
                // generate our persistent bookmark
                let bookmarkData = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                
                switch pickerTarget {
                case .model:
                    draftConfig.tts.modelPath = url.path
                    draftConfig.tts.modelBookmark = bookmarkData
                case .voice:
                    draftConfig.tts.voicePath = url.path
                    draftConfig.tts.voiceBookmark = bookmarkData
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
