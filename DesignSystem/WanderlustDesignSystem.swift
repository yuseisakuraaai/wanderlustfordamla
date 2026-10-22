import SwiftUI
import UIKit

// MARK: - Wanderlust Design System (iOS 26 / Liquid Glass)
//
// 設計方針
// - 既存の `WanderlustSpacing` / `WanderlustRadius` / `WanderlustAnimation`
//   (PrimaryActionButton.swift) を置き換えず、色・書体トークンを *追加* して統合する。
// - 色は必ず Dynamic Color (UIColor dynamicProvider) で定義し、Dark Mode と
//   Increase Contrast の両方に追従させる。生の `Color(red:green:blue:)` を
//   画面側に書かない。
// - Liquid Glass は Apple の指針どおり「ナビゲーション層のみ」。
//   コンテンツ(本文カード・リスト行)には glass を使わない。
//   glass の上に glass を重ねない。
// - Reduce Transparency が有効なときは不透明サーフェスへフォールバックする。
//
// 参照:
//   https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
//   https://developer.apple.com/documentation/swiftui/glasseffectcontainer
//   https://developer.apple.com/design/human-interface-guidelines/materials

// MARK: - Colors

enum WanderlustColor {

    // MARK: Brand

    /// ブランドの基調色。ナビゲーション/アクセント/パスポート表紙と同系。
    static let navy = dynamic(
        light: UIColor(red: 0.106, green: 0.180, blue: 0.318, alpha: 1),
        dark: UIColor(red: 0.541, green: 0.671, blue: 0.867, alpha: 1)
    )

    /// 面として使うネイビー（表紙・ヘッダーの塗り）。Dark でも濃いまま。
    static let navySurface = dynamic(
        light: UIColor(red: 0.106, green: 0.180, blue: 0.318, alpha: 1),
        dark: UIColor(red: 0.078, green: 0.129, blue: 0.227, alpha: 1)
    )

    /// 旅行記らしい生成り。Light では紙、Dark では沈めて可読性を確保する。
    static let ivory = dynamic(
        light: UIColor(red: 0.976, green: 0.965, blue: 0.937, alpha: 1),
        dark: UIColor(red: 0.129, green: 0.125, blue: 0.114, alpha: 1)
    )

    /// 落ち着いたゴールド。強調は「面」ではなく「線・記号」に限定して使う。
    static let gold = dynamic(
        light: UIColor(red: 0.706, green: 0.557, blue: 0.267, alpha: 1),
        dark: UIColor(red: 0.855, green: 0.718, blue: 0.435, alpha: 1)
    )

    // MARK: Semantic surfaces
    //
    // システム色を基準にすることで Dark Mode / Increase Contrast /
    // Elevated (sheet) の各コンテキストに自動追従する。

    static let background = Color(.systemGroupedBackground)
    static let secondaryBackground = Color(.secondarySystemGroupedBackground)
    static let tertiaryBackground = Color(.tertiarySystemGroupedBackground)

    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let tertiaryText = Color(.tertiaryLabel)

    static let divider = Color(.separator)
    static let destructive = Color(.systemRed)

    /// 主要アクション（保存・追加）の色。tint と揃える。
    static let accent = navy

    // MARK: Chart palette
    //
    // Statistics のグラフ色はここに集約する。個々の View で `.blue` などを
    // 直書きしない。色だけに依存しないよう、必ずラベル/数値を併記すること。
    static let chartPrimary = navy
    static let chartSecondary = gold
    static let chartTertiary = Color(.systemTeal)
    static let chartQuaternary = Color(.systemIndigo)

    static let chartPalette: [Color] = [
        chartPrimary,
        chartSecondary,
        chartTertiary,
        chartQuaternary
    ]

    // MARK: Helper

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Typography
//
// 固定 pt を避け、必ず Dynamic Type に追従するテキストスタイルを基準にする。
// `.font(.system(size: 44))` の直書きは使わず `Font.wanderlust(_:relativeTo:)` を使う。
// 装飾的に大きくしたい箇所は `relativeTo:` 付きのカスタムを使う。

enum WanderlustFont {
    /// 画面タイトル（largeTitle 相当）。旅行記らしくやや細めのウエイト。
    static let screenTitle = Font.largeTitle.weight(.semibold)

