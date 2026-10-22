import SwiftUI

enum WanderlustSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
    static let xxLarge: CGFloat = 32
}

enum WanderlustRadius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
    static let xLarge: CGFloat = 26
    static let capsule: CGFloat = 999
}

enum WanderlustAnimation {
    static let quick = Animation.snappy(duration: 0.22)
    static let standard = Animation.snappy(duration: 0.32)
    static let smooth = Animation.easeInOut(duration: 0.45)
}

struct WanderlustGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var radius: CGFloat = WanderlustRadius.large
    var isInteractive = false

    func body(content: Content) -> some View {
        // デプロイメントターゲットが iOS 26.0 なので `#available` 分岐は不要。
        // 残す必要があるのは Reduce Transparency のフォールバックだけ。
        if reduceTransparency {
            content
                .background(
                    Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(WanderlustColor.divider, lineWidth: 1)
                )
        } else {
            content
                .glassEffect(
                    .regular.interactive(isInteractive),
                    in: .rect(cornerRadius: radius)
                )
        }
    }
}

extension View {
    func wanderlustGlassSurface(
        radius: CGFloat = WanderlustRadius.large,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            WanderlustGlassSurface(
                radius: radius,
                isInteractive: isInteractive
            )
        )
    }

    func wanderlustCard(
        radius: CGFloat = WanderlustRadius.xLarge,
        padding: CGFloat = WanderlustSpacing.large
    ) -> some View {
        self
            .padding(padding)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(
                    cornerRadius: radius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: radius,
                    style: .continuous
                )
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

struct PrimaryActionButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }

                Text(title)
            }
            .font(.headline.weight(.semibold))
            .frame(minHeight: 50)
            .padding(.horizontal, WanderlustSpacing.xLarge)
            .background(
                WanderlustColor.accent,
                in: Capsule(style: .continuous)
            )
            .foregroundStyle(WanderlustColor.ivory)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryActionButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderlustSpacing.small) {
                if let systemImage {
                    Image(systemName: systemImage)
                }

                Text(title)
            }
            .font(.headline.weight(.semibold))
            .frame(minHeight: 48)
            .padding(.horizontal, WanderlustSpacing.xLarge)
            .background(
                Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(
                    cornerRadius: WanderlustRadius.capsule,
                    style: .continuous
                )
            )
            .foregroundStyle(.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct WanderlustSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: WanderlustSpacing.xSmall) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct WanderlustEmptyStateView<ActionLabel: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var action: () -> ActionLabel

    init(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder action: @escaping () -> ActionLabel = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            action()
                .padding(.top, WanderlustSpacing.small)
        }
        .frame(maxWidth: 320)
        .padding(.horizontal, WanderlustSpacing.xLarge)
        .accessibilityElement(children: .combine)
    }
}

struct WanderlustDestructiveActionRow: View {
    let title: String
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(emphasized ? .body.weight(.bold) : .body.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WanderlustSearchResultRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: WanderlustSpacing.medium) {
            leading()
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: WanderlustSpacing.small)

            trailing()
        }
        .padding(.vertical, WanderlustSpacing.small)
        .contentShape(Rectangle())
    }
}
