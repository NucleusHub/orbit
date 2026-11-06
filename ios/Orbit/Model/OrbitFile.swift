import Foundation

enum TranscodeStatus: String, Codable, Hashable {
    case none, pending, processing, done, failed

    var isActive: Bool { self == .pending || self == .processing }
}

/// A file as the Orbit server serializes it (`serializeFile`).
struct OrbitFile: Codable, Identifiable, Hashable {
    let id: String
    var filename: String
    var mimeType: String
    var size: Int64
    var folderId: String?
    var transcodeStatus: TranscodeStatus
    var transcodeProgress: Int?
    var transcodeEta: Double?
    /// Relative raw URL; absent while the file (or its folder) is locked.
    var url: String?
    var protected: Bool
    var shared: Bool
    var canEdit: Bool
    var createdAt: Date
    var updatedAt: Date

    var isLocked: Bool { protected && url == nil }
    var kind: FileKind { FileKind(mime: mimeType) }

    enum CodingKeys: String, CodingKey {
        case id = "_id", filename, mimeType, size, folderId, transcodeStatus, transcodeProgress, transcodeEta, url, protected, shared, canEdit, createdAt, updatedAt
    }

    init(id: String, filename: String, mimeType: String, size: Int64, folderId: String? = nil, transcodeStatus: TranscodeStatus = .none,
         transcodeProgress: Int? = nil, transcodeEta: Double? = nil, url: String? = nil, protected: Bool = false, shared: Bool = false,
         canEdit: Bool = true, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.folderId = folderId
        self.transcodeStatus = transcodeStatus
        self.transcodeProgress = transcodeProgress
        self.transcodeEta = transcodeEta
        self.url = url
        self.protected = protected
        self.shared = shared
        self.canEdit = canEdit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        filename = try c.decode(String.self, forKey: .filename)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? "application/octet-stream"
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        transcodeStatus = (try? c.decodeIfPresent(TranscodeStatus.self, forKey: .transcodeStatus)) ?? TranscodeStatus.none
        transcodeProgress = try c.decodeIfPresent(Int.self, forKey: .transcodeProgress)
        transcodeEta = try c.decodeIfPresent(Double.self, forKey: .transcodeEta)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        protected = try c.decodeIfPresent(Bool.self, forKey: .protected) ?? false
        shared = try c.decodeIfPresent(Bool.self, forKey: .shared) ?? false
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}
