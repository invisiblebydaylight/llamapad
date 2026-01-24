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
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(messages) { message in
                                MessageView(appState: appState, message: message).id(message.id)
                            }
                            
                            if appState.isGenerating, let pct = appState.processingProgress, let status = appState.processingStatus {
                                // if we're generating and reporting process, currently that's only done for prompt
                                // processing. Display the cicular progress widget
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
                                    }
                                    Spacer()
                                }
                            }
                            
                            // give some space for the scrolling to go past the last message
                            Spacer(minLength: 200)
                                .id("bottom-spacer")
                        }
                    }
                }
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
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled { return }
            
            withAnimation(.easeIn(duration: 0.25)) {
                proxy.scrollTo("bottom-spacer", anchor: .bottom)
            }
        
            lastScrollCount = currentCount
            self.scrollTask = nil
        }
    }
}
