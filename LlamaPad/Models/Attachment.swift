import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
    
    static func estimateImageTokens(imageData: Data) -> Int {
        #if os(macOS)
        guard let nsImage = NSImage(data: imageData) else { return 768 }
        let size = nsImage.size
        #else
        guard let uiImage = UIImage(data: imageData) else { return 768 }
        let size = uiImage.size
        #endif
        
        var width = size.width
        var height = size.height
        
        // scale to fit within 2048x2048
        let maxDim = max(width, height)
        if maxDim > 2048 {
            let scale = 2048 / maxDim
            width *= scale
            height *= scale
        }
        
        // scale up if shortest side < 768
        let minDim = min(width, height)
        if minDim < 768 {
            let scale = 768 / minDim
            width *= scale
            height *= scale
        }
        
        let tiles = ceil(width / 512) * ceil(height / 512)
        return 85 + Int(170 * tiles)
    }
}
