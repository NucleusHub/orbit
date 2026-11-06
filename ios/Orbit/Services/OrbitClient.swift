import Foundation

/// The live Orbit server at `/api/orbit` on the signed-in account's server.
final class OrbitClient: FilesService, @unchecked Sendable {
    private let auth: NucleusID

    init(auth: NucleusID) { self.auth = auth }

    // MARK: Folders

    func browse(_ folderID: String?, password: String?) async throws -> Listing {
        var headers: [String: String] = [:]
        if let password { headers["X-Folder-Password"] = password }
        return try OrbitAPI.listing(try await call("GET", "folders/browse", query: ["parentId": folderID], headers: headers))
    }

    func search(_ query: String) async throws -> Listing {
        var l = try OrbitAPI.listing(try await call("GET", "folders/search", query: ["q": query]))
        l.breadcrumbs = []
        return l
    }

    func allFolders() async throws -> [OrbitFolder] {
        try OrbitAPI.decoder().decode([OrbitFolder].self, from: try await call("GET", "folders/all"))
    }

    func createFolder(name: String, parentID: String?) async throws -> OrbitFolder {
        try decode(try await call("POST", "folders", body: ["name": name, "parentId": nullable(parentID)]))
    }

    func renameFolder(_ id: String, to name: String) async throws -> OrbitFolder {
        try decode(try await call("PATCH", "folders/\(id)/rename", body: ["name": name]))
    }

    func moveFolder(_ id: String, to parentID: String?) async throws {
        _ = try await call("PATCH", "folders/\(id)/move", body: ["parentId": nullable(parentID)])
    }

    func setFolderPassword(_ id: String, _ password: String?) async throws -> OrbitFolder {
        try decode(try await call("PATCH", "folders/\(id)/password", body: ["password": nullable(password)]))
    }

    func verifyFolder(_ id: String, password: String) async throws {
        _ = try await call("POST", "folders/\(id)/verify", body: ["password": password])
    }

    func deleteFolder(_ id: String) async throws { _ = try await call("DELETE", "folders/\(id)") }

    // MARK: Files

    func renameFile(_ id: String, to name: String) async throws -> OrbitFile {
        try decode(try await call("PATCH", "files/\(id)/rename", body: ["filename": name]))
    }

    func moveFile(_ id: String, to folderID: String?) async throws {
        _ = try await call("PATCH", "files/\(id)/move", body: ["folderId": nullable(folderID)])
    }

    func setFilePassword(_ id: String, _ password: String?) async throws -> OrbitFile {
        try decode(try await call("PATCH", "files/\(id)/password", body: ["password": nullable(password)]))
    }

    func unlockFile(_ id: String, password: String) async throws -> String {
        let data = try await call("POST", "files/\(id)/unlock", body: ["password": password])
        guard let url = NucleusID.object(data)["url"] as? String else { throw OrbitError.server(200, "No URL") }
        return url
    }

    func transcode(_ id: String) async throws -> OrbitFile { try decode(try await call("POST", "files/\(id)/transcode")) }

    func convertAll() async throws -> Int {
        NucleusID.object(try await call("POST", "files/convert-all"))["queued"] as? Int ?? 0
    }

    func deleteFile(_ id: String) async throws { _ = try await call("DELETE", "files/\(id)") }

    func settings() async throws -> OrbitSettings { try decode(try await call("GET", "settings")) }

    func saveSettings(_ settings: OrbitSettings) async throws -> OrbitSettings {
        try decode(try await call("PUT", "settings", body: ["transcodeVideos": settings.transcodeVideos, "convertImages": settings.convertImages]))
    }

    func setFaceIDLock(_ itemID: String, strict: Bool?) async throws -> OrbitSettings {
        if let strict { return try decode(try await call("PUT", "settings/face-id/\(itemID)", body: ["strict": strict])) }
        return try decode(try await call("DELETE", "settings/face-id/\(itemID)"))
    }

