import SwiftUI


struct ChatLogView: View {
    @ObservedObject var appState: AppState
    let messages: [Message]

    /// track the current scroll task
    @State private var scrollTask: Task<Void, Never>? = nil
    
    /// track the deepest index we've scrolled to
    @State private var lastScrollCount: Int = 0

    init (appState: AppState) {
        self.appState = appState
        messages = appState.messageLog
    }
    
    private var lastMessageId: UUID? {
        messages.last?.id
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
                } else if pct < 0.1 {
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
            ForEach(messages) { message in
                MessageView(appState: appState,
                            message: message,
                            isTTSEnabled: appState.modelConfig?.tts.isEnabled ?? false)
                .id(message.id)
            }
            
            progressIndicator
            
            // give some space for the scrolling to go past the last message
            Spacer(minLength: 200)
            
            // invisible anchor for scrolling
            Color.clear.frame(height: 1).id("scrollBottom")
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                if messages.isEmpty {
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
                            if let firstId = messages.first?.id {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(firstId, anchor: .top)
                                }
                            }
                            return .handled
                        }
                        if press.key == .downArrow && press.modifiers.contains(.command) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo("scrollBottom", anchor: .bottom)
                            }
                            return .handled
                        }
                        
                        return .ignored
                    }

                }
            }
            .onChange(of: appState.currentConversationID) { _, _ in
                lastScrollCount = 0
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
        let currentCount = appState.messageLog.count
        
        // we only scroll if the count has been increased from our last viewing
        guard currentCount > lastScrollCount else {
            return
        }
        
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            await Task.yield()
            if Task.isCancelled { return }
            proxy.scrollTo("scrollBottom", anchor: .bottom)
            lastScrollCount = currentCount
            self.scrollTask = nil
        }
    }
}
