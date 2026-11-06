import Foundation

/// The folder tree for the Move sheet, without the folders being moved (or anything inside them).
struct MoveTree {
    struct Node: Identifiable {
        let id: String
        let name: String
        let folder: OrbitFolder
        var children: [Node]
    }

    let roots: [Node]
    /// Where every moved item already is; moving there would do nothing.
    private let current: String??

    /// Face ID-locked folders: listed, but closed and not a target.
    private let sealed: Set<String>

    init(folders: [OrbitFolder], moving: [ItemRef], sealed: Set<String> = []) {
        self.sealed = sealed
        let excluded = Set(moving.compactMap { if case .folder(let f) = $0 { f.id } else { nil } })
        let byParent = Dictionary(grouping: folders.filter { !excluded.contains($0.id) }, by: \.parentId)
        func build(_ parent: String?) -> [Node] {
            (byParent[parent] ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { Node(id: $0.id, name: $0.name, folder: $0, children: sealed.contains($0.id) ? [] : build($0.id)) }
        }
        roots = build(nil)
        let locations = Set(moving.map { item -> String? in
            switch item {
            case .file(let f): f.folderId
            case .folder(let f): f.parentId
            }
        })
        current = locations.count == 1 ? locations.first : .none
    }

    func isDisabled(_ id: String?) -> Bool {
        if let id, sealed.contains(id) { return true }
        guard case .some(let here) = current else { return false }
        return here == id
    }

    func contains(_ id: String) -> Bool {
        func find(_ nodes: [Node]) -> Bool { nodes.contains { $0.id == id || find($0.children) } }
        return find(roots)
    }
}
