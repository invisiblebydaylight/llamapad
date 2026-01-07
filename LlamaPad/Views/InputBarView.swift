import SwiftUI

struct InputBarView: View {
    @ObservedObject var appState: AppState
    @Binding var inputText: String
    
    var onSend: (String) -> Void
    
    var body: some View {
        let isReady = appState.llamaContext != nil &&
            appState.modelConfig != nil &&
            appState.isLoadingModel == false
        HStack {
            TextEditor(text: $inputText)
                .padding(4)
                .frame(minHeight: 40, maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
                .scrollContentBackground(.hidden)
#if os(macOS)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
#else
                .background(Color(.secondarySystemBackground).opacity(0.5))
#endif
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                .onKeyPress(keys: [.return]) { press in
                    // don't send empty messages
                    guard isReady && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return .handled
                    }
                    
                    if press.modifiers.contains(.shift) {
                        // Shift+Enter: allow TextEditor to insert newline
                        return .ignored
                    } else {
                        // Enter: send message and prevent newline
                        let textToSend = inputText
                        inputText = ""
                        
                        // dispatch asynchronously to avoid publishing changes during view update
                        DispatchQueue.main.async {
                            onSend(textToSend)
                        }

                        return .handled
                    }
                }
            
            Button(action: {
                if !appState.isGenerating {
                    // don't send empty messages.
                    guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    
                    // call the action passed from the parent.
                    onSend(inputText)
                    
                    inputText = ""
                } else {
                    appState.shouldStopGenerating = true
                }
            }) {
                Image(systemName: appState.isGenerating ? "stop.fill" : "paperplane.fill")
                    .font(.title2)
                    .padding(10)
                    .background(appState.isGenerating ? Color.red : Color.blue)
                    .clipShape(Circle())
                    .foregroundColor(.white)
            }
            .padding(.leading, 4)
        }
        .padding()
        .buttonStyle(.borderless)
        .disabled(!isReady)
        .opacity(isReady ? 1.0 : 0.5)
    }
}
