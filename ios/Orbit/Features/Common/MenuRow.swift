import NucleusUI
import SwiftUI

/// A settings-style row with a choice, like Shell's host editor: the title on the left and the native
/// menu picker on the right, whose menu floats over the page. Only the small value button opens it,
/// so iOS 26 doesn't morph the whole glass section into the menu.
struct MenuRow<Value: Hashable>: View {
    let title: LocalizedStringKey
    let icon: IconTile
    @Binding var selection: Value
    let options: [(value: Value, title: String, icon: String?)]

    var body: some View {
        HStack(spacing: 12) {
            icon
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Nucleus.primaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            Picker(selection: $selection) {
                ForEach(options, id: \.value) { option in
                    if let icon = option.icon { Label(option.title, systemImage: icon).tag(option.value) } else { Text(option.title).tag(option.value) }
                }
            } label: {
                Text(title)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Nucleus.secondaryText)
            // The menu picker otherwise takes too little width and wraps short values like "Personal".
            .fixedSize()
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
    }
}