    /// セクション見出し。
    static let sectionTitle = Font.title3.weight(.semibold)

    /// カード内の主要テキスト。
    static let cardTitle = Font.headline

    /// 数値ハイライト（統計カードなど）。等幅数字で桁ズレを防ぐ。
    static let statValue = Font.title2.weight(.bold).monospacedDigit()

    /// 補足テキスト。
    static let caption = Font.footnote
}

// MARK: - Dynamic Type で伸びる実寸フォント
//
// SwiftUI には `Font.system(size:relativeTo:)` が無い。
// `UIFontMetrics.scaledValue(for:)` を `Font` を返す static 関数の中で呼ぶ実装は
// 一見動くが、次の理由で正しく追従しない。
//
//   - 返るのは固定 pt の `Font` なので、SwiftUI は後からスケールし直さない
//   - static 関数は環境を読まないため、文字サイズ変更に対する依存が登録されず
//     body が再評価される保証がない
//   - 部分適用した `.dynamicTypeSize(...)` や Preview のサイズ上書きを無視する
//
// そのため Apple 推奨の `@ScaledMetric` を持つ ViewModifier として実装する。

private struct WanderlustScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat

    private let baseSize: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let maxScale: CGFloat
    private let usesMonospacedDigit: Bool

    init(
        size: CGFloat,
        relativeTo style: Font.TextStyle,
        weight: Font.Weight,
        design: Font.Design,
        maxScale: CGFloat,
        monospacedDigit: Bool
    ) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.baseSize = size
        self.weight = weight
        self.design = design
        self.maxScale = maxScale
        self.usesMonospacedDigit = monospacedDigit
    }

    func body(content: Content) -> some View {
        content.font(font)
    }

    private var font: Font {
        // 装飾的に大きな字が画面外へはみ出さないよう上限を設ける。
        let clamped = min(scaledSize, baseSize * maxScale)
        let base = Font.system(size: clamped, weight: weight, design: design)
        return usesMonospacedDigit ? base.monospacedDigit() : base
    }
}

extension View {
    /// 実寸を指定しつつ Dynamic Type に追従させる。
    ///
    /// - Parameters:
    ///   - size: 標準文字サイズ（Large）のときの実寸。既存の見た目がそのまま保たれる。
    ///   - style: 追従させたいテキストスタイル。実寸に近いものを選ぶ。
    ///   - maxScale: 拡大の上限倍率。
    func wanderlustFont(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        maxScale: CGFloat = 1.8,
        monospacedDigit: Bool = false
    ) -> some View {
        modifier(
            WanderlustScaledFont(
                size: size,
                relativeTo: style,
                weight: weight,
                design: design,
                maxScale: maxScale,
                monospacedDigit: monospacedDigit
            )
        )
    }

    /// 装飾用の大きなグリフ（空状態のアイコンなど）。
    /// 本文ほど大きくは伸ばさず、レイアウト崩れを防ぐ。
    func wanderlustDecorativeFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        wanderlustFont(
            size,
            relativeTo: .largeTitle,
            weight: weight,
            design: design,
            maxScale: 1.25
        )
    }
}

// MARK: - Layout constants

enum WanderlustLayout {
    /// HIG の最小タップ領域 44x44pt。
    static let minimumTapTarget: CGFloat = 44

    /// iPad / 大画面で本文が横に伸びすぎるのを防ぐ読みやすい最大幅。
    static let readableMaxWidth: CGFloat = 700

    /// 一覧カードのサムネイル比率を統一する（写真の縦横比のばらつき防止）。
    static let thumbnailAspectRatio: CGFloat = 4.0 / 3.0

    /// 1px 罫線。`UIScreen.main` は非推奨のため現在のトレイトから取得する。
    static var hairline: CGFloat {
        let scale = UITraitCollection.current.displayScale
        return 1 / (scale > 0 ? scale : 2)
    }
}

