import SwiftUI

enum SupportConstants {
    static let email = "wanderlust.incapp@gmail.com"
}

enum SupportLinks {
    static let privacy = URL(string: "https://yuseisakuraaai.github.io/wanderlust-support/privacy.html")!
    static let terms   = URL(string: "https://yuseisakuraaai.github.io/wanderlust-support/terms.html")!
}

// NOTE: `WanderlustEmptyStateContainer` と `WanderlustEmptyStateScreen` は削除した。
// 自前で largeTitle と .padding(.top, 58) を描いていたため、機種ごとに余白がズレ、
// iOS 26 のスクロールエッジ効果も効かなかった。
// 空状態は Apple 標準の `ContentUnavailableView`、タイトルは `.navigationTitle` を使う。

extension View {
    /// 旧 API 互換のための薄いラッパー。
    /// デプロイメントターゲットが iOS 26.0 のため `#available` 分岐は不要になった。
    /// 新規コードは `wanderlustNavigationGlass(shape:)`
    /// （Reduce Transparency 対応込み）を使うこと。
    func wanderlustGlassEffect<S: Shape>(_ shape: S) -> some View {
        wanderlustNavigationGlass(shape: shape, isInteractive: false)
    }
}

public enum WanderlustAppearance: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system:
            WanderlustL10n.string("System", table: .settings)
        case .light:
            WanderlustL10n.string("Light", table: .settings)
        case .dark:
            WanderlustL10n.string("Dark", table: .settings)
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
