import Foundation

/// A file or a folder, for the actions that take either.
enum ItemRef: Hashable, Identifiable {
    case file(OrbitFile)
    case folder(OrbitFolder)

    var id: String {
        switch self {
        case .file(let f): "file-\(f.id)"
        case .folder(let f): "folder-\(f.id)"
        }
    }

    var rawID: String {
        switch self {
        case .file(let f): f.id
        case .folder(let f): f.id
        }
    }

    var name: String {
        switch self {
        case .file(let f): f.filename
        case .folder(let f): f.name
        }
    }

    var canEdit: Bool {
        switch self {
        case .file(let f): f.canEdit
        case .folder(let f): f.canEdit
        }
    }

    var isProtected: Bool {
        switch self {
        case .file(let f): f.protected
        case .folder(let f): f.protected
        }
    }

    var isFolder: Bool { if case .folder = self { true } else { false } }
}
