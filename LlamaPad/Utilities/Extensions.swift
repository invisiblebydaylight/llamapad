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
    
    /// returns a string that is not longer than `maxLength` with the final character being the `trailing` String.
    func truncated(to maxLength: Int, trailing: String = "…") -> String {
        guard self.count > maxLength else { return self }
        return String(self.prefix(maxLength - trailing.count)) + trailing
    }
}
