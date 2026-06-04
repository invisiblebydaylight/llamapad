// nanoseconds per second constant for timing stats
let NS_PER_S = 1_000_000_000.0

// defines the set of thinking block tags that are commonly used by models
struct ThinkingPattern {
    let opening: String
    let closing: String
    
    static let all: [ThinkingPattern] = [
        ThinkingPattern(opening: "<think>", closing: "</think>"),
        ThinkingPattern(opening: "<|channel>thought", closing: "<channel|>"),
        ThinkingPattern(opening: "[think]", closing: "[/think]")
    ]
    
    func appearsAtEnd(of text: String) -> Bool {
        text.lowercased().hasSuffix(opening.lowercased())
    }
}
