import Foundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
#endif
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// 広告の同意取得と SDK 初期化の順序を一元管理する。
///
/// ATT の許可ダイアログは初回起動体験を遮るため、起動時には要求しない。
/// UMP の同意情報だけ更新し、その後に Google Mobile Ads SDK を起動する。
///
/// 参照: https://developers.google.com/admob/ios/privacy
@MainActor
final class AdConsentCoordinator {

    static let shared = AdConsentCoordinator()

    private var hasStarted = false

    private init() {}

    /// アプリ起動後に一度だけ呼ぶ。
    ///
    /// - Important: ATT のダイアログはアプリがフォアグラウンドかつ `active` でないと
    ///   表示されずに即 `.denied` が返る。そのため呼び出しは
    ///   `didFinishLaunching` ではなく、画面が出てからにする。
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        await gatherConsent()
        startMobileAdsSDK()
    }

    /// 設定画面から同意フォームを開き直せるようにする（GDPR 対象地域で必要）。
    func presentPrivacyOptionsForm() async {
        #if canImport(UserMessagingPlatform)
        guard let root = Self.topViewController() else { return }
        await withCheckedContinuation { continuation in
            ConsentForm.presentPrivacyOptionsForm(from: root) { error in
                if let error {
                    WanderlustDiagnostics.warning(
                        "ump privacy options form failed: \(error.localizedDescription)",
                        category: .ui
                    )
                }
                continuation.resume()
            }
        }
        #endif
    }

    /// 設定画面に「プライバシー設定」の導線を出すべきか。
    var isPrivacyOptionsRequired: Bool {
        #if canImport(UserMessagingPlatform)
        return ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        #else
        return false
        #endif
    }

    // MARK: - Steps

    private func gatherConsent() async {
        #if canImport(UserMessagingPlatform)
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false

        // 1. 同意情報の更新
        let updateFailed: Bool = await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                if let error {
                    let nsError = error as NSError
                    WanderlustDiagnostics.warning(
                        "ump consent info update failed domain=\(nsError.domain) code=\(nsError.code): \(error.localizedDescription)",
                        category: .sync
                    )
                }
                WanderlustDiagnostics.info(
                    "ump consent status=\(ConsentInformation.shared.consentStatus.rawValue) canRequestAds=\(ConsentInformation.shared.canRequestAds)",
                    category: .sync
                )
                continuation.resume(returning: error != nil)
            }
        }

        guard !updateFailed else { return }

        // 2. 必要ならフォームを表示（不要な地域では即座に完了する）
        guard let root = Self.topViewController() else { return }
        await withCheckedContinuation { continuation in
            ConsentForm.loadAndPresentIfRequired(from: root) { error in
                if let error {
                    let nsError = error as NSError
                    WanderlustDiagnostics.warning(
                        "ump consent form failed domain=\(nsError.domain) code=\(nsError.code): \(error.localizedDescription)",
                        category: .ui
                    )
                }
                continuation.resume()
            }
        }
        #endif
    }

    private func startMobileAdsSDK() {
        #if canImport(GoogleMobileAds)
        MobileAds.shared.start { status in
            #if DEBUG
            let adapterSummary = status.adapterStatusesByClassName
                .map { "\($0.key)=\($0.value.state.rawValue)" }
                .sorted()
                .joined(separator: ",")
            WanderlustDiagnostics.info(
                "ads sdk initialized adapters=\(status.adapterStatusesByClassName.count) adapterStates=\(adapterSummary)",
                category: .performance
            )
            #endif
            Task { @MainActor in
                RewardedAdManager.shared.sdkDidInitialize()
            }
        }
        #endif
    }

    // MARK: - Helpers

    #if canImport(UIKit)
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
    #endif
}
