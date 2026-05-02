import SwiftUI
import UniformTypeIdentifiers

enum TTSPickerTarget {
    case model
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
                        
                        if draftConfig.tts.modelDirectory.isEmpty {
                            Text("Kokoro Folder Required...")
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
                
                VStack {
                    HStack {
                        Text("Kokoro Voice File")
                        
                        Spacer()
                        
                        // FIXME: TTS voice selection
                        Text("Disabled...")
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
            allowedContentTypes: [.folder],
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
                #if os(macOS)
                let bookmarkData = try url.bookmarkData(
                    options: .securityScopeAllowOnlyReadAccess,
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
