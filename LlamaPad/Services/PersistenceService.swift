import Foundation

/// errors that are thrown when reading configuration or chatlog files
enum PersistenceError: Error, LocalizedError {
    case fileNotFound
    case directoryCreationFailed(Error)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case writeFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "No configuration file found. Please complete initial setup."
        case .directoryCreationFailed(let error):
            return "Failed to create configuration directory: \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "Failed to encode data: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode data: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Failed to save file: \(error.localizedDescription)"
        }
    }
}

struct PersistenceService {
    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.invisiblebydaylight.llamapad"
    private static let appID = "llamapad"
    private static let conversationFolder = "conversations"
    
    /// this gets the application directory in the user's documents folder
    static func getAppDocsDirectory() throws -> URL {
        let fileManager = FileManager.default
        
        do {
            let appSupport = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            
            let folder = appSupport.appendingPathComponent(appID, isDirectory: true)
            
            try fileManager.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            return folder
        } catch {
            throw PersistenceError.directoryCreationFailed(error)
        }
    }
    
    /// this gets the folder that should contain all of the conversations
    static func getConversationsDirectory() throws -> URL {
        let fileManager = FileManager.default
        
        do {
            let appDocs = try getAppDocsDirectory()
            let folder = appDocs.appendingPathComponent(conversationFolder, isDirectory: true)

            try fileManager.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            return folder
        } catch {
            throw PersistenceError.directoryCreationFailed(error)
        }
    }
    
    
    /// this gets access to our application wide support directory
    static func getAppDataDirectory() throws -> URL {
        let fileManager = FileManager.default
        
        do {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            
            let folder = appSupport.appendingPathComponent(bundleID, isDirectory: true)
            
            try fileManager.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            return folder
        } catch {
            throw PersistenceError.directoryCreationFailed(error)
        }
    }

    static func save<T: Encodable>(_ data: T, to fileURL: URL) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            let data = try encoder.encode(data)
            try data.write(to: fileURL, options: .atomic)
        } catch let error as EncodingError {
            throw PersistenceError.encodingFailed(error)
        } catch {
            throw PersistenceError.writeFailed(error)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from fileURL: URL) throws -> T {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw PersistenceError.fileNotFound
            }
            
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(type.self, from: data)
        } catch let error as PersistenceError {
            throw error
        } catch let error as DecodingError {
            throw PersistenceError.decodingFailed(error)
        } catch {
            throw PersistenceError.decodingFailed(error)
        }
    }
    
    /// gets a particular file URL from within the specified Conversation id
    static func conversationFileUrl(for id: UUID, fileName: String) throws -> URL {
        let allConvsFolder = try getConversationsDirectory()
        let convFolder = allConvsFolder.appendingPathComponent(id.uuidString)
        return convFolder.appendingPathComponent(fileName)
    }
        
    private static func configFileURL() throws -> URL {
        let folder = try getAppDataDirectory()
        return folder.appendingPathComponent("config.json")
    }

    static func loadConfiguration() throws -> ModelConfiguration {
        let url = try configFileURL()
        return try load(ModelConfiguration.self, from: url)
    }
    
    static func saveConfiguration(_ config:ModelConfiguration) throws {
        let url = try configFileURL()
        return try save(config, to: url)
    }
}
