import NucleusUI
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let nucleusServer = UTType(exportedAs: "com.nucleushome.server")
}

/// Picks the Nucleus ID server, checks it and its code, then hands over to the browser sign-in.
struct ServerSignInSheet: View {
    @Environment(NucleusID.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var address: String
    @State private var scheme: String
    @State private var port: String
    @State private var discoveryPath: String
    @State private var code: String
    @State private var needsCode: Bool
    @State private var showsAdvanced: Bool
    @State private var revealsCode = false
    @State private var importing = false
    @State private var scanning = false
    @State private var working = false
    @State private var check: Task<Void, Never>?
    @State private var problem: ServerProblem?
    @State private var qrProblem: QRLogin.Problem?
    /// A website's sign-in request scanned here; the next check claims it instead of opening the browser.
    @State private var login: String?
    @State private var waiting = false

    init(prefill: NucleusServer?) {
        let s = prefill ?? ActiveServer.config?.server
        _address = State(initialValue: s?.host ?? "")
        _scheme = State(initialValue: s?.scheme ?? "https")
        _port = State(initialValue: s?.port.map(String.init) ?? "")
        _discoveryPath = State(initialValue: s?.discoveryPath ?? NucleusServer.defaultDiscoveryPath)
        _code = State(initialValue: s?.code ?? "")
        _needsCode = State(initialValue: s?.code != nil)
        _showsAdvanced = State(initialValue: s.map { $0.scheme != "https" || $0.port != nil || $0.discoveryPath != NucleusServer.defaultDiscoveryPath } ?? false)
    }

    private var canContinue: Bool { !working && !address.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NucleusSheetPage("Nucleus ID", onCancel: { check?.cancel(); dismiss() }) {
            if waiting { waitingView } else { form }
        }
        .onDisappear { check?.cancel() }
        .fullScreenCover(isPresented: $scanning) { QRScannerSheet(onScan: scanned) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.nucleusServer]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                apply(try NucleusServer.setup(fromFile: try Data(contentsOf: url)))
            } catch {
                problem = error as? ServerProblem ?? .badSetup
            }
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            hero
            NucleusSection(footer: footer) {
                NucleusField("Server address", text: $address, prompt: "nas.tail1234.ts.net", keyboard: .URL)
                    .submitLabel(.go)
                    .onSubmit(start)
                if needsCode { codeField }
            }
            Button(action: start) {
                HStack(spacing: 8) {
                    if working { ProgressView().tint(.white) }
                    Text(working ? "Checking…" : "Continue")
                }
            }
            .buttonStyle(NucleusPrimaryButtonStyle())
            .disabled(!canContinue)
            .padding(.bottom, 28)
            NucleusSection {
                Button { scanning = true } label: {
                    NucleusRow("Scan QR code", subtitle: Text("Fills in the server and its code"),
                               icon: IconTile("qrcode.viewfinder", tint: .violet)) { Chevron() }
                }
                .buttonStyle(NucleusRowButtonStyle())
                Button { importing = true } label: {
                    NucleusRow("Import setup", subtitle: Text("A link or file from your administrator"),
                               icon: IconTile("square.and.arrow.down", tint: .teal)) { Chevron() }
                }
                .buttonStyle(NucleusRowButtonStyle())
                Button { withAnimation(NucleusMotion.quick) { showsAdvanced.toggle() } } label: {
                    NucleusRow("Advanced", subtitle: Text("Protocol, port and path"),
                               icon: IconTile("slider.horizontal.3", tint: .slate)) {
                        Chevron().rotationEffect(.degrees(showsAdvanced ? 90 : 0))
                    }
                }
                .buttonStyle(NucleusRowButtonStyle())
                if showsAdvanced { advanced }
            }
        }
        .disabled(working)
    }

    private var waitingView: some View {
        VStack(spacing: 10) {
            IconTile("qrcode", tint: .violet, size: 60)
                .padding(.bottom, 6)
            Text("Approve on the website…")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Nucleus.primaryText)
            Text("Confirm signing in Orbit where you showed the QR code.")
                .font(.system(size: 15))
                .foregroundStyle(Nucleus.secondaryText)
                .multilineTextAlignment(.center)
            ProgressView()
                .padding(.vertical, 20)
            Button("Cancel") { check?.cancel() }
                .buttonStyle(NucleusSecondaryButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            IconTile("server.rack", tint: .indigo, size: 60)
                .padding(.bottom, 6)
            Text("Connect to your server")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Nucleus.primaryText)
            Text("Your account lives on a Nucleus server you or your administrator run. Enter its address to sign in.")
                .font(.system(size: 15))
                .foregroundStyle(Nucleus.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    private var footer: Text {
        if let problem { return Text(problem.message).foregroundStyle(Nucleus.danger) }
        if let qrProblem { return Text(qrProblem.message).foregroundStyle(Nucleus.danger) }
        return Text("A domain, an IP address or a Tailscale name.")
    }

    private var codeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Server code")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Nucleus.secondaryText)
            HStack {
                Group {
                    if revealsCode { TextField("nucleus…home", text: $code) } else { SecureField("nucleus…home", text: $code) }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, design: .monospaced))
                .submitLabel(.go)
                .onSubmit(start)
                Button { revealsCode.toggle() } label: { Image(systemName: revealsCode ? "eye.slash" : "eye") }
                    .accessibilityLabel(revealsCode ? Text("Hide code") : Text("Show code"))
                    .foregroundStyle(Nucleus.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: NucleusRadius.field, style: .continuous).fill(Nucleus.well))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var advanced: some View {
        NucleusRow("Protocol") {
            Picker("Protocol", selection: $scheme) {
                Text(verbatim: "https").tag("https")
                Text(verbatim: "http").tag("http")
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        NucleusRow("Port") {
            TextField(scheme == "https" ? "443" : "80", text: $port)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
        NucleusField("Discovery path", text: $discoveryPath, keyboard: .URL)
        Button {
            scheme = "https"
            port = ""
            discoveryPath = NucleusServer.defaultDiscoveryPath
        } label: {
            NucleusRow("Reset to defaults", titleColor: Nucleus.accent)
        }
        .buttonStyle(NucleusRowButtonStyle())
    }

    private func start() {
        guard canContinue else { return }
        working = true
        check = Task { await go() }
    }

    private func scanned(_ text: String) {
        do {
            switch try NucleusServer.scanned(text) {
            case .setup(let server):
                apply(server)
                start()
            case .code(let scannedCode):
                code = scannedCode
                needsCode = true
                problem = nil
            case .appLogin(let id, let server):
                apply(server)
                login = id
                start()
            case .webLogin:
                qrProblem = .signInFirst
            }
        } catch {
            problem = error as? ServerProblem ?? .badSetup
        }
    }

    private func apply(_ server: NucleusServer) {
        address = server.host
        scheme = server.scheme
        port = server.port.map(String.init) ?? ""
        discoveryPath = server.discoveryPath
        code = server.code ?? ""
        needsCode = server.code != nil
        showsAdvanced = server.scheme != "https" || server.port != nil || server.discoveryPath != NucleusServer.defaultDiscoveryPath
        problem = nil
        qrProblem = nil
        login = nil
    }

    private func go() async {
        working = true
        problem = nil
        qrProblem = nil
        defer { working = false }
        do {
            let portText = port.trimmingCharacters(in: .whitespaces)
            var portNumber: Int?
            if !portText.isEmpty {
                guard let p = Int(portText), (1...65535).contains(p) else { throw ServerProblem.badAddress }
                portNumber = p
            }
            var server = try NucleusServer.parse(address, scheme: scheme, port: portNumber, discoveryPath: discoveryPath)
            let endpoints = try await NucleusDiscovery.discover(server)
            // A code only goes to a server that asks for one; an open server would reject it.
            if endpoints.codeRequired {
                let entered = code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !entered.isEmpty else {
                    needsCode = true
                    return
                }
                try await NucleusDiscovery.check(code: entered, on: server)
                server.code = entered
            }
            // Cancelled mid-check: save nothing.
            guard !Task.isCancelled else { return }
            auth.use(ServerConfig(server: server, endpoints: endpoints))
            if let id = login {
                login = nil
                try await signIn(qr: id, on: server)
                return
            }
            dismiss()
            // Own task, so the sheet's cancellation can't stop the browser sign-in.
            Task { await auth.signIn() }
        } catch {
            // A cancelled check (URLSession reports it as unreachable) shows no message.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if let p = error as? QRLogin.Problem { qrProblem = p } else { problem = error as? ServerProblem ?? .unreachable }
        }
    }

    /// Claims the website's request and waits for its approval, then signs in with the code like the browser flow.
    private func signIn(qr id: String, on server: NucleusServer) async throws {
        waiting = true
        defer { waiting = false }
        let verifier = NucleusID.randomToken(48)
        let code = try await QRLogin.approval(of: id, on: server.origin, scope: NucleusID.signInScope,
                                              challenge: NucleusID.challenge(verifier), device: Device.name,
                                              send: NucleusID.send)
        guard !Task.isCancelled else { return }
        dismiss()
        // Own task, so the sheet's cancellation can't stop the sign-in.
        Task { await auth.signIn(code: code, verifier: verifier) }
    }
}
