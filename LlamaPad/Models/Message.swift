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
    let promptTps: Double
    let generationTps: Double
}

class Message: ObservableObject, Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case id, sender, content, stats
    }

    // should be a unique ID for this particular message
    let id = UUID()
    
    // indicates the origin of the message (AI || Human)
    let sender: MessageSender
    
    // the full actual content of the message
    @Published var content: String {
        didSet {
            parsedContent = ParsedMessage.parse(content)
        }
    }
    
    // the content property, but with the thinking
    // content parsed into a separate string.
    @Published private(set) var parsedContent: ParsedMessage
    
    // keeps track of whether or not the 'think' block is expanded
    // in the UI for this message
    @Published var isThinkingExpanded: Bool = false
    
    // the performance stats for the message - useful only for
    // non-user messages and locked-in at the time of Message generation.
    @Published var stats: MessageStats?
    
    init(sender: MessageSender, content: String) {
        self.sender = sender
        self.content = content
        let parsedContent = ParsedMessage.parse(content)
        self.parsedContent = parsedContent
    }

    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sender = try container.decode(MessageSender.self, forKey: .sender)
        let content = try container.decode(String.self, forKey: .content)
        let stats = try container.decodeIfPresent(MessageStats.self, forKey: .stats)
        
        self.init(sender: sender, content: content)
        self.stats = stats
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sender, forKey: .sender)
        try container.encode(content, forKey: .content)
        try container.encode(stats, forKey: .stats)
    }
}
