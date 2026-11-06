import Foundation

/// A multipart/form-data body written to disk, so a 5 GB upload never sits in memory.
enum Multipart {
    static func write(file: URL, filename: String, mimeType: String, fields: [String: String], boundary: String, to out: URL) throws {
        FileManager.default.createFile(atPath: out.path, contents: nil)
        let handle = try FileHandle(forWritingTo: out)
        defer { try? handle.close() }
        func put(_ s: String) throws { try handle.write(contentsOf: Data(s.utf8)) }

        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            try put("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        // Raw UTF-8 like browsers send: the server re-decodes multer's latin1 name, so `filename*` would garble.
        let quoted = filename.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        try put("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(quoted)\"\r\n")
        try put("Content-Type: \(mimeType)\r\n\r\n")

        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }
        try put("\r\n--\(boundary)--\r\n")
    }
}
