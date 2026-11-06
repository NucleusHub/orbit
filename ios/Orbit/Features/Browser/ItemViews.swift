import NucleusUI
import SwiftUI

/// The image of a photo, or its file type's symbol.
struct Thumbnail: View {
    let file: OrbitFile
    var maxPixel: CGFloat = 400
    @Environment(FilesStore.self) private var files
    @State private var image: UIImage?

    private var faceLocked: Bool { files.isFaceIDLocked(.file(file)) }

    var body: some View {
        ZStack {
            if let image, !faceLocked {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                TypeGlyph(kind: file.kind, locked: file.isLocked || files.resolvedURL(for: file) == nil, faceID: faceLocked)
            }
        }
        .task(id: "\(file.id)-\(file.updatedAt)-\(files.resolvedURL(for: file) ?? "")-\(faceLocked)") {
            // A Face ID item shows nothing of itself until it's unlocked.
            guard file.kind == .image, !faceLocked, files.resolvedURL(for: file) != nil else { image = nil; return }
            image = await ThumbnailCache.shared.image(for: file, store: files, maxPixel: maxPixel)
        }
    }
}

struct TypeGlyph: View {
    let kind: FileKind
    var locked = false
    var faceID = false
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            kind.tint.color.opacity(0.14)
            Image(systemName: faceID ? "faceid" : locked ? "lock.fill" : kind.symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(faceID ? Nucleus.accent : locked ? NucleusTint.amber.color : kind.tint.color)
        }
    }
}

/// Folder glyph: violet when shared with a group, like the web's FolderCard.
struct FolderGlyph: View {
    let folder: OrbitFolder
    var size: CGFloat = 40
    @Environment(FilesStore.self) private var files

    var body: some View {
        let tint: NucleusTint = folder.shared ? .violet : .indigo
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(tint.color.opacity(0.16))
            Image(systemName: folder.isGroupRoot ? "person.2.fill" : "folder.fill")
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(tint.gradient)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if files.ownFaceIDLock(.folder(folder)) != nil { FaceIDBadge().offset(x: 4, y: 4) } else if folder.protected { LockBadge().offset(x: 4, y: 4) }
        }
    }
}

struct FaceIDBadge: View {
    var body: some View {
        Image(systemName: "faceid")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Nucleus.accent))
            .accessibilityLabel("Locked with Face ID")
    }
}

struct LockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(NucleusTint.amber.color))
            .accessibilityLabel("Protected")
    }
}

/// "Queued", "42% · 12s" or "Converting", as on the web's FileCard.
struct ConvertingLabel: View {
    let file: OrbitFile

    var body: some View {
        if file.transcodeStatus.isActive {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(verbatim: Self.text(file))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(NucleusTint.violet.color)
        }
    }

    static func text(_ file: OrbitFile) -> String {
        if file.transcodeStatus == .pending { return String(localized: "Queued") }
        if let p = file.transcodeProgress {
            if let eta = Formatting.eta(file.transcodeEta) { return "\(p)% · \(eta)" }
            return "\(p)%"
        }
        return String(localized: "Converting")
    }
}

/// Selection mark in the corner of a tile or the start of a row.
struct SelectMark: View {
    let selected: Bool

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(selected ? Nucleus.accent : Nucleus.secondaryText)
            .background(Circle().fill(.background.opacity(selected ? 1 : 0.4)).padding(2))
    }
}

struct FolderTile: View {
    let folder: OrbitFolder
    var selecting = false
    var selected = false

    var body: some View {
        HStack(spacing: 12) {
            FolderGlyph(folder: folder, size: 40)
            Text(verbatim: folder.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Nucleus.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if selecting, folder.canEdit { SelectMark(selected: selected) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .nucleusGlass(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct FileTile: View {
    let file: OrbitFile
    var selecting = false
    var selected = false
    var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A fixed square that the photo fills; scaledToFill alone would widen the tile.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { Thumbnail(file: file) }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if selecting, file.canEdit { SelectMark(selected: selected).padding(6) }
                }
                .overlay(alignment: .topLeading) {
                    if file.shared { SharedBadge().padding(6) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: file.filename)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(1)
                if file.transcodeStatus.isActive {
                    ConvertingLabel(file: file)
                } else {
                    Text(verbatim: Formatting.size(file.size))
                        .font(.system(size: 12))
                        .foregroundStyle(Nucleus.secondaryText)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .nucleusGlass(cornerRadius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Nucleus.accent, lineWidth: highlighted ? 3 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct SharedBadge: View {
    var body: some View {
        Image(systemName: "person.2.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 18)
            .background(Capsule().fill(NucleusTint.violet.color))
            .accessibilityLabel("Shared")
    }
}

/// A list row: glyph, name, then size and date (or the conversion).
struct ItemRow: View {
    let item: ItemRef
    var selecting = false
    var selected = false
    var highlighted = false

    var body: some View {
        HStack(spacing: 12) {
            if selecting {
                SelectMark(selected: selected).opacity(item.canEdit ? 1 : 0.3)
            }
            switch item {
            case .folder(let folder):
                FolderGlyph(folder: folder, size: 38)
            case .file(let file):
                Thumbnail(file: file, maxPixel: 120)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                    .font(.system(size: 16))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(1)
                subtitle
            }
            Spacer(minLength: 4)
            if case .file(let f) = item, f.shared { SharedBadge() }
            if item.isProtected, case .file = item { Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(NucleusTint.amber.color) }
            if item.isFolder { Chevron() }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .background(highlighted ? Nucleus.accent.opacity(0.15) : .clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var subtitle: some View {
        switch item {
        case .folder(let f):
            if f.isGroupRoot { Text("Group folder").font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText) }
        case .file(let f):
            if f.transcodeStatus.isActive {
                ConvertingLabel(file: f)
            } else {
                Text(verbatim: "\(Formatting.size(f.size)) · \(Formatting.relative(f.createdAt))")
                    .font(.system(size: 13))
                    .foregroundStyle(Nucleus.secondaryText)
            }
        }
    }
}
