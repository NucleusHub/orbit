import NucleusUI
import SwiftUI

struct ToastView: View {
    @Environment(Navigator.self) private var navigator

    var body: some View {
        if let toast = navigator.toast {
            HStack(spacing: 10) {
                Image(systemName: toast.icon).foregroundStyle(Nucleus.accent)
                Text(verbatim: toast.message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(2)
                if let undo = toast.undo {
                    Button("Undo") {
                        Haptics.tap()
                        undo()
                        navigator.dismissToast()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Nucleus.accent)
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .nucleusGlass(in: Capsule(), interactive: true)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
            .onTapGesture { navigator.dismissToast() }
        }
    }
}
