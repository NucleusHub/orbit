import Foundation
import Observation

enum Route: Hashable {
    case folder(id: String, name: String)
    case search
    case settings
    case profile
}

/// A sheet over everything else. One at a time, as iOS presents them.
enum Sheet: Identifiable, Hashable {
    case welcome
    case report
    case signIn(NucleusServer?)
    case newFolder(parentID: String?)
    case rename(ItemRef, in: String?)
    case password([ItemRef], in: String?)
    case unlock(ItemRef)
    case move([ItemRef], from: String?)
    case preview(OrbitFile, in: String?)

    var id: String {
        switch self {
        case .welcome: "welcome"
        case .report: "report"
        case .signIn(let server): "sign-in-\(server?.origin.absoluteString ?? "")"
        case .newFolder(let parent): "new-folder-\(parent ?? "root")"
        case .rename(let item, _): "rename-\(item.id)"
        case .password(let items, _): "password-\(items.map(\.id).joined(separator: ","))"
        case .unlock(let item): "unlock-\(item.id)"
        case .move(let items, _): "move-\(items.map(\.id).joined(separator: ","))"
        case .preview(let file, _): "preview-\(file.id)"
        }
    }
}

/// A short message at the bottom, with an optional way back.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let icon: String
    var undo: (() -> Void)?

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

struct Confirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    let actions: [String]
    let destructive: Bool
    let answer: (Int?) -> Void
}

/// Where the app is: pushed pages, the open sheet and the toast.
@MainActor
@Observable
final class Navigator {
    var path: [Route] = []
    var sheet: Sheet?
    /// A file to point out once its folder shows (`…://open?folder=&highlight=`).
    var highlight: String?
    /// What to do once the unlock sheet succeeds.
    @ObservationIgnored var afterUnlock: (() -> Void)?
    /// What to do when the unlock sheet is cancelled (a protected folder page goes back).
    @ObservationIgnored var onUnlockCancel: (() -> Void)?
    private(set) var toast: Toast?
    private(set) var confirmation: Confirmation?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var waiting: [Confirmation] = []

    func open(_ route: Route) { path.append(route) }
    func present(_ sheet: Sheet) { self.sheet = sheet }

    func unlock(_ item: ItemRef, then action: @escaping () -> Void, onCancel: (() -> Void)? = nil) {
        afterUnlock = action
        onUnlockCancel = onCancel
        sheet = .unlock(item)
    }

    func show(_ message: String, icon: String = "checkmark.circle.fill", undo: (() -> Void)? = nil) {
        toast = Toast(message: message, icon: icon, undo: undo)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo == nil ? 2.5 : 4.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func fail(_ error: Error) {
        show(error.orbitMessage, icon: "exclamationmark.triangle.fill")
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    func confirm(title: String, message: String?, actions: [String], destructive: Bool = false) async -> Int? {
        await withCheckedContinuation { continuation in
            let c = Confirmation(title: title, message: message, actions: actions, destructive: destructive) { continuation.resume(returning: $0) }
            if confirmation == nil { confirmation = c } else { waiting.append(c) }
        }
    }

    /// Answers dialog `id` once; dismissing after a button tap calls this again and is ignored.
    func answer(_ id: UUID, _ index: Int?) {
        guard let current = confirmation, current.id == id else { return }
        confirmation = waiting.isEmpty ? nil : waiting.removeFirst()
        current.answer(index)
    }
}
