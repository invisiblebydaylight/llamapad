import SwiftUI

/// This view is the collapsable control that slides out the 'thought process' for the LLM if
/// thinking tokens were returned.
struct ThinkingView: View {
    let content: String
    let isThinking: Bool
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.blue)
                    Text(isThinking ? "Thinking..." : "Thoughts")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(content)
                        .textSelection(.enabled)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .lineLimit(nil)
                }
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// used to indicate which sidecar tray button is 'armed', or already pressed once.
enum ArmedButton {
    case None
    case Edit
    case Regenerate
    case Delete
    case Cancel
    case Commit
}

/// this extention just factors out some styling options for the sidecar tray buttons.
extension View {
    func sidecarTrayButtonStyle(background: Color, armed: Bool, showTray: Bool) -> some View {
        #if os(iOS)
        self.font(.body)
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(!armed ? Color.clear : background)
            .cornerRadius(10)
        #else
        self.font(.caption)
            .foregroundColor(.secondary)
            .padding(6)
            .contentShape(Circle())
            .background(Circle().fill(!armed ? Color.clear : background))
            .overlay(Circle().stroke(.secondary.opacity(0.6), lineWidth: 1))
        #endif
    }
}

/// This view represents a single `Message` to render in the chatlog view.
struct MessageView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var message: Message
    
    /// whether or not the thinking view is expanded and visible
    @State private var isThinkingExpanded: Bool
    
    /// whether to show the sidecar tray buttons or not
    @State private var showTray: Bool = false
    
    /// the task that ends up eventually toggling `showTray` after some delay; can get cancelled
    @State private var hoverTask: Task<Void, Never>?
    
    /// the button that is 'armed', i.e. already pressed once
    @State private var armedButton: ArmedButton

    /// whether or not the user is editing this message
    @State private var isEditing: Bool = false
    
    /// the drafted contents of the possible edit; not confirmed  yet
    @State private var draftContent: String = ""
    
    @FocusState private var isEditorFocused: Bool

    
    init(appState: AppState, message: Message) {
        self.message = message
        self.appState = appState
        armedButton = .None
        _isThinkingExpanded = State(initialValue: message.isThinkingExpanded)
    }

    private var SidecarTray: some View {
        HStack(spacing: 8) {
            if isEditing {
                // These are the CANCEL and COMMIT buttons shown when editing
                Button(action: {
                    isEditing = false
                    showTray = false
                    armedButton = .None
                }) {
                    Image(systemName: "xmark")
                        .sidecarTrayButtonStyle(background: .gray, armed: armedButton == .Cancel, showTray: showTray)
                        .help("Cancel")
                }
                .buttonStyle(.plain)

                Button(action: {
                    commitEditButtonAction()
                    isEditing = false
                    showTray = false
                    armedButton = .None
                }) {
                    Image(systemName: "checkmark")
                        .sidecarTrayButtonStyle(background: .green, armed: armedButton == .Commit, showTray: showTray)
                        .help("Save Edit")
                }
                .buttonStyle(.plain)
            }
            else {
                // These are the REGEN, EDIT, DELETE buttons shown when not editing
                if message.sender == .ai {
                    // only ai messages get the regenerate option...
                    Button(action: {
                        if armedButton == .Regenerate {
                            regenerateButtonAction()
                            armedButton = .None
                            showTray = false
                        } else {
                            armedButton = .Regenerate
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .sidecarTrayButtonStyle(background: .blue, armed: armedButton == .Regenerate, showTray: showTray)
                            .help("Regenerate")
                    }
                    .buttonStyle(.plain)
                }
                Button(action: {
                    if armedButton == .Edit {
                        editButtonAction()
                        armedButton = .None
                    } else {
                        armedButton = .Edit
                    }
                }) {
                    Image(systemName: "pencil")
                        .sidecarTrayButtonStyle(background: .blue, armed: armedButton == .Edit, showTray: showTray)
                        .help("Edit")
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if armedButton == .Delete {
                        deleteButtonAction()
                        armedButton = .None
                        showTray = false
                    } else {
                        armedButton = .Delete
                    }
                }) {
                    Image(systemName: "trash")
                        .sidecarTrayButtonStyle(background: .red, armed: armedButton == .Delete, showTray: showTray)
                        .help("Delete")
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(showTray ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.2), value: showTray)
    }
    
    private var MessageBubbleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // show thinking section if it exists and is from AI
            let isThinking = message.parsedContent.thinkingContent != nil && message.parsedContent.responseContent.isEmpty
            if message.sender == .ai, let thinking = message.parsedContent.thinkingContent {
                ThinkingView(
                    content: thinking,
                    isThinking: isThinking,
                    isExpanded: $isThinkingExpanded)
            }
            
            // if we're editing, we put everything in the TextField, otherwise it's just a plain Text widget
            if isEditing {
                TextEditor(text: $draftContent)
                    .focused($isEditorFocused)
                    .font(.body)
                    .frame(minHeight: 40, maxHeight: 400)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(.clear)
                    .onKeyPress(keys: [.return]) { press in
                        if press.modifiers.contains(.command) {
                            commitEditButtonAction()
                            isEditing = false
                            showTray = false
                            armedButton = .None
                        }
                        return .ignored
                    }
            } else {
                Text(message.parsedContent.responseContent)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(message.sender == .user ?
                    (isEditing ? Color.blue.opacity(0.2) : Color.blue) :
                        Color.gray.opacity(0.2))
        .foregroundColor(message.sender == .user ? .white : .primary)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.secondary.opacity(showTray ? 1.0 : 0), lineWidth: 1))
        #if os(iOS)
        .onTapGesture {
            withAnimation {
                showTray = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 80)
                .onChanged { _ in
                    // we don't change state mid-drag to prevent jitter
                }
                .onEnded { value in
                    if abs(value.translation.width) > 80 {
                        withAnimation {
                            showTray.toggle()
                        }
                    }
                }
        )
        #endif
    }
    
    var body: some View {
        HStack {
            HStack(alignment: .center, spacing: 0) {
                // user message alignment
                if message.sender == .user {
                    Spacer()
                    SidecarTray
                        .padding(.trailing, 8)
                    MessageBubbleContent
                }
                // ai message alignment
                else {
                    MessageBubbleContent
                    SidecarTray
                        .padding(.leading, 8)
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onChange(of: showTray) { _, shown in
                if !shown {
                    withAnimation {
                        armedButton = .None
                    }
                }
            }
            #if os(macOS)
            .onHover { hovering in
                if hovering {
                    // start a timer, but cancel if they leave quickly
                    hoverTask?.cancel()
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if !Task.isCancelled {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showTray = true
                            }
                        }
                    }
                } else {
                    // immediate dismissal if they leave the row
                    hoverTask?.cancel()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTray = false
                    }
                }

            }
            #endif
        }
    }
    
    private func regenerateButtonAction() {
        guard message.sender == .ai else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            appState.purgeMessages(from: message.id)
            appState.saveChatLog()
            Task {
                await appState.generateChatResponse()
            }
        }
    }
    
    private func editButtonAction() {
        draftContent = message.content
        isEditing = true;
        showTray = true;
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            isEditorFocused = true
        }
    }
    
    private func commitEditButtonAction() {
        message.content = draftContent
        appState.saveChatLog()
    }
    
    private func deleteButtonAction() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            appState.messageLog.removeAll(where: { $0.id == message.id })
            appState.saveChatLog()
        }
    }
}


