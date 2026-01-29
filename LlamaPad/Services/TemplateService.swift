import Foundation
import Jinja

struct TemplateSevice {
    let jinjaStr: String
        
    init(jinjaStr: String) {
        self.jinjaStr = jinjaStr
    }
    
    func render(messages: [(sender: MessageSender, content: String)], addAssistant: Bool = false, enableThinking: Bool = false) throws -> String? {
        let options = Template.Options(
            lstripBlocks: true,  // Strip leading whitespace from blocks
            trimBlocks: true     // Remove trailing newlines from blocks
        )
        let cachedTemplate = try Template(jinjaStr, with: options)
        
        let jinjaMessages = messages.map { msg in
            [
                "role": msg.sender == .user ? "user" : (msg.sender == .ai ? "assistant" : "system"),
                "content": msg.content
            ]
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let today = dateFormatter.string(from: Date())
        let yesterday = dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let fullTimestamp = ISO8601DateFormatter().string(from: Date())

        // NOTE: inside llama.cpp/common/chat.cpp, `common_chat_templates_apply_jinja()` can be
        // used for reference on what parameters to supply for templates.
        // We're still missing: grammar, tool_choice, tools, reasoning_format
        
        let context = [
            "messages": try Value(any:jinjaMessages),
            "today": try Value(any: today),
            "yesterday": try Value(any: yesterday),
            "now": try Value(any: fullTimestamp),
            "add_generation_prompt": try Value(any: addAssistant),
            "enable_thinking": try Value(any: enableThinking)
        ]
        
        let result = try cachedTemplate.render(context)
        return result
    }
}
