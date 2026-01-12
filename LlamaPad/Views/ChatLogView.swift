import SwiftUI


struct ChatLogView: View {
    let appState: AppState
    let messages: [Message]

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
                                MessageView(message: message).id(message.id)
                            }
                            // give some space for the scrolling to go past the last message
                            Spacer(minLength: 200)
                                .id("buttom-spacer")
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
        guard let lastId = lastMessageId else { return }
        // task ensures we're on the next run loop without a hardcoded delay
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}