    func upload(_ file: URL, filename: String, mimeType: String, folderID: String?,
                progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> OrbitFile {
        let boundary = "orbit-\(UUID().uuidString)"
        let body = FileManager.default.temporaryDirectory.appending(path: "upload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: body) }
        try Multipart.write(file: file, filename: filename, mimeType: mimeType, fields: folderID.map { ["folderId": $0] } ?? [:],
                            boundary: boundary, to: body)

        func send(_ token: String) async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: NucleusID.origin.appending(path: "\(OrbitAPI.base)/files/upload"))
            req.httpMethod = "POST"
            req.timeoutInterval = 3600
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return try await Uploader.shared.upload(req, from: body, progress: progress)
        }
        var (data, response) = try await send(try await auth.bearerToken())
        if response.statusCode == 401 {
            try await auth.refreshNow()
            (data, response) = try await send(try await auth.bearerToken())
        }
        guard (200..<300).contains(response.statusCode) else { throw OrbitAPI.error(status: response.statusCode, data: data) }
        return try decode(data)
    }

    func probe(at path: String) async throws {
        var req = URLRequest(url: OrbitAPI.absolute(path, origin: NucleusID.origin))
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (data, response) = try await auth.authorized(req, refreshOn401: OrbitAPI.shouldRefresh)
        guard (200..<300).contains(response.statusCode) else { throw OrbitAPI.error(status: response.statusCode, data: data) }
    }

    func download(at path: String) async throws -> URL {
        func fetch(_ token: String) async throws -> (URL, HTTPURLResponse) {
            var req = URLRequest(url: OrbitAPI.absolute(path, origin: NucleusID.origin))
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (file, response) = try await NucleusID.session.download(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            // The system deletes its temporary file when this returns; keep our own copy.
            let kept = FileManager.default.temporaryDirectory.appending(path: "download-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: file, to: kept)
            return (kept, http)
        }
        var (file, response) = try await fetch(try await auth.bearerToken())
        if response.statusCode == 401 {
            try? FileManager.default.removeItem(at: file)
            try await auth.refreshNow()
            (file, response) = try await fetch(try await auth.bearerToken())
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = (try? Data(contentsOf: file)) ?? Data()
            try? FileManager.default.removeItem(at: file)
            throw OrbitAPI.error(status: response.statusCode, data: body)
        }
        return file
    }

    func data(at path: String) async throws -> Data {
        let (data, response) = try await auth.authorized(URLRequest(url: OrbitAPI.absolute(path, origin: NucleusID.origin)), refreshOn401: OrbitAPI.shouldRefresh)
        guard (200..<300).contains(response.statusCode) else { throw OrbitAPI.error(status: response.statusCode, data: data) }
        return data
    }

    func streamRequest(for path: String) async throws -> (URL, [String: String]) {
        (OrbitAPI.absolute(path, origin: NucleusID.origin), ["Authorization": "Bearer \(try await auth.bearerToken())"])
    }

    func renewAccess() async throws { try await auth.refreshNow() }

    // MARK: Plumbing

    /// JSON null: the server reads it as "root" or "remove the password".
    private func nullable(_ value: String?) -> Any { value ?? NSNull() }

    private func decode<T: Decodable>(_ data: Data) throws -> T { try OrbitAPI.decoder().decode(T.self, from: data) }

    private func call(_ method: String, _ path: String, query: [String: String?] = [:], headers: [String: String] = [:],
                      body: [String: Any]? = nil) async throws -> Data {
        var c = URLComponents(url: NucleusID.origin.appending(path: "\(OrbitAPI.base)/\(path)"), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        if !items.isEmpty { c.queryItems = items }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalCacheData
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await auth.authorized(req, refreshOn401: OrbitAPI.shouldRefresh)
        guard (200..<300).contains(response.statusCode) else { throw OrbitAPI.error(status: response.statusCode, data: data) }
        return data
    }
}

/// Upload progress needs a task delegate; one shared session keeps them all.
final class Uploader: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = Uploader()
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    private let lock = NSLock()
    private var handlers: [Int: @Sendable (Int64, Int64) -> Void] = [:]

    func upload(_ request: URLRequest, from file: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> (Data, HTTPURLResponse) {
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.uploadTask(with: request, fromFile: file) { data, response, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let http = response as? HTTPURLResponse else { continuation.resume(throwing: URLError(.badServerResponse)); return }
                    continuation.resume(returning: (data ?? Data(), http))
                }
                lock.withLock { handlers[task.taskIdentifier] = progress }
                box.task = task
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let handler = lock.withLock { handlers[task.taskIdentifier] }
        handler?(totalBytesSent, totalBytesExpectedToSend)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        _ = lock.withLock { handlers.removeValue(forKey: task.taskIdentifier) }
    }
}

private final class TaskBox: @unchecked Sendable {
    var task: URLSessionTask?
}
