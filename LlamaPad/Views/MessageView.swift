import SwiftUI

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

// this version of the Message View gets used for messages that do not change
struct StaticMessageView: View {
    let message: Message
    @State private var isThinkingExpanded: Bool
    
    init(message: Message) {
        self.message = message
        _isThinkingExpanded = State(initialValue: message.isThinkingExpanded)
    }

    var body: some View {
        HStack {
            if message.sender == .user {
                Spacer(minLength: 40)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                let isThinking = message.parsedContent.thinkingContent != nil && message.parsedContent.responseContent.isEmpty
                            
                // show thinking section if it exists and is from AI
                if message.sender == .ai, let thinking = message.parsedContent.thinkingContent {
                    ThinkingView(
                        content: thinking,
                        isThinking: isThinking,
                        isExpanded: $isThinkingExpanded)
                }
                
                Text(message.parsedContent.responseContent)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(message.sender == .user ? Color.blue : Color.gray.opacity(0.2))
            .foregroundColor(message.sender == .user ? .white : .primary)
            .cornerRadius(16)

            if message.sender == .ai {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// this is the editable version of the Message View, which should be used
// for streaming responses or otherwise providing observation for changes
struct EditableMessageView: View {
    @ObservedObject var message: Message
    
    var body: some View {
        HStack {
            if message.sender == .user {
                Spacer(minLength: 40)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                let isThinking = message.parsedContent.thinkingContent != nil && message.parsedContent.responseContent.isEmpty
                            
                // show thinking section if it exists and is from AI
                if message.sender == .ai, let thinking = message.parsedContent.thinkingContent {
                    ThinkingView(
                        content: thinking,
                        isThinking: isThinking,
                        isExpanded: $message.isThinkingExpanded)
                }
                
                Text(message.parsedContent.responseContent)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(message.sender == .user ? Color.blue : Color.gray.opacity(0.2))
            .foregroundColor(message.sender == .user ? .white : .primary)
            .cornerRadius(16)

            if message.sender == .ai {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}
