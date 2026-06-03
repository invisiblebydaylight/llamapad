import Foundation

struct ParsedMessage {
    let thinkingContent: String?
    let responseContent: String
    
    static func parse(_ content: String) -> ParsedMessage {
        for pattern in ThinkingPattern.all {
            guard let openingRange = content.range(
                of: pattern.opening,
                options: .caseInsensitive
            ) else { continue }
            
            // Check for complete block
            if let closingRange = content.range(
                of: pattern.closing,
                options: .caseInsensitive,
                range: openingRange.upperBound..<content.endIndex
            ) {
                let thinking = String(content[openingRange.upperBound..<closingRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Remove exactly one tagged block instead of stripping all occurrences
                var response = content
                response.replaceSubrange(openingRange.lowerBound..<closingRange.upperBound, with: "")
                
                return ParsedMessage(
                    thinkingContent: thinking.isEmpty ? nil : thinking,
                    responseContent: String(response).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            
            // Handle incomplete block (streaming)
            let thinking = String(content[openingRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedMessage(
                thinkingContent: thinking.isEmpty ? nil : thinking,
                responseContent: ""
            )
        }
        return ParsedMessage(thinkingContent: nil, responseContent: content)
    }
}
