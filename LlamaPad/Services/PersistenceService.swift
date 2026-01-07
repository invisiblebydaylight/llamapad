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
    
    private static func getAppDataDirectory() throws -> URL {
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

    private static func save<T: Encodable>(_ data: T, to fileURL: URL) throws {
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

    private static func load<T: Decodable>(_ type: T.Type, from fileURL: URL) throws -> T {
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
        
    private static func chatLogURL() throws -> URL {
        let folder = try getAppDataDirectory()
        return folder.appendingPathComponent("chatlog.json")
    }

    private static func configFileURL() throws -> URL {
        let folder = try getAppDataDirectory()
        return folder.appendingPathComponent("config.json")
    }

    static func loadChatLog() throws -> [Message] {
        let url = try chatLogURL()
        return try load([Message].self, from: url)
    }
    
    static func loadConfiguration() throws -> ModelConfiguration {
        let url = try configFileURL()
        return try load(ModelConfiguration.self, from: url)
    }
    
    static func saveChatLog(_ log:[Message]) throws {
        let url = try chatLogURL()
        return try save(log, to: url)
    }
    
    static func saveConfiguration(_ config:ModelConfiguration) throws {
        let url = try configFileURL()
        return try save(config, to: url)
    }
}
