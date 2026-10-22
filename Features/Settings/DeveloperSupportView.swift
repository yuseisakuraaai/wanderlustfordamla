import SwiftUI
import UIKit
import Combine
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif
#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

// MARK: - Ad Configuration

enum AdMobConfiguration {
    static let googleRewardedTestAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    static var rewardedAdUnitID: String {
        if isTestBuild {
            return googleRewardedTestAdUnitID
        }
        return Bundle.main.object(forInfoDictionaryKey: "ADMOB_REWARDED_AD_UNIT_ID") as? String ?? ""
    }

    static var isUsingTestAdUnit: Bool {
        rewardedAdUnitID == googleRewardedTestAdUnitID
    }

    static var isEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "ATLAS_ADS_ENABLED") as? Bool) ?? true
    }

    private static var isTestBuild: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}

// MARK: - Rewarded Ad State

enum RewardedAdState: Equatable {
    case idle
    case loading
    case presenting
    case failed(message: String)

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

// MARK: - Support Level

enum SupportLevel: Equatable {
    case traveler, supporter, explorer, world, partner

    init(points: Int) {
        switch points {
        case 0..<10:  self = .traveler
        case 10..<20: self = .supporter
        case 20..<30: self = .explorer
        case 30..<40: self = .world
        default:      self = .partner
        }
    }

    func localizedName(lang: String) -> String {
        switch self {
        case .traveler:  return lang == "ja" ? "トラベラー"        : lang == "de" ? "Reisende"         : "Traveler"
        case .supporter: return lang == "ja" ? "サポーター"        : lang == "de" ? "Unterstützer"     : "Supporter"
        case .explorer:  return lang == "ja" ? "エクスプローラー"  : lang == "de" ? "Entdecker"        : "Explorer"
        case .world:     return lang == "ja" ? "ワールドサポーター" : lang == "de" ? "Weltunterstützer" : "World Supporter"
        case .partner:   return "Wanderlust Partner"
        }
    }

    var nextThreshold: Int? {
        switch self {
        case .traveler:  return 10
        case .supporter: return 20
        case .explorer:  return 30
        case .world:     return 40
        case .partner:   return nil
        }
    }

    var symbolName: String {
        switch self {
        case .traveler:  return "figure.walk"
        case .supporter: return "star.fill"
        case .explorer:  return "globe.americas.fill"
        case .world:     return "globe.europe.africa.fill"
        case .partner:   return "sparkles"
        }
    }

    var tintColor: Color {
        switch self {
        case .traveler:  return .gray
        case .supporter: return .blue
        case .explorer:  return .green
        case .world:     return Color(hue: 0.09, saturation: 0.85, brightness: 0.90)
        case .partner:   return .purple
        }
    }

    var cardGradientColors: [Color] {
        switch self {
        case .traveler:  return [.gray.opacity(0.08), .gray.opacity(0.02)]
        case .supporter: return [.blue.opacity(0.10), .blue.opacity(0.03)]
        case .explorer:  return [.green.opacity(0.10), .green.opacity(0.03)]
        case .world:     return [Color(hue: 0.09, saturation: 0.8, brightness: 0.95).opacity(0.16),
                                  Color.yellow.opacity(0.05)]
        case .partner:   return [.purple.opacity(0.14), .pink.opacity(0.06)]
        }
    }

    var cardBorderOpacity: Double {
        self == .partner ? 0.30 : 0.16
    }

    var cardBorderWidth: CGFloat {
        self == .partner ? 1.5 : 1.0
    }
}

// MARK: - Support Points Store

@MainActor
final class SupportPointsStore: ObservableObject {
    static let shared = SupportPointsStore()

    @Published private(set) var points: Int = 0

    private let defaultsKey = "wanderlust.supportPoints"
    private var listenedUID: String? = nil

    #if canImport(FirebaseFirestore)
    private var listener: ListenerRegistration?
    #endif

    private init() {
        points = UserDefaults.standard.integer(forKey: defaultsKey)
    }

    func connectIfNeeded() {
        #if canImport(FirebaseAuth)
        let uid = Auth.auth().currentUser?.uid
        guard uid != listenedUID else { return }
        listenedUID = uid
        #if canImport(FirebaseFirestore)
        listener?.remove()
        listener = nil
        guard let uid, !uid.isEmpty else { return }
        let ref = Firestore.firestore().collection("users").document(uid)
        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self, error == nil, let data = snapshot?.data() else { return }
            guard let serverPoints = Self.decodedSupportPoints(from: data["supportPoints"]) else {
                Task { @MainActor [weak self] in
                    guard let self, self.points > 0 else { return }
                    ref.setData(["supportPoints": self.points], merge: true)
                }
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let localPoints = UserDefaults.standard.integer(forKey: self.defaultsKey)
                let resolvedPoints = max(serverPoints, localPoints, self.points)
                self.points = resolvedPoints
                UserDefaults.standard.set(resolvedPoints, forKey: self.defaultsKey)
                if resolvedPoints > serverPoints {
                    ref.setData(["supportPoints": resolvedPoints], merge: true)
                }
            }
        }
        #endif
        #endif
    }

