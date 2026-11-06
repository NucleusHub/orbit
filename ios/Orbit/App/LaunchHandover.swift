import NucleusUI
import SwiftUI

/// The app mark, same image the launch screen shows.
struct AppGlyph: View {
    var size: CGFloat = 64

    var body: some View {
        Image("Splash")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: Color(hex: 0x4F46E5).opacity(0.45), radius: size * 0.2, y: size * 0.08)
    }
}

/// Watchlist's launch handover: the same layout as LaunchScreen.storyboard, drawn in SwiftUI
/// so the swap from the static screen is invisible, then lifted away in about a third of a second.
struct LaunchHandover: View {
    let onFinish: () -> Void
    @State private var gone = false

    var body: some View {
        ZStack {
            Color(hex: 0x0D0D1A)
                .ignoresSafeArea()
                .opacity(gone ? 0 : 1)
                .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3).delay(0.04), value: gone)
            GeometryReader { geo in
                let midY = geo.size.height / 2
                Image("Splash")
                    .resizable()
                    .frame(width: 120, height: 120)
                    .scaleEffect(gone ? 1.14 : 1)
                    .opacity(gone ? 0 : 1)
                    .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.34), value: gone)
                    .position(x: geo.size.width / 2, y: midY)
                Text(verbatim: "Orbit")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(gone ? 0 : 1)
                    .offset(y: gone ? 6 : 0)
                    .animation(.easeIn(duration: 0.16), value: gone)
                    .position(x: geo.size.width / 2, y: midY + 60 + 20 + 17)
            }
            .ignoresSafeArea()
            VStack(spacing: 4) {
                Spacer()
                Text("from")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                HStack(spacing: 6) {
                    Image("NucleusMark").resizable().frame(width: 22, height: 22)
                    Text(verbatim: "Nucleus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(height: 22)
            }
            .padding(.bottom, 12)
            .ignoresSafeArea(.keyboard)
            .opacity(gone ? 0 : 1)
            .animation(.easeIn(duration: 0.14), value: gone)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            // Let the first real frame paint underneath before letting go.
            try? await Task.sleep(for: .milliseconds(60))
            gone = true
            try? await Task.sleep(for: .milliseconds(420))
            onFinish()
        }
    }
}
