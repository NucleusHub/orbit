import NucleusUI

/// The web client's file types (`getFileTypeInfo`), by MIME type.
enum FileKind: Equatable {
    case image, video, audio, pdf, archive, code, text, other

    init(mime: String) {
        let m = mime.lowercased()
        if m.hasPrefix("image/") { self = .image }
        else if m.hasPrefix("video/") { self = .video }
        else if m.hasPrefix("audio/") { self = .audio }
        else if m == "application/pdf" { self = .pdf }
        else if ["zip", "tar", "rar", "7z"].contains(where: m.contains) { self = .archive }
        else if ["javascript", "json", "html", "css", "xml", "typescript"].contains(where: m.contains) { self = .code }
        else if m.hasPrefix("text/") { self = .text }
        else if m.contains("yaml") { self = .code }
        else { self = .other }
    }

    var symbol: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .audio: "music.note"
        case .pdf: "doc.richtext"
        case .archive: "archivebox"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .text: "doc.text"
        case .other: "doc"
        }
    }

    var tint: NucleusTint {
        switch self {
        case .image: .emerald
        case .video: .violet
        case .audio: .pink
        case .pdf: .rose
        case .archive: .amber
        case .code: .sky
        case .text, .other: .slate
        }
    }

    var hasTextPreview: Bool { self == .text || self == .code }

    private static let imagesNeedingConversion: Set<String> = ["image/heic", "image/heif", "image/tiff"]

    /// `canConvertMedia`: videos and HEIC/HEIF/TIFF photos the server hasn't converted or queued yet.
    static func canConvert(mime: String, status: TranscodeStatus) -> Bool {
        if status == .done || status.isActive { return false }
        return mime.hasPrefix("video/") || imagesNeedingConversion.contains(mime)
    }
}

extension OrbitFile {
    var canConvert: Bool { FileKind.canConvert(mime: mimeType, status: transcodeStatus) }
}
