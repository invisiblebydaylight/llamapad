import SwiftUI

struct ModelConfigTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var draftConfig: AppConfiguration
    @Binding var showingFilePicker: Bool
    
    @State private var isAdvSamplerExpanded = false
    @State private var isRemoteSamplerExpanded = false
    private let templateNames: [String] = LlamaBackend.BuiltinTemplateNames
    
    private var modelFilename: String {
        guard !draftConfig.modelPaths.isEmpty else { return "No model selected" }
        return URL(fileURLWithPath: draftConfig.modelPaths.first!).lastPathComponent
    }
    
    private struct SamplerDef {
        let key: String
        let label: String
    }
    
    private let remoteSamplerDefinitions = [
        SamplerDef(key: "temperature", label: "Temperature"),
        SamplerDef(key: "top_p", label: "Top-P"),
        SamplerDef(key: "top_k", label: "Top-K"),
        SamplerDef(key: "min_p", label: "Min-P"),
        SamplerDef(key: "frequency_penalty", label: "Frequency Penalty"),
        SamplerDef(key: "presence_penalty", label: "Presence Penalty"),
        SamplerDef(key: "repeat_penalty", label: "Repetition Penalty"),
        SamplerDef(key: "dry_multiplier", label: "DRY Multiplier"),
        SamplerDef(key: "xtc_probability", label: "XTC Probability"),
        SamplerDef(key: "xtc_threshold", label: "XTC Threshold"),
        SamplerDef(key: "seed", label: "Seed"),
    ]
    
    private func samplerValueField(for def: SamplerDef) -> AnyView {
        switch def.key {
        case "temperature":
            return AnyView(TextField("", value: $draftConfig.customSampler.temperature, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60))
        case "top_p":
            return AnyView(TextField("", value: $draftConfig.customSampler.topP, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60))
        case "top_k":
            return AnyView(TextField("", value: $draftConfig.customSampler.topK, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60))
        case "min_p":
            return AnyView(TextField("", value: $draftConfig.customSampler.minP, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60))
        case "frequency_penalty":
            return AnyView(TextField("", value: $draftConfig.customSampler.freqPenalty, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60))
        case "presence_penalty":
            return AnyView(TextField("", value: $draftConfig.customSampler.presencePenalty, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60))
        case "repeat_penalty":
            return AnyView(TextField("", value: $draftConfig.customSampler.repeatPenalty, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60))
        case "dry_multiplier":
            return AnyView(TextField("", value: $draftConfig.customSampler.dryMultiplier, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60))
        case "xtc_probability":
            return AnyView(TextField("", value: $draftConfig.customSampler.xtcProbability, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60))
        case "xtc_threshold":
            return AnyView(TextField("", value: $draftConfig.customSampler.xtcThreshold, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60))
        case "seed":
            return AnyView(TextField("", value: $draftConfig.customSampler.magic_seed, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60))
        default:
            return AnyView(EmptyView())
        }
    }
    
    var body: some View {
        let backend = draftConfig.backendType
        Form {
            Section("Model") {
                HStack {
                    Text("Backend")
                    Spacer()
                    Picker("", selection: Binding<InferenceBackendType>(
                        get: { draftConfig.backendType },
                        set: { newValue in
                            DispatchQueue.main.async {
                                draftConfig.backendType = newValue
                                draftConfig.modelPaths.removeAll()
                                draftConfig.modelBookmarks.removeAll()
                                draftConfig.apiKey.removeAll()
                                draftConfig.apiEndpoint.removeAll()
                                draftConfig.apiModelName.removeAll()
                            }
                        }
                    )) {
                        ForEach(InferenceBackendType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                VStack {
                    if backend == .llamaCPP || backend == .mlx {
                        HStack {
                            Text("Model File")
                            
                            Spacer()
                            
                            if draftConfig.modelPaths.isEmpty {
                                Text(backend == .llamaCPP ? "GGUF File(s) Required..." : "MLX Model Directory...")
                                    .foregroundColor(Color(.systemRed))
                                    .italic()
                            } else {
                                Text(URL(fileURLWithPath: draftConfig.modelPaths.first!).lastPathComponent)
                                    .foregroundColor(.primary)
                            }
                            
                            Button("Browse...") {
                                showingFilePicker = true
                            }
                            .buttonStyle(.bordered)
                            .fixedSize()
                        }
                        
                        if draftConfig.requiresReload(comparedTo: appState.modelConfig) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("Model settings changed and will reload upon save...").font(.caption)
                            }
                            .foregroundColor(.orange)
                        }
                    } else { // remote API config...
                        HStack() {
                            Text("API Endpoint:")
                            Spacer()
                            TextField("", text: $draftConfig.apiEndpoint)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth:200, maxWidth:300)
                                .help("The URL to the server that will be used to generate text.")
                        }
                        HStack() {
                            Text("API Key:")
                            Spacer()
                            SecureField("", text: $draftConfig.apiKey)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth:200, maxWidth:300)
                                .help("The key needed to authenticate with the server, if any.")
                        }
                        HStack() {
                            Text("Model Name:")
                            Spacer()
                            TextField("", text: $draftConfig.apiModelName)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth:200, maxWidth:300)
                                .help("The model name recognized by the server to use for text generation.")
                        }
                        
                    }
                }
                
                if backend == .llamaCPP {
                    HStack {
                        Text("Layers To Offload")
                        TextField("", value: $draftConfig.layerCountToOffload, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.layerCountToOffload, in: 0...200, step: 1)
                            .labelsHidden()
                    }
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
                    Stepper("", value: $draftConfig.maxGenerationLength, in: 0...(64*1024), step: 128)
                        .labelsHidden()
                }
                
                if backend == .llamaCPP {
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
                }
                
                if backend == .llamaCPP || backend == .mlx {
                    HStack {
                        Toggle("Enable Reasoning", isOn: $draftConfig.enableThinking)
                            .help("If supported by the model's chat template, this toggles the <think> block.")
                            .disabled(draftConfig.chatTemplate != nil)
                            .opacity(draftConfig.chatTemplate != nil ? 0.5 : 1.0)
                    }
                }
                
                if backend == .remoteAPI {
                    HStack {
                        Text("Reasoning Effort")
                        Spacer()
                        Picker("", selection: Binding<ReasoningEffort>(
                            get: { draftConfig.apiReasoningEffort },
                            set: { newValue in
                                draftConfig.apiReasoningEffort = newValue
                            }
                        )) {
                            ForEach(ReasoningEffort.allCases, id: \.self) { effort in
                                Text(effort.rawValue.capitalized).tag(ReasoningEffort?.some(effort))
                            }
                        }
                    }
                    HStack {
                        DisclosureGroup(isExpanded: $isRemoteSamplerExpanded) {
                            ForEach(remoteSamplerDefinitions, id: \.key) { def in
                                HStack {
                                    Toggle("", isOn: Binding(
                                        get: { draftConfig.apiEnabledSamplers.contains(def.key) },
                                        set: { isOn in
                                            if isOn {
                                                draftConfig.apiEnabledSamplers.insert(def.key)
                                            } else {
                                                draftConfig.apiEnabledSamplers.remove(def.key)
                                            }
                                       }
                                    ))
                                    .labelsHidden()
                                    .frame(minHeight: 20)
                                    
                                    Text(def.label)
                                    Spacer()

                                    if draftConfig.apiEnabledSamplers.contains(def.key) {
                                        samplerValueField(for: def)
                                            .frame(height: 20)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        label: {
                           Text("Remote Sampler Overrides")
                               .onTapGesture {
                                   withAnimation {
                                       isRemoteSamplerExpanded.toggle()
                                   }
                               }
                       }
                    }
                }
            }
            
            if backend == .llamaCPP || backend == .mlx {
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
            }
            
            DisclosureGroup(isExpanded: $isAdvSamplerExpanded) {
                if backend == .llamaCPP || backend == .mlx {
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
                    if backend == .llamaCPP {
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
                    }
                    HStack {
                        Text("Magic Seed")
                        TextField("", value: $draftConfig.customSampler.magic_seed, format: .number)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $draftConfig.customSampler.magic_seed)
                            .labelsHidden()
                    }
                }
                HStack {
                    Text("Reserved Context Buffer")
                    TextField("", value: $draftConfig.reservedContextBuffer, format: .number)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $draftConfig.reservedContextBuffer, in: 128...4096, step: 128)
                        .labelsHidden()
                        .opacity(draftConfig.maxGenerationLength > 0 ? 0.5 : 1.0)
                        .disabled(draftConfig.maxGenerationLength > 0) // only is effective if no max generation length set
                }
                HStack {
                    Text("Context Runway")
                    TextField("", value: $draftConfig.contextRunway, format: .number)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $draftConfig.contextRunway, in: 128...4096, step: 128)
                        .labelsHidden()
                }
                
                if backend == .llamaCPP {
                    HStack {
                        Text("KV Cache Type")
                        Spacer()
                        Picker("", selection: $draftConfig.kvCacheType) {
                            ForEach(KVCacheType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }.pickerStyle(.menu)
                    }
                }
                
                // Reset Advanced button
                Button("Reset Advanced to Defaults") {
                    draftConfig.customSampler = SamplerSettings()
                    draftConfig.kvCacheType = .f16
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
