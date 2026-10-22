import SwiftUI

struct WanderlustSortMenuItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: @MainActor () -> Void
}

struct WanderlustToolbarIconLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    var imageScale: Image.Scale = .medium

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .symbolRenderingMode(.monochrome)
            .imageScale(imageScale)
            .foregroundStyle(color)
    }
}

struct WanderlustSortMenuButton: View {
    let accessibilityLabel: String
    let items: [WanderlustSortMenuItem]

    private var computedAccessibilityValue: String {
        guard let selected = items.first(where: { $0.isSelected }) else { return "" }
        if let subtitle = selected.subtitle {
            let lang = Locale.current.language.languageCode?.identifier ?? ""
            let sep = lang == "ja" ? "、" : ", "
            return "\(selected.title)\(sep)\(subtitle)"
        }
        return selected.title
    }

    var body: some View {
        Menu {
            ForEach(items) { item in
                Toggle(isOn: Binding(
                    get: { item.isSelected },
                    set: { _ in item.action() }
                )) {
                    Text(item.title)
                    if item.isSelected, let subtitle = item.subtitle {
                        Text(subtitle)
                    }
                }
            }
        } label: {
            WanderlustToolbarIconLabel(
                title: accessibilityLabel,
                systemImage: "arrow.up.arrow.down",
                color: .blue,
                imageScale: .small
            )
        }
        .id(items.first(where: { $0.isSelected })?.id ?? "none")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(computedAccessibilityValue)
    }
}
