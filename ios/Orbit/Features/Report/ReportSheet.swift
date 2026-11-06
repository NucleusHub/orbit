import NucleusUI
import PhotosUI
import SwiftUI

/// Tell us what went wrong, with screenshots. Sent to Nucleus ID's reports endpoint, only when you tap Send.
struct ReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var email = ""
    @State private var shots: [UIImage] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var sending = false
    @State private var sent = false
    @State private var failure: String?
    @State private var confirmingDiscard = false

    private static let endpoint = URL(string: "https://nucleus-home.dev/api/v1/reports")!

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !details.trimmingCharacters(in: .whitespaces).isEmpty && !sending
    }

    private var hasInput: Bool { !title.isEmpty || !details.isEmpty || !shots.isEmpty }

    var body: some View {
        if sent {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(Nucleus.success)
                Text("Sent").font(.system(size: 24, weight: .bold))
                Text(email.isEmpty ? "Thanks for letting us know." : "Thanks. We'll get back to you.")
                    .foregroundStyle(Nucleus.secondaryText)
                Button("Done") { dismiss() }.buttonStyle(NucleusPrimaryButtonStyle()).frame(maxWidth: 240)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NucleusBackground())
        } else {
            form
        }
    }

    private var form: some View {
        NucleusSheetPage("Report a problem", confirmTitle: "Send", canConfirm: canSend,
                         onCancel: { if hasInput { confirmingDiscard = true } else { dismiss() } }, onConfirm: send) {
            NucleusSection(footer: failure.map { Text(verbatim: $0).foregroundStyle(Nucleus.danger) }) {
                TextField("What happened?", text: $title)
                    .font(.system(size: 17, weight: .medium))
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .onChange(of: title) { _, v in if v.count > 200 { title = String(v.prefix(200)) } }
                TextField("Steps, what you expected, what you saw", text: $details, axis: .vertical)
                    .lineLimit(5...14)
                    .padding(16)
                    .onChange(of: details) { _, v in if v.count > 10000 { details = String(v.prefix(10000)) } }
            }
            NucleusSection("Screenshots", footer: Text("Up to 4.")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(shots.enumerated()), id: \.offset) { i, image in
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 70, height: 120).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { shots.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .padding(4)
                                }
                        }
                        if shots.count < 4 {
                            PhotosPicker(selection: $picks, maxSelectionCount: 4 - shots.count, matching: .screenshots) {
                                Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(Nucleus.accent)
                                    .frame(width: 70, height: 120)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Nucleus.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                            }
                        }
                    }
                    .padding(12)
                }
            }
            NucleusSection("Reply to", footer: Text(verbatim: diagnostics)) {
                TextField("Email (optional)", text: $email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, 16).frame(minHeight: 52)
            }
        }
        .interactiveDismissDisabled(hasInput)
        .confirmationDialog("Discard this report?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
        }
        .onChange(of: picks) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), shots.count < 4 {
                        shots.append(image)
                    }
                }
                picks = []
            }
        }
    }

    private var diagnostics: String {
        "Orbit \(Bundle.main.versionString) · \(Device.name) · iOS \(UIDevice.current.systemVersion)"
    }

    private func send() {
        let mail = email.trimmingCharacters(in: .whitespaces)
        if !mail.isEmpty, mail.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) == nil {
            failure = String(localized: "That email doesn't look right.")
            return
        }
        sending = true
        failure = nil
        Task {
            defer { sending = false }
            var body: [String: Any] = [
                "title": title.trimmingCharacters(in: .whitespaces),
                "description": details.trimmingCharacters(in: .whitespaces),
                "locale": Locale.preferredLanguages.first ?? "en",
                "app": ["id": "orbit", "name": "Orbit",
                        "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                        "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""],
                "device": ["model": Device.name, "modelId": Device.modelID, "manufacturer": "Apple",
                           "platform": "ios", "os": "ios", "osVersion": UIDevice.current.systemVersion, "webView": NSNull()],
                "attachments": shots.compactMap { Device.jpeg($0, maxEdge: 1600, quality: 0.82) }
                    .map { ["type": "image/jpeg", "data": $0.base64EncodedString()] },
            ]
            if !mail.isEmpty { body["email"] = mail }
            var req = URLRequest(url: Self.endpoint)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                switch status {
                case 200..<300:
                    Haptics.success()
                    withAnimation { sent = true }
                case 429: failure = String(localized: "Too many reports. Try again later.")
                default: failure = String(localized: "Couldn't send it (\(status)).")
                }
            } catch {
                failure = String(localized: "You're offline. Try again when you're connected.")
            }
        }
    }
}

enum Device {
    static var modelID: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// Marketing name for the hardware identifier, e.g. "iPhone 16" for iPhone17,3. Unknown models fall back to the identifier.
    static var name: String {
        let id = modelID
        let simulator = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] != nil
        let base = names[id] ?? id
        return simulator ? "\(base) Simulator" : base
    }

    private static let names: [String: String] = [
        "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone Air",
    ]

    static func jpeg(_ image: UIImage, maxEdge: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
