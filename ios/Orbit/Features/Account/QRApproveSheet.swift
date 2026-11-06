import NucleusUI
import SwiftUI

/// Asks whether to sign in the device whose sign-in page this app scanned.
struct QRApproveSheet: View {
    let prompt: QRLogin.Prompt
    @Environment(NucleusID.self) private var auth
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var problem: QRLogin.Problem?

    var body: some View {
        NucleusSheetPage("Nucleus ID", onCancel: { dismiss() }) {
            VStack(spacing: 10) {
                IconTile("desktopcomputer", tint: .indigo, size: 60)
                    .padding(.bottom, 6)
                Text("Sign in on \(prompt.device)?")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Nucleus.primaryText)
                    .multilineTextAlignment(.center)
                Text("Requested at \(prompt.createdAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 15))
                    .foregroundStyle(Nucleus.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 28)

            NucleusSection(footer: problem.map { Text($0.message).foregroundStyle(Nucleus.danger) }) {
                NucleusRow("Only approve if you're signing in on a device in front of you right now.",
                           icon: IconTile("exclamationmark.shield.fill", tint: .amber))
            }

            VStack(spacing: 12) {
                Button { answer(true) } label: {
                    HStack(spacing: 8) {
                        if working { ProgressView().tint(.white) }
                        Text("Approve")
                    }
                }
                .buttonStyle(NucleusPrimaryButtonStyle())
                Button("Deny") { answer(false) }
                    .buttonStyle(NucleusSecondaryButtonStyle())
            }
            .disabled(working)
        }
    }

    private func answer(_ approve: Bool) {
        working = true
        problem = nil
        Task {
            defer { working = false }
            do {
                try await QRLogin.approve(prompt.id, approve, on: NucleusID.origin, send: auth.authorized)
                if approve {
                    Haptics.success()
                    navigator.show(String(localized: "Signed in on \(prompt.device)."))
                }
                dismiss()
            } catch {
                Haptics.error()
                problem = error as? QRLogin.Problem ?? .failed
            }
        }
    }
}
