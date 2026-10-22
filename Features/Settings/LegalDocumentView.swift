import SwiftUI
import SafariServices

// MARK: - Safari Sheet

struct WanderlustSafariSheet: View {
    let url: URL
    @State private var showError = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WanderlustSafariRepresentable(url: url, onLoadFailed: { showError = true })
            .ignoresSafeArea()
            .alert(
                WanderlustL10n.string("Couldn't Open Page", table: .errors, fallback: "Couldn't Open Page"),
                isPresented: $showError
            ) {
                Button(String(localized: "OK"), role: .cancel) { dismiss() }
            } message: {
                Text(WanderlustL10n.string(
                    "Couldn't open the page. Check your internet connection and try again.",
                    table: .errors,
                    fallback: "Couldn't open the page. Check your internet connection and try again."
                ))
            }
    }
}

private struct WanderlustSafariRepresentable: UIViewControllerRepresentable {
    let url: URL
    let onLoadFailed: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Legal Document (in-app fallback, no longer primary)

struct LegalDocumentView: View {
    enum Kind {
        case terms
        case privacy

        var title: String {
            switch self {
            case .terms: WanderlustL10n.string("Terms of Service", table: .settings)
            case .privacy: WanderlustL10n.string("Privacy Policy", table: .settings)
            }
        }
    }

    let kind: Kind