    func addPoint() async {
        #if canImport(FirebaseAuth)
        if let uid = Auth.auth().currentUser?.uid, !uid.isEmpty {
            #if canImport(FirebaseFirestore)
            do {
                let ref = Firestore.firestore().collection("users").document(uid)
                try await ref.setData(
                    ["supportPoints": FieldValue.increment(Int64(1))],
                    merge: true
                )
                return
            } catch {
                WanderlustDiagnostics.warning(
                    "supportPoints increment failed: \(error.localizedDescription)",
                    category: .sync
                )
            }
            #endif
        }
        #endif
        points += 1
        UserDefaults.standard.set(points, forKey: defaultsKey)
    }

    nonisolated private static func decodedSupportPoints(from value: Any?) -> Int? {
        switch value {
        case let points as Int:
            return max(points, 0)
        case let points as Int64:
            guard points <= Int64(Int.max) else { return Int.max }
            return max(Int(points), 0)
        case let points as NSNumber:
            return max(points.intValue, 0)
        default:
            return nil
        }
    }
}

// MARK: - Rewarded Ad Manager

@MainActor
final class RewardedAdManager: NSObject, ObservableObject {
    static let shared = RewardedAdManager()

    @Published private(set) var state: RewardedAdState = .idle

    private var isSDKInitialized = false
    private var rewardedAd: RewardedAd?
    private var hasGrantedReward = false
    private var pendingRewardCallback: (() -> Void)?

    private override init() { super.init() }

    func sdkDidInitialize() {
        isSDKInitialized = true
        #if DEBUG
        WanderlustDiagnostics.info("ads sdk initialized \(Self.adDiagnosticsSuffix())", category: .performance)
        #endif
    }

    /// Loads and immediately presents the ad. Called only on explicit user tap.
    func loadAndShow(onReward: @escaping () -> Void) async {
        guard state.isIdle else { return }
        guard AdMobConfiguration.isEnabled else {
            state = .failed(message: SupportLocalization.unavailable)
            return
        }
        guard isSDKInitialized else {
            WanderlustDiagnostics.warning("rewarded ad requested before sdk initialization \(Self.adDiagnosticsSuffix())", category: .performance)
            state = .failed(message: SupportLocalization.unavailable)
            return
        }
        #if canImport(UserMessagingPlatform)
        guard ConsentInformation.shared.canRequestAds else {
            WanderlustDiagnostics.warning("rewarded ad blocked canRequestAds=false \(Self.adDiagnosticsSuffix())", category: .performance)
            state = .failed(message: SupportLocalization.unavailable)
            return
        }
        #endif
        state = .loading
        rewardedAd = nil

        do {
            WanderlustDiagnostics.info("rewarded ad load started \(Self.adDiagnosticsSuffix())", category: .performance)
            let ad = try await RewardedAd.load(
                with: AdMobConfiguration.rewardedAdUnitID,
                request: Request()
            )
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
            WanderlustDiagnostics.info("rewarded ad load succeeded responseInfo=\(String(describing: ad.responseInfo))", category: .performance)

            guard let vc = topViewController() else {
                state = .failed(message: SupportLocalization.unavailable)
                return
            }
            state = .presenting
            hasGrantedReward = false
            pendingRewardCallback = onReward
            ad.present(from: vc) { @MainActor [weak self] in
                guard let self, !self.hasGrantedReward else { return }
                self.hasGrantedReward = true
                self.pendingRewardCallback?()
                self.pendingRewardCallback = nil
            }
        } catch {
            let nsError = error as NSError
            WanderlustDiagnostics.warning(
                "RewardedAd [\(nsError.domain):\(nsError.code)] \(nsError.localizedDescription) \(Self.adDiagnosticsSuffix())",
                category: .performance
            )
            state = .failed(message: SupportLocalization.unavailable)
        }
    }

    func resetToIdle() {
        state = .idle
    }

    private func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
        let root: UIViewController?
        if let base {
            root = base
        } else {
            root = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        }
        guard let root else { return nil }
        if let nav = root as? UINavigationController { return topViewController(nav.visibleViewController) }
        if let tab = root as? UITabBarController { return topViewController(tab.selectedViewController) }
        if let presented = root.presentedViewController { return topViewController(presented) }
        return root
    }

    private static func adDiagnosticsSuffix() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let unitID = AdMobConfiguration.rewardedAdUnitID
        let suffix = unitID.suffix(6)
        #if DEBUG
        let build = "Debug"
        #else
        let build = "Release"
        #endif
        #if canImport(UserMessagingPlatform)
        let consentStatus = "\(ConsentInformation.shared.consentStatus.rawValue)"
        let canRequestAds = ConsentInformation.shared.canRequestAds
        #else
        let consentStatus = "unavailable"
        let canRequestAds = true
        #endif
        return "build=\(build) bundleID=\(bundleID) adUnitType=\(AdMobConfiguration.isUsingTestAdUnit ? "test" : "production") adUnitSuffix=\(suffix) umpConsentStatus=\(consentStatus) canRequestAds=\(canRequestAds)"
    }
}