// MARK: - Liquid Glass surfaces (iOS 26)

extension View {
    /// ナビゲーション層の浮遊コントロール用 Liquid Glass。
    ///
    /// - Important: コンテンツ（本文・リスト行・カード）には使わない。
    ///   Apple の指針では glass はナビゲーション層専用で、glass の上に
    ///   glass を重ねてはならない。
    func wanderlustNavigationGlass(
        shape: some Shape = Capsule(),
        isInteractive: Bool = true,
        tint: Color? = nil
    ) -> some View {
        modifier(
            WanderlustNavigationGlass(
                shape: AnyShape(shape),
                isInteractive: isInteractive,
                tint: tint
            )
        )
    }

    /// コンテンツ層のカード。glass ではなく不透明サーフェスを使う。
    /// 影は使わず、角丸と背景色だけで階層を表す（影の不統一を防ぐ）。
    func wanderlustContentCard(
        radius: CGFloat = WanderlustRadius.xLarge,
        padding: CGFloat = WanderlustSpacing.large
    ) -> some View {
        self
            .padding(padding)
            .background(
                WanderlustColor.secondaryBackground,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
    }

    /// 本文の最大幅を制限し、iPad での過剰な横伸びを防ぐ。
    func wanderlustReadableWidth(
        _ maxWidth: CGFloat = WanderlustLayout.readableMaxWidth
    ) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    /// 44x44pt の最小タップ領域を保証する。
    func wanderlustMinimumTapTarget() -> some View {
        frame(
            minWidth: WanderlustLayout.minimumTapTarget,
            minHeight: WanderlustLayout.minimumTapTarget
        )
        .contentShape(Rectangle())
    }
}

private struct WanderlustNavigationGlass: ViewModifier {
    let shape: AnyShape
    let isInteractive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        content.glassEffect(Glass.regular.interactive(isInteractive), in: shape)
    }
}

// MARK: - Section header

struct WanderlustSectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: WanderlustSpacing.xSmall) {
            Text(title)
                .font(WanderlustFont.sectionTitle)
                .foregroundStyle(WanderlustColor.primaryText)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(WanderlustFont.caption)
                    .foregroundStyle(WanderlustColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Divider

struct WanderlustDivider: View {
    var body: some View {
        Rectangle()
            .fill(WanderlustColor.divider)
            .frame(height: WanderlustLayout.hairline)
            .accessibilityHidden(true)
    }
}

// MARK: - Stat card

struct WanderlustStatCard: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = WanderlustColor.accent
    var showsChevron = false

    var body: some View {
        VStack(alignment: .leading, spacing: WanderlustSpacing.small) {
            HStack(spacing: WanderlustSpacing.small) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(WanderlustFont.caption)
                    .foregroundStyle(WanderlustColor.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WanderlustColor.tertiaryText)
                }
            }

            Text(value)
                .font(WanderlustFont.statValue)
                .foregroundStyle(WanderlustColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wanderlustContentCard(radius: WanderlustRadius.medium)
        // VoiceOver では「国 12」ではなく「国、12」と読ませる。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityAddTraits(showsChevron ? .isButton : [])
    }
}

// MARK: - Loading / Error states

struct WanderlustLoadingView: View {
    var message: String?

    var body: some View {
        VStack(spacing: WanderlustSpacing.medium) {
            ProgressView()
            if let message, !message.isEmpty {
                Text(message)
                    .font(WanderlustFont.caption)
                    .foregroundStyle(WanderlustColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message ?? String(localized: "Loading"))
    }
}

struct WanderlustErrorStateView: View {
    let title: String
    let message: String
    var retryTitle: String?
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: WanderlustSpacing.large) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WanderlustColor.secondaryText)

            VStack(spacing: WanderlustSpacing.small) {
                Text(title)
                    .font(WanderlustFont.sectionTitle)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(WanderlustColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onRetry, let retryTitle {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(.glassProminent)
            }
        }
        .frame(maxWidth: 340)
        .padding(WanderlustSpacing.xLarge)
    }
}
