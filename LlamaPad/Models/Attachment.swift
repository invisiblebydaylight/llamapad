import Foundation

struct Attachment: Identifiable, Codable {
    let id: UUID
    let filename: String
    let contentType: AttachmentType
    let textContent: String?
    let tokenEstimate: Int
    
    enum AttachmentType: String, Codable {
        case text
        case image // TODO: in the future
    }
    
    init(filename: String, textContent: String, tokenEstimate: Int) {
        self.id = UUID()
        self.filename = filename
        self.contentType = .text
        self.textContent = textContent
        self.tokenEstimate = tokenEstimate
    }
}
