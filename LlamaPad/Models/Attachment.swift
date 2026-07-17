import Foundation

struct Attachment: Identifiable, Codable {
    let id: UUID
    let filename: String
    let contentType: AttachmentType
    let textContent: String?
    let imageData: Data?
    let mimeType: String
    let tokenEstimate: Int
    
    enum AttachmentType: String, Codable {
        case text
        case image
    }
    
    init(filename: String, textContent: String, tokenEstimate: Int) {
        self.id = UUID()
        self.filename = filename
        self.contentType = .text
        self.textContent = textContent
        self.imageData = nil
        self.mimeType = "text/plain"
        self.tokenEstimate = tokenEstimate
    }
    
    init(filename: String, imageData: Data, mimeType: String, tokenEstimate: Int) {
        self.id = UUID()
        self.filename = filename
        self.contentType = .image
        self.textContent = nil
        self.imageData = imageData
        self.mimeType = mimeType
        self.tokenEstimate = tokenEstimate
    }
}
