import NucleusUI
import SwiftUI

/// Floating progress for uploads (the web's UploadProgress).
struct UploadPanel: View {
    @Environment(UploadQueue.self) private var uploads
    @State private var expanded = true

    var body: some View {
        if !uploads.items.isEmpty || uploads.isPreparing {
            VStack(spacing: 0) {
                Button {
                    withAnimation(NucleusMotion.quick) { expanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(Nucleus.accent)
                        Text(summary).font(.system(size: 14, weight: .semibold)).foregroundStyle(Nucleus.primaryText)
                        Spacer()
                        if uploads.isPreparing { ProgressView().controlSize(.small) }
                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Nucleus.secondaryText)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(uploads.items) { item in row(item) }
                        }
                    }
                    .frame(maxHeight: 200)
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(.bottom, expanded && !uploads.items.isEmpty ? 6 : 0)
            .nucleusGlass(cornerRadius: 22)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onChange(of: uploads.items.count) { _, n in if n > 3 { expanded = false } }
        }
    }

    private var summary: String {
        let active = uploads.items.filter { $0.state == .uploading || $0.state == .waiting }.count
        let failed = uploads.items.filter(\.state.isFailed).count
        if active > 0 { return String(localized: "Uploading \(active) files") }
        if failed > 0 { return String(localized: "\(failed) uploads failed") }
        if uploads.isPreparing { return String(localized: "Preparing upload…") }
        return String(localized: "Uploaded")
    }

    private func row(_ item: UploadItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.filename).font(.system(size: 13, weight: .medium)).foregroundStyle(Nucleus.primaryText).lineLimit(1)
                switch item.state {
                case .failed(let message):
                    Text(verbatim: message).font(.system(size: 12)).foregroundStyle(Nucleus.danger).lineLimit(2)
                case .done:
                    Text("Done").font(.system(size: 12)).foregroundStyle(Nucleus.success)
                case .waiting:
                    Text("Waiting…").font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
                case .uploading:
                    ProgressView(value: item.progress).tint(Nucleus.accent)
                    Text(verbatim: details(item)).font(.system(size: 11)).foregroundStyle(Nucleus.secondaryText).monospacedDigit()
                }
            }
            if item.state.isFailed || item.state == .waiting {
                Button { uploads.dismiss(item.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Nucleus.glyph)
                        .frame(width: 26, height: 26).background(Circle().fill(Nucleus.well))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func details(_ item: UploadItem) -> String {
        var parts = ["\(Int(item.progress * 100))%"]
        if item.speed > 0 { parts.append(ByteCountFormatter.string(fromByteCount: Int64(item.speed), countStyle: .file) + "/s") }
        if let eta = Formatting.eta(item.eta) { parts.append(eta) }
        return parts.joined(separator: " · ")
    }
}
