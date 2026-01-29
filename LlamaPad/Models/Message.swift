import Combine
import SwiftUI

// describes who 'sent' the message
enum MessageSender: String, Codable {
    case user = "user"
    case ai = "ai"
    case system = "system"
}

class Message: ObservableObject, Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case id, sender, content
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
    
    init(sender: MessageSender, content: String) {
        self.sender = sender
        self.content = content
        self.parsedContent = ParsedMessage.parse(content)
    }

    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sender = try container.decode(MessageSender.self, forKey: .sender)
        let content = try container.decode(String.self, forKey: .content)
        
        self.init(sender: sender, content: content)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sender, forKey: .sender)
        try container.encode(content, forKey: .content)
    }
}
