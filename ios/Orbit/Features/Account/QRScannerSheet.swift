import NucleusUI
import SwiftUI
import VisionKit

/// Full-screen camera that reports the first QR code it reads.
struct QRScannerSheet: View {
    var caption: LocalizedStringKey = "Point the camera at the QR code from your server's administrator."
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                QRScannerView { text in
                    Haptics.success()
                    dismiss()
                    onScan(text)
                }
                .ignoresSafeArea()
            } else {
                NucleusBackground()
                VStack(spacing: 10) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Nucleus.secondaryText)
                    Text("The camera isn't available. Allow camera access in Settings.")
                        .font(.system(size: 15))
                        .foregroundStyle(Nucleus.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(maxHeight: .infinity)
            }
            HStack {
                GlassCircleButton("xmark") { dismiss() }
                    .accessibilityLabel("Cancel")
                Spacer()
            }
            .padding(16)
            Text(caption)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 48)
        }
    }
}

private struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var done = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            // The delegate keeps firing while the sheet animates away; report once.
            guard !done else { return }
            for case .barcode(let code) in items {
                guard let text = code.payloadStringValue else { continue }
                done = true
                onScan(text)
                return
            }
        }
    }
}
