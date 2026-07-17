import SwiftUI
import UniformTypeIdentifiers

struct InputBarView: View {
    @ObservedObject var appState: AppState
    @Binding var inputText: String
    
    @State private var draftAttachments: [Attachment] = []
    @State private var showingFilePicker = false
    @State private var showingTokenWarning = false
    @State private var pendingAttachment: Attachment? = nil

    var onSendUserMessage: (String, [Attachment]) -> Void
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
        if appState.shouldStopGenerating {
            return "hand.raised.fill"
        }

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
        if appState.shouldStopGenerating {
            return "Cancelling..."
        }
        
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
        VStack {
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
                            guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                return .handled
                            }
                            
                            let textToSend = inputText
                            let attachments = draftAttachments
                            inputText = ""
                            draftAttachments.removeAll()
                            
                            // dispatch asynchronously to avoid publishing changes during view update
                            DispatchQueue.main.async {
                                onSendUserMessage(textToSend, attachments)
                            }
                            
                            return .handled
                        }
                        return .ignored
                    }
                
                Button(action: {
                    showingFilePicker = true
                }) {
                    Image(systemName: "paperclip")
                        .font(.title2)
                        .padding(10)
                        .background(appState.isGenerating ? Color.red : Color.blue)
                        .clipShape(Circle())
                        .foregroundColor(.white)
                        .opacity(appState.shouldStopGenerating ? 0.6 : 1.0)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 4)
                .disabled(appState.isGenerating)
                .help("attach a file to this message")
                
                Button(action: {
                    switch nextAction {
                    case .StopGeneration:
                        // if we're genererating already, the button stops the current generation
                        appState.shouldStopGenerating = true
                    case .SendUserMessage:
                        // we do that by calling the action passed from the parent.
                        let attachments = draftAttachments
                        draftAttachments.removeAll()
                        onSendUserMessage(inputText, attachments)
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
                        .opacity(appState.shouldStopGenerating ? 0.6 : 1.0)
                }
                .padding(.leading, 4)
                .help(buttonTooltip)
                .animation(.easeInOut, value: appState.shouldStopGenerating)
            }
            .padding()
            .buttonStyle(.borderless)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in handleFileSelect(result) }
        .alert("Large File Warning", isPresented: $showingTokenWarning) {
            Button("Attach Anyway") {
                if let att = pendingAttachment { draftAttachments.append(att) }
                pendingAttachment = nil
            }
            Button("Cancel", role: .cancel) { pendingAttachment = nil }
        } message: {
            if let att = pendingAttachment {
                Text("This file is approximately \(att.tokenEstimate) tokens, which is more than 25% of your context window. Attaching it may consume most of your available context.")
            }
        }

        // chip row of draft attachements
        if !draftAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(draftAttachments) { att in
                        AttachmentChipView(
                            attachment: att,
                            onRemove: { draftAttachments.removeAll { $0.id == att.id } }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 28)
            .padding(8)
        }
    }
    
    private func handleFileSelect(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { @MainActor in
                for url in urls {
                    let gotAccess = url.startAccessingSecurityScopedResource()
                    defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
                    
                    guard let data = try? Data(contentsOf: url) else {
                        appState.reportError("Could not read \(url.lastPathComponent).")
                        continue
                    }
                    
                    if let mimeType = detectImageMimeType(for: url) {
                        // it's an image — route to image attachment
                        let estimate = 768
                        let attachment = Attachment(filename: url.lastPathComponent, imageData: data, mimeType: mimeType, tokenEstimate: estimate)
                        tryAppend(attachment, estimate: estimate)
                    } else if let text = String(data: data, encoding: .utf8) {
                        // it's text — route to text attachment
                        let estimate = await (appState.backend?.countTokens(for: text) ?? text.count / 4)
                        let attachment = Attachment(filename: url.lastPathComponent, textContent: text, tokenEstimate: estimate)
                        tryAppend(attachment, estimate: estimate)
                    } else {
                        appState.reportError("Could not read \(url.lastPathComponent) as text or image.")
                    }
                }
            }
        case .failure(let error):
            appState.reportError("File picker error: \(error.localizedDescription)")
        }
    }
    
    private func tryAppend(_ attachment: Attachment, estimate: Int) {
        let threshold = (appState.modelConfig?.contextLength ?? 4096) / 4
        if estimate > threshold {
            pendingAttachment = attachment
            showingTokenWarning = true
        } else {
            draftAttachments.append(attachment)
        }
    }

    private func detectImageMimeType(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return nil
        }
    }

}
