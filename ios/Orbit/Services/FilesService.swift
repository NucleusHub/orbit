import Foundation

/// Everything the app asks of an Orbit server. `OrbitClient` talks to one; `SampleFiles` is in memory.
protocol FilesService: AnyObject, Sendable {
    func browse(_ folderID: String?, password: String?) async throws -> Listing
    /// Folders and files matching `query` anywhere; breadcrumbs are empty.
    func search(_ query: String) async throws -> Listing
    func allFolders() async throws -> [OrbitFolder]
    func createFolder(name: String, parentID: String?) async throws -> OrbitFolder
    func renameFolder(_ id: String, to name: String) async throws -> OrbitFolder
    func moveFolder(_ id: String, to parentID: String?) async throws
    func setFolderPassword(_ id: String, _ password: String?) async throws -> OrbitFolder
    /// Throws `.wrongPassword` on a mismatch.
    func verifyFolder(_ id: String, password: String) async throws
    func deleteFolder(_ id: String) async throws
    func renameFile(_ id: String, to name: String) async throws -> OrbitFile
    func moveFile(_ id: String, to folderID: String?) async throws
    func setFilePassword(_ id: String, _ password: String?) async throws -> OrbitFile
    /// A raw URL carrying a 6-hour unlock token.
    func unlockFile(_ id: String, password: String) async throws -> String
    func transcode(_ id: String) async throws -> OrbitFile
    func convertAll() async throws -> Int
    func deleteFile(_ id: String) async throws
    func settings() async throws -> OrbitSettings
    func saveSettings(_ settings: OrbitSettings) async throws -> OrbitSettings
    /// Sets (or with nil removes) one item's Face ID lock.
    func setFaceIDLock(_ itemID: String, strict: Bool?) async throws -> OrbitSettings
    func upload(_ file: URL, filename: String, mimeType: String, folderID: String?,
                progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> OrbitFile
    /// Checks a raw URL is readable without fetching it (one byte), so a locked stream can ask for its password.
    func probe(at path: String) async throws
    /// Downloads a raw URL to a temporary file, for sharing files too big to hold in memory.
    func download(at path: String) async throws -> URL
    /// The bytes behind a relative raw URL.
    func data(at path: String) async throws -> Data
    /// An absolute URL and the headers a player needs to stream it.
    func streamRequest(for path: String) async throws -> (URL, [String: String])
    /// Forces a fresh token after a stream failed on an expired one.
    func renewAccess() async throws
}