    private var sections: [(String, [String])] {
        let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
        switch (kind, isJapanese) {
        case (.terms, true):
            return [
                ("1. サービス概要", ["Wanderlustは、旅行、訪問都市、訪問国、フライト、プロフィール情報を端末内で記録し、地図、パスポート、統計として表示する旅行記録アプリです。"]),
                ("2. アカウント", ["Wanderlustを利用するには、メールアドレス、Apple、またはGoogleによるログインが必要です。アカウント情報は本人確認、同期、データ管理のために使用します。"]),
                ("3. データ保存と同期", ["旅行、プロフィール、写真、設定、フライト情報は端末内に保存されます。ログイン時はデータの同期機能を利用する場合があります。"]),
                ("4. ユーザーの責任", ["入力内容の正確性、端末の管理、バックアップ、第三者に見られたくない情報の管理はユーザーの責任です。"]),
                ("5. 禁止事項", ["不正アクセス、リバースエンジニアリング、他者の権利侵害、虚偽情報による不正利用、法令に反する利用を禁止します。"]),
                ("6. 知的財産権", ["Wanderlustの画面、名称、ソフトウェア、デザインに関する権利は開発者または正当な権利者に帰属します。ユーザーが入力した旅行記録の権利はユーザーに残ります。"]),
                ("7. 地図・路線データ", ["Wanderlustは地図表示や空港・都市・国境データのために公開データを利用しています。路線情報は参考用であり、実際のフライト番号、運航日、時刻、運休、季節便を保証しません。"]),
                ("8. 広告", ["広告視聴は任意です。広告を見ない場合でもWanderlustの全機能を利用できます。"]),
                ("9. サービスの変更および停止", ["機能、画面、データソース、提供方法は、品質向上、保守、法令対応などのため変更または停止することがあります。"]),
                ("10. 保証の否認と免責", ["Wanderlustは現状有姿で提供されます。正確性、継続性、特定目的適合性、エラーがないことを保証しません。"]),
                ("11. 責任制限", ["適用法で認められる範囲で、Wanderlustの利用または利用不能により生じた間接損害、特別損害、逸失利益、データ損失について責任を負いません。"]),
                ("12. 準拠法", ["本規約は、抵触法の原則を除き、日本法に準拠します。"]),
                ("13. 規約変更", ["本規約を変更する場合、アプリ内表示または適切な方法で通知します。重要な変更は合理的な周知期間を設けます。"]),
                ("14. 発効日・最終更新日", ["発効日: 2026年7月15日", "最終更新日: 2026年7月17日"])
            ]
        case (.terms, false):
            return [
                ("1. Service Overview", ["Wanderlust is a travel journal app for recording trips, visited cities and countries, flights, profile details, and displaying them through maps, passport pages, and statistics."]),
                ("2. Eligibility and Use", ["You must use Wanderlust in compliance with applicable law, these terms, and App Store terms."]),
                ("3. Accounts", ["Wanderlust requires sign-in with an email address, Apple, or Google. Account information is used for authentication, sync, and data management."]),
                ("4. Data Storage and Sync", ["Trips, profile details, settings, and flight records are stored on your device. When signed in, data sync features may be used."]),
                ("5. User Responsibilities", ["You are responsible for the accuracy of entries, protecting your device, maintaining backups, and managing sensitive travel information."]),
                ("6. Prohibited Conduct", ["You may not misuse Wanderlust, attempt unauthorized access, reverse engineer protected components, infringe rights, submit fraudulent information, or use Wanderlust unlawfully."]),
                ("7. Intellectual Property", ["Wanderlust software, design, screens, and names belong to the developer or their owners. Your travel records remain yours."]),
                ("8. Maps and Route Data", ["Wanderlust uses publicly available data for maps, airports, cities, and country boundaries. Route information is for reference only and does not guarantee real flight numbers, schedules, cancellations, or seasonal service."]),
                ("9. Ads", ["Watching ads is optional. All Wanderlust features remain available if you do not watch ads."]),
                ("10. Changes or Suspension", ["Features, screens, data sources, and delivery methods may change or stop for maintenance, quality, legal, or operational reasons."]),
                ("11. Disclaimer of Warranties", ["Wanderlust is provided as is without warranties of accuracy, continuity, fitness for a particular purpose, or error-free operation."]),
                ("12. Limitation of Liability", ["To the extent permitted by law, Wanderlust is not liable for indirect, special, consequential damages, lost profits, or data loss arising from use or inability to use the app."]),
                ("13. Governing Law", ["These terms are governed by the laws of Japan, excluding conflict-of-law rules."]),
                ("14. Changes to Terms", ["Changes will be notified in the app or by another appropriate method. Material changes will include a reasonable notice period."]),
                ("15. Effective and Updated Dates", ["Effective: July 15, 2026", "Last updated: July 17, 2026"])
            ]
        case (.privacy, true):
            return [
                ("1. 収集する情報", ["Wanderlustは、名前、メールアドレス、居住国、プロフィール写真、旅行記録、国・都市・フライト情報、設定値、端末内下書き、オフラインキャッシュを保存します。"]),
                ("2. 位置情報", ["許可された場合、起動時の現在地表示、近くの都市・空港候補の提案に位置情報を使用します。拒否してもWanderlustは利用できます。"]),
                ("3. 通知権限", ["許可された場合、旅行記録のリマインダーなどに通知を使用します。現時点では広告通知や第三者マーケティングには使用しません。"]),
                ("4. 写真アクセス", ["プロフィール写真を選ぶために写真アクセスを使用します。制限付きアクセスの場合はユーザーが許可した写真だけを読み込みます。"]),
                ("5. 端末内保存と利用目的", ["記録の表示、検索、統計、地図塗りつぶし、パスポートスタンプ、フライト再生、設定反映のために情報を使用します。"]),
                ("6. 利用するサービスとデータソース", ["Wanderlustは地図表示のために地図サービスを、ログイン時にアカウント認証・同期機能を、任意広告視聴のために広告サービスを利用する場合があります。空港・都市・国境データは公開データを使用しています。"]),
                ("7. 広告", ["広告視聴は任意です。障害解析機能が有効な場合、クラッシュ情報、端末情報、アプリ状態が送信されることがあります。旅行記録そのものを広告事業者へ販売しません。"]),
                ("8. データ保持と削除", ["データはアプリ内で削除するか、アプリ削除またはアカウント削除まで保持されます。ログイン中に同期されたデータはアカウント削除後に削除対象となります。"]),
                ("9. バックアップとエクスポート", ["端末バックアップに含まれる場合があります。エクスポート機能を提供する場合は、ユーザー操作に基づいてファイルを作成します。"]),
                ("10. セキュリティ", ["WanderlustはOS標準の保存領域と権限制御を利用します。ただし、端末のロック解除、共有端末、バックアップ先の安全性はユーザーの管理に依存します。"]),
                ("11. 未成年者・国際利用", ["未成年者は保護者の同意を得て利用してください。国際的に利用する場合、地図・データ表示は地域により異なる場合があります。"]),
                ("12. ユーザーの権利", ["ユーザーは自分のデータの確認、修正、削除をアプリ内機能または問い合わせで求めることができます。未成年者は保護者の同意を得て利用してください。"]),
                ("13. ポリシー変更とお問い合わせ", ["変更時はアプリ内または適切な方法で通知します。お問い合わせは設定画面からご連絡ください。"]),
                ("14. 発効日・最終更新日", ["発効日: 2026年7月15日", "最終更新日: 2026年7月17日"])
            ]
        case (.privacy, false):
            return [
                ("1. Information We Collect", ["Wanderlust stores your name, email address, home country, profile photo, trip records, country, city and flight information, settings, local drafts, and offline cache."]),
                ("2. Location", ["If allowed, location is used to show your current position at launch and suggest nearby cities and airports. Wanderlust remains usable if you deny access."]),
                ("3. Notifications", ["If allowed, notifications may be used for travel record reminders. Wanderlust does not currently use notifications for advertising or third-party marketing."]),
                ("4. Photos Access", ["Photo access is used to select a profile photo. With limited access, Wanderlust reads only the photos you allow."]),
                ("5. On-Device Storage and Purposes", ["Information is used to display records, search trips, calculate statistics, fill countries on the map, create passport stamps, replay flights, and apply settings."]),
                ("6. Services and Data Sources", ["Wanderlust uses a map service for displaying maps, account sign-in and sync features when signed in, and ad services for optional rewarded ads. Airport, city, and country boundary data comes from publicly available sources."]),
                ("7. Ads", ["Watching ads is optional. If diagnostics are enabled, crash details, device information, and app state may be sent. Wanderlust does not sell your travel records to advertisers."]),
                ("8. Retention and Deletion", ["Data remains until deleted in the app, app deletion, or account deletion. Data synced while signed in will be targeted for deletion after account deletion."]),
                ("9. Backup and Export", ["Data may be included in device backups. If export features are provided, files will be created only through user action."]),
                ("10. Security", ["Wanderlust relies on standard OS storage and permission controls. Device lock state, shared devices, and backup destinations remain your responsibility."]),
                ("11. Children and International Use", ["Minors should use Wanderlust with guardian consent. Map and data presentation may vary by region."]),
                ("12. User Rights", ["You may request access, correction, or deletion through app features or contact. Minors should use Wanderlust with guardian consent."]),
                ("13. Changes and Contact", ["Policy changes will be notified in the app or by another appropriate method. Contact us from Settings."]),
                ("14. Effective and Updated Dates", ["Effective: July 15, 2026", "Last updated: July 17, 2026"])
            ]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.0)
                            .font(.headline)
                        ForEach(section.1, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(kind.title)
        .toolbarTitleDisplayMode(.inline)
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            Section(WanderlustL10n.string("Data Sources", table: .settings)) {
                licenseRow(
                    name: WanderlustL10n.string("GeoNames", table: .world),
                    description: WanderlustL10n.string("City and geographic name data", table: .trips),
                    url: WanderlustL10n.string("geonames.org · CC BY 4.0", table: .world)
                )
                licenseRow(
                    name: WanderlustL10n.string("Natural Earth", table: .world),
                    description: WanderlustL10n.string("Country boundary polygons", table: .world),
                    url: String(localized: "naturalearthdata.com · Public Domain")
                )
                licenseRow(
                    name: WanderlustL10n.string("OpenFlights", table: .settings),
                    description: WanderlustL10n.string("Airport and airline data", table: .airports),
                    url: WanderlustL10n.string("openflights.org · ODbL", table: .settings)
                )
            }
        }
        .navigationTitle(WanderlustL10n.string("Licenses", table: .settings))
        .toolbarTitleDisplayMode(.large)
    }

