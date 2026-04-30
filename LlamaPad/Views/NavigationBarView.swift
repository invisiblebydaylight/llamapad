import SwiftUI

struct NavigationBarView: View {
    @ObservedObject var appState: AppState
    var onSettingsTap: () -> Void

    @State private var isShowingDeleteConfirmation = false
    
    var body: some View {
        let isLoaded = appState.backend?.isLoaded ?? false
        HStack {
            Button(action: {
                isShowingDeleteConfirmation = true
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .padding(4)
                    Text("Clear")
                }
            }
            .disabled(appState.isBusy)
            .opacity(appState.isBusy ? 0.5 : 1.0)
            .confirmationDialog("Are you sure you want to delete all the messages?",
                                isPresented: $isShowingDeleteConfirmation) {
                Button("Clear Chat History", role: .destructive) {
                    // remove messages and save the blank chatlog
                    appState.removeAllMessages()
                    appState.saveChatLog()
                }
            }

            Spacer()
            
            if let config = appState.modelConfig,
               !config.modelPaths.isEmpty,
               let path = config.modelPaths.first,
               !path.isEmpty
            {
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
            
            Button(action: {
                // this button acts as a toggle and should load the model if not loaded
                // and free it otherwise if it already is loaded.
                if !isLoaded{
                    Task {
                        await appState.reloadModel()
                    }
                } else {
                    Task {
                        await appState.unloadModel()
                    }
                }
            }) {
                VStack(spacing: 2){
                    Image(systemName: isLoaded ? "eject" : "arrow.down.circle")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .padding(4)
                    Text(isLoaded ? "Eject" : "Load")
                }
            }
            .disabled(appState.isBusy)
            
            Button(action: onSettingsTap) {
                VStack(spacing: 2) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .padding(4)
                    Text("Config")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .buttonStyle(.borderless)
    }
}
