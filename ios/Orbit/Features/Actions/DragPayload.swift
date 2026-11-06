import Foundation

/// What's being dragged, as plain text so it travels through SwiftUI drag and drop; anything else is ignored.
struct DragPayload: Equatable {
    enum Kind: String { case file, folder }

    let kind: Kind
    let id: String

    private static let prefix = "orbit-item:"

    init(kind: Kind, id: String) {
        self.kind = kind
        self.id = id
    }

    init(_ item: ItemRef) {
        switch item {
        case .file(let f): self.init(kind: .file, id: f.id)
        case .folder(let f): self.init(kind: .folder, id: f.id)
        }
    }

    init?(text: String) {
        guard text.hasPrefix(Self.prefix) else { return nil }
        let parts = text.dropFirst(Self.prefix.count).split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = Kind(rawValue: parts[0]), !parts[1].isEmpty else { return nil }
        self.init(kind: kind, id: parts[1])
    }

    var text: String { "\(Self.prefix)\(kind.rawValue):\(id)" }

    /// A folder can't go into itself; the server refuses its own subfolders.
    func canDrop(into folderID: String?) -> Bool { !(kind == .folder && id == folderID) }
}