    private func licenseRow(name: String, description: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(url)
                .font(.caption2)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }
}

struct FutureFeaturesView: View {
    struct FeatureCategory: Identifiable {
        let id: String
        let systemImage: String
        let title: String
        let items: [String]
    }

    private var title: String {
        WanderlustL10n.string("Future Features", table: .settings)
    }

    private var categories: [FeatureCategory] {
        [
            FeatureCategory(
                id: "flights",
                systemImage: "airplane",
                title: WanderlustL10n.string("Flights", table: .settings),
                items: [
                    WanderlustL10n.string("Actual flight route display", table: .settings),
                    WanderlustL10n.string("Flight information API integration", table: .settings),
                    WanderlustL10n.string("Flight number suggestions", table: .settings)
                ]
            ),
            FeatureCategory(
                id: "experience",
                systemImage: "suitcase.rolling.fill",
                title: WanderlustL10n.string("Travel Experience", table: .settings, fallback: "Travel Experience"),
                items: [
                    WanderlustL10n.string("Widgets", table: .settings),
                    WanderlustL10n.string("Trip sharing", table: .settings),
                    WanderlustL10n.string("Offline improvements", table: .settings)
                ]
            ),
            FeatureCategory(
                id: "passport-statistics",
                systemImage: "chart.bar.doc.horizontal.fill",
                title: WanderlustL10n.string("Passport and Statistics", table: .settings, fallback: "Passport and Statistics"),
                items: [
                    WanderlustL10n.string("Passport feature expansion", table: .settings),
                    WanderlustL10n.string("Additional statistics", table: .settings)
                ]
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 12) {
                    ForEach(categories) { category in
                        FutureFeatureCategoryCard(category: category)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct FutureFeatureCategoryCard: View {
    let category: FutureFeaturesView.FeatureCategory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.14))
                    .frame(width: 34, height: 34)

                Image(systemName: category.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 22, height: 22)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 14) {
                Text(category.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(category.items, id: \.self) { item in
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
    }
}
