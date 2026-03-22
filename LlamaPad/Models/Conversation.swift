import SwiftUI

/// this keeps track of metadata for the conversation and is meant to be lightweight
/// and easy to load for the application.
struct ConversationMetadata: Identifiable, Codable {
    /// the unique id for the conversation
    let id: UUID
    
    /// this human-readable title mean to be shown in the interface for the conversation
    var title: String
    
    /// timestamp for when the conversation was created
    var createdAt: Date
    
    /// timestap for when the conversation was laste updated
    var updatedAt: Date
    
    /// the system message to use for this conversation
    var systemMessage: String?
}
