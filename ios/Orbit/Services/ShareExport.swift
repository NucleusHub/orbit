import UIKit

/// Downloads a file and opens the share sheet, which covers Save to Files and Save Image.
@MainActor
enum ShareExport {
    static func share(_ file: OrbitFile, files: FilesStore) async throws {
        let url = try await files.download(file)
        let dir = url.deletingLastPathComponent()
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: dir) }
        guard let top = topController() else { return }
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }

    private static func topController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}
