import Foundation

struct ParsedMessage {
    let thinkingContent: String?
    let responseContent: String
    
    static func parse(_ content: String) -> ParsedMessage {
        for pattern in ThinkingPattern.all {
            if content.contains(pattern.opening) {
                // Check for complete block
                if let closingRange = content.range(of: pattern.closing),
                   let openingRange = content.range(of: pattern.opening),
                   openingRange.lowerBound < closingRange.lowerBound {
                    
                    let thinkingContent = String(content[openingRange.upperBound..<closingRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let responseContent = content.replacingOccurrences(of: pattern.opening, with: "")
                                                 .replacingOccurrences(of: pattern.closing, with: "")
                                                 .replacingOccurrences(of: thinkingContent, with: "")
                                                 .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    return ParsedMessage(thinkingContent: thinkingContent.isEmpty ? nil : thinkingContent,
                                         responseContent: responseContent)
                }
                
                // Handle incomplete block (streaming)
                if let openingRange = content.range(of: pattern.opening, options: .backwards) {
                    let thinkingContent = String(content[openingRange.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return ParsedMessage(thinkingContent: thinkingContent.isEmpty ? nil : thinkingContent,
                                         responseContent: "")
                }
            }
        }
        return ParsedMessage(thinkingContent: nil, responseContent: content)
    }
}
