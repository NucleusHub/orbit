import NucleusUI
import SwiftUI

/// Folders then files, as a grid or a list (the web's FileBrowser).
struct ItemsView: View {
    let listing: Listing
    let actions: ItemActions
    let mode: ViewMode
    @Binding var selection: Set<String>?
    var highlight: String?

    private var selecting: Bool { selection != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !listing.folders.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle(Text("Folders"), count: listing.folders.count)
                    switch mode {
                    case .grid:
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(Array(listing.folders.enumerated()), id: \.element.id) { i, folder in
                                FolderTile(folder: folder, selecting: selecting, selected: isSelected(.folder(folder)))
                                    .modifier(ItemInteraction(item: .folder(folder), actions: actions, selection: $selection))
                                    .nucleusAppear(min(i, 12))
                            }
                        }
                    case .list:
                        NucleusSection {
                            ForEach(listing.folders) { folder in
                                ItemRow(item: .folder(folder), selecting: selecting, selected: isSelected(.folder(folder)))
                                    .modifier(ItemInteraction(item: .folder(folder), actions: actions, selection: $selection, swipes: true))
                            }
                        }
                    }
                }
            }
            if !listing.files.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle(Text("Files"), count: listing.files.count)
                    switch mode {
                    case .grid:
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(Array(listing.files.enumerated()), id: \.element.id) { i, file in
                                FileTile(file: file, selecting: selecting, selected: isSelected(.file(file)), highlighted: highlight == file.id)
                                    .modifier(ItemInteraction(item: .file(file), actions: actions, selection: $selection))
                                    .nucleusAppear(min(i + listing.folders.count, 12))
                                    .id(file.id)
                            }
                        }
                    case .list:
                        NucleusSection {
                            ForEach(listing.files) { file in
                                ItemRow(item: .file(file), selecting: selecting, selected: isSelected(.file(file)), highlighted: highlight == file.id)
                                    .modifier(ItemInteraction(item: .file(file), actions: actions, selection: $selection, swipes: true))
                                    .id(file.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private func isSelected(_ item: ItemRef) -> Bool { selection?.contains(item.id) ?? false }
}

/// Tap to open (or select), long-press for the menu, and on list rows swipe to move or delete.
private struct ItemInteraction: ViewModifier {
    let item: ItemRef
    let actions: ItemActions
    @Binding var selection: Set<String>?
    var swipes = false
    @Environment(FilesStore.self) private var files
    @Environment(Navigator.self) private var navigator

    @State private var targeted = false

    func body(content: Content) -> some View {
        let tappable = content
            .overlay {
                // A folder lights up while something is dragged over it.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Nucleus.accent, lineWidth: targeted ? 3 : 0)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Nucleus.accent.opacity(targeted ? 0.12 : 0)))
                    .allowsHitTesting(false)
            }
            .animation(NucleusMotion.quick, value: targeted)
            .onTapGesture {
                if selection != nil {
                    guard item.canEdit else { return }
                    Haptics.selection()
                    if selection!.contains(item.id) { selection!.remove(item.id) } else { selection!.insert(item.id) }
                } else {
                    Haptics.tap()
                    actions.open(item)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(verbatim: item.name))
        if selection == nil {
            let menu = tappable
                .modifier(DragAndDrop(item: item, actions: actions, targeted: $targeted))
                .contextMenu { actions.menu(for: item) }
            if swipes, item.canEdit {
                menu.nucleusSwipeActions(
                    leading: NucleusSwipeAction("Move", icon: "folder", tint: NucleusTint.indigo.color) { actions.move([item]) },
                    trailing: .delete { actions.delete([item]) }
                )
            } else {
                menu
            }
        } else {
            tappable
        }
    }
}

/// Long-press and drag an item onto a folder to move it there (the web's useDnd).
private struct DragAndDrop: ViewModifier {
    let item: ItemRef
    let actions: ItemActions
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        let dragged = item.canEdit && !actions.files.isFaceIDLocked(item)
            ? AnyView(content.draggable(DragPayload(item).text) { DragPreview(item: item) })
            : AnyView(content)
        if case .folder(let folder) = item {
            dragged.dropDestination(for: String.self) { texts, _ in
                guard let payload = texts.first.flatMap(DragPayload.init(text:)), payload.canDrop(into: folder.id) else { return false }
                actions.drop(payload, into: folder)
                return true
            } isTargeted: { targeted = $0 }
        } else {
            dragged
        }
    }
}

/// The small card that follows the finger.
private struct DragPreview: View {
    let item: ItemRef

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: { if case .folder = item { "folder.fill" } else { "doc.fill" } }())
                .foregroundStyle(Nucleus.accent)
            Text(verbatim: item.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(.regularMaterial))
    }
}
