import Combine
import SwiftUI

// describes who 'sent' the message
enum MessageSender: String, Codable {
    case user = "user"
    case ai = "ai"
    case system = "system"
}

// keep track of performance stats for the message
struct MessageStats: Codable {
    let modelName: String?
    let promptTps: Double?
    let generationTps: Double
}

class Message: ObservableObject, Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case id, sender, content, stats, attachments
    }

    // should be a unique ID for this particular message
    let id = UUID()
    
    // indicates the origin of the message (AI || Human)
    let sender: MessageSender
    
    // the full actual content of the message
    @Published var content: String {
        didSet {
            guard content != oldValue else { return }
            
            if parseComplete {
                // If we're just appending (the streaming case), don't re-parse.
                // Slice off the prefix we already saw and append the delta.
                if let range = content.range(of: oldValue),
                   range.lowerBound == content.startIndex {
                    let delta = String(content[range.upperBound...])
                    parsedContent = ParsedMessage(
                        thinkingContent: parsedContent.thinkingContent,
                        responseContent: parsedContent.responseContent + delta
                    )
                    return
                }
                // If content changed non-monotonically (edit), fall through to re-parse.
                parseComplete = false
            }
            
            let newParsed = ParsedMessage.parse(content)
            parsedContent = newParsed
            parseComplete = (newParsed.thinkingContent != nil && !newParsed.responseContent.isEmpty)
        }
    }
    
    /// Returns the response content with any text attachments folded in
    /// using XML-style file tags. Used by all backends for token counting
    /// and prompt construction.
    var contentWithAttachments: String {
        var content = parsedContent.responseContent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard sender == .user,
              let attachments = attachments,
              !attachments.isEmpty else {
            return content
        }
        
        let attachmentText = attachments.compactMap { att in
            guard let text = att.textContent else { return nil }
            return "<file path=\"\(att.filename)\">\n\(text)\n</file>"
        }.joined(separator: "\n\n")
        
        if !attachmentText.isEmpty {
            content = "\(attachmentText)\n\n\(content)"
        }
        
        return content
    }

    
    // the content property, but with the thinking
    // content parsed into a separate string.
    @Published private(set) var parsedContent: ParsedMessage
    private var parseComplete: Bool = false
    
    // keeps track of whether or not the 'think' block is expanded
    // in the UI for this message
    @Published var isThinkingExpanded: Bool = false
    
    // the performance stats for the message - useful only for
    // non-user messages and locked-in at the time of Message generation.
    @Published var stats: MessageStats?
    
    ///  cloned content attachments associated with this message.
    @Published var attachments: [Attachment]?
    
    init(sender: MessageSender, content: String) {
        self.sender = sender
        self.content = content
        let parsedContent = ParsedMessage.parse(content)
        self.parsedContent = parsedContent
        self.parseComplete = (parsedContent.thinkingContent != nil && !parsedContent.responseContent.isEmpty)
        self.attachments = nil
    }

    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sender = try container.decode(MessageSender.self, forKey: .sender)
        let content = try container.decode(String.self, forKey: .content)
        let stats = try container.decodeIfPresent(MessageStats.self, forKey: .stats)
        let attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments)

        self.init(sender: sender, content: content)
        self.stats = stats
        self.attachments = attachments
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sender, forKey: .sender)
        try container.encode(content, forKey: .content)
        try container.encode(stats, forKey: .stats)
        try container.encodeIfPresent(attachments, forKey: .attachments)
    }
}
