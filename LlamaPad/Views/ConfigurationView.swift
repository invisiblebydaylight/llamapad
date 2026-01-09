import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var templateNames: [String]
    
    @State private var isSysMsgExpanded = false
    @State private var isAdvSamplerExpanded = false
    
    @State private var showingFilePicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    /// Draft configuration - all edits happen here
    @StateObject private var draftConfig: ModelConfiguration

    /// keeps track of the token count for the system message text
    @State private var systemMessageTokenCount: Int = 0
    
    init(appState: AppState) {
        self.appState = appState
        
        let baseConfig = appState.modelConfig ?? ModelConfiguration()
        _draftConfig = StateObject(wrappedValue: ModelConfiguration(baseConfig))
        templateNames = getBuiltinTemplateNames()
    }
 
    
    // Extract just the filename for display
    private var modelFilename: String {
        guard !draftConfig.modelPath.isEmpty else {
            return "No model selected"
        }
        return URL(fileURLWithPath: draftConfig.modelPath).lastPathComponent
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    HStack {
                        Text("Model File")
                        
                        Spacer()
                        
                        if draftConfig.modelPath.isEmpty {
                            Text("GGUF File Required...")
                                .foregroundColor(Color(.systemRed))
                                .italic()
                        } else {
                            Text(URL(fileURLWithPath: draftConfig.modelPath).lastPathComponent)
                                .foregroundColor(.primary)
                        }
                            
                        Button("Browse...") {
                            showingFilePicker = true
                        }
                        .buttonStyle(.bordered)
                        .fixedSize()
                    }
                    
                    HStack {
                        Text("Layers To Offload")
                        TextField("", value: $draftConfig.layerCountToOffload, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.layerCountToOffload, in: 0...200, step: 1)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("Context Length")
                        TextField("", value: $draftConfig.contextLength, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.contextLength, in: 4096...(64*1024), step: 1024)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("Max Generation Length")
                        TextField("", value: $draftConfig.maxGenerationLength, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.maxGenerationLength, in: 64...(64*1024), step: 64)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("Chat Template")
                        Picker("", selection: Binding<String>(
                            get: { draftConfig.chatTemplate ?? "None" },
                            set: { newValue in
                                draftConfig.chatTemplate = (newValue == "None") ? nil : newValue
                            }
                        )) {
                            Text("Autodetect").tag("None")
                            ForEach(templateNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .pickerStyle(.menu)  // Makes it compact and native
                    }
                }

                Section("Sampling") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature")
                            TextField("", value: $draftConfig.customSampler.temperature, format: .number)
                                .multilineTextAlignment(.trailing)
                            Stepper("", value: $draftConfig.customSampler.temperature, in: 0.0...2.0, step: 0.01)
                                .labelsHidden()
                        }
                        HStack {
                            Text("Top-P")
                            TextField("", value: $draftConfig.customSampler.topP, format: .number)
                                .multilineTextAlignment(.trailing)
                            Stepper("", value: $draftConfig.customSampler.topP, in: 0.0...1.0, step: 0.01)
                                .labelsHidden()
                        }
                        HStack {
                            Text("Top-K")
                            TextField("", value: $draftConfig.customSampler.topK, format: .number)
                                .multilineTextAlignment(.trailing)
                            Stepper("", value: $draftConfig.customSampler.topK, in: 0...200)
                                .labelsHidden()
                        }
                        HStack {
                            Text("Min-P")
                            TextField("", value: $draftConfig.customSampler.minP, format: .number)
                                .multilineTextAlignment(.trailing)
                            Stepper("", value: $draftConfig.customSampler.minP, in: 0.0...1.0, step: 0.01)
                                .labelsHidden()
                        }
                    }
                }
                
                DisclosureGroup(isExpanded: $isAdvSamplerExpanded) {
                    HStack {
                        Text("Repetition Penalty")
                        TextField("", value: $draftConfig.customSampler.repeatPenalty, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.customSampler.repeatPenalty, in: 0.5...2.0, step: 0.01)
                            .labelsHidden()
                    }
                    HStack {
                        Text("Repetition Penalty Length")
                        TextField("", value: $draftConfig.customSampler.repeatLastN, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.customSampler.repeatLastN, in: 64...4096, step: 64)
                            .labelsHidden()
                    }
                    HStack {
                        Text("Presence Penalty")
                        TextField("", value: $draftConfig.customSampler.presencePenalty, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.customSampler.presencePenalty, in: -2.0...2.0, step: 0.1)
                            .labelsHidden()
                    }
                    HStack {
                        Text("Frequency Penalty")
                        TextField("", value: $draftConfig.customSampler.freqPenalty, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.customSampler.freqPenalty, in: -2.0...2.0, step: 0.1)
                            .labelsHidden()
                    }
                    HStack {
                        Text("DRY Multiplier")
                        TextField("", value: $draftConfig.customSampler.dryMultiplier, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.customSampler.dryMultiplier, in: 0.0...2.0, step: 0.1)
                            .labelsHidden()
                    }
                    HStack {
                        Text("XTC Probability")
                        TextField("", value: $draftConfig.customSampler.xtcProbability, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.customSampler.xtcProbability, in: 0.0...1.0, step: 0.01)
                            .labelsHidden()
                    }
                    HStack {
                        Text("XTC Threshold")
                        TextField("", value: $draftConfig.customSampler.xtcThreshold, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.customSampler.xtcThreshold, in: 0.0...0.5, step: 0.01)
                            .labelsHidden()
                    }
                    HStack {
                        Text("XTC Minimum Kept")
                        TextField("", value: $draftConfig.customSampler.xtcMinKeep, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.customSampler.xtcMinKeep, in: 0...10, step: 1)
                            .labelsHidden()
                    }
                    HStack {
                        Text("Magic Seed")
                        TextField("", value: $draftConfig.customSampler.magic_seed, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.customSampler.magic_seed)
                            .labelsHidden()
                    }
                    // Reset Advanced button
                    Button("Reset Advanced to Defaults") {
                        draftConfig.customSampler = SamplerSettings()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    .font(.caption)

                } label: {
                    Text("Advanced Sampling")
                        .onTapGesture {
                            withAnimation {
                                isAdvSamplerExpanded.toggle()
                            }
                        }
                }
                
                DisclosureGroup(isExpanded: $isSysMsgExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $draftConfig.systemMessage)
                            .frame(minHeight: 100)
                            .listRowSeparator(.hidden)
                            .scrollContentBackground(.hidden)
                            .onChange(of: draftConfig.systemMessage) {
                                Task {
                                    systemMessageTokenCount = await appState.getTokenCount(for: draftConfig.systemMessage)
                                }
                            }
                            .onAppear(){
                                Task {
                                    systemMessageTokenCount = await appState.getTokenCount(for: draftConfig.systemMessage)
                                }
                            }

                        // Optional: Character counter
                        if systemMessageTokenCount > 0 {
                            Text("\(systemMessageTokenCount) tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowSeparator(.hidden)
                } label: {
                    Text("System Message")
                        .onTapGesture {
                            withAnimation {
                                isSysMsgExpanded.toggle()
                            }
                        }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Language Model Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Changes") {
                        Task {
                            appState.modelConfig = ModelConfiguration(draftConfig)
                            do {
                                try PersistenceService.saveConfiguration(draftConfig)
                                await appState.reloadModel()
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                        }
                        dismiss()
                    }
                    .disabled(draftConfig.modelPath.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType(importedAs: "com.invisiblebydaylight.llamapad.gguf")],
            allowsMultipleSelection: false
        ) { result in
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
                    
                    draftConfig.modelPath = url.path
                    draftConfig.modelBookmark = bookmarkData
                } catch {
                    errorMessage = "Failed to create the bookmark for the model: \(error)"
                    showingError = true
                }
            case .failure(let error):
                errorMessage = "File picker error: \(error)"
                showingError = true
            }
        }
        .alert("Configuration Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
}
