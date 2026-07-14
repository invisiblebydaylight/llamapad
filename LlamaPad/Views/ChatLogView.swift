import SwiftUI


struct ChatLogView: View {
    @ObservedObject var appState: AppState
    let messages: [Message]

    /// track the current scroll task
    @State private var scrollTask: Task<Void, Never>? = nil
    
    /// whether or not all messages should get rendered.
    @State private var showAllMessages: Bool = false

    init (appState: AppState) {
        self.appState = appState
        messages = appState.messageLog
    }
    
    private var lastMessageId: UUID? {
        messages.last?.id
    }
    
    private var visibleMessages: [Message] {
        if showAllMessages || self.appState.lastIncludedMessageIDs == nil {
            return messages
        }
        guard let includedIDs = appState.lastIncludedMessageIDs else {
            return messages
        }
        let includedSet = Set(includedIDs)
        // always show the last message (the AI message being generated)
        return messages.filter { includedSet.contains($0.id) || $0.id == messages.last?.id }
    }

    @ViewBuilder
    private var progressIndicator: some View {
        if let pct = appState.processingProgress, let status = appState.processingStatus {
            HStack {
                Spacer()
                if pct <= 0.99 && pct >= 0.01 {
                    VStack(spacing: 8) {
                        ProgressView(value: pct)
                            .progressViewStyle(.circular)
                            .padding(.top, 8)
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if pct < 0.01 {
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .padding(.top, 8)
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var scrollContent: some View {
            if !showAllMessages,
               let includedIDs = appState.lastIncludedMessageIDs,
               includedIDs.count < messages.count {
                let hiddenCount = messages.count - includedIDs.count
                Button("Load \(hiddenCount) Earlier Messages...") {
                    showAllMessages = true
                }
                .padding(.vertical, 8)
            } else {
                Button("Show Only In-Context Messages...") {
                    showAllMessages = false
                }
                .padding(.vertical, 8)
            }

         
            ForEach(visibleMessages) { message in
                MessageView(appState: appState,
                            message: message,
                            isTTSEnabled: appState.modelConfig?.tts.isEnabled ?? false)
                .id(message.id)
            }
            
            progressIndicator
                        
            // invisible anchor for scrolling
            Color.clear.frame(height: 1).id("scrollBottom")
            Color.clear.frame(height: 200)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                if visibleMessages.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "scribble.variable")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary.opacity(0.3))
                        Text("The canvas is blank, Poet.")
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            scrollContent
                        }
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .onKeyPress(phases: .down) { press in
                        if press.key == .upArrow && press.modifiers.contains(.command) {
                            DispatchQueue.main.async {
                                if let firstId = visibleMessages.first?.id {
                                    proxy.scrollTo(firstId, anchor: .top)
                                }
                            }
                            return .handled
                        }
                        if press.key == .downArrow && press.modifiers.contains(.command) {
                            DispatchQueue.main.async {
                                if let lastId = visibleMessages.last?.id {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                            return .handled
                        }
                        
                        return .ignored
                    }

                }
            }
            .onChange(of: appState.currentConversationID) { _, _ in
                showAllMessages = false
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
            if Task.isCancelled { return }
            proxy.scrollTo("scrollBottom", anchor: .bottom)
            self.scrollTask = nil
        }
    }
}
