extension String {
    func trimmingSuffixWhitespace() -> String {
        guard let lastNonWhitespace = lastIndex(where: { !$0.isWhitespace }) else {
            return "" // String is all whitespace
        }
        return String(self[...lastNonWhitespace])
    }
    
    mutating func trimSuffixWhitespace() {
        guard let lastNonWhitespace = lastIndex(where: { !$0.isWhitespace }) else {
            self = ""
            return
        }
        removeSubrange(index(after: lastNonWhitespace)...)
    }
}