// MARK: - FullScreenContentDelegate

#if canImport(GoogleMobileAds)
extension RewardedAdManager: FullScreenContentDelegate {
    nonisolated func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        WanderlustDiagnostics.info("rewarded ad presented", category: .ui)
        #endif
    }

    nonisolated func adDidRecordImpression(_ ad: FullScreenPresentingAd) {}
    nonisolated func adDidRecordClick(_ ad: FullScreenPresentingAd) {}

    nonisolated func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        let nsError = error as NSError
        WanderlustDiagnostics.warning(
            "rewarded ad present failed domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)",
            category: .ui
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.rewardedAd = nil
            self.hasGrantedReward = false
            self.pendingRewardCallback = nil
            self.state = .failed(message: SupportLocalization.presentFailed)
        }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        WanderlustDiagnostics.info("rewarded ad dismissed", category: .ui)
        #endif
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.rewardedAd = nil
            self.hasGrantedReward = false
            self.pendingRewardCallback = nil
            self.state = .idle
        }
    }
}
#endif

// MARK: - Localization

private enum SupportLocalization {
    static var rewardDescription: String {
        switch lang {
        case "ja": return "広告を最後まで見ると、サポートポイントを1ポイント獲得できます。"
        case "de": return "Sieh dir die Anzeige an und erhalte 1 Supportpunkt."
        default:   return "Watch the ad to earn 1 Support Point."
        }
    }

    static var watchButtonTitle: String {
        switch lang {
        case "ja": return "広告を見てサポートする"
        case "de": return "Anzeige ansehen und unterstützen"
        default:   return "Watch Ad to Support"
        }
    }

    static var loadingButtonTitle: String {
        switch lang {
        case "ja": return "読み込み中…"
        case "de": return "Wird geladen…"
        default:   return "Loading…"
        }
    }

    static var presentingButtonTitle: String {
        switch lang {
        case "ja": return "広告を表示中…"
        case "de": return "Anzeige läuft…"
        default:   return "Showing Ad…"
        }
    }

    static var adUnavailableTitle: String {
        switch lang {
        case "ja": return "広告を利用できません"
        case "de": return "Anzeige nicht verfügbar"
        default:   return "Ad Unavailable"
        }
    }

    static var adUnavailableBody: String {
        switch lang {
        case "ja": return "現在広告を利用できません。時間を空けてもう一度お試しください。"
        case "de": return "Derzeit ist keine Anzeige verfügbar. Bitte versuche es später erneut."
        default:   return "Ads are not available right now. Please try again later."
        }
    }

    static var earnedTitle: String {
        switch lang {
        case "ja": return "ありがとうございます"
        case "de": return "Vielen Dank"
        default:   return "Thank You"
        }
    }

    static var earnedBody: String {
        switch lang {
        case "ja": return "サポートポイントを1ポイント獲得しました。"
        case "de": return "Du hast 1 Supportpunkt erhalten."
        default:   return "You earned 1 Support Point."
        }
    }

    static var unavailable: String {
        switch lang {
        case "ja": return "現在広告を利用できません。"
        case "de": return "Keine Anzeige verfügbar."
        default:   return "No ad available."
        }
    }

    static var presentFailed: String {
        switch lang {
        case "ja": return "広告を表示できませんでした。"
        case "de": return "Anzeige konnte nicht angezeigt werden."
        default:   return "Failed to display the ad."
        }
    }

    static var levelLabel: String {
        switch lang {
        case "ja": return "サポートランク"
        case "de": return "Support-Rang"
        default:   return "Support Rank"
        }
    }

    static var totalPointsLabel: String {
        switch lang {
        case "ja": return "累計サポートポイント"
        case "de": return "Gesamte Supportpunkte"
        default:   return "Total Support Points"
        }
    }

    static func nextLevelText(remaining: Int) -> String {
        switch lang {
        case "ja": return "あと \(remaining) ポイントで次のランク"
        case "de": return "\(remaining) Punkt\(remaining == 1 ? "" : "e") bis zum nächsten Rang"
        default:   return "\(remaining) point\(remaining == 1 ? "" : "s") to next rank"
        }
    }

