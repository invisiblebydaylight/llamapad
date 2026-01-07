import Foundation

struct ParsedMessage {
    let thinkingContent: String?
    let responseContent: String
    
    static func parse(_ content: String) -> ParsedMessage {
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        
        // First check for the opening tag to determine if we're in a thinking block
        let openingTagPattern = "<think>"
        if content.contains(openingTagPattern) {
            // Check for complete thinking block first
            let completeThinkingPattern = "<think>([\\s\\S]*?)</think>"
            if let completeRegex = try? NSRegularExpression(pattern: completeThinkingPattern, options: [.dotMatchesLineSeparators]),
               let completeMatch = completeRegex.firstMatch(in: content, options: [], range: range),
               let thinkingRange = Range(completeMatch.range(at: 1), in: content) {
                
                let thinkingContent = String(content[thinkingRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Remove the thinking block from the response
                let responseContent = completeRegex.stringByReplacingMatches(
                    in: content,
                    options: [],
                    range: range,
                    withTemplate: ""
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                
                return ParsedMessage(
                    thinkingContent: thinkingContent.isEmpty ? nil : thinkingContent,
                    responseContent: responseContent
                )
            }
            
            // If we have opening tag but no closing tag, treat everything after it as thinking
            let incompleteThinkingPattern = "<think>([\\s\\S]*)$"
            if let incompleteRegex = try? NSRegularExpression(pattern: incompleteThinkingPattern, options: [.dotMatchesLineSeparators]),
               let incompleteMatch = incompleteRegex.firstMatch(in: content, options: [], range: range),
               let thinkingRange = Range(incompleteMatch.range(at: 1), in: content) {
                
                let thinkingContent = String(content[thinkingRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                return ParsedMessage(
                    thinkingContent: thinkingContent.isEmpty ? nil : thinkingContent,
                    responseContent: ""  // No response content until thinking is complete
                )
            }
        }
        
        // No thinking content or opening tag found
        return ParsedMessage(thinkingContent: nil, responseContent: content)
    }
}
