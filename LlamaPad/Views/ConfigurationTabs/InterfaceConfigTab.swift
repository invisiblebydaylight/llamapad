import SwiftUI

struct InterfaceConfigTab: View {
    @ObservedObject var draftConfig: AppConfiguration

    var body: some View {
        Form {
            Section("Text Size") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    TextField("", value: $draftConfig.appSettings.fontSize,
                              format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Text("pt")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $draftConfig.appSettings.fontSize,
                       in: 12.0...22.0, step: 0.5)
                
                // live preview so you can see what you're getting
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(.system(size: draftConfig.appSettings.fontSize))
                    .padding(.top, 4)
            }
            
            Section("Chat Behavior") {
                Toggle("Auto-scroll during generation",
                       isOn: $draftConfig.appSettings.autoScrollDuringGeneration)
                    .help("Automatically follow new text as the AI generates it. Disable if you prefer to scroll freely while generation is in progress.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
