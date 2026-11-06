import NucleusUI
import SwiftUI

/// An uppercase heading above a glass group, with room for a count and an action (Shell's group header).
struct SectionTitle<Trailing: View>: View {
    let title: Text
    var icon: String?
    var tint: NucleusTint?
    var count: Int?
    let trailing: Trailing

    init(_ title: Text, icon: String? = nil, tint: NucleusTint? = nil, count: Int? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.count = count
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon { IconTile(icon, tint: tint ?? .indigo, size: 22) }
            title
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Nucleus.secondaryText)
            if let count {
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Nucleus.secondaryText.opacity(0.8))
                    .contentTransition(.numericText())
            }
            Spacer()
            trailing
        }
        .padding(.leading, icon == nil ? 16 : 12)
        .padding(.trailing, 8)
        .padding(.bottom, 8)
    }
}

/// A ring that fills to `progress` in the accent, with content in the middle.
struct ProgressRing<Content: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = Nucleus.accent
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Circle().stroke(Nucleus.well, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(AngularGradient(colors: [tint.opacity(0.6), tint], center: .center), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 ? 1 : 0)
            content
        }
    }
}
