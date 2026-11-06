import Foundation

/// A folder as the Orbit server serializes it (`serializeFolder`). `locked` there means a group root, not a password.
struct OrbitFolder: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var parentId: String?
    var protected: Bool
    var shared: Bool
    var isGroupRoot: Bool
    var canEdit: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id", name, parentId, protected, shared, isGroupRoot, canEdit, createdAt
    }

    init(id: String, name: String, parentId: String? = nil, protected: Bool = false, shared: Bool = false,
         isGroupRoot: Bool = false, canEdit: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.protected = protected
        self.shared = shared
        self.isGroupRoot = isGroupRoot
        self.canEdit = canEdit
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        protected = try c.decodeIfPresent(Bool.self, forKey: .protected) ?? false
        shared = try c.decodeIfPresent(Bool.self, forKey: .shared) ?? false
        isGroupRoot = try c.decodeIfPresent(Bool.self, forKey: .isGroupRoot) ?? false
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct Breadcrumb: Codable, Hashable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey { case id = "_id", name }
}

/// What a folder (or a search) shows.
struct Listing: Equatable {
    var folders: [OrbitFolder] = []
    var files: [OrbitFile] = []
    var breadcrumbs: [Breadcrumb] = []

    var isEmpty: Bool { folders.isEmpty && files.isEmpty }
}

/// A Face ID lock the iOS app keeps on a folder or file, synced through Orbit's settings; the web ignores it.
struct FaceIDLock: Codable, Equatable, Hashable {
    /// No passcode or password fallback: Face ID or nothing.
    var strict: Bool
}

struct OrbitSettings: Codable, Equatable {
    var transcodeVideos: Bool
    var convertImages: Bool
    /// By folder or file id.
    var faceIdLocks: [String: FaceIDLock] = [:]

    init(transcodeVideos: Bool, convertImages: Bool, faceIdLocks: [String: FaceIDLock] = [:]) {
        self.transcodeVideos = transcodeVideos
        self.convertImages = convertImages
        self.faceIdLocks = faceIdLocks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transcodeVideos = try c.decodeIfPresent(Bool.self, forKey: .transcodeVideos) ?? true
        convertImages = try c.decodeIfPresent(Bool.self, forKey: .convertImages) ?? true
        faceIdLocks = try c.decodeIfPresent([String: FaceIDLock].self, forKey: .faceIdLocks) ?? [:]
    }
}

enum OrbitError: Error, Equatable {
    case folderLocked, wrongPassword, forbidden, notFound, tooLarge, offline
    case server(Int, String)

    var message: String {
        switch self {
        case .folderLocked: String(localized: "This folder is protected.")
        case .wrongPassword: String(localized: "Wrong password")
        case .forbidden: String(localized: "You don't have access to this.")
        case .notFound: String(localized: "It's no longer there.")
        case .tooLarge: String(localized: "The file is too large for the server.")
        case .offline: String(localized: "Couldn't reach your Nucleus server.")
        case .server(_, let message): message
        }
    }
}

extension Error {
    var orbitMessage: String {
        if let e = self as? OrbitError { return e.message }
        if self is URLError { return OrbitError.offline.message }
        return localizedDescription
    }
}
