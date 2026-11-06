import Foundation

/// Mapping between the Orbit server's JSON and the app's models. No I/O.
enum OrbitAPI {
    static let base = "api/orbit"

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return d
    }

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    private struct Wire: Decodable {
        var folders: [OrbitFolder]?
        var files: [OrbitFile]?
        var breadcrumbs: [Breadcrumb]?
    }

    static func listing(_ data: Data) throws -> Listing {
        let w = try decoder().decode(Wire.self, from: data)
        return Listing(folders: w.folders ?? [], files: w.files ?? [], breadcrumbs: w.breadcrumbs ?? [])
    }

    /// `error` is a string from Orbit's routes and `{code, message}` from core auth and the app gate.
    static func error(status: Int, data: Data) -> OrbitError {
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let message = (o["error"] as? String) ?? ((o["error"] as? [String: Any])?["message"] as? String) ?? (o["message"] as? String)
        switch status {
        case 401 where o["locked"] as? Bool == true: return .folderLocked
        case 401 where message == "Wrong password": return .wrongPassword
        case 403: return .forbidden
        case 404: return .notFound
        case 413: return .tooLarge
        default: return .server(status, message ?? "HTTP \(status)")
        }
    }

    /// Orbit answers a missing or wrong folder/file password with 401 too; only auth failures warrant a new token.
    static func shouldRefresh(after data: Data) -> Bool {
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return o["locked"] as? Bool != true && o["error"] as? String != "Wrong password"
    }

    /// The server hands out root-relative URLs (`/api/orbit/files/<id>/raw?t=…`).
    static func absolute(_ path: String, origin: URL) -> URL {
        URL(string: path, relativeTo: origin)?.absoluteURL ?? origin.appending(path: path)
    }
}
