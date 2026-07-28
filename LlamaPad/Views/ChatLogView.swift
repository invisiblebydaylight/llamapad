import SwiftUI

#if os(macOS)
import AppKit

/// This helper class is used to detect scrolling changes with the scroll wheel, allowing the ChatLogView to react  to those changes.
/// Other ways of using geometry tricks couldn't reliably work on macOS.
private struct ScrollWheelMonitor: NSViewRepresentable {
    let onScroll: () -> Void
    let onScrollDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll, onScrollDown: onScrollDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitoredView = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.onScrollDown = onScrollDown
        context.coordinator.monitoredView = view
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var onScroll: () -> Void
        var onScrollDown: () -> Void
        weak var monitoredView: NSView?
        private var eventMonitor: Any?

        init(onScroll: @escaping () -> Void, onScrollDown: @escaping () -> Void) {
            self.onScroll = onScroll
            self.onScrollDown = onScrollDown
        }

        func installMonitor() {
            guard eventMonitor == nil else { return }

            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.scrollWheel, .leftMouseDown, .leftMouseDragged]
            ) { [weak self] event in
                guard let self,
                      let view = monitoredView,
                      let window = view.window,
                      event.window === window else {
                    return event
                }

                let locationInWindow = event.locationInWindow
                if event.type ==  .scrollWheel {
                    let location = view.convert(locationInWindow, from: nil)
                    if view.bounds.contains(location) {
                        if event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
                            onScroll()
                        }
                        
                        if event.scrollingDeltaY < 0 {
                            onScrollDown()
                        }
                    }
                } else if event.type == .leftMouseDown || event.type == .leftMouseDragged {
                    if let contentView = window.contentView {
                        let hitView = contentView.hitTest(locationInWindow)
                        if hitView is NSScroller {
                            onScroll()
                        }
                    }
                }
                    
                
                return event
            }
        }

        func removeMonitor() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }
        
        deinit {
            removeMonitor()
        }
    }
}
#endif

private struct StreamingMessageObserver: View {
    @ObservedObject var message: Message
    let onContentChange: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: message.content) { _, _ in
                onContentChange()
            }
    }
}

struct ChatLogView: View {
    @ObservedObject var appState: AppState

    /// whether or not all messages should get rendered.
    @State private var showAllMessages: Bool = false
    
    @State private var isAutoScrollEnabled = true
    @State private var pendingAutoScroll: Task<Void, Never>?
    
    private var lastMessageId: UUID? {
        appState.messageLog.last?.id
    }
    
    private var visibleMessages: [Message] {
        let messages = appState.messageLog
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
    private var contextToggle: some View {
        let messages = appState.messageLog
        let includedIDs = appState.lastIncludedMessageIDs
        
        if showAllMessages {
            // showing everything — only offer to filter if there are actually out-of-context messages
            if let includedIDs = includedIDs, includedIDs.count < messages.count {
                Button("Show Only In-Context Messages...") {
                    showAllMessages = false
                }
                .padding(.vertical, 8)
            }
        } else {
            // showing filtered — only offer to expand if we're actually hiding something
            if let includedIDs = includedIDs {
                let includedSet = Set(includedIDs)
                let visibleCount = messages.filter {
                    includedSet.contains($0.id) || $0.id == messages.last?.id
                }.count
                if visibleCount < messages.count {
                    let hiddenCount = messages.count - visibleCount
                    Button("Load \(hiddenCount) Earlier Messages...") {
                        showAllMessages = true
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    @ViewBuilder
    private var scrollContent: some View {
        contextToggle
     
        ForEach(visibleMessages) { message in
            MessageView(appState: appState,
                        message: message,
                        isTTSEnabled: appState.modelConfig?.tts.isEnabled ?? false)
            .equatable()
            .id(message.id)
        }
        
        progressIndicator
        
        // invisible anchor for scrolling
        Color.clear.frame(height: 1).id("scrollBottom")
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
                    .background {
                        if let lastMessage = appState.messageLog.last {
                            StreamingMessageObserver(message: lastMessage) {
                                scheduleAutoScroll(proxy: proxy)
                            }
                        }
                        #if os(macOS)
                        ScrollWheelMonitor {
                            disableAutoScroll()
                        } onScrollDown: {
                            if !isAutoScrollEnabled {
                                isAutoScrollEnabled = true
                                scheduleAutoScroll(proxy: proxy)
                            }
                        }
                        #endif
                    }
                    #if os(iOS)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { _ in disableAutoScroll() }
                    )
                    #endif
                }
            }
            .onChange(of: appState.currentConversationID) { _, _ in
                showAllMessages = false
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: appState.isGenerating) { _, generating in
                if generating {
                    isAutoScrollEnabled = true
                    scheduleAutoScroll(proxy: proxy)
                }
            }
            .onChange(of: appState.messageLog.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear() {
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private func scheduleAutoScroll(proxy: ScrollViewProxy) {
        guard isAutoScrollEnabled, pendingAutoScroll == nil else { return }

        pendingAutoScroll = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))

            if !Task.isCancelled && isAutoScrollEnabled {
                proxy.scrollTo("scrollBottom", anchor: .bottom)
            }

            pendingAutoScroll = nil
        }
    }
    
    private func disableAutoScroll() {
        isAutoScrollEnabled = false
        pendingAutoScroll?.cancel()
        pendingAutoScroll = nil
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo("scrollBottom", anchor: .bottom)
        }
    }
}
