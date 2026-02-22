import SwiftUI

struct ModelConfigTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var draftConfig: AppConfiguration
    @Binding var showingFilePicker: Bool
    
    @State private var isAdvSamplerExpanded = false
    private let templateNames: [String] = getBuiltinTemplateNames()
    
    private var modelFilename: String {
        guard !draftConfig.modelPath.isEmpty else { return "No model selected" }
        return URL(fileURLWithPath: draftConfig.modelPath).lastPathComponent
    }
    
    private var needsReload: Bool {
        if let current = appState.modelConfig {
            return (draftConfig.modelPath != current.modelPath) ||
                   (draftConfig.contextLength != current.contextLength) ||
                   (draftConfig.layerCountToOffload != current.layerCountToOffload)
        }
        return true
    }
    
    var body: some View {
        Form {
            Section("Model") {
                VStack {
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
                    
                    if needsReload {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Model settings changed and will reload upon save...").font(.caption)
                        }
                        .foregroundColor(.orange)
                    }
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
                        Text("Jinja / Autodetect").tag("None")
                        ForEach(templateNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)  // Makes it compact and native
                }
                
                HStack {
                    Toggle("Enable Reasoning", isOn: $draftConfig.enableThinking)
                        .help("If supported by the model's chat template, this toggles the <think> block.")
                        .disabled(draftConfig.chatTemplate != nil)
                        .opacity(draftConfig.chatTemplate != nil ? 0.5 : 1.0)
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
                HStack {
                    Text("Reserved Context Buffer")
                    TextField("", value: $draftConfig.reservedContextBuffer, format: .number)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $draftConfig.reservedContextBuffer, in: 128...4096, step: 128)
                        .labelsHidden()
                }
                HStack {
                    Text("Context Runway")
                    TextField("", value: $draftConfig.contextRunway, format: .number)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $draftConfig.contextRunway, in: 128...4096, step: 128)
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
                Text("Advanced Settings")
                    .onTapGesture {
                        withAnimation {
                            isAdvSamplerExpanded.toggle()
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