    static var maxLevelText: String {
        switch lang {
        case "ja": return "最高ランクに到達しました"
        case "de": return "Höchsten Rang erreicht"
        default:   return "Maximum rank reached"
        }
    }

    static var lang: String {
        let rawCode = Bundle.main.preferredLocalizations.first
            ?? Bundle.main.developmentLocalization ?? "en"
        return rawCode
            .split(separator: "@", maxSplits: 1).first?
            .split(whereSeparator: { $0 == "_" || $0 == "-" }).first?
            .lowercased() ?? "en"
    }
}

// MARK: - DeveloperSupportView

struct DeveloperSupportView: View {
    @ObservedObject private var adManager = RewardedAdManager.shared
    @ObservedObject private var pointsStore = SupportPointsStore.shared

    @State private var showEarnedAlert = false
    @State private var showAdFailedAlert = false
    @State private var adUnavailableForCurrentPresentation = false
    @State private var presentationResetID = UUID()

    private var lang: String { SupportLocalization.lang }
    private var level: SupportLevel { SupportLevel(points: pointsStore.points) }

    private var viewTitle: String {
        lang == "ja" ? "開発者をサポート" : lang == "de" ? "Entwickler unterstützen" : "Support"
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack {
                    Spacer(minLength: 0)

                    VStack(spacing: 30) {
                        levelCard
                        descriptionSection
                        adSection
                    }
                    .frame(maxWidth: 430)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
                .padding(.bottom, 104)
                .frame(minHeight: proxy.size.height)
            }
        }
        .navigationTitle(viewTitle)
        .toolbarTitleDisplayMode(.inline)
        .onAppear {
            resetPresentationState()
            pointsStore.connectIfNeeded()
        }
        .onDisappear {
            resetPresentationState()
        }
        .onChange(of: adManager.state) { _, newState in
            if case .failed = newState {
                adUnavailableForCurrentPresentation = true
                showAdFailedAlert = true
            }
        }
        .alert(SupportLocalization.adUnavailableTitle, isPresented: $showAdFailedAlert) {
            Button(WanderlustL10n.string("OK", table: .general), role: .cancel) {}
        } message: {
            Text(SupportLocalization.adUnavailableBody)
        }
        .alert(SupportLocalization.earnedTitle, isPresented: $showEarnedAlert) {
            Button(WanderlustL10n.string("OK", table: .general)) {}
        } message: {
            Text(SupportLocalization.earnedBody)
        }
    }

    // MARK: - Level Card

    private var levelCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .center, spacing: 4) {
                    Text(SupportLocalization.levelLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: level.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(level.tintColor)
                        Text(level.localizedName(lang: lang))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(level.tintColor)
                    }
                    .animation(.spring(duration: 0.4), value: level)
                }
                Spacer()
                VStack(alignment: .center, spacing: 4) {
                    Text(SupportLocalization.totalPointsLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(pointsStore.points)")
                        .font(.title2.weight(.bold))
                        .contentTransition(.numericText())
                        .animation(.default, value: pointsStore.points)
                }
            }

            Divider()

            if let nextThreshold = level.nextThreshold {
                let remaining = max(nextThreshold - pointsStore.points, 0)
                Text(SupportLocalization.nextLevelText(remaining: remaining))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(SupportLocalization.maxLevelText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: level.cardGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous)
                .strokeBorder(
                    level == .partner
                        ? AnyShapeStyle(LinearGradient(
                            colors: [.purple.opacity(0.5), .pink.opacity(0.35), .indigo.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          ))
                        : AnyShapeStyle(level.tintColor.opacity(level.cardBorderOpacity)),
                    lineWidth: level.cardBorderWidth
                )
        }
        .animation(.spring(duration: 0.4), value: level)
    }

    // MARK: - Description

    private var descriptionSection: some View {
        Text(SupportLocalization.rewardDescription)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Ad Section

    private var adSection: some View {
        Button {
            Task {
                await adManager.loadAndShow {
                    Task { @MainActor in
                        await pointsStore.addPoint()
                        showEarnedAlert = true
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if case .loading = adManager.state {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                }
                Text(buttonTitle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .disabled(!adManager.state.isIdle || adUnavailableForCurrentPresentation)
        .animation(.default, value: adManager.state)
        .id(presentationResetID)
    }

    private var buttonTitle: String {
        switch adManager.state {
        case .idle:       return SupportLocalization.watchButtonTitle
        case .loading:    return SupportLocalization.loadingButtonTitle
        case .presenting: return SupportLocalization.presentingButtonTitle
        case .failed:     return SupportLocalization.watchButtonTitle
        }
    }

    private func resetPresentationState() {
        showEarnedAlert = false
        showAdFailedAlert = false
        adUnavailableForCurrentPresentation = false
        presentationResetID = UUID()
        if case .failed = adManager.state {
            adManager.resetToIdle()
        }
    }
}
