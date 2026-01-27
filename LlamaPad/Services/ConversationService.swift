import SwiftUI

struct ConversationService {
    private static let metadataFile = "conversation.json"
    private static let chatLogFile = "chatlog.json"

    /// returns a list of all conversations found in the documents directory,
    /// sorted by most recently updated.
    static func listConversations() throws -> [ConversationMetadata] {
        let root = try PersistenceService.getConversationsDirectory()
        print("DEBUG: Root URL: \(root.path)")
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )

        return directories.compactMap { url in
            guard url.hasDirectoryPath else { return nil }
            let metaURL = url.appendingPathComponent(metadataFile)
            return try? PersistenceService.load(ConversationMetadata.self, from: metaURL)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// creates the directory structure and initial files for a new conversation.
    static func createConversation(title: String = "New Discourse") throws -> ConversationMetadata {
        let newMeta = ConversationMetadata(
            id: UUID(),
            title: title,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try saveMetadata(newMeta)
        // Initialize an empty chat log
        try saveChatLog([], for: newMeta.id)
        
        return newMeta
    }
    
    static func setTitle(for id: UUID, newTitle:String) throws {
        if var meta = try? loadMetadata(for: id) {
            meta.title = newTitle
            meta.updatedAt = Date()
            try saveMetadata(meta)
        }
    }

    static func loadChatLog(for id: UUID) throws -> [Message] {
        let url = try PersistenceService.conversationFileUrl(for: id, fileName: chatLogFile)
        return try PersistenceService.load([Message].self, from: url)
    }

    static func saveChatLog(_ log: [Message], for id: UUID) throws {
        let url = try PersistenceService.conversationFileUrl(for: id, fileName: chatLogFile)
        let directory = url.deletingLastPathComponent()
        
        //ensure path is created
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil)
        } catch {
            print("ERROR: Failed to create conversation directory: \(error.localizedDescription)")
        }
        
        try PersistenceService.save(log, to: url)
        
        // Update the timestamp in the metadata
        if var meta = try? loadMetadata(for: id) {
            meta.updatedAt = Date()
            try saveMetadata(meta)
        }
    }

    /// deletes the whole conversation directory and all files in it.
    static func deleteConversation(id: UUID) throws {
        let root = try PersistenceService.getConversationsDirectory()
        let folder = root.appendingPathComponent(id.uuidString)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    private static func loadMetadata(for id: UUID) throws -> ConversationMetadata {
        let url = try PersistenceService.conversationFileUrl(for: id, fileName: metadataFile)
        return try PersistenceService.load(ConversationMetadata.self, from: url)
    }

    private static func saveMetadata(_ meta: ConversationMetadata) throws {
        let url = try PersistenceService.conversationFileUrl(for: meta.id, fileName: metadataFile)
        let directory = url.deletingLastPathComponent()
        
        //ensure path is created
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil)
        } catch {
            print("ERROR: Failed to create conversation directory: \(error.localizedDescription)")
        }
        
        try PersistenceService.save(meta, to: url)
    }
}

