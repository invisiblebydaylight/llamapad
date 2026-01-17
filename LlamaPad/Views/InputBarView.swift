import SwiftUI

struct InputBarView: View {
    @ObservedObject var appState: AppState
    @Binding var inputText: String
    
    var onSendUserMessage: (String) -> Void
    var onGenerateAiResponse: (Bool) -> Void

    /// represents the action that this view's button should take when pressed
    private enum NextAction {
        /// stop the currently in-progress text generation
        case StopGeneration
        
        /// add the user's provided text to the chatlog and generate an ai response
        case SendUserMessage
        
        /// generate a new ai response without adding any new text from the user
        case GenerateNewResponse
        
        /// continue the last message from ai
        case Continue
    }

    /// encapsulates the logic of figuring out how the 'send' button will act
    /// to make sure that we're consistent
    private var nextAction: NextAction {
        if appState.isGenerating {
            return .StopGeneration
        } else if !isInputIsEmpty(){
            return .SendUserMessage
        } else if let last = appState.messageLog.last {
            if last.sender == .user {
                return .GenerateNewResponse
            }
        }
        return .Continue
    }

    /// returns the icon to use for the 'send' button.
    private var buttonIcon: String {
        switch nextAction {
        case .StopGeneration:
            return "stop.fill"
        case .SendUserMessage:
            return "paperplane.fill"
        case .GenerateNewResponse:
            return "sparkles"
        case .Continue:
            return "arrow.right.circle"
        }
    }
    
    /// returns the help string for the next action the 'send' button does
    private var buttonTooltip: String {
        switch nextAction {
        case .StopGeneration:
            return "Stop Generating"
        case .SendUserMessage:
            return "Send Message"
        case .GenerateNewResponse:
            return "Generate New Response"
        case .Continue:
            return "Continue Last Message"
        }
    }
        
    /// helper method to encapsulate logic to check the trimmed String in the input TextEditor
    private func isInputIsEmpty() -> Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                    if press.modifiers.contains(.command) {
                        // don't send empty messages
                        guard isReady && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return .handled
                        }

                        let textToSend = inputText
                        inputText = ""
                        
                        // dispatch asynchronously to avoid publishing changes during view update
                        DispatchQueue.main.async {
                            onSendUserMessage(textToSend)
                        }

                        return .handled
                    }
                    return .ignored
                }
            
            Button(action: {
                switch nextAction {
                case .StopGeneration:
                    // if we're genererating already, the button stops the current generation
                    appState.shouldStopGenerating = true
                case .SendUserMessage:
                    // we do that by calling the action passed from the parent.
                    onSendUserMessage(inputText)
                    inputText = ""
                case .GenerateNewResponse:
                    onGenerateAiResponse(false)
                case .Continue:
                    onGenerateAiResponse(true)
                }
            }) {
                Image(systemName: buttonIcon)
                    .font(.title2)
                    .padding(10)
                    .background(appState.isGenerating ? Color.red : Color.blue)
                    .clipShape(Circle())
                    .foregroundColor(.white)
            }
            .padding(.leading, 4)
            .help(buttonTooltip)
        }
        .padding()
        .buttonStyle(.borderless)
        .disabled(!isReady)
        .opacity(isReady ? 1.0 : 0.5)
    }
}
