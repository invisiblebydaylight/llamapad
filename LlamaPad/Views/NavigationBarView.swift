import SwiftUI

struct NavigationBarView: View {
    @ObservedObject var appState: AppState
    var onSettingsTap: () -> Void

    @State private var isShowingDeleteConfirmation = false
    
    var body: some View {
        HStack {
            Button(action: {
                isShowingDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .padding(4)
            }
            .disabled(appState.isGenerating)
            .opacity(appState.isGenerating ? 0.5 : 1.0)
            .confirmationDialog("Are you sure you want to delete all the messages?",
                                isPresented: $isShowingDeleteConfirmation) {
                Button("Clear Chat History", role: .destructive) {
                    // remove messages and save the blank chatlog
                    appState.removeAllMessages()
                    appState.saveChatLog()
                }
            }

            Spacer()
            
            if let path = appState.modelConfig?.modelPath, !path.isEmpty {
                let modelDisplayName = URL(fileURLWithPath: path).lastPathComponent
                Text(modelDisplayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(path)
            } else {
                Text("No Model Loaded")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .padding(4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .buttonStyle(.borderless)
    }
}
